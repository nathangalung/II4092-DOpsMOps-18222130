# Platform tool versions — 2026-04-21 (post-audit + tool expansion + Phase C + post-audit closure)

All versions are 2026 releases (ADR-006).  For removed / added tools see
`platform/DECISIONS.md` (ADR-005).

## Storage
postgres;           via CloudNativePG 1.29.0 (image ghcr.io/cloudnative-pg/postgresql:18.3-trixie, 3-replica Cluster CR)
mysql;              Official Images/8.4.8-oraclelinux9 (KFP metadata only; single replica)
clickhouse;         via Altinity Operator 0.26.2 (image clickhouse/clickhouse-server:26.2.7.17-jammy, 2-shard × 2-replica CHI + 3-node Keeper quorum)
valkey;             valkey/valkey:9.0.3 (BSD-3-Clause, LF governance; replaces Redis 8.6.1 AGPL tri-license. 15-37% faster, 28% less memory, wire-compatible RESP protocol)
minio;              pgsty/RELEASE.2026-04-17T00-00-00Z (community fork — minio/minio archived Feb 2026); KMS SSE enabled; ExternalSecret-backed credentials
qdrant;             qdrant/v1.17.1
spicedb;            authzed/v1.51.1 (PostgreSQL-backed datastore; 2 replicas; schema loaded by Job)
lakefs;             treeverse/1.80.0
lakekeeper;         quay.io/lakekeeper/catalog:0.9.0 (Rust Iceberg REST catalog; remote signing for MinIO. Pre-2026 release — violates ADR-006 2026-minimum rule. Task #25 defers crossing the 0.11.0 minor boundary as architectural exception: 0.11.0 (2026-01-01, GA) flips the S3 default credential-vending from `remote-signing` → `vended-credentials` when clients omit the `access-delegation` header, removes the deprecated `undrop_tabular` / `project_by_id` endpoints, re-shapes the permissions/check warehouse-ID contract, and renames the create-warehouse response field `id` → `warehouse_id`. Crossing the boundary requires auditing every Iceberg REST client (Trino, Spark, dbt, kafka-connect iceberg-sink) for access-delegation header behaviour and API-contract compatibility, plus persisting a `sts-enabled=false` + `remote-signing-enabled=true` storage-profile per warehouse via upstream PR #1518's credential-control flags. The use-case-side iceberg-sink init Job already sends both forward-compat flags (see `<use-case>/manifests/base/connectors/iceberg-sink.yaml`), so the server-side config is provisionally ready; the open work is the client-side header/API audit. Current upstream: 0.11.5 (patch) / 0.12.0 (minor) — both past the default-flip boundary. Tracked as 2026-rule exception in AUDIT_FINAL §25 and §34.)
longhorn;           v1.11.1 — default StorageClass; 3 additional profiles; Velero-integrated backups

## Ingestion
kafka;              via Strimzi 0.51.0 (Kafka 4.2.0, 3-broker KRaft, RF=3, min.insync=2)
karapace;           ghcr.io/aiven-open/karapace:6.1.3
kafka-connect;      quay.io/debezium/connect:3.5.0.Final
kafka-exporter;     danielqsj/kafka-exporter:v1.9.0 (no 2026 GA yet; v1.9.0 from 2025-02-17 is current upstream HEAD — ADR-006 exception by necessity)
kafka-ui;           ghcr.io/kafbat/kafka-ui:v1.5.0 (2026-04-20 — adds MessagePack serde, Swagger UI, consumer-lag live updates, CSV export, connector consumer-group integration; additive over v1.4.2)
meltano;            meltano/meltano:v3.9.3-python3.11-slim (MIT; replaces Airbyte ELv2) — schedule-driven ELT for 550+ Singer connectors; Airflow KubernetesPodOperator orchestration; external Postgres (CNPG `meltano` DB) + MinIO `meltano-state`

## Data processing
airflow;            apache/slim-3.1.8-python3.13 (primary orchestrator — ADR-003; OpenLineage → DataHub)
flink;              apache/2.2.0-scala_2.12-java21 (OpenLineage listener env → DataHub GMS)
spark;              apache/4.1.1-scala2.13-java21-python3-r-ubuntu (OpenLineage spark_2.13:1.26.0; Iceberg catalog via Lakekeeper REST; OTel env)
superset;           apache/superset:6.0.0
trino;              trinodb/trino:480
dbt;                ghcr.io/dbt-labs/dbt-clickhouse:1.10.0 (2026-02-16 — dbt-core 1.10 support; py≥3.10; PyPI publishing via Trusted Publisher; drops py3.9, adds py3.13. Upstream now ClickHouse/dbt-clickhouse — verify `dbt-labs/` ghcr image path still mirrored, else switch to `clickhouse/dbt-clickhouse:1.10.0`)
great-expectations; Python library in Airflow (no pod). Writes routed via features.quality_write_buffer → gold.data_quality_expectations MV (fixes Views-not-writable bug)

## Model lifecycle
mlflow;             ghcr.io/mlflow/mlflow:v3.11.1
feast;              quay.io/feastdev/feature-server:0.62.0; feature_store.yaml rendered by init container from Vault (no plaintext POSTGRES_PASSWORD)
kubeflow-pipelines; ghcr.io/kubeflow/kfp-api-server:2.16.0 (bundled Argo Workflows controller handles workflows.argoproj.io cluster-wide)
kubeflow-notebooks; ghcr.io/kubeflow/kubeflow/notebook-controller:v1.10.0
kubeflow-trainer;   ghcr.io/kubeflow/trainer/trainer-controller-manager:v2.1.0
kubeflow-katib;     ghcr.io/kubeflow/katib-controller:v0.19.0
  REMOVED: kuberay       — Ray not used (traditional FLAML tabular ML only, ADR-005)
  REMOVED: label-studio  — no human labelling workflow (tabular supervised only, ADR-005)

## Model serving
kserve;             kserve/kserve-controller:v0.17.0
  ClusterServingRuntimes kept: kserve-mlserver (MLflow path), kserve-lgbserver, kserve-sklearnserver, kserve-xgbserver (FLAML palette fallbacks)
  REMOVED at audit (ADR-025, 2026-04-21): kserve-huggingfaceserver[-multinode], kserve-paddleserver, kserve-pmmlserver, kserve-predictiveserver, kserve-tensorflow-serving, kserve-torchserve, kserve-tritonserver, 8 × LLMInferenceServiceConfig
  llmisvc-controller / localmodel-controller: orphan scale-to-0 patches removed — the Deployments DID exist (bundled by upstream KServe v0.17 single-file `kserve.yaml` install applied 2026-04-08) and ran 12d with ~97-98 restarts before being deleted 2026-04-21 alongside their ServiceAccounts, Services, ClusterRoles/Bindings, Leases, and CRDs (llminferenceservices, llminferenceserviceconfigs, localmodelcaches, localmodelnodegroups). Kustomize/ArgoCD cannot prune what it didn't manage — hence the manual cleanup. See AUDIT_FINAL_2026-04-21.md §16.1.
kueue;              registry.k8s.io/kueue/kueue:v0.16.2

## Observability (ADR-010)
kube-prometheus-stack; helm 83.6.0 (Prometheus v3.6, Operator v0.90.1, 2026-03-25) — Prometheus Operator + Alertmanager (HA 3) + kube-state-metrics + node-exporter. Upstream v0.91 is scheduled 2026-04-29; bump to 83.7+ once it ships.
grafana;            grafana/12.4.2-ubuntu (OIDC via Dex, PVC storage, admin password from Vault)
loki;               grafana/3.7.1 (MinIO chunks, 30d retention, WAL on longhorn PVC)
tempo;              grafana/tempo:2.10.4 (helm 1.24.0, 2026-02-25) — OTLP trace backend on MinIO S3 `tempo-traces`; metrics_generator emits span-metrics + service-graphs to kube-prometheus-stack; sole Grafana traces datasource (Jaeger v2 removed 2026-04-21, ADR-010 / ADR-025)
alloy;              grafana/alloy (DaemonSet)
opentelemetry-operator; helm 0.110.0 (2026-04, appVersion 0.148.0 — Collector 0.148.0 gateway + agent DaemonSet + Auto-instrumentation CRD; container tag pinned in both chart default AND CR `spec.image` to stay in lockstep with operator-manager appVersion)
evidently;          evidently/evidently-service:0.7.21 (workspace on longhorn PVC)
opencost;           ghcr.io/opencost/opencost:1.119.1
pushgateway;        prom/v1.11.2 (no 2026 GA yet; v1.11.2 from 2025-10-30 is current upstream HEAD — ADR-006 exception by necessity)
  REMOVED: prometheus-adapter — ADR-026 (2026-04-21) retired the adapter entirely after migrating its last HPA consumer (gateway HTTP-RPS) to KEDA. KEDA 2.19.0 is now the single metrics-apiserver for custom/external HPA sources. Drove the decision: v0.12.0 (2024-05-17 HEAD) fails the repo-wide 2026-minimum-release rule and the only live consumer was a single HPA.
sloth;              ghcr.io/slok/sloth:v0.12.0 (helm 0.12.0, 2026-01-22) — SLO-as-code controller; PrometheusServiceLevel CR → MWMBR recording + alerting rules with `release: kube-prometheus-stack` label
pyroscope;          grafana/pyroscope:2.0.1 (chart 2.0.0, 2026-04-20) — continuous profiling (LGTM++); eBPF profiler DaemonSet + MinIO S3 `pyroscope-profiles`; 14d retention; Vault-backed S3 creds

## Security (ADR-008, ADR-009, ADR-012, ADR-014)
vault;              quay.io/openbao/openbao:2.5.3 (MPL-2.0, LF fork of HashiCorp Vault; HA Raft, 3 replicas; bootstrap Job seeds platform secrets. Migrated from hashicorp/vault:1.21.5 BSL-1.1 → OpenBao MPL-2.0 for thesis open-source compliance)
external-secrets;   v0.22.x (helm 2.3.0, 2026-04-13) — ClusterSecretStore `platform-vault`
apisix;             apache/apisix:3.15.0-debian (TLS 1.3 on :9443, HTTP/3, cert from platform-ca; OIDC via Dex)
oauth2-proxy;       quay.io/oauth2-proxy/oauth2-proxy:v7.15.2
dex;                ghcr.io/dexidp/dex:v2.45.1 (single OIDC source)
cert-manager;       quay.io/jetstack/cert-manager-controller:v1.20.0 (2026-03-09); ClusterIssuers platform-ca + letsencrypt-{staging,prod}
kyverno;            v1.17 (CEL-based engine, 2026-02-02) — policies + auto-default-deny-networkpolicy GeneratingPolicy
cosign;             v3.0.3 — keyless Fulcio signing in Tekton, verified at admission by Kyverno
velero;             v1.18.0 + velero-plugin-for-aws v1.14.0 (2026-03-06) — Kopia uploader; daily full + hourly data-namespace snapshots to MinIO `velero-backups`. Plugin bumped from v1.12.1 (2025-05-19) to satisfy 2026-minimum rule; v1.13.x/v1.14.x release notes are purely Golang toolchain bumps (no plugin API change).
chaos-mesh;         2.8.2 — PodChaos / NetworkChaos / IOChaos / StressChaos / TimeChaos
falco;              falcosecurity/falco-no-driver:0.43.1 (helm 6.0.6, 2026-02-18) — runtime security DaemonSet via modern eBPF driver; falcosidekick 2.32.1 fans alerts to Alertmanager + Loki + MinIO `falco-audit`
trivy-operator;     aquasecurity/trivy-operator:0.30.1 + trivy:0.69.3 (helm 0.32.1, 2026-03-13) — VulnerabilityReport / ConfigAuditReport / ExposedSecretReport / InfraAssessmentReport / SbomReport CRs; Trivy server on longhorn PVC for DB caching

## GitOps (ADR-003, ADR-005)
argo-cd;            quay.io/argoproj/argocd:v3.3.3; AppProject `platform` + ApplicationSet `platform-components` + per-use-case AppProject `<use-case>` (one per registered use-case namespace; see `<use-case>/argocd/` and `<use-case>/docs/CHANGELOG.md`)
argo-rollouts;      quay.io/argoproj/argo-rollouts:v1.9.0 (chart 2.40.9, 2026-03-20) — progressive delivery; Istio traffic routing; AnalysisTemplate `success-rate-p99` (success-rate + p99-latency SLO gates); separate `rollouts.argoproj.io` CRD so no lease contention with KFP's Argo Workflows
  REMOVED: standalone argo-workflows — KFP's bundled controller is the single cluster-wide one (ADR-003)
  REMOVED: flagger — replaced by argo-rollouts (2026-03-20 > flagger v1.42.0 2025-10-16; single-ecosystem alignment with argo-cd)
gitea;              gitea/1.25.4
tekton;             ghcr.io/tektoncd/pipeline/controller:v1.9.0 (added `merge-platform-overlay` task — ADR reconciliation for Kaniko contexts)

## Data governance (ADR-013)
datahub-gms;        acryldata/datahub-gms:v1.5.0.1
datahub-frontend-react; acryldata/datahub-frontend-react:v1.5.0.1
datahub-upgrade;    acryldata/datahub-upgrade:v1.5.0.1
datahub-actions;    acryldata/datahub-actions:v1.5.0.1
opensearch;         opensearchproject/opensearch:2.19.4 (Apache-2.0, LF governance; replaces Elasticsearch 9.3.1 AGPL tri-license. DataHub v1.5 officially supports OpenSearch 2.x via ELASTICSEARCH_SHIM_ENGINE_TYPE=OPENSEARCH_2. Security plugin disabled — internal-only, defended by Istio mTLS + NetworkPolicies)
  REMOVED: neo4j         — Elasticsearch graph impl in DataHub GMS (GRAPH_SERVICE_IMPL=elasticsearch)
openlineage;        Native integration (ConfigMap only); env wired into Airflow, Flink, Spark
datahub-ingestion;  acryldata/datahub-ingestion:v1.5.0.1 — 8 CronJobs (PG, CH, MinIO, Kafka, Airflow, Feast, MLflow, dbt)

## Common / service mesh
istio;              1.28.6 (2026-04-13 patch; PeerAuthentication STRICT mesh-wide, default AuthorizationPolicy deny, DestinationRule TLS 1.3). Minor bump to 1.29+ deferred as Task #26 architectural exception — not a re-render, a forward-port. The vendored `istio-install.yaml` is `istioctl manifest generate` output (label `helm.sh/chart: istio-ingress-1.28.6` is an istioctl signature, not plain `helm template`) with load-bearing post-generate surgical edits: (1) mesh-ConfigMap `extensionProviders` block registering `oauth2-proxy` as `envoyExtAuthzHttp` (L814–830) — required by `action: CUSTOM` AuthorizationPolicies (ADR-024); (2) `accessLogFile: /dev/stdout` + three `tcpKeepalive` blocks (L802, L809, L3196, L3287); (3) sidecar-injector `busybox:1.28` → `busybox:1.36` override (L1693) for ADR-006 compliance. Non-default `--set` inputs (`components.cni.enabled=true`, `values.cni.cniNamespace=kube-system`, `values.gateways.istio-ingressgateway.type=ClusterIP`) must be re-supplied at 1.29.2 but schema-drift across patch versions (cniNamespace rejected at 1.28.5, accepted at 1.28.6) proves the flags are not cross-version stable. Proper path = inventory → regenerate → forward-port each surgical edit → end-to-end verify ext_authz→oauth2-proxy contract. Tracked as 2026-rule exception in AUDIT_FINAL §25.5 and §35.
knative-serving;    1.16.2 (Jan 2025; violates 2026-minimum rule — Task #27 defers the bump). Upstream constraint: "only upgrade by one minor version at a time" (CRD conversion webhooks chain between minors). 1.16 → 1.21 therefore requires 5 staged sync waves (1.16 → 1.17 → 1.18 → 1.19 → 1.20 → 1.21) with verification gates between each; 1.17 is EOL with no 2026 patch so the first hop lands on a non-compliant intermediate. Tracked as 2026-rule exception in AUDIT_FINAL §25. (Prior entry "1.20" was documentation drift — actual tree pin verified via direct read of platform/components/common/knative/knative-serving.yaml.)

## Removed at audit (2026-04-17)
- argo-workflows (standalone, gitops namespace) — KFP bundled controller subsumes it (ADR-003, ADR-005)
- seaweedfs (model-lifecycle)                   — MinIO covers KFP artifacts via minio-service.kubeflow ExternalName (ADR-005)
- metacontroller (model-lifecycle)              — not required in KFP v2 (ADR-005)
- embedded KFP minio + mysql Deployments        — use storage/minio + storage/mysql canonical
- llmisvc-controller / localmodel-controller    — tabular ML only, not LLM
- httpbin demo pod                              — test fixture leftover
- empty namespaces auth / oauth2-proxy / ml-pipeline
- k3s built-in traefik / servicelb — replaced by Istio Gateway + APISIX; disabled via k3s `disable:` flags in `/etc/rancher/k3s/config.yaml` (not coming back). prometheus-adapter also retired in this same audit track by ADR-026 (2026-04-21) — KEDA now serves the custom-metrics APIs.
  - NOTE: metrics-server is INTENTIONALLY RETAINED (previous VERSION.MD revisions incorrectly listed it here). ~31 live HPAs across common / data-governance / data-ingestion / data-processing / gitops / istio-system / knative-serving / model-lifecycle / model-serving still consume `metrics.k8s.io` Resource metrics (CPU / memory utilisation); KEDA provides `external.metrics.k8s.io` only and cannot substitute. `config.yaml` keeps metrics-server enabled with inline comment "metrics-server stays (31 HPAs with Resource metrics still depend on it until HPA-to-KEDA migration is scoped in a follow-up ADR)". No 2026-minimum-release concern — the bundled metrics-server ships with k3s v1.34.6 and is refreshed via k3s upgrades.

## Removed at audit (2026-04-21, ADR-025)
- platform/services/base/deployments/flink-job.yaml          — Deployment deleted; FlinkDeployment CR in each use case (ADR-023) is the canonical stream-processing path
- platform/services/base/deployments/ml-bridge.yaml (Deployment) — rewritten to ship only the Service; Argo Rollout (ADR-016) is the sole pod owner
- per-use-case scale-to-0 placeholder patches (`<use-case>/manifests/base/patches/flink-job.yaml`, `<use-case>/manifests/base/patches/ml-bridge-disable-deployment.yaml`) — deleted along with the target Deployments; per-use-case audit list in `<use-case>/docs/CHANGELOG.md`
- kserve-huggingfaceserver[-multinode], kserve-paddleserver, kserve-pmmlserver, kserve-predictiveserver, kserve-tensorflow-serving, kserve-torchserve, kserve-tritonserver — LLM/GPU/TF/Torch/PMML ClusterServingRuntimes unused by the FLAML palette
- 8 × LLMInferenceServiceConfig CRs                          — templates for an LLMInferenceService subsystem we do not deploy
- flink-job image/replicas/resources overrides in overlays/{generic,local,cloud,local-phase1} — no-ops once the Deployment was gone
- platform/components/observability/jaeger/                  — Jaeger v2 Deployment+Service+PDB+HPA; Tempo is the sole trace backend (ADR-010 / ADR-025). Dropped the `otlp/jaeger` OTel exporter, the Grafana Jaeger datasource, the `JAEGER_ENDPOINT` ConfigMap entry, the Makefile port-forward, the RBAC `jaeger-query` resourceName, and the data-governance shared-ES note. Elasticsearch in data-governance is now DataHub-only.

## Added at audit (2026-04-17)
- Longhorn v1.11.1           — default StorageClass (ADR-007)
- Strimzi 0.51.0             — Kafka operator + 3-broker cluster (ADR-011)
- CloudNativePG 1.29.0       — PG operator + 3-replica cluster with PITR to MinIO (ADR-011)
- Altinity 0.26.2            — ClickHouse operator + 2-shard × 2-replica CHI + Keeper quorum (ADR-011)
- External Secrets Operator  — v0.22.x, ClusterSecretStore backed by Vault (ADR-008)
- Vault HA Raft              — 3-replica StatefulSet with bootstrap Job (ADR-008)
- kube-prometheus-stack 83.6.0 — Prometheus Operator + Alertmanager (ADR-010)
- OpenTelemetry Operator + Collector — gateway + agent + auto-instrumentation (ADR-010, KNF-06)
- Kyverno 1.17               — admission + image-signature policies (ADR-012)
- Cosign v3.0.3              — keyless image signing (ADR-012)
- Velero 1.18.0              — PVC backup + restore to MinIO (ADR-014)
- Chaos Mesh 2.8.2           — chaos engineering (ADR-014, KNF-04 validation)
- ClusterIssuer platform-ca  — internal CA anchored by self-signed root (KNF-07)
- DataHub ingestion CronJobs — 8 sources wired (ADR-013)

## Added at tool expansion (2026-04-19)
- Grafana Tempo 2.10.4        — OTLP trace backend (MinIO S3); sole trace backend after Jaeger v2 removal 2026-04-21; LGTM-stack (ADR-010 / ADR-025)
- Falco 0.43.1 + falcosidekick 2.32.1 — runtime syscall detection via modern eBPF; alerts to Alertmanager/Loki/MinIO (ADR-014)
- Meltano v3.9.3 (MIT)        — schedule-driven ELT for 550+ Singer connectors; replaces Airbyte (ELv2 — not OSI-approved open source)
- Sloth 0.12.0                — SLO-as-code; PrometheusServiceLevel CR → MWMBR rule generator (ADR-010)
- Trivy Operator 0.31.0       — continuous CVE / config / SBOM / secret scanning exposed as CRs + Prom metrics (ADR-014)

## Added at Phase C (2026-04-20)
- Pyroscope 2.0.1 (chart 2.0.0)  — continuous profiling, completes LGTM++ observability stack (ADR-010 amendment); eBPF DaemonSet + MinIO S3; Vault-backed creds
- Argo Rollouts v1.9.0 (chart 2.40.9) — progressive delivery with Istio traffic routing; AnalysisTemplate SLO gates; supersedes Flagger (ADR-016)
- Alloy OTLP receiver         — ports 4317/4318 added; Alloy is now unified telemetry edge (logs + traces → Tempo + metrics → kube-prometheus-stack); migration path to retire standalone OTel Collector agent DaemonSet (ADR-010)
- per-use-case retrain-on-drift Argo CronWorkflow — every 6h queries `gold.drift_metrics`; triggers KFP `retraining_pipeline` on PSI > 0.2 / KS > 0.15; pushes exemplars to Pushgateway (ADR-017; use-case scope; concrete CronWorkflow name + thresholds per `<use-case>/docs/CHANGELOG.md`)

## Bug fixes (2026-04-20)
- GE analyzer writes routed via Null-engine `features.quality_write_buffer` → `features.data_quality_expectations_mv` MV → `gold.data_quality_expectations` (Views are read-only — prior code INSERTed into a View)
- workflow-controller Deployment: added `limits: {cpu: 1000m, memory: 1Gi}` (Kyverno `require-resource-limits` was failing on missing limits block)
- app-of-apps `platform` AppProject sourceRepos extended: argoproj helm repo, Apache Flink downloads, Kubeflow Spark Operator repo (were missing → ArgoCD rejected their Applications)

## Post-audit closure (2026-04-21) — P0 fixes, P1 security hardening, P2 polish

> Note on phase naming: the AUDIT §7 action plan reserves "Phase D" for the
> storage-consolidation track (CHK, Strimzi KafkaNodePool, CNPG migration,
> Longhorn decision). The landings below are audit-recommendation closures
> out-of-phase, not that storage migration. Tracked here as "post-audit
> closure" to avoid the collision.

### P0 — Production blockers
- Kyverno ValidatingPolicies (`require-resource-limits`, `require-read-only-root-filesystem`, `disallow-privileged`, `require-probes`, `require-runAsNonRoot`) now exempt `cnpg-system` in `excludeResourceRules.namespaces` (ADR-019). Fixes CNPG backup pod 46-restart loop.
- Kyverno `ImageValidatingPolicy verify-platform-images-cosign` `matchImageReferences` scoped to internal Gitea registry (`gitea.gitops.svc.cluster.local/platform/*`, `gitea.gitops.svc.cluster.local/use-case-*/*`, `localhost:5000/*`) + Tekton SA identity `system:serviceaccount:gitops:tekton-cosign-signer` (ADR-020). Stops admission-reject of public community images. Per-use-case registry pattern appendices live in `<use-case>/docs/CHANGELOG.md`.
- Use-case namespaces with `istio-injection: disabled` added to the Kyverno ADR-009 opt-out allowlist via use-case overlay patches (without the patch, namespace UPDATE is rejected). Per-use-case patch list in `<use-case>/docs/CHANGELOG.md`.
- Katib `flaml-automl-hpo` Experiment `END_DATE` bumped `2026-04-14` → `2026-04-20` (thesis-viva demo window).

### P0 — Domain SLOs (use-case owned, per ADR-021)
- Per-use-case Sloth `PrometheusServiceLevel` CRs at `<use-case>/manifests/base/observability/slos-<use-case>.yaml` (typically 3 per use-case: prediction freshness, pipeline lag, model freshness). Concrete CR names + targets in `<use-case>/docs/CHANGELOG.md`.

### P0 — Autoscaling reshaped (ADR-022)
- Per-use-case KEDA `ScaledObject` set at `<use-case>/manifests/base/scaling/scaledobjects.yaml` with native `kafka` triggers (one ScaledObject per stream-consuming Deployment). Topic names, lag thresholds, and replica bounds in `<use-case>/docs/CHANGELOG.md`.
- Per-use-case `<use-case>/manifests/base/hpa/autoscaling.yaml` collapses to an explanation comment: `feature-engine-hpa` DELETED (KEDA + HPA collision); `gateway-hpa` DELETED under ADR-026 (2026-04-21) along with prometheus-adapter — replaced by a `gateway-http-rps` KEDA `ScaledObject` (prometheus + cpu + memory triggers). Remaining HPAs (CPU-only, adapter-independent): `rest-collector-hpa`, `dashboard-backend-hpa`.

### P0 — Stream runtime reshaped (ADR-023)
- Per-use-case `<use-case>/manifests/base/flink/flinkdeployment.yaml` — `flink.apache.org/v1beta1 FlinkDeployment` CR (Flink 2.2.0, application mode, OpenLineage listener, single JM metrics reporter on `:9249`). Image, jarURI, entryClass, checkpoint path, ExternalSecret name, RBAC scope are use-case-specific — see `<use-case>/docs/CHANGELOG.md` and `<use-case>/docs/ADRS.md` ADR-023.

### P1 — Security hardening (ADR-024)
- Per-use-case Istio `AuthorizationPolicy` pair at `<use-case>/manifests/base/authorization/edge-authz.yaml` (DENY admin/internal/debug paths; ALLOW public API + healthz + metrics; CIDR-scoped dashboard).
- Per-use-case `<use-case>/manifests/base/network-policies.yaml` rewritten with per-pod allowlists (replacing prior coarse "namespace → all pods" rules), `allow-istio-control-plane-to-gateway`, and Prometheus port 9249 (Flink reporter). Concrete selector lists in `<use-case>/docs/CHANGELOG.md`.

### P1 — Progressive delivery on ml-bridge (ADR-016 use-case binding)
- Per-use-case `<use-case>/manifests/base/rollouts/ml-bridge-rollout.yaml` — `argoproj.io/v1alpha1 Rollout` + local `AnalysisTemplate` (canary 20% → analyze → 50% → analyze → 100%; SLO gates: success-rate ≥ 99%, p99 ≤ 500ms).

### P2 — Resilience experiments (thesis §4.5 KNF-11)
- Per-use-case `<use-case>/manifests/base/chaos/resilience-experiments.yaml` — 3 Chaos Mesh `Schedule` CRs (gateway network loss, feature-cache pod-kill, ml-bridge → MLflow latency) + per-use-case game-day `Workflow` for manual thesis-viva demo. Schedules + selectors in `<use-case>/docs/CHANGELOG.md`.

### P2 — OpenLineage emission (ADR-018)
- Per-use-case lakehouse DAG (`<use-case>/dags/<use-case>_lakehouse_dag.py`) emits manual OpenLineage `RunEvent`s from 4 PythonOperator callables (LakeFS branch create / merge / delete + Trino QC). Custom run facet `<use-case>_qc` carries domain row-count + coverage metrics.
- Events POST to DataHub GMS via `OPENLINEAGE_URL` env. Flink / Spark continue to use native OL listeners; dbt uses its own OL provider. No double-counting.

### P2 — Policy cross-references in kustomization
- Per-use-case `<use-case>/manifests/base/kustomization.yaml` registers the new resources (SLOs, ScaledObjects, FlinkDeployment, Rollout, chaos schedules, edge AuthZ). Concrete resource list per use-case in `<use-case>/docs/CHANGELOG.md`.
