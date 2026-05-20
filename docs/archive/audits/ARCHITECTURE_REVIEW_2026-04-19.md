# Architecture Review — DataOps/MLOps Platform on Kubernetes

**Thesis:** *Pengembangan Arsitektur DataOps dan MLOps Terintegrasi pada Kubernetes dengan Pemanfaatan Open Source Tools: Studi Kasus Jual Beli Saham dan Kripto*
**Review date:** 2026-04-19
**Reviewer:** Architecture audit — cluster `kubectl` state vs `platform/`, `use-case-crypto/`, `materials/`
**Verdict:** **NOT PRODUCTION-READY; NOT THESIS-DEFENSIBLE AS-IS.** The platform design is ambitious and largely coherent on paper, but the live cluster diverges from the design in ways that invalidate three of the four Research Questions. Fix the P0 items before any defense or demo.

---

## 0. Executive Scorecard

| Dimension | Design intent | Live cluster | Gap |
|---|---|---|---|
| Pods running healthy | ~180 across 25 namespaces | ~150 Running, ~8 CrashLoop/Error, ~12 never-scheduled | **P0** |
| Ingest → Serving E2E | CoinGecko/DeFiLlama/FearGreed → Kafka → Flink → ClickHouse → Feast → KServe | Terminates at ClickHouse; **no InferenceService, no trainer, no drift** | **P0 (breaks RQ2)** |
| Security posture | STRICT mTLS mesh-wide, Kyverno admission, Vault-backed secrets, Falco runtime | mTLS only in `knative-serving`+`security`; Kyverno has zero policies; Vault pod not Ready; Falco absent | **P0 (breaks RQ3)** |
| Observability | Prom+Loki+Tempo+OTel+OpenCost+HPA on Prom metrics | Prom/Loki/Tempo/OTel OK; **prometheus-adapter missing → HPA blind**; OpenCost installed but unverified | **P1** |
| Storage & DR | Longhorn replicated PVs + Velero + Chaos Mesh | Default SC is `local-path`; Longhorn **never installed** (ns stuck Terminating 47h); Velero + Chaos Mesh not deployed | **P0 (breaks RQ3/RQ4)** |
| GitOps | ArgoCD app-of-apps + Tekton pipelines | ArgoCD installed but **zero Applications**; `crypto-use-case` Application never applied | **P0 (breaks RQ1)** |
| Boundary hygiene | `platform/` domain-agnostic, `use-case-crypto/` overrides | One crypto DAG leaks into `platform/components/data-processing/airflow/dags/` | **P1** |
| Thesis scope (Bab 1) | Both **saham** + **kripto** | `use-case-stock/` does not exist | **P0 (breaks Batasan Masalah)** |

**Overall readiness:** Design 7/10 · Implementation 4/10 · Evidence for thesis claims 3/10.

---

## 1. Cluster State By Namespace

Enumerated from live `kubectl` at review time. Only notable findings listed.

### 1.1 Control / Infrastructure

| Namespace | State | Notes |
|---|---|---|
| `kube-system` | OK | k3s built-in metrics-server healthy (serves `v1beta1.metrics.k8s.io`). Traefik present but not used (APISIX is primary). |
| `istio-system` | OK | Pilot, ingress gateway Running. **BUT**: `istio-injection=enabled` set on only `knative-serving` and `security`. Data plane namespaces (`use-case-crypto`, `model-lifecycle`, `model-serving`, `data-ingest`, `data-processing`, `mlops`) have **`istio-injection=disabled`** — so ADR-009's "STRICT mTLS mesh-wide" claim is **false in production**. |
| `knative-serving` | OK | Serving + Activator + Autoscaler Running. No KServe InferenceServices exist to exercise it end-to-end. |
| `argocd` | Degraded | Controllers Running; `kubectl get applications -A` returns **No resources found**. `use-case-crypto/argocd/application.yaml` has never been `kubectl apply`-ed. |
| `tekton-pipelines` | OK | Controller + webhook + chains Running. Only `el-crypto-crypto-build-listener` triggered in use-case ns. |
| `cert-manager` | OK | ClusterIssuers configured. |
| `kyverno` | **Empty** | Admission controller Running, but `kubectl get cpol,pol -A` returns zero policies. ADR-013's "policy-as-code enforced" is aspirational. |

### 1.2 Security & Secrets

| Namespace | State | Notes |
|---|---|---|
| `vault` | **CrashLoop / NotReady** | `vault-0` readiness probe fails because image `hashicorp/vault:1.21.x` ships without `jq`, and the probe shells `vault status -format=json \| jq -e`. Remediation in `platform/REMEDIATION_RUNBOOK.md §10.1` is written but not applied. External Secrets Operator cannot hydrate secrets while Vault is Down. |
| `external-secrets` | OK-idle | ESO Running but `ClusterSecretStore` points at Vault → currently failing. Downstream: any pod expecting a synced secret either has a stale copy or is using hard-coded values. |
| `security` | Partial | SpiceDB Running (model loaded); **Falco not deployed**; **Trivy Operator not deployed**; **Cosign verifying webhook not wired**. |
| `kes` | Not deployed | Key Encryption Service for MinIO planned but absent. |

### 1.3 Observability

| Namespace | State | Notes |
|---|---|---|
| `observability` | Mostly OK | kube-prometheus-stack (Prom, Alertmanager, Grafana), Loki, Tempo, Jaeger, Alloy, OpenTelemetry Collector, Sloth, Pushgateway, OpenCost all Running. |
| `observability` | **Broken** | `prometheus-adapter` **never installed**. APIServices `v1beta1.custom.metrics.k8s.io` and `v1beta1.external.metrics.k8s.io` have shown `False (MissingEndpoints)` for **7d7h**. Consequence: every HPA in the cluster is effectively blind to custom/external metrics; crypto feature-engine's 2-replica HPA is actually scaling on CPU only. |

### 1.4 Storage

| Namespace | State | Notes |
|---|---|---|
| `minio` | OK | Operator + tenant Running. Bucket layout matches LakeFS/Iceberg intent. |
| `longhorn-system` | **Stuck Terminating 47h** | Namespace was deleted but finalizers blocked by the two stale custom/external metrics APIServices above. Once prometheus-adapter is installed (or those APIServices are deleted), termination will complete. **No Longhorn is actually running** — default StorageClass is `local-path` (rancher.io/local-path). Design's replicated PV assumption is false on this single-node k3s. |

### 1.5 Data Plane — Persistence

| Namespace | State | Notes |
|---|---|---|
| `postgres` | OK | CloudNativePG cluster `pg-shared` 1 primary + 1 replica Running; used by Airflow, MLflow, Superset, DataHub, Feast registry. |
| `mysql` | OK | Single instance. Used only by legacy Superset dep check — candidate for removal (ADR-candidate). |
| `clickhouse` | OK | Altinity operator Running; `chi-analytics` 2 shards 1 replica. Bronze/silver/gold schemas created. |
| `redis` | OK | Used by Feast online store, feature-cache. |
| `qdrant` | OK | HNSW index for embeddings (vector-embedding cronjob). |
| `lakefs` | OK | Backed by MinIO. Used by crypto lakehouse DAG. |
| `lakekeeper` | OK | Iceberg REST catalog — verified serving; Trino + Spark configured as clients. |

### 1.6 Data Plane — Ingestion / Streaming / Processing

| Namespace | State | Notes |
|---|---|---|
| `kafka` | OK | Strimzi operator + KRaft cluster `platform-kafka` Running; Karapace (schema registry) Running; Kafka Connect Running with source/sink connectors registered. |
| `kafka-dev` | Redundant | Older Bitnami-chart Kafka still deployed. **Dual Kafka** = both carry topics; risk of publish/consume skew. ADR needed to consolidate on Strimzi and decommission. |
| `flink` | OK | Flink Operator Running; `crypto-features` FlinkDeployment Running (1 JM + 2 TM). |
| `spark` | OK | Spark Operator Running; batch jobs triggered via Airflow. |
| `data-ingest` | Mixed | Airbyte Running (used for static reference data). Several collector deployments live in `use-case-crypto` instead (intentional per boundary). |
| `data-processing` | OK | Airflow webserver + scheduler + 3 workers Running, Triggerer Running, DAGs loaded (from git-sync). One DAG `crypto_hourly_features.py` leaks into this namespace via `platform/components/…/airflow/dags/` — **boundary violation**. |
| `data-quality` | OK | Great Expectations runner + OpenLineage marquez Running. Evidently deployment exists but no drift jobs scheduled. |
| `data-catalog` | OK | DataHub GMS + frontend + actions Running; ingestions emitting from Airflow OpenLineage. |

### 1.7 ML Plane

| Namespace | State | Notes |
|---|---|---|
| `mlops` | Partial | MLflow tracking + model registry Running; Feast registry + online + offline components Running; **Kubeflow Pipelines API Server NotReady (image pull)**; Kubeflow Trainer + Katib Running; Metadata + Notebooks Running. Orphan `workflow-controller` from a prior KFP reinstall present — see REMEDIATION §10.5. |
| `model-lifecycle` | **Empty for crypto** | Templates exist in `platform/services/{trainer,drift,retraining,scoring}`, but **no crypto overlay has been applied**. No trainer CronWorkflow, no drift job, no retraining trigger. RQ2 cannot be validated. |
| `model-serving` | **Empty for crypto** | KServe control plane Running; **zero InferenceService objects**. No serving path exists. RQ2 cannot be validated. |
| `feature-store` | OK | Feast push/materialization pods Running; registry pointed at postgres. Crypto features defined in `use-case-crypto/feast/`; materialization CronJob absent (only declaration). |
| `labeling` | Not deployed | Label Studio planned; no workload. Acceptable if supervised labeling is out-of-scope. |
| `experimentation` | OK | GrowthBook Running. No feature flags referenced from serving (because serving is absent). |

### 1.8 Use-Case Namespace

| Namespace | Workload | State | Purpose |
|---|---|---|---|
| `use-case-crypto` | `analyzer` | Running | Post-trade analytics |
| | `dashboard-backend` | Running | API for frontend |
| | `dashboard-frontend` | Running | React UI |
| | `feature-cache` | Running | Redis-fronted hot cache |
| | `feature-engine` (2 replicas) | Running | Computes online features from Kafka |
| | `flink-job` | Running | Streaming aggregations |
| | `gateway` | Running | Request router / model bridge (no model to route to) |
| | `ml-bridge` | Running | Placeholder; expects InferenceService |
| | `rest-collector` | Running | Pulls from REST endpoints |
| | `validator` | Running | Schema + GE validation before Kafka topic |
| | `websocket-collector` | Running | Streams live ticks from exchange WS |
| | `el-crypto-crypto-build-listener` | Running | Tekton EventListener for image builds |
| | CronJobs: `coingecko` (15 * * * *), `defillama` (30 */6 * * *), `feargreed` (0 * * * *), `source` (*/5 * * * *), `vector-embedding` (*/5 * * * *) | Active | Source ingestion |

**Use-case gap:** no `trainer`, `drift`, `retraining`, `scoring`, `inference-engine`, `materialization` overlay — so the ML half of the pipeline is unwired.

### 1.9 GitOps / CI

| Namespace | State | Notes |
|---|---|---|
| `gitea` | OK | Source of truth for git-sync (Airflow DAGs) + ArgoCD (if it were wired). |
| `argocd` | Empty | See §1.1. |
| `tekton-pipelines` | OK | One pipeline wired (crypto image build). No pipeline for platform component upgrades. |

### 1.10 Scheduling / Batch

| Namespace | State | Notes |
|---|---|---|
| `kueue-system` | OK | Kueue Running; **zero ClusterQueue / LocalQueue objects** — so batch jobs currently bypass Kueue and compete directly for node resources. |

---

## 2. Tool Inventory — KEEP / ADD / REMOVE

Traceable to `platform/DECISIONS.md` ADR-001…ADR-014 and thesis KNF (Kebutuhan Non-Fungsional).

### 2.1 KEEP (validated against use case + ADRs)

| Layer | Tool | Why keep |
|---|---|---|
| Orchestration | k3s, Istio, Knative, ArgoCD, Tekton, Kyverno (once policies exist) | Control-plane KNF-3 (portability) |
| Ingest | Airbyte, Kafka Connect, WebSocket collectors | Covers both reference + streaming |
| Streaming | **Strimzi Kafka** + Karapace | Schema-first contracts (ADR-012) |
| Processing | Flink (stream), Spark (batch), Airflow, dbt | Matches RQ1 pipeline-as-code |
| Storage | MinIO, LakeFS, Lakekeeper (Iceberg REST), ClickHouse, PostgreSQL (CNPG), Redis, Qdrant | Lakehouse + OLAP + vector |
| Query | Trino, ClickHouse, Superset | Federated BI (RQ1) |
| Quality | Great Expectations, Evidently, OpenLineage, DataHub | RQ1 (lineage, contracts) |
| ML | Kubeflow Pipelines, Katib, Trainer, MLflow, Feast, KServe | RQ2 end-to-end (once wired) |
| Observability | kube-prometheus-stack, Grafana, Loki, Tempo, Jaeger, OpenTelemetry, Alloy, Sloth, Pushgateway, OpenCost | RQ3 SRE / FinOps |
| Security | Vault, ESO, SpiceDB, APISIX | Secrets, ReBAC, edge |
| FF / experimentation | GrowthBook | RQ2 champion/challenger |
| Scheduling | Kueue | Batch fairness (once queues are declared) |

### 2.2 ADD (gaps that must close before defense)

| Tool | Layer | Justification |
|---|---|---|
| **prometheus-adapter** | Obs | Restores custom/external metrics API → HPA works; unblocks RQ3 scaling claims. Also unsticks `longhorn-system` termination. |
| **Falco + Falcosidekick** | Security | Runtime anomaly detection; ADR-013 claims runtime policy enforcement — currently nothing runtime-watching. |
| **Trivy Operator** | Security | Image vuln scanning in-cluster + VulnerabilityReport CRDs; admission via Kyverno `verifyImages`. |
| **Cosign policy-controller** (or Kyverno `verifyImages` rule) | Security | Supply-chain signature verification (ADR-013). |
| **Velero + restic** | DR | RPO/RTO KNF; no backups exist today. |
| **Chaos Mesh** | Resilience | ADR-014 resilience testing is promised evidence for RQ3/RQ4. |
| **KES (Key Encryption Service)** | Storage security | MinIO SSE-KMS via Vault transit. |
| **InferenceService (KServe) for crypto** | ML serving | THE missing link making E2E pipeline actually end-to-end. |
| **KFP compiled pipelines for crypto (train/eval/register/deploy)** | MLOps | Evidence for RQ2. |
| **Feast materialization CronJob for crypto** | Feature store | Currently only declarations. |
| **Evidently drift CronJob / KServe transformer** | ML monitoring | RQ2 drift evidence. |
| **ClusterQueue + LocalQueue for crypto** | Scheduling | Activates Kueue. |
| **Longhorn (or decision to not use it)** | Storage | Either install on multi-node or formally retire the claim in ADRs + thesis. On single-node k3s, `local-path` is acceptable if scope is narrowed; for HA claim it is not. |
| **NetworkPolicies (namespace-default-deny)** | Security | Currently nothing except istio PeerAuthentication in two namespaces. |
| **Kyverno policies** (namespace quota, required labels, image origin, securityContext baseline) | Security | Controller is installed but idle. |

### 2.3 REMOVE (redundant / unused / superseded)

| Tool | Reason |
|---|---|
| **`kafka-dev` Bitnami Kafka** | Duplicates Strimzi cluster in `kafka`. Consolidate topics to Strimzi, decommission. |
| **`mysql`** | Only Superset legacy dep; Superset already points at PostgreSQL per CNPG. |
| **Traefik in `kube-system`** | APISIX is the chosen edge (ADR-002); Traefik is unused but still admits traffic. |
| **Orphan `workflow-controller`** in `mlops` | Leftover from a prior KFP reinstall (REMEDIATION §10.5). |
| **Label Studio** | Not referenced by any DAG or KFP step and supervised labeling isn't in thesis scope — retire unless a labeling task is added. |
| **Legacy Airflow DAG `crypto_hourly_features.py`** under `platform/components/data-processing/airflow/dags/` | Boundary violation: move into `use-case-crypto/dags/` (the other three crypto DAGs live there correctly). |

### 2.4 DO-NOT-ADD (explicitly declined, to prevent scope creep)

- **Ray Serve / BentoML / Seldon Core** — KServe already chosen (ADR). Adding a second serving runtime doubles ops surface.
- **Apache NiFi** — Airbyte + Kafka Connect + Airflow already cover the ingestion graph; NiFi would duplicate.
- **Prometheus Pushgateway for streaming jobs** — OpenTelemetry metrics pipeline already exists.
- **Jenkins / CircleCI / GitHub Actions self-hosted runner** — Tekton is the chosen CI. Pick one.
- **Prefect / Dagster** — Airflow + KFP already split orchestration per ADR-006. Do not add a third.

---

## 3. P0 / P1 / P2 Findings (with remediation commands)

### 3.1 P0 — blocks thesis defense or demo

**P0-1: Vault pod NotReady (jq missing in image).**
- Evidence: `kubectl -n vault get pod vault-0` → `0/1 Running`, readiness probe `exec [/bin/sh -c vault status -format=json | jq -e …]` failing.
- Impact: External Secrets Operator cannot sync; any subsequent rotation will fail.
- Fix: apply `platform/REMEDIATION_RUNBOOK.md §10.1` — replace probe with `vault status` (exit-code-based) OR switch base image to one with jq; then `kubectl -n vault rollout restart statefulset/vault`.
- Owner: platform.
- ADR ref: ADR-011 (Vault + ESO).

**P0-2: Istio mTLS claim contradicted by namespace labels.**
- Evidence: `kubectl get ns -L istio-injection` — only `knative-serving` and `security` have `enabled`; data plane and ML plane all `disabled`.
- Impact: ADR-009 "STRICT mTLS mesh-wide" is false. Thesis Bab 3 security story weakens.
- Fix (option A, aligned with ADR): `kubectl label ns use-case-crypto data-ingest data-processing kafka mlops model-lifecycle model-serving data-quality data-catalog istio-injection=enabled --overwrite` then rollout restart each ns's workloads, then apply `PeerAuthentication mode: STRICT` in `istio-system`. Verify with `istioctl authn tls-check`.
- Fix (option B, retract claim): amend ADR-009 + thesis to "STRICT mTLS at ingress and serving tier only" and remove the mesh-wide claim. Either is acceptable; **pick one before defense**.

**P0-3: prometheus-adapter missing → HPA blind + Longhorn ns stuck.**
- Evidence: `kubectl get apiservice v1beta1.custom.metrics.k8s.io` → `False (MissingEndpoints)` 7d7h. `longhorn-system` Terminating 47h.
- Fix: install `prometheus-community/prometheus-adapter` with rule-set for Feast online-store QPS, Kafka consumer-lag, KServe P99 latency. Then `kubectl delete apiservice v1beta1.custom.metrics.k8s.io v1beta1.external.metrics.k8s.io` if the chart re-creates them, to break the Longhorn finalizer stall.
- Verify: `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .`
- ADR ref: ADR-010.

**P0-4: ArgoCD empty — crypto application never applied.**
- Evidence: `kubectl get applications -A` → No resources found. `use-case-crypto/argocd/application.yaml` exists on disk only.
- Impact: RQ1 "GitOps-driven reproducibility" has zero runtime evidence.
- Fix: `kubectl apply -f use-case-crypto/argocd/application.yaml` — creates AppProject `use-case-crypto` and Application `crypto-use-case` tracking `use-case-crypto/` path in repo. Confirm sync-wave ordering for namespace-first then manifests.

**P0-5: End-to-end pipeline terminates at ClickHouse.**
- Evidence: no InferenceService, no trainer workflow, no drift job.
- Impact: RQ2 fails entirely — there is nothing to measure model latency, drift, or retraining cadence against.
- Fix plan (minimum viable path):
  1. Compile a KFP pipeline under `use-case-crypto/kfp/crypto_train_eval_register.py`: pulls Feast offline features → trains LightGBM (price-direction classifier) → logs to MLflow → registers if `auc > threshold`.
  2. Deploy `InferenceService crypto-direction-v1` in `model-serving` (KServe + Knative revision) pointed at the registered MLflow model artifact via `storageUri: s3://mlflow/…`.
  3. Add Evidently drift CronJob reading from ClickHouse gold → writes reports + metric → Prom alert rule.
  4. Wire `ml-bridge` deployment to the InferenceService URL.
  5. Activate Feast materialization CronJob to keep online store warm.

**P0-6: `use-case-stock/` missing — Batasan Masalah breached.**
- Evidence: Bab 1 §Batasan Masalah includes Yahoo Finance 1-year stock data and CoinGecko 6-month crypto data.
- Fix: either (a) author a minimum `use-case-stock/` overlay mirroring crypto layout (collectors, DAGs, Feast views, KFP pipeline, InferenceService) or (b) amend Batasan Masalah to scope only crypto. For thesis integrity, (a) is stronger; (b) is faster.

### 3.2 P1 — material weaknesses

**P1-1: Kyverno policies empty.** Controller installed, zero `ClusterPolicy`/`Policy`. Add baseline: require labels `app.kubernetes.io/part-of`, deny `:latest` tags, enforce `runAsNonRoot`, restrict image registries to allow-list, verify Cosign signatures.
**P1-2: Velero / Chaos Mesh / Falco / Trivy absent.** See §2.2.
**P1-3: Dual Kafka.** Consolidate on Strimzi; migrate consumers/producers; delete `kafka-dev`.
**P1-4: High restart counts.** Spot-check: `feature-engine` restart=9, `ml-bridge` restart=14 (no backend), `dashboard-backend` restart=5. Investigate liveness tuning and downstream reachability.
**P1-5: Kueue unused.** Declare `ClusterQueue` for ML training with GPU tolerations (even if GPU-less node, still define the abstraction) and `LocalQueue` in `use-case-crypto` + `model-lifecycle`. Submit training as Jobs with `queue-name` label.
**P1-6: Observability has no SLO dashboards tied to thesis metrics.** Sloth is installed but no SLO YAMLs. Author SLOs for `ingestion-freshness`, `feature-materialization-latency`, `inference-p99-latency`, `dag-success-rate`.

### 3.3 P2 — nice-to-have / post-defense

- Single-node k3s is a demo setup. Note explicitly in thesis Bab 4 that HA claims (RQ3) are modelled, not measured. If time permits, stand up a 3-node k3s cluster for the evaluation chapter.
- Images using `localhost:5000/*:latest` in-cluster registry should be pinned to SHA digests for reproducibility claim.
- No load / chaos test evidence. Add a `locust` or `k6` job + Chaos Mesh `NetworkChaos` experiment report.
- GrowthBook not actually gating any serving path (because no serving path exists). Once P0-5 done, wire at least one champion/challenger.

---

## 4. Platform / Use-Case Boundary Audit

**Rule:** `platform/` is domain-agnostic (`config.yaml`, `components/*`, `services/*`, `DECISIONS.md`, runbooks). `use-case-*/` adds or overrides domain-specific DAGs, features, schemas, pipelines, ArgoCD Applications.

| Issue | File | Resolution |
|---|---|---|
| Boundary leak: crypto DAG in domain-agnostic path | `platform/components/data-processing/airflow/dags/crypto_hourly_features.py` | Move to `use-case-crypto/dags/crypto_hourly_features.py`. Update git-sync manifest filter. |
| Service templates reference `feature_engine` expecting crypto-like schema | `platform/services/feature-engine/values.yaml` | Parameterize via values override in `use-case-crypto/services/feature-engine/values.yaml`. |
| `platform/config/services.yaml` `depends_on` lists `coingecko-source` | should not name domain sources | Move to `use-case-crypto/config/services.yaml`; keep platform entry generic (`depends_on: data-source-rest`). |
| No `use-case-stock/` exists | repo root | Create scaffold or amend Batasan Masalah (see P0-6). |
| ArgoCD Application path in `use-case-crypto/argocd/application.yaml` points at `platform/` for shared components | correct pattern | Keep, but add an AppProject source repo allow-list pinning both `platform/` and `use-case-crypto/`. |

**Verdict:** boundary design is sound; one leak + one missing use-case overlay. Low effort to fix.

---

## 5. End-to-End Flow (Target State, annotated with current gaps)

```
[Exchange WS]    [CoinGecko REST]    [DeFiLlama REST]    [FearGreed REST]
     │                 │                   │                    │
     ▼                 ▼                   ▼                    ▼
 websocket-      coingecko CJ        defillama CJ          feargreed CJ
  collector      (15 * * * *)        (30 */6 * * *)        (0 * * * *)
     │                 │                   │                    │
     ▼                 ▼                   ▼                    ▼
            ┌────────────── rest-collector ──────────────┐
            │                      │                     │
            ▼                      ▼                     ▼
        validator (GE + schema)  →  Karapace subject check
            │
            ▼
        Kafka (Strimzi, topic: crypto.raw.v1, crypto.feargreed.v1, …)
            │
            ├──► Kafka Connect → MinIO raw (bronze, Parquet)
            │
            ├──► Flink SQL (crypto-features) → Kafka (crypto.features.v1)
            │                                         │
            │                                         ▼
            │                                    feature-engine
            │                                         │
            │                                         ├──► Redis (online store, Feast)
            │                                         ├──► Qdrant (embeddings, vector-embedding CJ)
            │                                         └──► feature-cache
            │
            ▼
        ClickHouse bronze  →  dbt (silver)  →  dbt (gold)
            │                                         │
            ▼                                         ▼
        Trino federates (bronze+silver+gold+iceberg via Lakekeeper)
            │
            ▼
        Superset BI dashboards  +  DataHub lineage + OpenLineage events

  ── MLOps branch ──
        gold / feast offline  →  KFP pipeline (train/eval/register)
                                         │                                           
                                         ▼                                           
                                 MLflow model registry  →  [GAP] no promotion hook  
                                         │                                           
                                         ▼                                           
                                 KServe InferenceService ( [GAP] not deployed )     
                                         │                                           
                                         ▼                                           
                                 ml-bridge → gateway → dashboard-backend → dashboard-frontend
                                         │
                                         ▼
                                 Evidently drift CJ ( [GAP] not scheduled )
                                         │
                                         ▼
                                 Prom alert → retraining KFP ( [GAP] not wired )

  ── Observability / Security cross-cuts ──
        OpenTelemetry Collector (logs/metrics/traces) → Prom + Loki + Tempo → Grafana
        OpenLineage → DataHub
        Great Expectations → DataHub assertions
        Vault → ESO → Secret (per ns) [GAP: Vault not Ready]
        Istio mTLS STRICT [GAP: only 2 namespaces]
        APISIX edge → Istio ingress gateway
        ArgoCD app-of-apps [GAP: no Applications registered]
        OpenCost → Prom → Grafana (FinOps)
        Kueue ClusterQueue [GAP: no queues declared]
```

**Evidence the design is coherent:** every tool has a place; no orphaned components in the design.
**Evidence the implementation is incomplete:** every `[GAP]` marker is a real runtime gap, not a design gap.

---

## 6. Research Question Alignment Matrix

| RQ (from Bab 1) | Design covers? | Runtime evidence? | Missing for defense |
|---|---|---|---|
| **RQ1 — How to integrate DataOps pipeline-as-code with lineage, contracts, and reproducibility on Kubernetes?** | Yes (Airflow+dbt+Kafka+GE+DataHub+OpenLineage+Karapace+ArgoCD) | Partial — pipelines run, but ArgoCD GitOps not actively reconciling; Karapace schemas not enforced at producers outside crypto ns | Register ArgoCD app; add producer-side schema-id header assertion; demo reroll via `argocd app sync` |
| **RQ2 — How to operationalize MLOps end-to-end with feature store, registry, serving, and drift on Kubernetes?** | Yes (Feast+MLflow+KFP+Katib+KServe+Evidently+GrowthBook) | **No** — no trainer, no serving, no drift | Deliver P0-5 minimum viable ML path |
| **RQ3 — How to achieve SRE/observability/security posture (mTLS, policy, secrets, HPA) for this platform?** | Yes (Prom/Loki/Tempo/OTel/Istio/Kyverno/Vault/ESO/Falco/Trivy/Sloth/OpenCost) | Partial — obs mostly on; security posture is aspirational (mTLS selective, Kyverno empty, Falco/Trivy absent, Vault Down) | P0-1, P0-2, P0-3, P1-1, P1-2 |
| **RQ4 — How does the architecture behave under domain specialization (saham + kripto) with reuse?** | Yes (platform/ + use-case-*/) | Partial — crypto mostly wired, stocks entirely absent, one boundary leak | P0-6 + boundary leak fix |

---

## 7. Prioritized Remediation Backlog (7-day plan)

| Day | Deliverable | Owner |
|---|---|---|
| 1 | Apply Vault jq probe fix; restart vault-0; confirm ESO reconcile | platform |
| 1 | Install prometheus-adapter; delete stale APIServices; confirm Longhorn ns gone | platform |
| 2 | Decide Istio option A vs B; if A, label namespaces + restart + verify tls-check; if B, amend ADR-009 + Bab 3 text | platform + thesis |
| 2 | `kubectl apply -f use-case-crypto/argocd/application.yaml`; verify sync | platform |
| 3 | Compile KFP `crypto_train_eval_register` pipeline; first run to MLflow | ML |
| 3 | Declare Kueue ClusterQueue + LocalQueue; move training Job under Kueue | ML |
| 4 | Deploy KServe InferenceService `crypto-direction-v1`; wire ml-bridge | ML |
| 4 | Feast materialization CronJob active | ML |
| 5 | Evidently drift CronJob + Prom alert | ML |
| 5 | Install Falco + Trivy Operator; author 5 Kyverno baseline policies; install Cosign verify rule | security |
| 6 | Install Velero (MinIO as backup target); take first backup; install Chaos Mesh | SRE |
| 6 | Retire `kafka-dev`, `mysql`, orphan workflow-controller, Traefik; move crypto DAG out of platform/ | platform |
| 7 | Either scaffold `use-case-stock/` (preferred) or amend Bab 1 Batasan Masalah (faster); add at least Yahoo-Finance collector CronJob and stock KFP pipeline | thesis |
| 7 | Author Sloth SLOs for 4 metrics; load-test with k6; one Chaos Mesh experiment; capture evidence for Bab 4 evaluation | SRE |

---

## 8. Thesis-level Recommendations

1. **Bab 3 (Analisis Masalah)**: re-check that every stated non-functional requirement (KNF) has a tool-to-requirement mapping. Several KNFs currently map to tools that are installed-but-idle (Kyverno, Kueue, Chaos Mesh, Falco); call out "available but not yet configured" honestly rather than claiming enforced.
2. **Bab 4 (Evaluasi)**: run the 7-day backlog first, then collect evidence with (a) `kubectl` transcripts, (b) Grafana dashboards for each SLO, (c) ArgoCD screenshots showing Sync/Healthy, (d) MLflow run pages + KServe InferenceService Ready, (e) Evidently drift report, (f) Chaos Mesh experiment report, (g) Falco runtime event sample. Without these, the evaluation chapter will be narrative rather than measured.
3. **Scope truth**: explicitly document in Bab 1/3 that the cluster is **single-node k3s**; frame HA/DR claims as *design-level* with a multi-node extension plan, rather than measured on this node.
4. **Subtraction bias**: if timeline is tight, **cut** scope (drop supervised labeling, drop stocks) rather than add tools. The platform is already ambitious for an undergraduate thesis; reviewers will respect a tight, evidenced subset over a broad, unfinished one.

---

## 9. Appendix — Cross-reference to existing docs

- `platform/DECISIONS.md` ADR-001 … ADR-014 — design rationale (still valid; only ADR-009 needs amendment per P0-2)
- `platform/REMEDIATION_RUNBOOK.md` — §10.1 (Vault jq), §10.3 (Longhorn ns), §10.5 (orphan workflow-controller), §10.10 (prometheus-adapter) are all pre-written; apply them
- `platform/MIGRATION.md` — PG/ClickHouse/Kafka/Vault migration procedures (relevant for `kafka-dev` retirement)
- `platform/config.yaml` — central platform config; no change needed
- `platform/components/VERSION.MD` — 2026 version pin inventory

---

**End of review.**
