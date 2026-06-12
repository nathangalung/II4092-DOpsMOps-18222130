#!/usr/bin/env bash
# =============================================================================
# experiments/parity/parity-check.sh
# KF-11 / SK-F-11 — batch ↔ stream feature PARITY oracle
# =============================================================================
# The data engineer's read-only answer to "do the two halves of the lambda
# architecture agree?". The stream path (Flink FeatureFunction →
# crypto.features.v1 → ClickHouse Kafka engine → MV → STREAM_TABLE) and the
# batch path (Airflow lakehouse DAG → dbt → BATCH_TABLE) both compute a
# trailing N-event volume mean per symbol in event-time order:
#
#   stream: Indicators.rollingMean(volume, FLINK_SECONDARY_AVG_PERIOD=20)
#           → column `secondary_avg`
#   batch:  avg(volume) OVER (PARTITION BY symbol ORDER BY timestamp
#           ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
#           → column `volume_sma_20`  (dbt marts/fct_ohlcv_features.sql)
#
# This script inner-joins the two tables on (symbol, event-time) over a
# lookback window and asserts a tolerance-based match rate. It SELECTs only
# MergeTree tables; it never touches pipeline state.
#
# Known, legitimate divergence sources (why this is a MATCH RATE, not strict
# equality):
#   * stream warm-up — after a Flink restart without state restore the
#     trailing window refills from empty, so the first <N events per symbol
#     average fewer rows than the batch side (which always sees full history);
#   * dedup ordering — batch reads the deduplicated silver view while the
#     stream averages events in arrival order, so a duplicate-heavy second can
#     shift the trailing window by one event;
#   * float representation — Java double vs ClickHouse Float64 round-trip
#     through JSON; covered by the relative tolerance.
#
# ┌─ WARNING — never query a *_kafka table ────────────────────────────────────┐
# │ ENGINE = Kafka() tables consume topic offsets on SELECT. Always point the   │
# │ *_TABLE vars at the MergeTree target the _consumer MV writes into.          │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# Run (after loading the config — see experiments/README.md):
#   set -a; . experiments/config.crypto.env; set +a
#   # optional: admin creds if the in-pod default user is password-protected
#   export CLICKHOUSE_USER=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
#     -o jsonpath='{.data.username}' | base64 -d)
#   export CLICKHOUSE_PASSWORD=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
#     -o jsonpath='{.data.password}' | base64 -d)
#   ./experiments/parity/parity-check.sh
#
# Exit 0 = match rate ≥ threshold; 1 = parity broken (or no overlapping rows);
# 2 = setup error.
# =============================================================================
set -euo pipefail

CLICKHOUSE_NAMESPACE="${CLICKHOUSE_NAMESPACE:-storage}"
CLICKHOUSE_CHI="${CLICKHOUSE_CHI:-platform}"
EVENT_TIME_COLUMN="${EVENT_TIME_COLUMN:-timestamp}"
PARITY_BATCH_TABLE="${PARITY_BATCH_TABLE:-gold.fct_ohlcv_features}"
PARITY_BATCH_COLUMN="${PARITY_BATCH_COLUMN:-volume_sma_20}"
PARITY_STREAM_TABLE="${PARITY_STREAM_TABLE:-bronze.crypto_ohlcv_features}"
PARITY_STREAM_COLUMN="${PARITY_STREAM_COLUMN:-secondary_avg}"
PARITY_LOOKBACK_HOURS="${PARITY_LOOKBACK_HOURS:-24}"
# A row matches when |batch - stream| <= max(ABS_TOLERANCE, REL_TOLERANCE*|stream|).
PARITY_REL_TOLERANCE="${PARITY_REL_TOLERANCE:-0.000001}"
PARITY_ABS_TOLERANCE="${PARITY_ABS_TOLERANCE:-0.000001}"
# KF-11 pass criterion: fraction of joined rows inside tolerance.
PARITY_MIN_MATCH_RATE="${PARITY_MIN_MATCH_RATE:-0.99}"

# --- footgun guard: refuse any _kafka (ENGINE=Kafka) table ------------------
for t in "$PARITY_BATCH_TABLE" "$PARITY_STREAM_TABLE"; do
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

CH_AUTH=()
[[ -n "${CLICKHOUSE_USER:-}" ]] && CH_AUTH+=(--user "$CLICKHOUSE_USER")
[[ -n "${CLICKHOUSE_PASSWORD:-}" ]] && CH_AUTH+=(--password "$CLICKHOUSE_PASSWORD")

ch_query() {
  kubectl -n "$CLICKHOUSE_NAMESPACE" exec "$POD" -c clickhouse -- \
    clickhouse-client ${CH_AUTH[@]+"${CH_AUTH[@]}"} --query "$1"
}

echo "batch↔stream parity check  pod=$POD  ns=$CLICKHOUSE_NAMESPACE"
echo "  batch : ${PARITY_BATCH_TABLE}.${PARITY_BATCH_COLUMN}"
echo "  stream: ${PARITY_STREAM_TABLE}.${PARITY_STREAM_COLUMN}"
echo "  window: last ${PARITY_LOOKBACK_HOURS}h   tolerance: rel=${PARITY_REL_TOLERANCE} abs=${PARITY_ABS_TOLERANCE}   pass: match_rate>=${PARITY_MIN_MATCH_RATE}"
echo "------------------------------------------------------------------------"

# One round trip: joined rows, matched rows, p50/p99 relative error, worst row.
# FINAL collapses ReplacingMergeTree duplicates on the stream side so a not-yet-
# merged restart duplicate cannot double-join.
OUT="$(ch_query "
  WITH b AS (
    SELECT symbol, ${EVENT_TIME_COLUMN} AS ts, ${PARITY_BATCH_COLUMN} AS batch_v
    FROM ${PARITY_BATCH_TABLE}
    WHERE ${EVENT_TIME_COLUMN} >= now() - INTERVAL ${PARITY_LOOKBACK_HOURS} HOUR
  ),
  s AS (
    SELECT symbol, ${EVENT_TIME_COLUMN} AS ts, ${PARITY_STREAM_COLUMN} AS stream_v
    FROM ${PARITY_STREAM_TABLE} FINAL
    WHERE ${EVENT_TIME_COLUMN} >= now() - INTERVAL ${PARITY_LOOKBACK_HOURS} HOUR
  )
  SELECT
    count()                                                            AS joined,
    countIf(abs(batch_v - stream_v)
            <= greatest(${PARITY_ABS_TOLERANCE},
                        ${PARITY_REL_TOLERANCE} * abs(stream_v)))      AS matched,
    ifNull(toString(round(quantile(0.5)(
        abs(batch_v - stream_v) / nullIf(abs(stream_v), 0)), 9)), '-') AS p50_rel_err,
    ifNull(toString(round(quantile(0.99)(
        abs(batch_v - stream_v) / nullIf(abs(stream_v), 0)), 9)), '-') AS p99_rel_err
  FROM b INNER JOIN s USING (symbol, ts)
  FORMAT TabSeparated" 2>/dev/null || echo $'ERR\t0\t-\t-')"

joined="$(echo "$OUT" | cut -f1)"
matched="$(echo "$OUT" | cut -f2)"
p50="$(echo "$OUT" | cut -f3)"
p99="$(echo "$OUT" | cut -f4)"

if [[ "$joined" == "ERR" ]]; then
  echo "ERROR: parity query failed — check tables/columns exist (has dbt published ${PARITY_BATCH_COLUMN} yet?)." >&2
  exit 2
fi

printf 'joined rows : %s\nmatched     : %s\np50 rel err : %s\np99 rel err : %s\n' \
  "$joined" "$matched" "$p50" "$p99"

if [[ "$joined" == "0" ]]; then
  echo "------------------------------------------------------------------------"
  echo "FAIL: zero overlapping (symbol, ${EVENT_TIME_COLUMN}) rows in the last ${PARITY_LOOKBACK_HOURS}h."
  echo "Either one path is not landing (run experiments/etl/data-landed-check.sh)"
  echo "or the batch table was last built before the stream window began."
  exit 1
fi

# match rate with 6-decimal precision via awk (bash has no float arithmetic)
rate="$(awk -v m="$matched" -v j="$joined" 'BEGIN { printf "%.6f", m / j }')"
echo "match rate  : $rate"
echo "------------------------------------------------------------------------"
ok="$(awk -v r="$rate" -v t="$PARITY_MIN_MATCH_RATE" 'BEGIN { print (r >= t) ? 1 : 0 }')"
if [[ "$ok" == "1" ]]; then
  echo "PASS: batch↔stream parity holds (KF-11 / SK-F-11)."
  exit 0
fi
echo "FAIL: match rate $rate < ${PARITY_MIN_MATCH_RATE} — the lambda halves disagree."
echo "Inspect the worst offenders:"
echo "  SELECT symbol, ${EVENT_TIME_COLUMN}, ${PARITY_BATCH_COLUMN}, ${PARITY_STREAM_COLUMN}"
echo "  FROM ${PARITY_BATCH_TABLE} INNER JOIN ${PARITY_STREAM_TABLE} FINAL USING (symbol, ${EVENT_TIME_COLUMN})"
echo "  ORDER BY abs(${PARITY_BATCH_COLUMN} - ${PARITY_STREAM_COLUMN}) DESC LIMIT 20"
exit 1
