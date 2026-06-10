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
# Coursier download cache (BuildKit): persists resolved Maven/Flink jars across
# builds so a source edit no longer re-downloads ~100MB of dependencies. Mill's
# `out/` stays in-layer (not a cache mount) so the assembled fat jar remains
# COPY-able from this stage.
RUN --mount=type=cache,id=coursier,target=/root/.cache/coursier \
    for i in 1 2 3 4 5; do \
        mill -j 0 flink.assembly && exit 0; \
        echo "[build] attempt $i failed, retrying in 15s..."; \
        sleep 15; \
    done; \
    echo "[build] failed after 5 attempts" >&2; \
    exit 1

# Runtime image — official Flink 2.2 distribution (Java 21 line).
#   - Operator application-mode: the flink-kubernetes-operator drives the
#     standard Flink `standalone-job` entrypoint against THIS image (the
#     FlinkDeployment `job.jarURI: local:///opt/flink/usrlib/flink-job.jar`
#     points at the fat JAR placed below). This is the real operator-managed
#     JobManager+TaskManager path — NOT a MiniCluster-in-a-pod (the prior
#     in-pod runtime was flagged as an anti-pattern; see speed-layer ADR).
#   - One image, not two: the fat JAR still bundles Flink core, but Flink's
#     default `classloader.parent-first-patterns` (org.apache.flink.*,
#     org.slf4j, log4j) load the framework + logging from the base image's
#     /opt/flink/lib, so the bundled copies are shadowed — no duplicate-class
#     or SLF4J-binding conflict. Only the application + Kafka connector +
#     Jackson/Lettuce/commons-math3 are loaded from the user jar (child-first).
FROM flink:2.2.0-scala_2.12-java21

# Place the application fat JAR where the operator's standalone-job entrypoint
# and the FlinkDeployment jarURI expect user code.
COPY --from=builder /app/out/flink/assembly.dest/out.jar /opt/flink/usrlib/flink-job.jar

# Activate the Hadoop S3 filesystem plugin so the JobManager + TaskManager can
# resolve the `s3://` scheme used by Kubernetes-HA storage, checkpoints, and
# savepoints (stream-processor.yaml: high-availability.storageDir +
# state.{checkpoints,savepoints}.dir on MinIO). Without it the JM crashes at
# startup with UnsupportedFileSystemSchemeException for scheme 's3'.
#
#   - WHY hadoop, not presto: the FlinkDeployment tunes the S3 client via
#     `s3.connection.maximum` / `s3.connection.request.timeout` /
#     `s3.socket.timeout`, which Flink forwards as `fs.s3a.*` — Hadoop-S3A
#     semantics. The presto plugin ignores those keys, so hadoop keeps the
#     manifest config honest. Credentials arrive via AWS_* env (S3A's default
#     EnvironmentVariableCredentialsProvider), endpoint/path-style via the
#     forwarded `s3.endpoint` / `s3.path.style.access`.
#   - WHY copy into plugins/, not ENABLE_BUILT_IN_PLUGINS: that env var is
#     handled only by the image's docker-entrypoint.sh, which the
#     flink-kubernetes-operator bypasses (it drives KubernetesApplication-
#     ClusterEntrypoint directly). Flink scans plugins/<name>/ at startup
#     regardless of entrypoint, so a build-time copy is robust either way.
#   - The shipped jar is a self-contained shaded uber-jar (relocated
#     hadoop-aws + aws-sdk); the single-file copy needs no extra hadoop libs.
#     Glob the version (S3 plugins are not scala-versioned).
# Runs as root (before USER flink) so it can write under /opt/flink/plugins.
RUN mkdir -p /opt/flink/plugins/s3-fs-hadoop && \
    cp /opt/flink/opt/flink-s3-fs-hadoop-*.jar /opt/flink/plugins/s3-fs-hadoop/

# The official Flink image already runs as the non-root `flink` user (uid 9999),
# matching the FlinkDeployment podTemplate securityContext. No CMD/ENTRYPOINT
# override — the operator supplies the standalone-job command + args at submit.
USER flink
