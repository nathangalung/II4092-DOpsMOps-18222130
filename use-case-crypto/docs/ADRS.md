# Use-case Crypto ADRs (cross-references to platform/DECISIONS.md)

These ADRs capture use-case-specific implementations of platform-level decisions.
Each section here maps to a platform ADR that defines the *generic* decision;
this document captures the *specific* implementation for the crypto use-case.

For platform-level ADRs (mechanism, rationale, supersession), see
`platform/DECISIONS.md`.

## ADR-003 (use-case implementation) — Airflow DAGs for crypto data pipeline

Maps to platform ADR-003 (Airflow for data, KFP for ML).

The crypto use-case ships four Airflow DAGs, all in `use-case-crypto/dags/`:

- `data_pipeline.py` — hourly OHLCV → feature table + daily backfill (DAG IDs `crypto_hourly_features`, `crypto_daily_backfill`)
- `lakehouse.py` — LakeFS branch / merge / delete + Trino QC (DAG ID `crypto_lakehouse`)
- `quality_gate.py` — Great Expectations + SQL checks + OpenLineage (DAG ID `crypto_data_quality_gate`)

DAG IDs are derived from `Variable.get("USE_CASE", default_var="crypto")` so a
clone of this use-case repo can re-bind without body edits (cycle-5 / cycle-6
master-knob refactor; see audit §15-§17).

## ADR-018 (use-case implementation) — Manual OpenLineage emission helpers

Maps to platform ADR-018 (manual in domain DAGs, native in Flink/Spark).

`use-case-crypto/dags/lakehouse.py` declares helpers `_ol_dataset`,
`_ol_event`, `_ol_emit`, `_ol_run_id` plus Variables `OPENLINEAGE_URL`,
`OPENLINEAGE_NAMESPACE`, `OPENLINEAGE_PRODUCER_LAKEHOUSE`. Wired into four
PythonOperator callables (LakeFS branch create/merge/delete + Trino quality
gate). Custom run facet `crypto_qc` carries:

- `goldRowCount`
- `predictionRowCount`
- `predictionCoverageRatio`
- `goldLatestTimestamp`

These are queryable in DataHub's lineage explorer and feed the
"data completeness" Grafana panel.

`use-case-crypto/dags/quality_gate.py` declares `OPENLINEAGE_PRODUCER_QUALITY_GATE`
(per-DAG isolation; cycle-6 split prevents seed-time collision with the
lakehouse producer Variable).

## ADR-021 (use-case implementation) — Crypto Sloth SLOs

Maps to platform ADR-021 (Sloth SLO authorship).

`use-case-crypto/manifests/base/observability/slos.yaml` ships three
`PrometheusServiceLevel` CRs:

- `crypto-prediction-freshness` — 99.5% over 30d, SLI
  `crypto_prediction_freshness_seconds < 300`
- `crypto-pipeline-lag` — 99.0% over 7d, SLI
  `sum(kafka_consumergroup_lag{group=~"crypto-.*"}) < 10000`
- `crypto-model-freshness` — 99.0% over 30d, SLI
  `mlflow_model_age_hours{use_case="crypto"} < 168`

All compile to 8 MWMBR alerts each (2h/5m page, 6h/30m page, 24h/2h ticket,
72h/6h ticket) labelled `release: kube-prometheus-stack` so the Prometheus
Operator picks them up.

## ADR-022 (use-case implementation) — Crypto KEDA ScaledObjects

> **Amended by ADR-026 + ADR-027.** The original three-row baseline below is
> kept for provenance. The live set is now `validator-kafka-lag`,
> `analyzer-kafka-lag`, and `gateway-http-rps`: the `feature-engine` row is
> RETIRED (ADR-027 — the Rust feature-engine is retired and the Flink speed
> layer owns crypto feature engineering with NO ScaledObject) and a
> `gateway-http-rps` ScaledObject is ADDED (ADR-026 — prometheus RPS + cpu +
> memory triggers, replacing the retired prometheus-adapter HPA).

Maps to platform ADR-022 (KEDA ScaledObjects for stream consumers).

`use-case-crypto/manifests/base/scaling/scaledobjects.yaml` declares three
`keda.sh/v1alpha1 ScaledObject` with native `kafka` triggers:

| Deployment | Topic trigger | Threshold | min/max |
|---|---|---|---|
| `feature-engine` | `crypto.validated` | `lagThreshold: "1000"` | 1 / 10 |
| `validator` | `crypto.rest.raw` + `crypto.ws.raw` (2 triggers) | `lagThreshold: "2000"` | 1 / 8 |
| `analyzer` | `crypto.predictions.v1` | `lagThreshold: "500"` | 1 / 5 |

KEDA queries Kafka brokers directly via
`bootstrapServers: platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092`.

HPA/KEDA collision: `feature-engine-hpa` is **deleted** (not patched) to avoid
dual-controller fighting. `use-case-crypto/manifests/base/hpa/autoscaling.yaml`
no longer declares `feature-engine-hpa`; an explanatory comment marks where it was.

## ADR-023 (use-case implementation) — Crypto FlinkDeployment CR

> **SUPERSEDED BY ADR-027.** The original shape below (a bespoke
> `crypto-stream-processor` image carrying a `com.usecase.functions.*`
> extension jar, a single-JM metrics port, and reuse of the
> `crypto-feature-engine` consumer group) was retired. End-state Y (ADR-027)
> runs the **generic** platform `flink-job` image with **no** extension jar
> (the feature function is the platform `com.pipeline.functions.FeatureFunction`),
> scrapes JM **and** TM via a PodMonitor on `:9249`, owns the `flink-features`
> consumer group, and is the sole speed-layer producer (the Rust feature-engine
> is retired). The manifest moved to `flink/stream-processor.yaml`. The
> historical record below is kept for provenance.

Maps to platform ADR-023 (FlinkDeployment CR replaces in-pod Deployment).

`use-case-crypto/manifests/base/flink/flinkdeployment.yaml` declares:

- **Image**: `crypto-stream-processor:latest` (the crypto overlay jar baked into the
  operator's Flink 2.2.0 base image)
- **Mode**: `application` (driver-in-JM, matches prior shape)
- **jarURI**: `local:///opt/flink/usrlib/crypto-stream-processor.jar`
- **entryClass**: `com.pipeline.StreamJob` — the platform's domain-agnostic
  harness. Streams are config-driven (`ENABLED_STREAMS` + `STREAM_<NAME>_*` in
  the `pipeline-config` ConfigMap); the crypto overlay jar contributes the
  `com.usecase.functions.*` feature functions, resolved by reflection at deploy
  time. (No `CryptoStreamJob` subclass exists — the use-case ships functions,
  not a bespoke entrypoint.)
- **Checkpointing**: `s3://flink-checkpoints/crypto/` (MinIO-backed),
  interval 60s. Credentials from Vault via ExternalSecret `crypto-flink-s3`
- **Observability**: OpenLineage listener (ADR-018) emits to DataHub GMS;
  `pipeline.openlineage.namespace=crypto`. Metrics reporter on `:9249`
  (single JM port; TaskManager scrape removed, cardinality drops ~10×)
- **RBAC**: ServiceAccount `crypto-flink` + Role + RoleBinding scoped to the
  `use-case-crypto` namespace; operator reconciles

**Kafka consumer-group**: the FlinkDeployment reuses `crypto-feature-engine`
consumer group. During rollout the legacy Deployment was scaled to 0 BEFORE
the FlinkDeployment applied, to avoid split-brain rebalancing.

## ADR-024 (use-case implementation) — Crypto NetworkPolicy + edge AuthZ

Maps to platform ADR-024 (NetworkPolicy as sole L7 enforcement in
istio-disabled namespaces).

The `use-case-crypto` namespace is on the ADR-009 Istio opt-out allowlist
(`istio-injection: disabled`). Two-plane enforcement:

**Edge (L7 AuthZ)** — `use-case-crypto/manifests/base/authorization/edge-authz.yaml`:
- DENY `/admin/*`, `/internal/*`, `/_debug/*` on hosts `crypto.*`
- ALLOW `GET|POST|OPTIONS /api/v1/*`, `/healthz`, `/metrics` publicly
- ALLOW `GET /dashboard/*` only from `10.0.0.0/8 + 172.16.0.0/12 +
  192.168.0.0/16` CIDRs (env-patched by overlays)

**East-west (L3/4 allowlist)** —
`use-case-crypto/manifests/base/network-policies.yaml`:
- `default-deny-ingress` (baseline)
- `allow-same-namespace` (intra-ns trust — single trust boundary)
- Per-peer-namespace rules named by destination pods:
  `allow-airflow-to-processing` selector lists
  `validator|analyzer` (post-ADR-025 `flink-job` removed because Airflow does
  not call Flink JM directly; post-ADR-027 `feature-engine` removed — Rust
  feature-engine retired, Flink owns the speed layer)
  `allow-kfp-to-training-targets` selector lists
  `ml-bridge` only (post-ADR-027 `feature-engine` removed; the Flink
  stream-processor is not exposed — KFP training reads ClickHouse / Feast,
  not the live speed layer)
- `allow-prometheus-scrape` includes port 9249 (Flink reporter, ADR-023)
- `allow-ingress-to-gateway` restricts istio-system → only `app: gateway`
  pod on `:8080`

**Latency budget rationale (why crypto stays out of mesh)**: Sidecar adds
~5ms p50 on the gateway hot path. Thesis SLO `p99 < 500ms` tolerates it but
the ADR-009 decision tree explicitly keeps crypto OUT so the latency budget
is spent on feature engineering, not mTLS handshake. If this assumption
changes, re-read platform ADR-009 first.

## ADR-025 (use-case implementation) — Crypto scale-to-zero placeholder cleanup

Maps to platform ADR-025 (delete scale-to-zero placeholders).

Use-case-side actions:

1. Files deleted:
   - `use-case-crypto/manifests/base/patches/flink-job.yaml`
   - `use-case-crypto/manifests/base/patches/ml-bridge-disable-deployment.yaml`

2. Kustomization edits:
   - `base/kustomization.yaml` — `- .../flink-job.yaml` + two `patches:` entries removed
   - `base-data/kustomization.yaml` — `- .../flink-job.yaml` replaced with
     `- ../base/flink/flinkdeployment.yaml`
   - `overlays/{local,cloud,local-data}/kustomization.yaml` — `name: flink-job`
     image / replicas / resource / probe patches removed

3. Resources rescoped to FlinkDeployment pod labels:
   - `base/hpa/autoscaling.yaml` — `stream-processor-jobmanager-pdb` selects
     `app: crypto-stream-processor, component: jobmanager`
   - `base/observability/servicemonitors.yaml` — **PodMonitor**
     selecting `app: crypto-stream-processor, component: jobmanager` on named port
     `metrics` (9249)
   - `base/network-policies.yaml` — port 8083 removed; selectors updated
     per ADR-024 implementation above
   - `base/flink/flinkdeployment.yaml` — podTemplate declares named ports
     `metrics` (9249) and `jm-rest` (8081) so PodMonitor can scrape by name

**Why the FlinkDeployment is NOT lifted to platform/services/base**: the CR
embeds the crypto image name, jar entry class, checkpoint paths, and
consumer-group id. Lifting it either re-introduces templating noise or
forces nine lines of overrides per use case. Leaving it use-case-scoped is
consistent with platform ADR-013's domain-agnostic split.

## ADR-026 (use-case implementation) — Crypto gateway HPA → KEDA migration

Maps to platform ADR-026 (retire prometheus-adapter; KEDA single plane).

Use-case-side actions:

1. Delete the legacy custom-metric HPA:
   ```bash
   kubectl delete hpa -n use-case-crypto crypto-gateway-hpa --ignore-not-found
   ```

2. Apply the new KEDA `ScaledObject` (declared in
   `use-case-crypto/manifests/base/scaling/scaledobjects.yaml` per ADR-022):
   ```bash
   kubectl apply -k use-case-crypto/manifests/overlays/local
   ```

The new ScaledObject `gateway-http-rps` has three triggers (prometheus +
cpu + memory), OR-combined into a single KEDA-generated HPA
(`keda-hpa-gateway-http-rps`). The `behavior` block preserves the prior
HPA's scale-up burst (Max of +100% or +4 pods per 15s) and 5-minute
scale-down window.

Apply order matters: APIService deletions BEFORE Deployment deletion (or
`kubectl apply` leaves APIService pointing at non-existent Service and every
custom-metric HPA query returns `failed to fetch metric` for ~30 min).

## ADR-027 (use-case implementation) — Flink owns the crypto speed layer (End-state Y)

Supersedes ADR-023. The crypto streaming feature path is owned end-to-end by a
single Apache Flink application-mode `FlinkDeployment`
(`use-case-crypto/manifests/base/flink/stream-processor.yaml`). The bespoke Rust
`feature-engine` Deployment is **retired**.

### Decision

One engine for the speed layer. The platform `flink-job` image
(`com.pipeline.StreamJob`, a domain-agnostic harness) runs **as-is** — crypto
references it through the overlay `images:` mapping
(`flink-job` → `localhost:5000/crypto-flink-job:latest`), exactly like every
other service. There is **no** crypto extension jar and **no**
`crypto-stream-processor` image (the ADR-023 shape): the feature function is the
platform `com.pipeline.functions.FeatureFunction`, wired purely by env on the
FlinkDeployment podTemplate (`ENABLED_STREAMS=time_series`,
`STREAM_TIME_SERIES_*`, `VALKEY_HOST/PORT`). All indicator knobs stay in
`configmaps/features.yaml` (inherited via `pipeline-config`). A new use case
copies `use-case-crypto/`, edits these env values, and reuses the same image.

### Dual sink (lambda speed layer)

1. **Kafka** `crypto.features.v1` (EXACTLY_ONCE, txn-id prefix `crypto.flink-features`)
   → ClickHouse `bronze.crypto_features_kafka` Kafka-engine → MV →
   `bronze.crypto_ohlcv_features`. Feeds the batch↔stream parity oracle (KF-11 /
   SK-F-11).
2. **Valkey** `features:{symbol}` (online low-latency cache) — enabled by
   `STREAM_TIME_SERIES_KEY_PREFIX`; `RedisSink` strips the routing fields
   (`symbol`, numeric `timestamp`) so the stored value is the pure
   `{feature: number}` map.

### Schema parity (the make-or-break of the cutover — VERIFIED statically)

`bronze.crypto_features_kafka` and the `feature-cache` reader were built for the
**Rust** feature-engine's JSON. Replacing that producer with the **Java**
`FeatureFunction` only works if the serialized fields match. Verified field-by-field:

- **Bronze**: `FeatureFunction` main output is `{symbol, timestamp (string
  "yyyy-MM-dd HH:mm:ss.SSS"), <passthrough OHLCV + source>, <indicators>}`.
  `Indicators.computeAll` emits exact-match keys for every MV-consumed column —
  `rolling_mean_7/14`, `rolling_ema_12/26`, `momentum_14`, `band_upper/lower`,
  `dispersion`, `value_change`, `secondary_avg` — plus `trend_convergence` /
  `trend_signal` from the stateful `computeTrend`. The period suffixes are driven
  by `FLINK_ROLLING_MEAN_PERIODS=7,14`, `FLINK_EXP_AVG_PERIODS=12,26`,
  `FLINK_MOMENTUM_PERIOD=14`; bands + trend are enabled in `features.yaml`. Extra
  keys (`value`, `band_middle`, `trend_hist`) are ignored by `JSONEachRow`.
- **Valkey**: `RedisSink` writes the indicator map alone (`BTreeMap<String,f64>`-
  compatible) — byte-compatible with the historical writer, so `feature-cache`'s
  `serde_json::from_str::<Features>` parses identically.

### EXACTLY_ONCE → bronze isolation

Flink writes transactional records to `crypto.features.v1` (feature-engine wrote
plain). The ClickHouse Kafka engine consumes via **librdkafka, whose
`isolation.level` default is `read_committed`** — so aborted-transaction records
are never surfaced, and `bronze.crypto_ohlcv_features`
(`ReplicatedReplacingMergeTree ORDER BY (symbol,timestamp)`) dedupes any
transient restart duplicate on merge. No isolation config change required.

### Deliberate divergence — `trend_signal`

`FeatureFunction.computeTrend` derives a real **stateful EMA** signal line over
the MACD-line window, replacing the feature-engine's `signal = convergence*0.2`
approximation. This strictly improves correctness; it does **not** affect
batch↔stream parity, which is asserted on the volume SMA (`secondary_avg` ↔ dbt
`volume_sma_20`), not the trend triple.

### Kustomize plumbing (the CRD is opaque to kustomize)

- **Image**: the image transformer does not walk `FlinkDeployment.spec.image`
  (a CRD field, not a PodSpec container path). An `images:` FieldSpec in
  `kustomize-config/name-reference.yaml` teaches it to — additive, so regular
  Deployment images keep being rewritten.
- **Name references**: `namePrefix: crypto-` does not rewrite CRD-internal string
  refs. nameReference rules rewrite `spec/serviceAccount` (`flink`→`crypto-flink`)
  and the podTemplate `configMapRef` (`pipeline-config`→`crypto-pipeline-config`).
  The `secretRef` envFroms (`pipeline-secrets`, `flink-s3-secret`,
  `crypto-app-consumer`) stay **raw** — each is an ExternalSecret `target.name`
  literal, so the rendered ref already matches the live Secret.
- **Operator reachability**: crypto has istio-injection disabled, so NetworkPolicy
  is the sole layer. `allow-flink-operator` permits the operator
  (`flink-operator` ns) → JM REST `:8081`; without it the FlinkDeployment hangs
  in RECONCILING (regression class of the #475 status disconnect).
  `allow-prometheus-scrape` gains port `:9249`.

### Kafka ACL (zero change)

The shared `crypto-app-consumer` KafkaUser already grants group `flink-*`, topic
`crypto.*` (R/W), and transactionalId `crypto.*` (Write). The stream's group
`flink-features`, topics `crypto.validated`/`crypto.features.v1`, and txn-id
prefix `crypto.flink-features` all fall under those prefixes — EXACTLY_ONCE works
with no ACL edit.

### Cutover — atomic swap, not "both running"

feature-engine and Flink target the **same** sinks; rendering both would
double-write bronze (~2× rows per `(symbol,timestamp)`). So the swap is atomic in
one change: Flink **in** the data path, feature-engine **out** (resource line,
ScaledObject, kafka-sasl patch entry, ServiceMonitor→PodMonitor, PDB, SLO →
`flink-features`). feature-engine **source is kept on disk** for rollback (re-add
one resource line). The data-path slice of the retirement collapses into Phase 2;
the cosmetic scrub (dead `pipeline-config` group-id key, scram-users ACL entries,
Tekton CI build step, secondary overlays, chaos exp) follows.

**Apply ordering (hard dependency):** `crypto-flink-job` must exist in the
registry (`make usecase-crypto-build`) **before** applying the overlay, or the
speed layer is down until it does. The static gate is
`kustomize build --load-restrictor LoadRestrictionsNone
use-case-crypto/manifests/overlays/local` (verified: image/SA/configMapRef
rewrite correctly, secretRefs stay raw, no dangling patches).

### Classloader

The bundled fat jar sets Flink `classloader.parent-first-patterns` to shadow the
bundled Flink core + logging, so it runs cleanly on the `flink:2.2.0` base image.

## Drift-driven retrain (ADR-017 use-case implementation)

Maps to platform ADR-017 (retrain-on-drift via Argo CronWorkflow).

The drift CronWorkflow lives in `use-case-crypto/manifests/base/workflows/retrain-on-drift.yaml`:

- ExternalSecret `crypto-retrain-on-drift` bound to
  `secret/usecases/crypto/clickhouse-admin`
- Argo CronWorkflow `crypto-retrain-on-drift` schedule `0 */6 * * *`
- `measure-drift` template queries `gold.drift_metrics`
- `decide-and-trigger` template POSTs to
  `http://ml-pipeline.model-lifecycle.svc.cluster.local:8888/apis/v2beta1/runs`
  when `PSI > 0.2` or `KS > 0.15`
- Pushes `crypto_retrain_on_drift_{psi,ks,triggered}` samples to Pushgateway
  on every probe (triggered or not) so Prometheus always has a heartbeat
- Prom alert fires on `absent(crypto_retrain_on_drift_psi)` — heartbeat
  missing means the probe itself is broken

Why this lives in use-case scope (not platform): the drift signal is
domain-specific (which `gold.drift_metrics` columns? what thresholds?) and
the consumer-group / topic structure is use-case bound. Platform ADR-017
defines the CronWorkflow pattern; this implementation is the use-case
binding.
