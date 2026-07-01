package pipeline.sinks;

import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.sink.KafkaSinkBuilder;

import java.util.Objects;
import java.util.Properties;

/**
 * Builds a Kafka sink for emitting processed feature records.
 *
 * <p>Two construction paths:
 * <ul>
 *   <li>{@code (bootstrapServers, topic)} — minimal, AT_LEAST_ONCE, no auth.
 *       Used by unit tests and PLAINTEXT dev clusters.</li>
 *   <li>{@code (bootstrapServers, topic, producerConfig, transactionalIdPrefix)}
 *       — production path. {@code producerConfig} carries the client security
 *       properties (SASL_SSL / SCRAM / PEM truststore) and tuning such as
 *       {@code transaction.timeout.ms}. A non-empty {@code transactionalIdPrefix}
 *       switches the sink to EXACTLY_ONCE (two-phase commit on Flink checkpoints);
 *       the prefix MUST satisfy the broker's transactionalId ACL.</li>
 * </ul>
 */
public class KafkaSinkFactory {

    private final String bootstrapServers;
    private final String topic;
    private final Properties producerConfig;
    private final String transactionalIdPrefix;

    public KafkaSinkFactory(String bootstrapServers, String topic) {
        this(bootstrapServers, topic, new Properties(), null);
    }

    public KafkaSinkFactory(
            String bootstrapServers,
            String topic,
            Properties producerConfig,
            String transactionalIdPrefix) {
        this.bootstrapServers = Objects.requireNonNull(bootstrapServers, "bootstrapServers");
        this.topic = Objects.requireNonNull(topic, "topic");
        this.producerConfig = (producerConfig == null) ? new Properties() : producerConfig;
        // Empty / null prefix ⇒ no transactions ⇒ AT_LEAST_ONCE.
        this.transactionalIdPrefix =
            (transactionalIdPrefix == null || transactionalIdPrefix.isEmpty()) ? null : transactionalIdPrefix;
    }

    public KafkaSink<String> createSink() {
        KafkaSinkBuilder<String> builder = KafkaSink.<String>builder()
                .setBootstrapServers(bootstrapServers)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic(topic)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build());

        if (!producerConfig.isEmpty()) {
            builder.setKafkaProducerConfig(producerConfig);
        }

        if (transactionalIdPrefix != null) {
            // EXACTLY_ONCE: the sink commits its Kafka transaction on each
            // successful Flink checkpoint. Downstream ClickHouse Kafka-engine
            // consumers read committed (librdkafka default isolation.level=
            // read_committed), so aborted/in-flight transactions never reach
            // the bronze table — end-to-end exactly-once on the durable path.
            builder.setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
                   .setTransactionalIdPrefix(transactionalIdPrefix);
        } else {
            builder.setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE);
        }

        return builder.build();
    }
}
