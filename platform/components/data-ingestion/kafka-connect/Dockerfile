# Custom Strimzi Kafka Connect image - Debezium-PostgreSQL CDC + Iceberg sink
# Replaces the in-cluster KafkaConnect `.spec.build` path. Strimzi 1.0.0's build
# runs rootless buildah, which calls unshare(CLONE_NEWUSER) - blocked by this
# single-node cluster's hardened kernel/PSA ("Operation not permitted"), so the
# connect-build pod never produced the image and the KafkaConnect never reached
# Ready. Pre-building externally and referencing via `KafkaConnect.spec.image` is
# the Strimzi-documented alternative (proc-deploy-kafka-connect-new-image-from-base).
#
# Plugins are fetched + extracted ON THE HOST by `make build-kafka-connect` and
# COPYed in here. In-build network egress is unreliable on this network - apk /
# package-CDN mirrors are blocked even with `docker build --network=host` (the
# #300 BuildKit-DNS-isolation pattern), so all downloading is done host-side
# where egress works (it already pulls images + runs seed-gitea). This image
# therefore needs ZERO in-build network.
#
# Build (load-gated - run ALONE on the single HDD):  make build-kafka-connect
# In-cluster the image is pulled as
#   registry.platform-registry.svc.cluster.local:5000/kafka-connect:debezium-3.0.7-iceberg-0.6.19
# (k3s containerd maps the hostPort-5000 registry to that Service DNS).
# Pins: Debezium 3.0.7.Final, Iceberg connect 0.6.19 (April 2026 cap respected).
FROM quay.io/strimzi/kafka:1.0.0-kafka-4.2.0
USER root:root
# `plugins/` is populated host-side by the Makefile target immediately before
# build: plugins/debezium-postgres/*.jar + plugins/iceberg-kafka-connect/**.jar.
# Strimzi Kafka Connect loads every plugin found under /opt/kafka/plugins
# (recursively) at worker startup.
COPY plugins/ /opt/kafka/plugins/
# Restore Strimzi's default non-root Connect user for runtime (the hardened
# connectContainer securityContext also sets runAsNonRoot + drops ALL caps).
USER 1001
