package com.pipeline;

import com.pipeline.sinks.RedisSink;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.KafkaSourceBuilder;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Properties;

/**
 * Domain-agnostic Flink streaming harness.
 *
 * The set of streams (topics + feature functions) is declared entirely at
 * deploy time through environment variables; the harness itself holds no
 * reference to any use-case concept (crypto, stock, IoT, log, ...).
 *
 * Env contract
 *   KAFKA_BROKERS                       Bootstrap servers (required)
 *   KAFKA_SECURITY_PROTOCOL             PLAINTEXT | SASL_PLAINTEXT | SASL_SSL | SSL
 *                                         (optional; default PLAINTEXT). When SASL_*,
 *                                         the JAAS config is built from
 *                                         KAFKA_SASL_USERNAME / KAFKA_SASL_PASSWORD.
 *   KAFKA_SASL_MECHANISM                e.g. SCRAM-SHA-512 (required when SASL_*).
 *   KAFKA_SASL_USERNAME / _PASSWORD     SCRAM creds, injected from a KafkaUser secret.
 *   KAFKA_SSL_CA_LOCATION               PEM path for ssl.truststore.location
 *                                         (Strimzi cluster CA cert; required for SSL/SASL_SSL).
 *   VALKEY_HOST, VALKEY_PORT, VALKEY_PASSWORD   Sink parameters (required;
 *                                         Valkey speaks Redis-RESP — Lettuce client below)
 *   ENABLED_STREAMS                     Comma-separated stream names, e.g.
 *                                         "time_series" or
 *                                         "time_series,trades,orderbook"
 *                                       Default: "time_series"
 *
 *   For every stream NAME in ENABLED_STREAMS:
 *     STREAM_{NAME}_TOPIC               Kafka topic (required)
 *     STREAM_{NAME}_FUNCTION            Fully-qualified class name of a
 *                                         KeyedProcessFunction&lt;String,String,String&gt;
 *                                         (required; loaded via reflection)
 *     STREAM_{NAME}_GROUP               Consumer group id (optional,
 *                                         defaults to flink-{name})
 *
 * Use-case responsibility
 *   Use-cases ship a container image that extends this image (or otherwise
 *   augments the classpath) with their own function classes and declare
 *   the above env vars from their ConfigMap. The platform image ships only
 *   com.pipeline.functions.FeatureFunction as a time-series primitive.
 */
public class StreamJob {
    private static final Logger LOG = LoggerFactory.getLogger(StreamJob.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    public static void main(String[] args) throws Exception {
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60000);

        final String kafkaBrokers = required("KAFKA_BROKERS");
        final String valkeyHost = System.getenv().getOrDefault("VALKEY_HOST", "localhost");
        final int valkeyPort = Integer.parseInt(System.getenv().getOrDefault("VALKEY_PORT", "6379"));
        final String valkeyPassword = System.getenv().getOrDefault("VALKEY_PASSWORD", "");

        final String enabled = System.getenv().getOrDefault("ENABLED_STREAMS", "time_series");
        LOG.info("ENABLED_STREAMS={}", enabled);

        int wired = 0;
        for (String rawName : enabled.split(",")) {
            final String name = rawName.trim();
            if (name.isEmpty()) continue;

            final String up = name.toUpperCase();
            final String topic = System.getenv("STREAM_" + up + "_TOPIC");
            final String funcClass = System.getenv("STREAM_" + up + "_FUNCTION");
            final String group = System.getenv().getOrDefault("STREAM_" + up + "_GROUP", "flink-" + name);

            if (topic == null || topic.isEmpty() || funcClass == null || funcClass.isEmpty()) {
                LOG.warn("Stream '{}' skipped — missing STREAM_{}_TOPIC or STREAM_{}_FUNCTION", name, up, up);
                continue;
            }

            @SuppressWarnings("unchecked")
            KeyedProcessFunction<String, String, String> fn =
                (KeyedProcessFunction<String, String, String>)
                    Class.forName(funcClass).getDeclaredConstructor().newInstance();

            KafkaSource<String> src = buildKafkaSource(kafkaBrokers, topic, group);
            DataStream<String> out = env
                .fromSource(src, WatermarkStrategy.noWatermarks(), name + " Source")
                .keyBy(StreamJob::extractSymbol)
                .process(fn)
                .name(name + " Feature Computation");

            out.sinkTo(new RedisSink(valkeyHost, valkeyPort, valkeyPassword))
                .name(name + " Valkey Sink (RESP)");

            LOG.info("Wired stream '{}' topic={} function={}", name, topic, funcClass);
            wired++;
        }

        if (wired == 0) {
            throw new IllegalStateException(
                "No streams wired. Set ENABLED_STREAMS and STREAM_<NAME>_TOPIC / _FUNCTION env vars.");
        }

        env.execute("Feature Stream (" + wired + " streams)");
    }

    private static String required(String key) {
        String v = System.getenv(key);
        if (v == null || v.isEmpty()) {
            throw new IllegalStateException("Missing required env var: " + key);
        }
        return v;
    }

    private static KafkaSource<String> buildKafkaSource(String brokers, String topic, String groupId) {
        KafkaSourceBuilder<String> b = KafkaSource.<String>builder()
            .setBootstrapServers(brokers)
            .setTopics(topic)
            .setGroupId(groupId)
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(new SimpleStringSchema());

        // Forward Kafka client security properties from the env so Strimzi
        // SASL_SSL listeners (9093) are reachable. setProperties merges into
        // the AdminClient + Consumer configs used by KafkaSourceEnumerator
        // and KafkaPartitionSplitReader respectively.
        Properties sec = kafkaSecurityProperties();
        if (!sec.isEmpty()) {
            b.setProperties(sec);
            LOG.info("Kafka security: protocol={} mechanism={} truststore={}",
                sec.getProperty("security.protocol"),
                sec.getProperty("sasl.mechanism"),
                sec.getProperty("ssl.truststore.location"));
        }
        return b.build();
    }

    /**
     * Build Kafka client security Properties from env vars. Returns empty
     * when KAFKA_SECURITY_PROTOCOL is unset / PLAINTEXT (Strimzi 9092
     * listener path used by single-node dev clusters without auth).
     *
     * SSL truststore uses PEM type — Kafka 3.0+ supports loading the
     * Strimzi-emitted ca.crt directly without a JKS conversion step.
     */
    private static Properties kafkaSecurityProperties() {
        Properties p = new Properties();
        String proto = System.getenv("KAFKA_SECURITY_PROTOCOL");
        if (proto == null || proto.isEmpty() || "PLAINTEXT".equalsIgnoreCase(proto)) {
            return p;
        }
        p.setProperty("security.protocol", proto);

        if (proto.startsWith("SASL_")) {
            String mech = System.getenv().getOrDefault("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512");
            String user = required("KAFKA_SASL_USERNAME");
            String pass = required("KAFKA_SASL_PASSWORD");
            p.setProperty("sasl.mechanism", mech);
            // Only SCRAM mechanisms are configured here; PLAIN/OAUTHBEARER would
            // need a different LoginModule. SCRAM is the Strimzi default.
            String loginModule = "org.apache.kafka.common.security.scram.ScramLoginModule";
            p.setProperty("sasl.jaas.config",
                loginModule + " required username=\"" + user + "\" password=\"" + pass + "\";");
        }

        if (proto.endsWith("SSL")) {
            String ca = System.getenv().getOrDefault("KAFKA_SSL_CA_LOCATION", "/etc/kafka/ca/ca.crt");
            p.setProperty("ssl.truststore.type", "PEM");
            p.setProperty("ssl.truststore.location", ca);
        }
        return p;
    }

    private static String extractSymbol(String json) {
        try {
            JsonNode node = MAPPER.readTree(json);
            return node.has("symbol") ? node.get("symbol").asText() : "unknown";
        } catch (Exception e) {
            return "unknown";
        }
    }
}
