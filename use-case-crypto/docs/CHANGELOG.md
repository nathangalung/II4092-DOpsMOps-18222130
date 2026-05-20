# Use-case Crypto changelog (cross-references to platform/components/VERSION.MD)

Per-use-case landings that pair with the platform-side audit closure
recorded in `platform/components/VERSION.MD`. Generic platform versioning
lives in the platform doc; this file captures the use-case-specific
manifest landings, source-code changes, and post-audit cleanup.

## Removed at audit (2026-04-21, ADR-025) — use-case scope

- `use-case-crypto/manifests/base/patches/flink-job.yaml` — scale-to-0
  placeholder deleted along with the target Deployment.
- `use-case-crypto/manifests/base/patches/ml-bridge-disable-deployment.yaml`
  — scale-to-0 placeholder deleted; no Deployment exists to race the
  Rollout.
- `flink-job` image / replicas / resources overrides in
  `use-case-crypto/manifests/overlays/{local,cloud,local-phase1}/` — no-ops
  once the Deployment was gone.

## Added at Phase C (2026-04-20) — use-case scope

- `crypto-retrain-on-drift` Argo CronWorkflow at
  `use-case-crypto/manifests/base/workflows/retrain-on-drift.yaml` — every
  6h queries `gold.drift_metrics`; triggers KFP `retraining_pipeline` on
  `PSI > 0.2` or `KS > 0.15`; pushes `crypto_retrain_on_drift_{psi,ks,
  triggered}` exemplars to Pushgateway. Maps to platform ADR-017; see
  `use-case-crypto/docs/ADRS.md` ADR-017.

## Post-audit closure (2026-04-21) — P0/P1/P2 use-case landings

### P0 — Production blockers (use-case scope)

- `use-case-crypto` namespace added to the Kyverno ADR-009 Istio opt-out
  allowlist via use-case overlay patch (the namespace has
  `istio-injection: disabled` but was missing from the platform-default
  allowlist; without the patch any namespace UPDATE would be rejected).
- `use-case-crypto` registry pattern appended to the Kyverno
  `verify-platform-images-cosign` `matchImageReferences` list:
  `gitea.gitops.svc.cluster.local/use-case-crypto/*` (ADR-020).

### P0 — Domain SLOs (ADR-021)

`use-case-crypto/manifests/base/observability/slos-crypto.yaml` — 3 Sloth
`PrometheusServiceLevel` CRs:

- `crypto-prediction-freshness` (99.5%, 30d)
- `crypto-pipeline-lag` (99.0%, 7d)
- `crypto-model-freshness` (99.0%, 30d)

### P0 — Autoscaling reshaped (ADR-022)

`use-case-crypto/manifests/base/scaling/scaledobjects.yaml` — 3 KEDA
`ScaledObject` with native `kafka` triggers:

- `feature-engine-kafka-lag` (topic `crypto.validated`, threshold 1000, 1-10)
- `validator-kafka-lag` (topics `crypto.rest.raw` + `crypto.ws.raw`,
  threshold 2000, 1-8)
- `analyzer-kafka-lag` (topic `crypto.predictions.v1`, threshold 500, 1-5)

`use-case-crypto/manifests/base/hpa/autoscaling.yaml` — `feature-engine-hpa`
DELETED (KEDA + HPA collision); `gateway-hpa` DELETED under ADR-026
(2026-04-21) along with prometheus-adapter — replaced by a
`gateway-http-rps` KEDA `ScaledObject` with prometheus + cpu + memory
triggers in `scaling/scaledobjects.yaml`. Remaining HPAs:
`rest-collector-hpa`, `dashboard-backend-hpa` (CPU-only, adapter-independent).

### P0 — Stream runtime reshaped (ADR-023)

`use-case-crypto/manifests/base/flink/flinkdeployment.yaml` — new
`flink.apache.org/v1beta1 FlinkDeployment` CR (`crypto-flink-job`,
Flink 2.2.0, application mode, S3 checkpoints at
`s3://flink-checkpoints/crypto/`, OpenLineage listener, single JM
metrics reporter on `:9249`). Includes ServiceAccount + Role +
RoleBinding + ExternalSecret `crypto-flink-s3`.

### P1 — Security hardening (ADR-024)

`use-case-crypto/manifests/base/authorization/edge-authz.yaml` — 2 Istio
`AuthorizationPolicy` on `istio-ingressgateway`:

- `crypto-gateway-deny-admin-path` (denies `/admin/*`, `/internal/*`,
  `/_debug/*`)
- `crypto-gateway-allow-api-and-dashboard` (allows `/api/v1/*` public,
  `/dashboard/*` from `10.0.0.0/8 + 172.16.0.0/12 + 192.168.0.0/16` —
  overlay-patched)

`use-case-crypto/manifests/base/network-policies.yaml` — rewritten:

- Removed overly-broad `allow-istio-system`.
- Per-pod allowlists replace 3 prior "namespace → all pods" rules
  (`allow-airflow-to-processing`, `allow-kfp-to-training-targets`,
  `allow-model-serving-to-serving-tier`).
- Added `allow-istio-control-plane-to-gateway`.
- Added port 9249 to Prometheus scrape (Flink reporter).

### P1 — Progressive delivery on ml-bridge (ADR-016 use-case binding)

`use-case-crypto/manifests/base/rollouts/ml-bridge-rollout.yaml` —
`argoproj.io/v1alpha1 Rollout` + local `AnalysisTemplate` (canary
20% → analyze → 50% → analyze → 100%; SLO gates: success-rate ≥ 99%,
p99 ≤ 500ms).

### P2 — Resilience experiments (thesis §4.5 KNF-11)

`use-case-crypto/manifests/base/chaos/resilience-experiments.yaml` — 3
Chaos Mesh `Schedule` CRs (gateway network loss Tue 11:00, feature-cache
pod-kill Wed 12:00, ml-bridge → MLflow latency Thu 13:00 via target
selector) + `crypto-game-day` Workflow for manual thesis-viva demo.

### P2 — OpenLineage emission (ADR-018)

`use-case-crypto/dags/crypto_lakehouse_dag.py` — manual OpenLineage
`RunEvent` emission from 4 PythonOperator callables (create / merge /
delete LakeFS branch + Trino QC). Custom run facet `crypto_qc` carries
`goldRowCount`, `predictionRowCount`, `predictionCoverageRatio`,
`goldLatestTimestamp`. Events POST to DataHub GMS via
`OPENLINEAGE_URL` env.

### P2 — Kustomization registrations

`use-case-crypto/manifests/base/kustomization.yaml` registered new
resources: `observability/slos-crypto.yaml`, `scaling/scaledobjects.yaml`,
`flink/flinkdeployment.yaml`, `rollouts/ml-bridge-rollout.yaml`,
`chaos/resilience-experiments.yaml`, `authorization/edge-authz.yaml`.
Added `patches/ml-bridge-disable-deployment.yaml`.
