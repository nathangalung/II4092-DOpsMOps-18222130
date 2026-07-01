#!/usr/bin/env bash
# Live-demo scenario runner.
# Entry point is experiments/Makefile.
# Usage: bash demo.sh <scenario>
set -euo pipefail

# Resolve paths from script.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH_POD="chi-platform-main-0-0-0"

# Query the ClickHouse pod.
ch() {
  local u p
  u=$(kubectl get secret -n storage clickhouse-admin -o jsonpath='{.data.CLICKHOUSE_USER}' | base64 -d)
  p=$(kubectl get secret -n storage clickhouse-admin -o jsonpath='{.data.CLICKHOUSE_PASSWORD}' | base64 -d)
  kubectl exec -n storage "$CH_POD" -c clickhouse -- \
    clickhouse-client --user "$u" --password "$p" -q "$1"
}

# Find a service by keyword.
svc_in() {
  kubectl get svc -n "$1" -o name 2>/dev/null | grep -iE "$2" | head -1
}

scenario_data() {
  echo "KF-03/05 Data landing, bronze to gold"
  ch "SELECT * FROM (
        SELECT 'bronze.crypto_ohlcv'     AS tbl, count() AS rows FROM bronze.crypto_ohlcv
        UNION ALL SELECT 'bronze.crypto_trades',    count() FROM bronze.crypto_trades
        UNION ALL SELECT 'bronze.crypto_sentiment', count() FROM bronze.crypto_sentiment
        UNION ALL SELECT 'gold.fct_training_data',  count() FROM gold.fct_training_data
      ) ORDER BY tbl FORMAT PrettyCompact"
  echo "Coverage window"
  ch "SELECT toString(min(timestamp)) AS first_bar, toString(max(timestamp)) AS last_bar,
             count() AS bars FROM bronze.crypto_ohlcv FORMAT PrettyCompact"
}

scenario_drift() {
  echo "KF-07 Drift detection, multi-scale PSI and KS"
  ch "SELECT scale, feature_name, round(psi_value,3) AS PSI, round(ks_statistic,3) AS KS,
             drift_detected, trigger_retrain
      FROM gold.drift_multi_scale ORDER BY psi_value DESC LIMIT 6 FORMAT PrettyCompact"
  echo "Retrain workflow triggered by drift"
  kubectl get workflow -n model-lifecycle 2>/dev/null | grep -i retrain \
    || echo "scale up model-lifecycle to see the workflow"
}

scenario_predict() {
  echo "Serving, latest predictions and direction"
  ch "SELECT symbol, round(predicted_price,2) AS predicted_price, predicted_direction AS direction,
             round(confidence,3) AS confidence, model_type
      FROM gold.crypto_predictions ORDER BY created_at DESC LIMIT 8 FORMAT PrettyCompact"
  echo "Direction is the buy hold sell signal, model is FLAML-selected lightgbm"
}

scenario_lineage() {
  echo "KF-08 DataHub lineage UI"
  local s; s=$(svc_in data-governance 'datahub-frontend|frontend')
  [ -z "$s" ] && { echo "datahub-frontend service not found"; return 1; }
  echo "Open http://localhost:9002 then press Ctrl-C"
  kubectl port-forward -n data-governance "$s" 9002:9002
}

scenario_vector() {
  echo "KF-04 Qdrant vector-search latency"
  kubectl port-forward -n storage svc/qdrant 6333:6333 >/dev/null 2>&1 &
  local pf=$!; sleep 4
  if command -v k6 >/dev/null 2>&1; then
    k6 run "$HERE/load/vector-search-latency.js" || echo "k6 run failed, check Qdrant"
  else
    # Fallback without k6, time the API.
    local key; key=$(kubectl get secret -n use-case-crypto pipeline-secrets -o jsonpath='{.data.QDRANT_API_KEY}' 2>/dev/null | base64 -d)
    echo "k6 absent, measuring Qdrant API latency over 50 calls"
    for i in $(seq 1 50); do
      curl -s -o /dev/null -w "%{time_total}\n" -H "api-key: $key" http://localhost:6333/collections
    done | awk '{ ms=$1*1000; s+=ms; if(ms>mx)mx=ms; n++ } END{ printf "avg=%.2fms max=%.2fms n=%d\n", s/n, mx, n }'
  fi
  kill "$pf" 2>/dev/null || true
}

case "${1:-help}" in
  data)    scenario_data ;;
  drift)   scenario_drift ;;
  predict) scenario_predict ;;
  lineage) scenario_lineage ;;
  vector)  scenario_vector ;;
  *) echo "usage: bash demo.sh {data|drift|predict|lineage|vector}" ;;
esac
