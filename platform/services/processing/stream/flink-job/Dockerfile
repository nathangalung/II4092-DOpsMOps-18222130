# Multi-stage build for Flink job using Mill (5-10x faster than Maven, instant incremental builds)
FROM eclipse-temurin:25-jdk-alpine AS builder

WORKDIR /app

# Install Mill build tool 1.1.5 (must match host version for build.mill API
# compatibility).
#
# Two-step install bypasses the launcher's internal `curl` call:
#   1. Pre-fetch the mill-dist bootstrap binary (.exe = self-executing JAR with
#      shebang, *not* Windows) into the launcher's expected cache slot at
#      ~/.cache/mill/download/$MILL_VERSION.  When the launcher next runs it
#      sees the cache hit (`[ -s "${MILL}" ]`) and skips its curl-based
#      download path entirely.
#   2. Install the launcher shell script onto PATH.
#
# Why not `apk add curl`?  Apk needs dl-cdn.alpinelinux.org which is flaky
# behind some campus/firewalled networks, while Maven Central is consistently
# reachable via the JDK's TLS stack.  BusyBox wget (already in the temurin
# alpine base) handles HTTPS via libtls without any package install.
#
# JAVA_HOME export so Mill skips downloading its own JDK.
RUN mkdir -p /root/.cache/mill/download && \
    wget -q -O /root/.cache/mill/download/1.1.5 https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5.exe && \
    chmod +x /root/.cache/mill/download/1.1.5 && \
    wget -q -O /usr/local/bin/mill https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5-mill.sh && \
    chmod +x /usr/local/bin/mill
ENV MILL_JAVA_HOME=$JAVA_HOME

# Copy build config and source
COPY build.mill .
COPY src ./src

# Build fat JAR (resolve deps + compile + assemble in single step)
RUN mill -j 0 flink.assembly

# Runtime image - use JRE base (no full Flink cluster needed for MiniCluster mode).
# Tag `25-jre-alpine` is the official Adoptium rolling alpine variant; the dated
# `-alpine3.XX` suffix is not published for the JRE line (only the JDK line had
# it historically).  Sticking to the rolling tag keeps the image on the latest
# Alpine 3.x point release picked up at build time.
FROM eclipse-temurin:25-jre-alpine

RUN adduser -D -u 1000 -s /sbin/nologin app

# Copy the fat JAR (includes Flink runtime + all dependencies)
COPY --from=builder --chown=1000:1000 /app/out/flink/assembly.dest/out.jar /app/flink-job.jar

USER 1000:1000

# MiniCluster mode: runs JobManager + TaskManager in one JVM process
# StreamExecutionEnvironment.getExecutionEnvironment() auto-creates a local MiniCluster
CMD ["java", "-Xmx512m", "-cp", "/app/flink-job.jar", "com.pipeline.StreamJob"]
