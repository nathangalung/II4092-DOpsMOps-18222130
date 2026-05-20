# License Compliance Register

**Last updated:** 2026-04-24
**Thesis:** Pengembangan Arsitektur DataOps dan MLOps Terintegrasi pada Kubernetes dengan Pemanfaatan Open Source Tools
**Constraint:** Every tool must carry an OSI-approved open-source license.

## Summary

- **Total tools:** 65
- **OSI-approved:** 65/65 (100%)
- **License families:** Apache-2.0 (53), AGPL-3.0 (6), MIT (3), BSD-3-Clause (1), MPL-2.0 (1), GPL-2.0-only (1)
- **Tri-licensed tools replaced:** Redis 8 → Valkey 9 (BSD-3-Clause), Elasticsearch 9 → OpenSearch 2.19 (Apache-2.0)
- **Non-OSI tools removed:** HashiCorp Vault BSL-1.1 (replaced by OpenBao, ADR-008), Airbyte ELv2 (replaced by Meltano, ADR-027)

## License Election Policy

All previously tri-licensed tools have been replaced with permissively-licensed Linux Foundation forks:
Redis 8 (RSALv2/SSPL/AGPL) → Valkey 9 (BSD-3-Clause); Elasticsearch 9 (AGPL/SSPL/ELv2) → OpenSearch 2.19 (Apache-2.0).
No tri-license elections remain in the platform.

## Full Register

### Storage

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| PostgreSQL (via CNPG) | ghcr.io/cloudnative-pg/postgresql:18.3 | Apache-2.0 | Yes | CNPG operator Apache-2.0; PG itself is PostgreSQL (OSI-approved) |
| MySQL | Official Images/8.4.8 | GPL-2.0-only | Yes | Oracle Community edition; Universal FOSS Exception applies |
| ClickHouse | clickhouse/clickhouse-server:26.2.7.17 | Apache-2.0 | Yes | Relicensed from Apache-2.0 in 2024; community edition remains Apache-2.0 |
| Altinity Operator | altinity/clickhouse-operator:0.26.2 | Apache-2.0 | Yes | |
| Valkey | valkey/valkey:9.0.3 | BSD-3-Clause | Yes | LF fork of Redis; replaces Redis 8 tri-license (RSALv2/SSPL/AGPL). 15-37% faster, 28% less memory |
| MinIO | pgsty/RELEASE.2026-04-17 | AGPL-3.0-or-later | Yes | pgsty fork created Oct 2025, after April 2025 AGPL relicense; LICENSE is AGPL-3.0-or-later |
| Qdrant | qdrant/qdrant:v1.17.1 | Apache-2.0 | Yes | |
| SpiceDB | authzed/spicedb:v1.51.1 | Apache-2.0 | Yes | |
| LakeFS | treeverse/lakefs:1.80.0 | Apache-2.0 | Yes | |
| Lakekeeper | quay.io/lakekeeper/catalog:0.9.0 | Apache-2.0 | Yes | Rust Iceberg REST catalog |
| Longhorn | longhornio/longhorn-manager:v1.11.1 | Apache-2.0 | Yes | CNCF Graduated |

### Data Ingestion

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| Kafka (via Strimzi) | Strimzi 0.51.0 / Kafka 4.2.0 | Apache-2.0 | Yes | CNCF Graduated |
| Karapace | ghcr.io/aiven-open/karapace:6.1.3 | Apache-2.0 | Yes | |
| Kafka Connect (Debezium) | quay.io/debezium/connect:3.5.0.Final | Apache-2.0 | Yes | |
| kafka-exporter | danielqsj/kafka-exporter:v1.9.0 | Apache-2.0 | Yes | |
| Kafka UI (Kafbat) | ghcr.io/kafbat/kafka-ui:v1.5.0 | Apache-2.0 | Yes | |
| Meltano | meltano/meltano:v3.9.3 | MIT | Yes | Replaces Airbyte ELv2 (ADR-027) |

### Data Processing

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| Apache Airflow | apache/airflow:slim-3.1.8 | Apache-2.0 | Yes | |
| Apache Flink | apache/flink:2.2.0 | Apache-2.0 | Yes | |
| Apache Spark | apache/spark:4.1.1 | Apache-2.0 | Yes | |
| Apache Superset | apache/superset:6.0.0 | Apache-2.0 | Yes | |
| Trino | trinodb/trino:480 | Apache-2.0 | Yes | |
| dbt-clickhouse | ghcr.io/dbt-labs/dbt-clickhouse:1.10.0 | Apache-2.0 | Yes | |
| Great Expectations | Python library (no pod) | Apache-2.0 | Yes | |

### Model Lifecycle

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| MLflow | ghcr.io/mlflow/mlflow:v3.11.1 | Apache-2.0 | Yes | |
| Feast | quay.io/feastdev/feature-server:0.62.0 | Apache-2.0 | Yes | |
| Kubeflow Pipelines | ghcr.io/kubeflow/kfp-api-server:2.16.0 | Apache-2.0 | Yes | |
| Kubeflow Notebooks | ghcr.io/kubeflow/notebook-controller:v1.10.0 | Apache-2.0 | Yes | |
| Kubeflow Trainer | ghcr.io/kubeflow/trainer-controller-manager:v2.1.0 | Apache-2.0 | Yes | |
| Kubeflow Katib | ghcr.io/kubeflow/katib-controller:v0.19.0 | Apache-2.0 | Yes | |

### Model Serving

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| KServe | kserve/kserve-controller:v0.17.0 | Apache-2.0 | Yes | |
| Kueue | registry.k8s.io/kueue/kueue:v0.16.2 | Apache-2.0 | Yes | |

### Observability

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| kube-prometheus-stack | helm 83.6.0 | Apache-2.0 | Yes | Prometheus, Alertmanager, kube-state-metrics, node-exporter |
| Grafana OSS | grafana/grafana:12.4.2 | AGPL-3.0-only | Yes | OSS edition only; Enterprise is proprietary |
| Loki | grafana/loki:3.7.1 | AGPL-3.0-only | Yes | |
| Tempo | grafana/tempo:2.10.4 | AGPL-3.0-only | Yes | |
| Alloy | grafana/alloy | Apache-2.0 | Yes | |
| OTel Operator + Collector | helm 0.110.0 | Apache-2.0 | Yes | CNCF Graduated |
| Evidently | evidently/evidently-service:0.7.21 | Apache-2.0 | Yes | |
| OpenCost | ghcr.io/opencost/opencost:1.119.1 | Apache-2.0 | Yes | CNCF Sandbox |
| Pushgateway | prom/pushgateway:v1.11.2 | Apache-2.0 | Yes | |
| Sloth | ghcr.io/slok/sloth:v0.12.0 | Apache-2.0 | Yes | |
| Pyroscope | grafana/pyroscope:2.0.1 | AGPL-3.0-only | Yes | |

### Security

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| OpenBao | quay.io/openbao/openbao:2.5.3 | MPL-2.0 | Yes | LF fork of Vault; replaces HashiCorp Vault BSL-1.1 (ADR-008) |
| External Secrets Operator | v0.22.x | Apache-2.0 | Yes | |
| Apache APISIX | apache/apisix:3.15.0 | Apache-2.0 | Yes | |
| oauth2-proxy | quay.io/oauth2-proxy/oauth2-proxy:v7.15.2 | MIT | Yes | |
| Dex | ghcr.io/dexidp/dex:v2.45.1 | Apache-2.0 | Yes | |
| cert-manager | quay.io/jetstack/cert-manager:v1.20.0 | Apache-2.0 | Yes | |
| Kyverno | v1.17 | Apache-2.0 | Yes | |
| Cosign | sigstore/cosign:v3.0.3 | Apache-2.0 | Yes | |
| Velero | v1.18.0 | Apache-2.0 | Yes | |
| Chaos Mesh | 2.8.2 | Apache-2.0 | Yes | CNCF Incubating |
| Falco | falcosecurity/falco:0.43.1 | Apache-2.0 | Yes | CNCF Graduated |
| Falcosidekick | falcosecurity/falcosidekick:2.32.1 | Apache-2.0 | Yes | |
| Trivy Operator | aquasecurity/trivy-operator:0.30.1 | Apache-2.0 | Yes | |
| Trivy | aquasecurity/trivy:0.69.3 | Apache-2.0 | Yes | |
| KES | minio/kes | AGPL-3.0-or-later | Yes | MinIO Key Encryption Service |

### GitOps

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| Argo CD | quay.io/argoproj/argocd:v3.3.3 | Apache-2.0 | Yes | CNCF Graduated |
| Argo Rollouts | quay.io/argoproj/argo-rollouts:v1.9.0 | Apache-2.0 | Yes | |
| Gitea | gitea/gitea:1.25.4 | MIT | Yes | |
| Tekton Pipelines | ghcr.io/tektoncd/pipeline/controller:v1.9.0 | Apache-2.0 | Yes | |

### Data Governance

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| DataHub (GMS, Frontend, Upgrade, Actions, Ingestion) | acryldata/datahub-*:v1.5.0.1 | Apache-2.0 | Yes | |
| OpenSearch | opensearchproject/opensearch:2.19.4 | Apache-2.0 | Yes | LF fork of ES; replaces Elasticsearch 9 tri-license (AGPL/SSPL/ELv2). DataHub v1.5 officially supports OpenSearch 2.x |
| OpenLineage | ConfigMap integration | Apache-2.0 | Yes | |

### Common / Service Mesh

| Tool | Image / Chart | SPDX | OSI | Notes |
|------|--------------|------|-----|-------|
| Istio | 1.28.6 | Apache-2.0 | Yes | CNCF Graduated |
| Knative Serving | 1.16.2 | Apache-2.0 | Yes | CNCF Graduated |
| KEDA | 2.19.0 | Apache-2.0 | Yes | CNCF Graduated |

## AGPL-3.0 Obligations

The following tools are deployed under AGPL-3.0-only:

1. **Grafana OSS** (12.4.2)
2. **Loki** (3.7.1)
3. **Tempo** (2.10.4)
4. **Pyroscope** (2.0.1)
5. **KES** (MinIO) — AGPL-3.0-or-later
6. **MinIO** (pgsty/RELEASE.2026-04-17) — AGPL-3.0-or-later

Note: Redis 8 (AGPL elected from tri-license) and Elasticsearch 9 (AGPL elected from tri-license)
were replaced by Valkey 9 (BSD-3-Clause) and OpenSearch 2.19 (Apache-2.0) respectively,
eliminating all tri-license elections from the platform.

**AGPL-3.0 compliance for self-hosted internal deployments:**
- Source code of all AGPL-licensed components is publicly available via their upstream repositories.
- No modifications are made to AGPL-licensed source code; all are deployed as upstream binary releases.
- The platform is a self-hosted internal deployment, not a SaaS offering. AGPL's Section 13 (network interaction clause) applies only if the platform is made available to external users over a network — in that case, source availability must be ensured.
- No AGPL-licensed code is combined with incompatibly-licensed code in a way that would trigger copyleft obligations on the platform's own codebase.

## Tri-Licensed Tools Replaced

| Tool | Former License | Replacement | Rationale |
|------|---------------|-------------|-----------|
| Redis 8 (8.6.1) | RSALv2/SSPL/AGPL-3.0 (tri-license) | Valkey 9.0.3 (BSD-3-Clause) | 15-37% faster throughput, 28% less memory, LF governance, wire-compatible drop-in |
| Elasticsearch 9 (9.3.1) | AGPL-3.0/SSPL/ELv2 (tri-license) | OpenSearch 2.19.4 (Apache-2.0) | 1.6x faster general workloads, DataHub officially supported, ES 9 has analytics bug (#15955), LF governance |

## Non-OSI Tools Removed

| Tool | Former License | Replacement | ADR |
|------|---------------|-------------|-----|
| HashiCorp Vault | BUSL-1.1 (source-available) | OpenBao 2.5.3 (MPL-2.0) | ADR-008 |
| Airbyte | Elastic-2.0 (source-available) | Meltano v3.9.3 (MIT) | ADR-027 |

## Verification

To verify any license claim in this register:
```bash
# Check upstream LICENSE file directly
curl -sL https://raw.githubusercontent.com/<org>/<repo>/main/LICENSE | head -5
```

All SPDX identifiers follow the [SPDX License List v3.25](https://spdx.org/licenses/).
