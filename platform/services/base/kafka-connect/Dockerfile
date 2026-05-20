# Custom Kafka Connect image with Debezium + Iceberg sink connector
# Base: Debezium Connect (includes Debezium CDC connectors)
# Added: Apache Iceberg Kafka Connect runtime (for S3/MinIO Iceberg archival)
FROM quay.io/debezium/connect:3.5.0.Final

ARG ICEBERG_CONNECT_VERSION=0.6.19
ARG ICEBERG_ZIP_URL=https://github.com/databricks/iceberg-kafka-connect/releases/download/v${ICEBERG_CONNECT_VERSION}/iceberg-kafka-connect-runtime-${ICEBERG_CONNECT_VERSION}.zip

USER root

RUN mkdir -p /kafka/connect/iceberg && \
    curl -fSL "${ICEBERG_ZIP_URL}" -o /tmp/iceberg-connect.zip && \
    unzip -j /tmp/iceberg-connect.zip -d /kafka/connect/iceberg/ && \
    rm /tmp/iceberg-connect.zip && \
    echo "Iceberg Kafka Connect v${ICEBERG_CONNECT_VERSION} installed"

USER 1001
