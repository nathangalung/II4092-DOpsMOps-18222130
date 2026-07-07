package pipeline;

import pipeline.sinks.KafkaSinkFactory;
import pipeline.sinks.RedisSink;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.KafkaSourceBuilder;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Properties;

/**
 * Domain-agnostic Flink streaming harness.
 *
 * <p>The set of streams (topics + feature functions + sinks) is declared
 * entirely at deploy time through environment variables; the harness itself
 * holds no reference to any use-case concept (financial ticks, IoT telemetry,
 * logs, ...).
 *
 * <p><b>Dual-sink model.</b> A stream's {@link KeyedProcessFunction} emits two
 * projections of each record: its <em>main</em> output (the full feature record)
 * goes to a Kafka topic for the durable bronze path; its
 * {@link Tags#CACHE_TAG} side output (the indicator-only projection) goes to the
 * Valkey online-serving cache. Either sink is optional per stream - configure
 * whichever the use-case needs.
 *
 * <p>Env contract
 * <pre>
 *   KAFKA_BROKERS                       Bootstrap servers (required)
 *   KAFKA_SECURITY_PROTOCOL             PLAINTEXT | SASL_PLAINTEXT | SASL_SSL | SSL
 *                                         (optional; default PLAINTEXT). When SASL_*,
 *                                         JAAS is built from KAFKA_SASL_USERNAME / _PASSWORD.
 *   KAFKA_SASL_MECHANISM                e.g. SCRAM-SHA-512 (required when SASL_*).
 *   KAFKA_SASL_USERNAME / _PASSWORD     SCRAM creds, injected from a KafkaUser secret.
 *   KAFKA_SSL_CA_LOCATION               PEM path for ssl.truststore.location.
 *   VALKEY_HOST, VALKEY_PORT, VALKEY_PASSWORD   Online-cache sink parameters.
 *   ENABLED_STREAMS                     Comma-separated stream names (default "time_series").
 *
 *   For every stream NAME in ENABLED_STREAMS:
 *     STREAM_{NAME}_TOPIC               Source Kafka topic (required)
 *     STREAM_{NAME}_FUNCTION            FQCN of a KeyedProcessFunction&lt;String,String,String&gt;
 *                                         (required; loaded via reflection)
 *     STREAM_{NAME}_GROUP               Source consumer group (default flink-{name})
 *     STREAM_{NAME}_SINK_TOPIC          Kafka sink topic for the main output
 *                                         (default env OUTPUT_TOPIC; omit to disable
 *                                         the durable Kafka sink)
 *     STREAM_{NAME}_SINK_TXN_ID_PREFIX  When set, the Kafka sink runs EXACTLY_ONCE
 *                                         with this transactional.id prefix (must match
 *                                         the broker's transactionalId ACL). Omit for
 *                                         AT_LEAST_ONCE. (default env KAFKA_SINK_TXN_ID_PREFIX)
 *     STREAM_{NAME}_KEY_PREFIX          Valkey key namespace for the CACHE_TAG side
 *                                         output. SET to enable the online-cache sink;
 *                                         omit to disable it. Use the bare "features:"
 *                                         to own the canonical online feature cache
 *                                         (features:{symbol}); use "features:{name}:"
 *                                         to keep a stream's cache in its own keyspace.
 * </pre>
 *
 * <p>Use-cases ship a container image that extends this image with their own
 * function classes and declare the above env vars from their ConfigMap. The
 * platform image ships {@code pipeline.functions.FeatureFunction} as a
 * time-series primitive.
 */
public class StreamJob {
    private static final Logger LOG = LoggerFactory.getLogger(StreamJob.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    public static void main(String[] args) throws Exception {
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60000);

        final String kafkaBrokers = required("KAFKA_BROKERS");
        final String valkeyHost = env("VALKEY_HOST", "localhost");
        final int valkeyPort = Integer.parseInt(env("VALKEY_PORT", "6379"));
        final String valkeyPassword = env("VALKEY_PASSWORD", "");

        final String enabled = env("ENABLED_STREAMS", "time_series");
        LOG.info("ENABLED_STREAMS={}", enabled);

        int wired = 0;
        for (String rawName : enabled.split(",")) {
            final String name = rawName.trim();
            if (name.isEmpty()) continue;

            final String up = name.toUpperCase();
            final String topic = System.getenv("STREAM_" + up + "_TOPIC");
            final String funcClass = System.getenv("STREAM_" + up + "_FUNCTION");
            final String group = env("STREAM_" + up + "_GROUP", "flink-" + name);

            if (topic == null || topic.isEmpty() || funcClass == null || funcClass.isEmpty()) {
                LOG.warn("Stream '{}' skipped — missing STREAM_{}_TOPIC or STREAM_{}_FUNCTION", name, up, up);
                continue;
            }

            @SuppressWarnings("unchecked")
            KeyedProcessFunction<String, String, String> fn =
                (KeyedProcessFunction<String, String, String>)
                    Class.forName(funcClass).getDeclaredConstructor().newInstance();

            KafkaSource<String> src = buildKafkaSource(kafkaBrokers, topic, group);
            SingleOutputStreamOperator<String> processed = env
                .fromSource(src, WatermarkStrategy.noWatermarks(), name + " Source")
                .keyBy(StreamJob::extractSymbol)
                .process(fn)
                .name(name + " Feature Computation");

            boolean sinkWired = false;

            // Durable Kafka sink (main output to bronze contract)
            final String sinkTopic = env("STREAM_" + up + "_SINK_TOPIC", System.getenv("OUTPUT_TOPIC"));
            if (sinkTopic != null && !sinkTopic.isEmpty()) {
                final String txnPrefix = env(
                    "STREAM_" + up + "_SINK_TXN_ID_PREFIX", System.getenv("KAFKA_SINK_TXN_ID_PREFIX"));
                Properties producerProps = kafkaSecurityProperties();
                if (txnPrefix != null && !txnPrefix.isEmpty()) {
                    // Comfortably below the broker's transaction.max.timeout.ms
                    // (Strimzi/Kafka default 900000) and far above the 60s
                    // checkpoint interval. Flink's own default (1h) EXCEEDS the
                    // broker max, so the transactional producer would fail to init.
                    producerProps.setProperty("transaction.timeout.ms", "600000");
                }
                processed.sinkTo(new KafkaSinkFactory(kafkaBrokers, sinkTopic, producerProps, txnPrefix).createSink())
                    .name(name + " Kafka Sink");
                LOG.info("Stream '{}' Kafka sink → topic={} delivery={}",
                    name, sinkTopic,
                    (txnPrefix != null && !txnPrefix.isEmpty()) ? "EXACTLY_ONCE(" + txnPrefix + ")" : "AT_LEAST_ONCE");
                sinkWired = true;
            }

            // Valkey online-cache sink (CACHE_TAG side output)
            final String keyPrefix = System.getenv("STREAM_" + up + "_KEY_PREFIX");
            if (keyPrefix != null && !keyPrefix.isEmpty()) {
                processed.getSideOutput(Tags.CACHE_TAG)
                    .sinkTo(new RedisSink(valkeyHost, valkeyPort, valkeyPassword, keyPrefix))
                    .name(name + " Valkey Cache Sink (RESP)");
                LOG.info("Stream '{}' Valkey cache sink → keyPrefix={}", name, keyPrefix);
                sinkWired = true;
            }

            if (!sinkWired) {
                LOG.warn("Stream '{}' has NO sink — set STREAM_{}_SINK_TOPIC and/or STREAM_{}_KEY_PREFIX", name, up, up);
            }

            LOG.info("Wired stream '{}' topic={} function={}", name, topic, funcClass);
            wired++;
        }

        if (wired == 0) {
            throw new IllegalStateException(
                "No streams wired. Set ENABLED_STREAMS and STREAM_<NAME>_TOPIC / _FUNCTION env vars.");
        }

        env.execute("Feature Stream (" + wired + " streams)");
    }

    private static String env(String key, String def) {
        String v = System.getenv(key);
        return (v == null || v.isEmpty()) ? def : v;
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
     * Build Kafka client security Properties from env vars. Returns empty when
     * KAFKA_SECURITY_PROTOCOL is unset / PLAINTEXT (Strimzi 9092 listener path
     * used by single-node dev clusters without auth). Shared by the source
     * (consumer) and the sink (producer).
     *
     * <p>SSL truststore uses PEM type - Kafka 3.0+ loads the Strimzi-emitted
     * ca.crt directly without a JKS conversion step.
     */
    private static Properties kafkaSecurityProperties() {
        Properties p = new Properties();
        String proto = System.getenv("KAFKA_SECURITY_PROTOCOL");
        if (proto == null || proto.isEmpty() || "PLAINTEXT".equalsIgnoreCase(proto)) {
            return p;
        }
        p.setProperty("security.protocol", proto);

        if (proto.startsWith("SASL_")) {
            String mech = env("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512");
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
            String ca = env("KAFKA_SSL_CA_LOCATION", "/etc/kafka/ca/ca.crt");
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
