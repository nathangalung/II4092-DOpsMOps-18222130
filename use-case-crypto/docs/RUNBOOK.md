# Use-case Crypto Remediation Runbook

Use-case-specific procedures that layer on top of `platform/REMEDIATION_RUNBOOK.md`.
Apply order: platform runbook first (sets up shared infrastructure), then this
runbook (applies use-case-crypto resources to that infrastructure).

Each section here references the parent platform section (e.g. §7 ↔ platform §7)
where applicable.

## 7 — Post-migration hostname updates (use-case scope)

Some `use-case-crypto` manifests still reference the pre-operator hostnames
for ClickHouse (3 files). Migrate them once the platform CHI is reconciling
(gated on default StorageClass being present per platform §0):

- `use-case-crypto/manifests/base/configmaps/feast.yaml:56`
- `use-case-crypto/manifests/base/configmaps/sources.yaml:46`
- `use-case-crypto/manifests/base/katib/experiment-lightgbm.yaml:88`

Change `clickhouse.storage.svc.cluster.local` → `clickhouse-platform.storage.svc.cluster.local`
(load-balanced convenience Service created by the Altinity operator, backed
by cluster `main` pods `chi-platform-main-{0..1}-{0..1}`). Prefer the Service
DNS; pod-specific DNS is fragile to topology changes.

## 11.4 — Crypto retrain-on-drift CronWorkflow (ADR-017, use-case scope)

New manifest:

- `use-case-crypto/manifests/base/workflows/retrain-on-drift.yaml`
  - ExternalSecret `crypto-retrain-on-drift` (ClickHouse admin creds)
  - Argo CronWorkflow `crypto-retrain-on-drift` schedule `0 */6 * * *`
  - `measure-drift` template: clickhouse-client queries
    `gold.drift_metrics` for max PSI + KS in lookback window
  - `decide-and-trigger` template: POSTs to
    `http://ml-pipeline.model-lifecycle.svc.cluster.local:8888/apis/v2beta1/runs`
    when `PSI > 0.2` or `KS > 0.15`; pushes metrics to Pushgateway
- `use-case-crypto/manifests/base/kustomization.yaml` — resources list
  extended with `- workflows/retrain-on-drift.yaml`

Namespace: `model-lifecycle` (KFP's Argo controller is there).

Verification:

```bash
kubectl -n model-lifecycle get cronworkflow crypto-retrain-on-drift
kubectl -n model-lifecycle get externalsecret crypto-retrain-on-drift
# Run once manually to verify ClickHouse auth + KFP API reachability:
kubectl -n model-lifecycle create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: crypto-retrain-on-drift-manual-
  namespace: model-lifecycle
spec:
  workflowTemplateRef:
    name: crypto-retrain-on-drift
EOF
# Prometheus metric check (after one run):
# crypto_retrain_on_drift_psi, _ks, _triggered should appear in Mimir
```

## 12.2 — Katib experiment END_DATE bump (use-case scope)

Change:

- `use-case-crypto/manifests/base/katib/experiment-lightgbm.yaml` — END_DATE
  `2026-04-14` → `2026-04-20` with thesis-viva comment.

Verification:

```bash
kubectl -n use-case-crypto get experiment flaml-automl-hpo -o jsonpath='{.spec.maxTrialCount}'
kubectl -n use-case-crypto get experiment flaml-automl-hpo \
  -o jsonpath='{.metadata.annotations.thesis\.example\.com/end-date}'
# Confirm Katib SDK-spawned run-scoped experiments inherit the template
# (not the expired baseline):
kubectl -n use-case-crypto get experiments -l parent=flaml-automl-hpo
```

## 12.3 — Crypto Sloth SLOs (ADR-021)

New manifest:

- `use-case-crypto/manifests/base/observability/slos.yaml` — three
  `sloth.slok.dev/v1 PrometheusServiceLevel` CRs:
  - `crypto-prediction-freshness` (99.5%, 30d)
  - `crypto-pipeline-lag` (99.0%, 7d)
  - `crypto-model-freshness` (99.0%, 30d)

Each compiles (via the Sloth controller) to 8 MWMBR PrometheusRules
labelled `release: kube-prometheus-stack` so the Prometheus Operator
picks them up automatically.

Verification:

```bash
kubectl -n use-case-crypto get prometheusservicelevel
kubectl -n use-case-crypto get prometheusrule -l sloth.slok.dev/service=crypto-prediction-freshness
# Inspect compiled burn-rate rules (should see page/ticket window pairs):
kubectl -n use-case-crypto get prometheusrule crypto-prediction-freshness -o yaml | \
  yq '.spec.groups[].rules[] | select(.alert) | .alert'
# Prom alert check:
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
curl -s 'http://127.0.0.1:9090/api/v1/alerts' | jq '.data.alerts[] | select(.labels.slo)'
```

## 12.4 — Crypto KEDA ScaledObjects (ADR-022)

New manifest:

- `use-case-crypto/manifests/base/scaling/scaledobjects.yaml` — three
  `keda.sh/v1alpha1 ScaledObject` with `type: kafka` triggers:
  - `feature-engine-kafka-lag`  topic `crypto.validated`  lagThreshold 1000  1-10
  - `validator-kafka-lag`       topics `crypto.rest.raw` + `crypto.ws.raw`  lagThreshold 2000  1-8
  - `analyzer-kafka-lag`        topic `crypto.predictions.v1`  lagThreshold 500  1-5

Bootstrap: `platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092`
(in-cluster plain listener). When SASL is required a `triggerAuthentication`
CR backed by an ExternalSecret is added.

Change:

- `use-case-crypto/manifests/base/hpa/autoscaling.yaml` — `feature-engine-hpa`
  DELETED. KEDA ScaledObject generates its own HPA; dual controllers fight.
  Gateway and dashboard-backend HPAs remain (CPU/RPS, not consumer-driven).

Verification:

```bash
kubectl -n use-case-crypto get scaledobject
kubectl -n use-case-crypto get hpa   # KEDA-generated + gateway/dashboard-backend only
# Generate load on a topic and watch replicas:
kubectl -n data-ingestion exec kafka-cluster-0 -- \
  kafka-producer-perf-test.sh --topic crypto.validated \
    --num-records 200000 --throughput 5000 \
    --record-size 1024 --producer-props bootstrap.servers=localhost:9092
kubectl -n use-case-crypto get deploy feature-engine -w
```

Rollback: `git revert`. Recreate the deleted HPA from git history if needed.

## 12.5 — Crypto FlinkDeployment CR (ADR-023)

New manifest:

- `use-case-crypto/manifests/base/flink/flinkdeployment.yaml` — bundles:
  - ServiceAccount `crypto-flink`, Role + RoleBinding (scoped to the ns)
  - ExternalSecret `crypto-flink-s3` (MinIO access/secret → Vault
    `secret/platform/minio/root`)
  - `flink.apache.org/v1beta1 FlinkDeployment crypto-stream-processor`
    (application mode, Flink 2.2.0, jarURI `local:///opt/flink/usrlib/crypto-stream-processor.jar`,
    entryClass `io.mlops.crypto.flink.CryptoStreamJob`)
  - Checkpoints to `s3://flink-checkpoints/crypto/` at 60s interval
  - `pipeline.openlineage.url` → DataHub GMS; `pipeline.openlineage.namespace=crypto`
  - Metrics reporter on port 9249 (JobManager-only — TM reporter disabled
    to cut cardinality ~10×)

ADR-025 follow-up (2026-04-21): the legacy `flink-job` Deployment is now
DELETED from `platform/services/base/deployments/`, along with the
scale-to-0 patch in `use-case-crypto/manifests/base/patches/`. Operator-
managed pods carry `app: crypto-stream-processor` + `component: jobmanager|taskmanager`;
PDBs, the PodMonitor, and NetworkPolicies target those labels directly.
The FlinkDeployment `podTemplate` now declares named ports `metrics`
(9249) and `jm-rest` (8081).

Verification:

```bash
kubectl -n use-case-crypto get flinkdeployment crypto-stream-processor
kubectl -n use-case-crypto get pods -l app=crypto-stream-processor          # 1 JM + N TM
kubectl -n use-case-crypto logs -l component=jobmanager --tail=50           # should see OL events
kubectl -n use-case-crypto port-forward svc/crypto-stream-processor-rest 8081:8081
curl -s http://127.0.0.1:8081/jobs | jq
# Savepoint round-trip:
kubectl -n use-case-crypto annotate flinkdeployment crypto-stream-processor \
  flinkdeployments.flink.apache.org/savepointTrigger=manual-test --overwrite
# PodMonitor scrape check:
kubectl -n use-case-crypto get podmonitor crypto-stream-processor
# PDB targeting the JobManager:
kubectl -n use-case-crypto get pdb crypto-stream-processor-jobmanager-pdb
```

Kafka consumer-group integrity: the FlinkDeployment uses a dedicated
consumer group per the application jar's Kafka source config. First-
time apply is safe. For subsequent migrations from an older job, drain
via savepoint before switching.

## 12.6 — Edge AuthZ + per-pod NetworkPolicies (ADR-024, use-case scope)

New manifest:

- `use-case-crypto/manifests/base/authorization/edge-authz.yaml` — two
  Istio `AuthorizationPolicy` in `istio-system` scoped to
  `selector: istio: ingressgateway`:
  - `crypto-gateway-deny-admin-path` (DENY `/admin/*`, `/internal/*`, `/_debug/*`)
  - `crypto-gateway-allow-api-and-dashboard` (ALLOW `/api/v1/*` + healthz + metrics
     publicly; `/dashboard/*` from `10.0.0.0/8 + 172.16.0.0/12 + 192.168.0.0/16`)

Change:

- `use-case-crypto/manifests/base/network-policies.yaml` — rewrite:
  - Removed `allow-istio-system` (too broad).
  - Three prior "namespace → all pods" rules replaced with per-pod allowlists:
    - `allow-airflow-to-processing` names
      `feature-engine|validator|analyzer` (ADR-025 dropped `flink-job` —
      Airflow does not call the Flink JM directly)
    - `allow-kfp-to-training-targets` names
      `feature-engine|crypto-stream-processor|ml-bridge`
    - `allow-model-serving-to-serving-tier` names
      `gateway|ml-bridge`
  - `allow-ingress-to-gateway` scoped to `app: gateway` + port 8080 only.
  - Added `allow-istio-control-plane-to-gateway`.
  - Added port 9249 to Prometheus scrape (Flink reporter).

Verification:

```bash
kubectl -n istio-system get authorizationpolicy \
  crypto-gateway-deny-admin-path crypto-gateway-allow-api-and-dashboard
# Admin path should 403 at the edge:
curl -sk https://crypto.example.com/admin/foo -o /dev/null -w '%{http_code}\n'   # 403
curl -sk https://crypto.example.com/api/v1/healthz -o /dev/null -w '%{http_code}\n' # 200
# Dashboard from allowed CIDR: 200; from public egress IP: 403 (envoy will reject).
kubectl -n use-case-crypto get networkpolicy
# Flink scrape:
kubectl -n observability exec deploy/prometheus-operator-prometheus-0 -- \
  wget -qO- http://crypto-stream-processor-rest.use-case-crypto.svc.cluster.local:9249/metrics | head -20
```

Rollback: `git revert`. With AuthZ removed the gateway admits admin paths;
with per-pod NetPol removed east-west is broadly permitted. Low risk in
single-node dev; schedule carefully in prod.

## 12.7 — Argo Rollouts on ml-bridge (ADR-016 use-case example)

New manifests:

- `use-case-crypto/manifests/base/rollouts/ml-bridge-rollout.yaml` —
  `argoproj.io/v1alpha1 Rollout ml-bridge`; canary steps 20% → analyze →
  50% → analyze → 100%. Local `AnalysisTemplate` queries the Istio edge
  metrics (`istio_requests_total`, `istio_request_duration_milliseconds_bucket`)
  for success-rate ≥ 99% and p99 ≤ 500ms.
- ADR-025 follow-up (2026-04-21): `patches/ml-bridge-disable-deployment.yaml`
  is DELETED. `platform/services/base/deployments/ml-bridge.yaml` now
  ships only the Service — no Deployment exists to race the Rollout for
  pods. The Service selector (`app: ml-bridge`) matches the Rollout's
  ReplicaSet pods directly.

Verification:

```bash
kubectl -n use-case-crypto get rollout ml-bridge
kubectl -n use-case-crypto get deploy ml-bridge     # NotFound — expected (ADR-025)
kubectl -n use-case-crypto get svc ml-bridge        # 8086/TCP → 8000
kubectl argo rollouts -n use-case-crypto get rollout ml-bridge
# Trigger a canary: bump the image tag on the Rollout, watch the steps:
kubectl -n use-case-crypto set image rollout/ml-bridge ml-bridge=ghcr.io/example/ml-bridge:v1.2.3
kubectl argo rollouts -n use-case-crypto get rollout ml-bridge --watch
# If the AnalysisTemplate fails, the rollout pauses at the next step —
# abort or promote manually:
kubectl argo rollouts -n use-case-crypto promote ml-bridge
kubectl argo rollouts -n use-case-crypto abort   ml-bridge
```

Rollback: revert the image bump (`kubectl argo rollouts undo`).

## 12.8 — Chaos Mesh crypto resilience experiments

New manifest:

- `use-case-crypto/manifests/base/chaos/resilience-experiments.yaml` —
  three `Schedule` CRs (gateway network-loss Tue 11:00, feature-cache
  pod-kill Wed 12:00, ml-bridge→MLflow latency Thu 13:00 with target
  selector) + one `Workflow` `crypto-game-day` that sequences all three
  for manual thesis-viva demonstration.

Observability hook: every experiment is labelled
`experiment.thesis=KNF-11-<name>` so the "Crypto Resilience" Grafana
dashboard plots SLO burn (see §12.3) before / during / after each
experiment window.

Verification:

```bash
kubectl -n chaos-mesh get schedule -l use-case=crypto
kubectl -n chaos-mesh get workflow crypto-game-day
# Trigger game-day manually:
kubectl -n chaos-mesh annotate workflow crypto-game-day \
  chaos-mesh.org/trigger-now=$(date -Iseconds) --overwrite
# Watch SLO burn on Grafana: dashboard "Crypto Resilience" → panel
# "prediction-freshness burn rate"  (should rise during experiment,
# recover within deadline).
```

Rollback: `kubectl delete schedule,workflow -n chaos-mesh -l use-case=crypto`.
The experiments are scheduled low-cadence so idle rollback has no effect
until the next cron window.

## 12.9 — OpenLineage emission in crypto DAGs (ADR-018)

Change:

- `use-case-crypto/dags/lakehouse.py` — added helpers
  `_ol_dataset`, `_ol_event`, `_ol_emit`, `_ol_run_id` and variables
  `OPENLINEAGE_URL`, `OPENLINEAGE_NAMESPACE`. Wired into four
  PythonOperator callables (LakeFS branch create/merge/delete + Trino
  quality gate). Custom run facet `crypto_qc` carries
  `goldRowCount`, `predictionRowCount`, `predictionCoverageRatio`,
  `goldLatestTimestamp`.

Why manual (not `openlineage-airflow` auto-extractor): dbt's own OL
provider already emits lineage for dbt models; the auto-extractor would
double-emit for any `BashOperator` wrapping `dbt run`. Flink and Spark
continue to use their native OL listeners.

Verification:

```bash
# Trigger the DAG once:
kubectl -n data-processing exec deploy/airflow-scheduler -- \
  airflow dags trigger crypto_lakehouse_dag
# Tail DataHub GMS for incoming RunEvents:
kubectl -n data-governance logs deploy/datahub-gms --since=5m | grep -i openlineage
# DataHub UI: navigate to Datasets → crypto.gold.* → Lineage tab;
# the crypto_lakehouse_dag run should appear within 60s.
```

Rollback: revert the DAG commit. The helpers are no-op if
`OPENLINEAGE_URL` is unset, so a blank env variable effectively disables
emission without a code change.

## Apply order (use-case overlay)

After applying platform overlay (Kyverno policy updates, etc.), apply this
use-case overlay second so resources land against admission policies that
permit them:

```bash
kubectl apply -k use-case-crypto/manifests/overlays/local
```

Order matters on first apply:

1. `platform/overlays/local` FIRST (so the updated Kyverno policies let
   the new use-case resources through admission).
2. `use-case-crypto/manifests/overlays/local` SECOND.
3. ADR-025 (2026-04-21) retired the legacy in-pod Flink Deployment and
   its scale-to-0 patch outright. First-time cluster brings up the
   FlinkDeployment CR directly; there is no legacy Deployment to drain.

Rollback: `kubectl delete -k <path>` in reverse order; or `git revert` on
the landing commits. ADR-015 through ADR-024 remain in `docs/ADRS.md` as
historical record even if the code is reverted.

## 13 — ADR-025 cleanup (2026-04-21) — use-case-side edits

ADR-025 retires every scale-to-zero placeholder. The platform side of this
cleanup (file deletions, KServe runtime trim, platform kustomization edits)
is documented in `platform/REMEDIATION_RUNBOOK.md` §13. This section captures
the use-case-side edits.

### 13.1 — Files deleted

```
use-case-crypto/manifests/base/patches/flink-job.yaml                       (scale-to-0 patch)
use-case-crypto/manifests/base/patches/ml-bridge-disable-deployment.yaml    (scale-to-0 patch)
```

### 13.2 — Kustomization references cleaned

| File | Change |
|---|---|
| `use-case-crypto/manifests/base/kustomization.yaml` | `- .../flink-job.yaml` + two `patches:` entries removed |
| `use-case-crypto/manifests/base-data/kustomization.yaml` | `- .../flink-job.yaml` replaced with `- ../base/flink/flinkdeployment.yaml`; `patches/flink-job.yaml` entry removed |
| `use-case-crypto/manifests/overlays/{local,cloud,local-data}/kustomization.yaml` | `name: flink-job` image / replicas / resource / probe patches removed (all were no-ops once the Deployment was gone) |

### 13.3 — Resources rescoped to FlinkDeployment pod labels

The Flink Kubernetes Operator labels its pods `app: <deployment-name>` +
`component: jobmanager|taskmanager`. Selectors are NOT rewritten by
kustomize namePrefix, so the `app:` value is the literal FlinkDeployment
`metadata.name` (`crypto-stream-processor`):

| File | Was | Now |
|---|---|---|
| `use-case-crypto/manifests/base/hpa/autoscaling.yaml` | `flink-job-pdb` selecting `app: flink-job` | `stream-processor-jobmanager-pdb` selecting `app: crypto-stream-processor, component: jobmanager` |
| `use-case-crypto/manifests/base/observability/servicemonitors.yaml` | ServiceMonitor selecting `app: flink-job` on port `metrics` (8083) | **PodMonitor** selecting `app: crypto-stream-processor, component: jobmanager` on named port `metrics` (9249) |
| `use-case-crypto/manifests/base/network-policies.yaml` | port 8083 on Prometheus scrape; `flink-job` in `allow-airflow-to-processing` + `allow-kfp-to-training-targets` selectors | port 8083 removed; `allow-airflow-to-processing` drops `flink-job` (Airflow does not call Flink JM); `allow-kfp-to-training-targets` uses `crypto-stream-processor` |
| `use-case-crypto/manifests/base/flink/flinkdeployment.yaml` | podTemplate had no named container ports | Added `ports: [{name: metrics, 9249}, {name: jm-rest, 8081}]` so PodMonitor can scrape by port name |

### 13.4 — Use-case verification

```bash
# Use-case overlays kustomize-build cleanly:
kubectl kustomize use-case-crypto/manifests/overlays/local        >/dev/null
kubectl kustomize use-case-crypto/manifests/overlays/cloud        >/dev/null
kubectl kustomize use-case-crypto/manifests/overlays/local-data >/dev/null

# No legacy Deployment references survive in use-case manifests:
! grep -rn "deployments/flink-job.yaml" use-case-crypto

# FlinkDeployment + rescoped PDB + PodMonitor admitted:
kubectl -n use-case-crypto get flinkdeployment crypto-stream-processor
kubectl -n use-case-crypto get pdb crypto-stream-processor-jobmanager-pdb
kubectl -n use-case-crypto get podmonitor crypto-stream-processor
```
