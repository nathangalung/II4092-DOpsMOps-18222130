#!/usr/bin/env bash
# Live-demo runner: data scenarios plus UI port-forwards.
# Entry point is experiments/Makefile.
# Usage: bash demo.sh <target>
set -euo pipefail

# Resolve paths and bind address.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH_POD="chi-platform-main-0-0-0"
ADDR="${DEMO_ADDR:-127.0.0.1}"

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

# Port-forward a UI, resolving the real service port.
pf() {
  local ns="$1" re="$2" local_port="$3" want="${4:-}" path="${5:-}"
  local svc port
  svc=$(svc_in "$ns" "$re")
  [ -z "$svc" ] && { echo "no service matching '$re' in namespace $ns"; return 1; }
  # Prefer a named or numbered port, else take the first.
  if [ -n "$want" ]; then
    port=$(kubectl get "$svc" -n "$ns" -o jsonpath="{.spec.ports[?(@.name=='$want')].port}" 2>/dev/null)
    [ -z "$port" ] && port=$(kubectl get "$svc" -n "$ns" -o jsonpath="{.spec.ports[?(@.port==$want)].port}" 2>/dev/null)
  fi
  [ -z "$port" ] && port=$(kubectl get "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  [ -z "$port" ] && { echo "could not resolve a port for $svc"; return 1; }
  echo "${svc#service/} in $ns  ->  http://${ADDR}:${local_port}${path}"
  echo "Press Ctrl-C to stop the port-forward"
  kubectl port-forward --address "$ADDR" -n "$ns" "$svc" "${local_port}:${port}"
}

# Decode one secret key, print a fallback.
secret_val() {
  local v; v=$(kubectl get secret -n "$1" "$2" -o jsonpath="{.data.$3}" 2>/dev/null | base64 -d 2>/dev/null)
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "check secret $1/$2"
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
  pf data-governance 'datahub-frontend|frontend' 9002 9002
}

scenario_vector() {
  echo "KF-04 Qdrant vector-search latency"
  kubectl port-forward -n storage svc/qdrant 6333:6333 >/dev/null 2>&1 &
  local p=$!; sleep 4
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
  kill "$p" 2>/dev/null || true
}

# Print UI login details read live.
creds() {
  echo "UI login details, values read from live cluster secrets"
  echo ""
  printf '%-11s %-28s %s\n' TOOL URL LOGIN
  printf '%-11s %-28s %s\n' grafana    "http://${ADDR}:3000" "$(secret_val observability grafana-admin GF_SECURITY_ADMIN_USER) / $(secret_val observability grafana-admin GF_SECURITY_ADMIN_PASSWORD)"
  printf '%-11s %-28s %s\n' datahub    "http://${ADDR}:9002" "datahub / datahub"
  printf '%-11s %-28s %s\n' superset   "http://${ADDR}:8088" "admin / $(secret_val data-processing superset-admin ADMIN_PASSWORD)"
  printf '%-11s %-28s %s\n' argocd     "http://${ADDR}:8081" "admin / $(secret_val gitops argocd-initial-admin-secret password)"
  printf '%-11s %-28s %s\n' minio      "http://${ADDR}:9001" "$(secret_val storage minio MINIO_ROOT_USER) / $(secret_val storage minio MINIO_ROOT_PASSWORD)"
  printf '%-11s %-28s %s\n' mlflow     "http://${ADDR}:5000" "no login"
  printf '%-11s %-28s %s\n' kafka-ui   "http://${ADDR}:8080" "no login"
  printf '%-11s %-28s %s\n' prometheus "http://${ADDR}:9090" "no login"
  printf '%-11s %-28s %s\n' trino      "http://${ADDR}:8082" "any username, no password"
  printf '%-11s %-28s %s\n' airflow    "http://${ADDR}:8085" "admin / $(secret_val data-processing airflow-admin password)"
  printf '%-11s %-28s %s\n' qdrant     "http://${ADDR}:6333/dashboard" "api-key header (pipeline-secrets QDRANT_API_KEY)"
}

case "${1:-help}" in
  data)       scenario_data ;;
  drift)      scenario_drift ;;
  predict)    scenario_predict ;;
  lineage)    scenario_lineage ;;
  vector)     scenario_vector ;;
  creds)      creds ;;
  grafana)    pf observability 'grafana$' 3000 http ;;
  datahub)    pf data-governance 'datahub-frontend|frontend' 9002 9002 ;;
  superset)   pf data-processing 'superset$' 8088 ;;
  argocd)     pf gitops 'argocd-server' 8081 http ;;
  minio)      pf storage '^service/minio$|/minio$' 9001 console ;;
  mlflow)     pf model-lifecycle 'mlflow$' 5000 ;;
  kafka-ui)   pf data-ingestion 'kafka-ui' 8080 ;;
  prometheus) pf observability 'kube-prometheus-stack-prometheus$' 9090 web ;;
  trino)      pf data-processing 'trino$' 8082 ;;
  airflow)    pf data-processing 'airflow-(api-server|webserver|web)$' 8085 ;;
  qdrant)     pf storage 'qdrant$' 6333 6333 /dashboard ;;
  *) echo "usage: bash demo.sh {data|drift|predict|lineage|vector|creds|grafana|datahub|superset|argocd|minio|mlflow|kafka-ui|prometheus|trino|airflow|qdrant}" ;;
esac
