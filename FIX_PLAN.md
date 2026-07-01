# FIX PLAN — end-to-end audit 2026-06-28 (5 parallel domain agents)

Consolidated, exact-spec fix list. Source fixes are durable (apply to file). Live/rebuild
steps are sequenced to avoid IO bursts on the QEMU spinning disk (never rebuild + retrain
concurrently). Honest data-coverage + metric notes per advisor.

## VERIFIED-CORRECT (no action)
- Ingest OHLCV (Coinbase BTC+ETH, 512K rows, 2026-01-01→06-28), trades, tickers — REAL.
- bronze→silver→gold dbt OHLCV/TA path — REAL varying (close 1.5k–98k, RSI 0–100).
- 80/20 split: `platform/services/trainer/src/trainer.py:92` `train_test_split(..., shuffle=False)` —
  time-ordered, NO temporal leakage. ✓
- Drift windows: `platform/services/quality/drift/main.py:241-243` — adjacent equal-length windows
  (comp=[now-Δ,now], ref=[now-2Δ,now-Δ]) per scale (5m/1h/24h/7d/30d). COMPARABLE. ✓ (empty only
  because Flink upstream `bronze.crypto_ohlcv_features`=0.)
- No same-bar OHLC leakage: target=`close.shift(-1)` (next bar); current bar = legit lag feature. ✓
- KServe `crypto-predictor` Ready + serving; MLflow, DataHub GMS, GE, datahub-ingest (clickhouse/
  minio/postgres/feast/mlflow) all WORKING. Filename purity clean (0 violations).

## ⚠️ METRIC HONESTY (thesis-critical)
Trainer r2=0.96 is **autocorrelation/persistence inflation** (target=close[t+1], hourly returns have
tiny variance vs price level). NOT predictive skill. Honest metrics = **directional accuracy** +
**r2 on returns** (`close[t+1]/close[t]-1`). Adding sentiment will NOT change this. Reframe report
claims: "real-data loop closed end-to-end", not "model improved". Add a returns-r2/dir-acc eval to trainer.

## APPLIED THIS SESSION (source, durable)
- platform/services/processing/stream/.../FeatureFunction.java:28 — domain-leak comment genericized.
- platform/scripts/generate_kustomization.py:19 — `usecase-crypto-` → `usecase-<name>-`.
- supplementary-coingecko.yaml — added RESPONSE_FIELD_MAPPING `timestamp=last_updated,value=price_change_percentage_24h,title=name,symbol=symbol`.
- supplementary-defillama.yaml — added mapping `value=change_1d,title=name,symbol=slug` + BACKFILL_ENABLED=false.

## DATA REALITY — per-source coverage (no-synthesis rule)
| source | status | historical? |
|--------|--------|-------------|
| OHLCV/trades/tickers | REAL | full 178d (training-grade) |
| fear-greed | REAL (mapping fixed) | 90d landed, **3066d available** via limit=0 → re-run to full 178d. TRAINING-GRADE |
| coingecko | mapping fixed → real value | snapshot-only → live-serving only, NOT historical |
| defillama | mapping fixed → real value | snapshot-only → live-serving only |
| cryptopanic (news) | TODO config | recent-only → live-serving only |
Leave pre-backfill rows NULL. Do NOT forward-fill/interpolate. Only fear-greed is a real *historical*
training feature; state per-source in report (don't over-claim "sentiment integrated").

## THIS-SESSION CHAIN (scoped): sentiment → gold → retrain
1. Full fear-greed backfill: re-trigger feargreed job (env already limit=0 + mapping) → extend 90d→178d.
2. READ dbt sentiment join FIRST (dim_fear_greed.sql, fct_sentiment_agg.sql, fct_training_data.sql).
   Likely fix = re-run + join-by-DATE for market-wide fear-greed (sentiment.symbol = source-name, NOT
   pair → must NOT join on symbol). dim_fear_greed already exists (0 rows, stale) → may just need re-run.
3. Re-run dbt (silver.stg_sentiment + marts.fct_sentiment_* + dim_fear_greed + fct_training_data).
4. **VARIANCE GATE**: `SELECT uniqExact(fear_greed_value) FROM gold.fct_training_data` must be >1.
   If still 1 → join NOT fixed; do NOT retrain on constant data.
5. Retrain (frame: closes real-data loop). Add returns-r2 + directional-accuracy to trainer eval.

## DEFERRED (exact specs — next session / as budget; serialize heavy IO)

### P1 Flink (online features.v1 + drift) — ✅ DONE + VERIFIED 2026-06-28
DONE: IndicatorConfig Serializable fix applied → rebuilt flink-job + retagged crypto-flink-job:latest →
redeployed FlinkDeployment. Live: job=RUNNING/STABLE, JM+TM 1/1, checkpoints completing, NO
NotSerializableException, `bronze.crypto_ohlcv_features` flowing (live, growing). Unblocks drift_multi_scale
(drift-detector reads it — populates as windows accumulate) + Feast online speed layer.
NOTE: the redeploy burst (large-image unpack + JM/TM cluster spin-up) triggered a ~25-min IO cascade
(load→207, MinIO 0/1) that SELF-RECOVERED. Capacity ceiling — bring heavy services up one-at-a-time,
load-gated. Original spec below (for reference / reproducibility):

### P1 Flink (original spec — applied)
- `platform/services/processing/stream/src/main/java/pipeline/functions/IndicatorConfig.java:12`
  `public final class IndicatorConfig` → `... implements java.io.Serializable` + `private static final long serialVersionUID = 1L;`
  (root cause: `NotSerializableException` → bronze.crypto_ohlcv_features=0 → drift_multi_scale=0).
  Rebuild flink-job image + redeploy. (Decoupled from gold/training path — #476.)

### P1 vector embeddings — needs REBUILD
- DOMAIN-AGNOSTIC CORRECTION: do NOT change embedding.py default to `bronze.crypto_sentiment` (that
  leaks crypto into platform/). Platform stays generic (`text_data` default; already reads
  `VECTOR_DATA_TABLE` env at jobs/embedding.py:33). The real fix is split:
  - USE-CASE (no rebuild): `use-case-crypto/manifests/base/cronjobs/vector-embedding.yaml` — set env
    `VECTOR_DATA_TABLE=bronze.crypto_sentiment` (currently the job wrongly inherits DATA_TABLE=
    bronze.crypto_ohlcv from the shared pipeline-config; VECTOR_DATA_TABLE overrides it).
  - PLATFORM (rebuild, generic): `platform/services/processing/vector/config.py` `load_config()` —
    add `SYMBOLS` env override (generic mechanism; currently defaults SAMPLE-001/002, never reads
    SYMBOLS). Use-case already sets SYMBOLS=BTC-USD,ETH-USD in its ConfigMap.

### P1 cryptopanic news source (source edit, no rebuild)
- `use-case-crypto/manifests/base/patches/supplementary-source.yaml` add:
  `SUPPLEMENTARY_SOURCE_NAME=cryptopanic`, `SUPPLEMENTARY_SOURCE_URL=https://cryptopanic.com/api/v1/posts/?kind=news&public=true`,
  `SUPPLEMENTARY_SOURCE_API_KEY` (valueFrom pipeline-secrets CRYPTOPANIC_API_KEY, optional),
  `RESPONSE_FIELD_MAPPING=root=results,timestamp=published_at,title=title,url=url,symbol=source.domain,value=votes.positive`,
  `SUPPLEMENTARY_BACKFILL_ENABLED=false`. (config.go gates on SUPPLEMENTARY_SOURCE_NAME+URL.)

### P1 sentiment symbol semantics (dbt) 
bronze.crypto_sentiment.symbol = source-name (fear-greed/coingecko/defillama), NOT BTC-USD/ETH-USD.
fear-greed/news = MARKET-WIDE → join to OHLCV by DATE, broadcast to all pairs. coingecko per-coin
(btc/eth) → map to BTC-USD/ETH-USD if used. Fix in dbt models, not ingestion.

### P2 iris canary (platform-health-check Init:CrashLoop)
- `platform/components/storage/minio/bucket-bootstrap.yaml:~409` — the `else` branch after the
  `if [ -f /shared/iris-mlflow/MLmodel ]` guard echoes + exits 0 (silent success) → bucket empty,
  ArgoCD green. Change to `echo "ERROR..." >&2; exit 1`. Then re-run the bootstrap Job (force sync
  storage app) to populate s3://platform-models/sklearn/iris/.

### P2 ops health
- openbao OOM: `platform/components/security/openbao/statefulset.yaml` mem 1Gi→2Gi + readiness timeoutSeconds 1→3.
- chaos-mesh ArgoCD OutOfSync (cert-manager caBundle): add ignoreDifferences on webhook caBundle.
- opentelemetry-operator ArgoCD OutOfSync (CRD caBundle): ignoreDifferences on CRD conversion caBundle.
- kafka-connect-connect-build Error (Kyverno blocks Strimzi buildah needs root): Kyverno PolicyException
  for strimzi build pods (require-capability-drop-all + require-run-as-nonroot).
- ge-checkpoint.yaml:264 `run_and_push uv run /tmp/ge_check.py` → `uv run /tmp/ge_check.py` (push-helper
  bash redundant; py already pushes; uv image lacks curl/wget).

### P2 airflow stale pods (87 inert Error, orphaned, 0 CPU — safe GC)
- Cleanup: `kubectl delete pods -n use-case-crypto -l kubernetes_pod_operator=True,already_checked=True`.
- Prevent: KPO `on_finish_action="delete_pod"` in DAGs + `ttlSecondsAfterFinished: 3600` on pod template.
- Root cause of exit-1 (batch-features/dbt-run ≥2d): diagnose logs from a fresh run (blocks dbt lineage).

### P2 training/drift deploy (not applied live)
- Katib experiment: apply base-train overlay. KFP: run `use-case-crypto/pipelines/submit_recurring.py`.
- retrain-on-drift CronWorkflow: `kubectl apply -f manifests/base/workflows/retrain-on-drift.yaml -n model-lifecycle`
  (after KFP pipeline registered). NOTE: drift needs Flink features first.

### P1 storage / data-lake / online-store (5th agent)
- **feature-cache** FIXED (source): `platform/services/base/deployments/feature-cache.yaml` — env
  `FCACHE_REDIS_URL/HEALTH_PORT/GRPC_PORT` → `FCACHE__...` (double-underscore; config crate
  `prefix("FCACHE").separator("__")` ignored single-underscore → redis_url fell to localhost:6379 →
  ECONNREFUSED → Valkey empty → ml-bridge served nulls). No rebuild; rollout to apply.
- **lakeFS crypto repo: ✅ DONE 2026-06-28** — created `lakefs://crypto` (storage s3://lakefs/crypto,
  branch main) via `lakectl` in the lakefs pod. Verified in repo list. Reproducible: the lakehouse DAG's
  idempotent `ensure_lakefs_repo` (#487) recreates it; manual create just unblocked now.
- **lakekeeper 0 warehouses**: PG rebuild (2d5h ago) wiped the lakekeeper DB; the
  `iceberg-sink-registration` PostSync hook (use-case-crypto/manifests/base/connectors/iceberg-sink.yaml)
  completed+deleted 16d ago so won't re-run. FIX = re-run that Job (ArgoCD re-sync use-case-crypto, OR
  render+apply just the iceberg-sink Job) → recreates warehouse + bronze namespace + Iceberg sink.
  NOTE: an ad-hoc curl pod got HTTP 000 to lakekeeper:8181 — the storage-ns NetworkPolicy/mesh only admits
  the actual Job pod's labels, so use the real Job (don't ad-hoc). Unblocks Trino `iceberg` catalog.
- **Valkey empty / Feast registry 54B**: cascade from feature-cache (now fixed) + batch_features failing.
  After feature-cache rollout + batch_features fix → feast materialize populates Valkey → ml-bridge real.
- Trino self-announce warnings: cosmetic (queries to clickhouse catalog work, 512K verified). Optional:
  discovery.uri localhost→FQDN in trino/deployment.yaml.

### P3 structure (low — mostly acceptable Kustomize convention)
- 3 platform lone-file dirs (opencost/opensearch/kafka-ui) lack kustomization.yaml.
- `platform/services/drift-reporter/` → move under `platform/services/quality/evidently-reporter/` (consistency).
- base/kustomize-config/name-reference.yaml could inline into base kustomization `configurations:`.
- Feast 177 restarts (online store unstable) — separate investigation.
