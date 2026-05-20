# =============================================================================
# Kafka Connect with Debezium + Iceberg Sink
# =============================================================================
# Extends the official Debezium Connect image with the Apache Iceberg
# Kafka Connect sink connector for streaming data to Iceberg tables.
#
# Connectors included:
#   - Debezium PostgreSQL/MySQL (CDC source) — built-in
#   - Apache Iceberg (Lakehouse sink) — added
# =============================================================================
FROM quay.io/debezium/connect:3.5.0.Final

# Download Apache Iceberg Kafka Connect sink connector
# https://iceberg.apache.org/docs/nightly/kafka-connect/
USER root
RUN mkdir -p /kafka/connect/iceberg-sink && \
    cd /kafka/connect/iceberg-sink && \
    curl -sL "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-kafka-connect-runtime-catalog-rest/1.9.1/iceberg-kafka-connect-runtime-catalog-rest-1.9.1.jar" -o iceberg-kafka-connect-runtime.jar && \
    echo "Iceberg Kafka Connect sink installed"
USER 1001
