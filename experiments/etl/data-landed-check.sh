#!/usr/bin/env bash
# =============================================================================
# experiments/etl/data-landed-check.sh
# SK-F-11 / SK-N-05 — "did the data actually land?" medallion parity probe
# (validates KF-11 batch+stream landing; supports KNF-05 data-quality).
# =============================================================================
# The data engineer's read-only answer to "is the ETL flowing?". For each
# medallion layer it reports row count and (on the landing table) event-time
# freshness, so an empty silver/gold immediately points at the broken hop —
# this is the manual form of the diagnoses behind #463 (bronze empty) and #470
# (gold empty). It SELECTs only MergeTree target tables; it never touches the
# pipeline state.
#
# ┌─ WARNING — never query a *_kafka table ───────────────────────────────────┐
# │ bronze.crypto_ohlcv_kafka, *_sentiment_kafka, *_features_kafka, *_tickers_  │
# │ kafka, *_trades_kafka, gold.cdc_predictions_kafka are ENGINE = Kafka().     │
# │ A plain SELECT on them CONSUMES the topic offset — the rows you read are    │
# │ dropped from the live stream and never reach the MergeTree target, silently │
# │ corrupting the running pipeline. Always query the MergeTree table the       │
# │ matching *_consumer materialized view writes into (e.g. bronze.crypto_ohlcv │
# │ — the value of $BRONZE_LANDING_TABLE), never the _kafka source. This script │
# │ refuses to run if any configured table name ends in `_kafka`.               │
# └────────────────────────────────────────────────────────────────────────────┘
#
# Run (after loading the config — see experiments/README.md):
#   set -a; . experiments/config.crypto.env; set +a
#   # optional: admin creds if the in-pod default user is password-protected
#   export CLICKHOUSE_USER=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
#     -o jsonpath='{.data.username}' | base64 -d)
#   export CLICKHOUSE_PASSWORD=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
#     -o jsonpath='{.data.password}' | base64 -d)
#   ./experiments/etl/data-landed-check.sh
#
# Exit 0 = every layer has rows; 1 = a layer is empty (broken hop); 2 = setup error.
# =============================================================================
set -euo pipefail

CLICKHOUSE_NAMESPACE="${CLICKHOUSE_NAMESPACE:-storage}"
CLICKHOUSE_CHI="${CLICKHOUSE_CHI:-platform}"
EVENT_TIME_COLUMN="${EVENT_TIME_COLUMN:-timestamp}"
BRONZE_LANDING_TABLE="${BRONZE_LANDING_TABLE:-bronze.crypto_ohlcv}"
SILVER_STAGING_TABLE="${SILVER_STAGING_TABLE:-silver.stg_ohlcv}"
GOLD_FEATURES_TABLE="${GOLD_FEATURES_TABLE:-gold.fct_ohlcv_features}"
GOLD_TRAINING_TABLE="${GOLD_TRAINING_TABLE:-gold.fct_training_data}"

# --- footgun guard: refuse any _kafka (ENGINE=Kafka) table ------------------
for t in "$BRONZE_LANDING_TABLE" "$SILVER_STAGING_TABLE" "$GOLD_FEATURES_TABLE" "$GOLD_TRAINING_TABLE"; do
  if [[ "$t" == *_kafka ]]; then
    echo "REFUSING: '$t' looks like an ENGINE=Kafka table — SELECTing it consumes topic offsets." >&2
    echo "Point the *_TABLE var at the MergeTree target the _consumer MV writes into." >&2
    exit 2
  fi
done

# --- locate the CHI pod ------------------------------------------------------
POD="$(kubectl -n "$CLICKHOUSE_NAMESPACE" get pods \
  -l "clickhouse.altinity.com/chi=${CLICKHOUSE_CHI}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$POD" ]]; then
  echo "ERROR: no ClickHouse pod found (ns=$CLICKHOUSE_NAMESPACE, chi=$CLICKHOUSE_CHI)." >&2
  exit 2
fi

# clickhouse-client auth: pass creds only if supplied (in-pod default user is
# often trusted on localhost; admin creds live in the clickhouse-admin secret).
CH_AUTH=()
[[ -n "${CLICKHOUSE_USER:-}" ]] && CH_AUTH+=(--user "$CLICKHOUSE_USER")
[[ -n "${CLICKHOUSE_PASSWORD:-}" ]] && CH_AUTH+=(--password "$CLICKHOUSE_PASSWORD")

ch_query() {
  # ${CH_AUTH[@]+...} expands to nothing when the array is empty (safe under
  # set -u on bash < 4.4, e.g. macOS) and to the quoted flags when populated.
  kubectl -n "$CLICKHOUSE_NAMESPACE" exec "$POD" -c clickhouse -- \
    clickhouse-client ${CH_AUTH[@]+"${CH_AUTH[@]}"} --query "$1"
}

echo "medallion data-landed check  pod=$POD  ns=$CLICKHOUSE_NAMESPACE"
printf '%-28s %12s  %s\n' "LAYER (table)" "ROWS" "FRESHNESS"
echo "------------------------------------------------------------------------"

empty=0

check_layer() {
  local label="$1" table="$2" with_freshness="${3:-no}"
  local rows freshness="-"
  if [[ "$with_freshness" == "freshness" ]]; then
    # count + max(event-time) + lag seconds, in one round trip
    local out
    out="$(ch_query "SELECT count(), ifNull(toString(max(${EVENT_TIME_COLUMN})),'-'), ifNull(toString(dateDiff('second', max(${EVENT_TIME_COLUMN}), now())),'-') FROM ${table} FORMAT TabSeparated" 2>/dev/null || echo $'ERR\t-\t-')"
    rows="$(echo "$out" | cut -f1)"
    local maxts lag
    maxts="$(echo "$out" | cut -f2)"; lag="$(echo "$out" | cut -f3)"
    freshness="max=${maxts} (${lag}s ago)"
  else
    rows="$(ch_query "SELECT count() FROM ${table}" 2>/dev/null || echo ERR)"
  fi
  printf '%-28s %12s  %s\n' "$label ($table)" "$rows" "$freshness"
  if [[ "$rows" == "0" || "$rows" == "ERR" ]]; then empty=$((empty + 1)); fi
}

check_layer "bronze landing" "$BRONZE_LANDING_TABLE" freshness
check_layer "silver staging" "$SILVER_STAGING_TABLE"
check_layer "gold features"  "$GOLD_FEATURES_TABLE"
check_layer "gold training"  "$GOLD_TRAINING_TABLE"

echo "------------------------------------------------------------------------"
if [[ "$empty" -gt 0 ]]; then
  echo "FAIL: $empty layer(s) empty or unreadable — the ETL has a broken hop upstream of them."
  exit 1
fi
echo "PASS: every medallion layer has rows. KF-11 batch+stream landing verified."
