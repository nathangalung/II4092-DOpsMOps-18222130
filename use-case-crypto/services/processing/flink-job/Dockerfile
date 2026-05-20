# =============================================================================
# use-case-crypto :: crypto-flink-job image (Flink Operator application mode)
# =============================================================================
# Built FROM the official Flink runtime so the Flink Kubernetes Operator
# can invoke `/docker-entrypoint.sh kubernetes-application` on it (ADR-023).
#
# Layout: jars under /opt/flink/usrlib/ are auto-discovered by
# StandaloneApplicationClusterEntryPoint. Two jars are copied:
#
#   /opt/flink/usrlib/crypto-flink-job.jar
#       Platform fat jar (com.pipeline.StreamJob + Flink runtime deps).
#       Pulled from the platform-built flink-job:latest image so we don't
#       rebuild Mill twice.
#
#   /opt/flink/usrlib/crypto-extensions.jar
#       Thin overlay jar with crypto-specific feature functions
#       (OrderbookFeatureFunction, TradeFeatureFunction) that the
#       platform StreamJob resolves via reflection at job-graph build time.
#
# Build order (orchestrated by root `make usecase-crypto-build`):
#   1. platform-build-services builds `flink-job:latest`
#      (PLATFORM_SERVICES → platform/services/processing/stream/flink-job)
#   2. This Dockerfile assembles the operator-compatible image on top of
#      flink:2.2.0-scala_2.12-java21 (matches FlinkDeployment.flinkVersion=v2_2
#      and platform session cluster image).
# =============================================================================

# ---- Stage 1: extract the platform fat jar from the builder image -----------
FROM flink-job:latest AS platform_jar

# ---- Stage 2: compile crypto extension jar with Mill ------------------------
FROM eclipse-temurin:25-jdk-alpine AS builder

WORKDIR /app

# Install Mill 1.1.5 in two steps to bypass its internal curl dependency:
#   1. Pre-fetch the mill-dist bootstrap binary (`.exe` is a self-executing
#      JAR with shebang, not Windows) directly into the launcher's cache slot.
#      When the launcher runs it finds the cache hit and skips its curl path.
#   2. Install the launcher shell wrapper.
# wget is already shipped via BusyBox in the temurin alpine base, so no
# `apk add` round-trip to dl-cdn.alpinelinux.org is needed.
RUN mkdir -p /root/.cache/mill/download && \
    wget -q -O /root/.cache/mill/download/1.1.5 https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5.exe && \
    chmod +x /root/.cache/mill/download/1.1.5 && \
    wget -q -O /usr/local/bin/mill https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5-mill.sh && \
    chmod +x /usr/local/bin/mill
ENV MILL_JAVA_HOME=$JAVA_HOME

COPY build.mill .
COPY src ./src

RUN mill -j 0 flink.assembly

# ---- Stage 3: assemble Flink Operator-compatible runtime image --------------
# flink:2.2.0-scala_2.12-java21 ships /docker-entrypoint.sh which the operator
# invokes with `kubernetes-application` to start the JobManager / TaskManager
# (StandaloneApplicationClusterEntryPoint loads jars from /opt/flink/usrlib/).
FROM flink:2.2.0-scala_2.12-java21

# Platform fat jar carries com.pipeline.StreamJob + all Flink-side deps.
COPY --from=platform_jar /app/flink-job.jar /opt/flink/usrlib/crypto-flink-job.jar

# Crypto extension jar — feature-function classes that StreamJob loads via
# reflection (STREAM_<NAME>_FUNCTION env keys). Thin overlay (Flink + Jackson
# + SLF4J marked provided in build.mill).
COPY --from=builder /app/out/flink/assembly.dest/out.jar /opt/flink/usrlib/crypto-extensions.jar

# Enable Flink S3 filesystem plugins. The base image ships the JARs in
# /opt/flink/opt/ but Flink only loads plugins that live in their own
# subfolder under /opt/flink/plugins/ (isolated ChildFirstClassLoader per
# plugin — prevents Hadoop classpath bleed into core Flink).
#
# Required because FlinkDeployment.flinkConfiguration uses s3:// for:
#   - high-availability.storageDir  (s3-fs-presto: lower-latency small writes)
#   - state.checkpoints.dir          (s3-fs-presto)
#   - state.savepoints.dir           (s3-fs-presto)
# Hadoop variant is shipped alongside for any downstream user code that
# performs broader S3 read/write semantics (sink committers, file-system
# connectors). Each plugin runs in its own classloader, so coexistence is
# safe — see https://nightlies.apache.org/flink/flink-docs-release-2.2/docs/deployment/filesystems/plugins/
RUN mkdir -p /opt/flink/plugins/s3-fs-presto /opt/flink/plugins/s3-fs-hadoop && \
    cp /opt/flink/opt/flink-s3-fs-presto-*.jar /opt/flink/plugins/s3-fs-presto/ && \
    cp /opt/flink/opt/flink-s3-fs-hadoop-*.jar /opt/flink/plugins/s3-fs-hadoop/
