# Multi-stage build for Flink job using Mill (5-10x faster than Maven, instant incremental builds)
#
# JDK version pin: eclipse-temurin 21-jdk-alpine.
#   - Flink 2.2 line officially supports Java 21 (DockerHub publishes
#     flink:2.2.0-scala_2.12-java21 as the runtime image).
#   - Java 21 is the current LTS as of April 2026 (next LTS = Java 25, Sep 2025
#     GA but Flink 2.2 has not certified it for production).
#   - Aligning builder JDK with runtime JDK avoids `--release` cross-compile
#     warnings and ensures `mill-jvm-version: system` (see build.mill) lands
#     on the same major version Flink will execute.
FROM eclipse-temurin:21-jdk-alpine AS builder

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
# JAVA_HOME export pairs with `//| mill-jvm-version: system` in build.mill so
# Mill resolves the base-image JDK instead of downloading zulu:21 from
# cdn.azul.com (which is not reachable from this lab network). Both are
# required: env var alone is insufficient, the build-header opt-in is what
# stops coursier's JVM-index lookup.
RUN mkdir -p /root/.cache/mill/download && \
    wget -q -O /root/.cache/mill/download/1.1.5 https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5.exe && \
    chmod +x /root/.cache/mill/download/1.1.5 && \
    wget -q -O /usr/local/bin/mill https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.1.5/mill-dist-1.1.5-mill.sh && \
    chmod +x /usr/local/bin/mill
ENV MILL_JAVA_HOME=$JAVA_HOME

# Copy build config and source
COPY build.mill .
COPY src ./src

# Build fat JAR (resolve deps + compile + assemble in single step).
#
# Retry wrapper handles transient DNS failures from the campus uplink resolver
# (167.205.22.123). Coursier's per-artifact retry covers 5xx but not
# UnknownHostException, and the launcher-level mill-runner-daemon pom fetch
# happens before any user code runs — a single DNS blip kills the whole job.
# Mill's `out/` is preserved across iterations so completed work is not redone.
RUN for i in 1 2 3 4 5; do \
        mill -j 0 flink.assembly && exit 0; \
        echo "[build] attempt $i failed, retrying in 15s..."; \
        sleep 15; \
    done; \
    echo "[build] failed after 5 attempts" >&2; \
    exit 1

# Runtime image — eclipse-temurin 21-jre-alpine.
#   - Matches the JDK 21 builder so the fat JAR runs on the same major it
#     was compiled against (no AOT bytecode-version mismatch risk).
#   - Matches Flink 2.2's officially supported Java 21 runtime line.
#   - JRE-only base — application-mode submission via Flink Operator runs
#     this image only for the MiniCluster fallback path (see CMD below);
#     the operator-driven path uses a use-case overlay image built on top
#     of flink:2.2.0-scala_2.12-java21 (see use-case/manifests/.../flink/).
FROM eclipse-temurin:21-jre-alpine

RUN adduser -D -u 1000 -s /sbin/nologin app

# Copy the fat JAR (includes Flink runtime + all dependencies)
COPY --from=builder --chown=1000:1000 /app/out/flink/assembly.dest/out.jar /app/flink-job.jar

USER 1000:1000

# MiniCluster mode: runs JobManager + TaskManager in one JVM process
# StreamExecutionEnvironment.getExecutionEnvironment() auto-creates a local MiniCluster
CMD ["java", "-Xmx512m", "-cp", "/app/flink-job.jar", "com.pipeline.StreamJob"]
