#!/usr/bin/env bash
# Live demo and evaluation runner.
# Entry point is experiments/Makefile.
# Usage: bash demo.sh <command> [stage]
set -euo pipefail

# Resolve paths and bind address.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ADDR="${DEMO_ADDR:-127.0.0.1}"
CONFIG="${EXPERIMENTS_CONFIG:-$HERE/config.crypto.env}"

# Load domain and endpoint values.
if [ -f "$CONFIG" ]; then set -a; . "$CONFIG"; set +a; fi

# Demo-only defaults, config overrides.
USE_CASE_NAMESPACE="${USE_CASE_NAMESPACE:-use-case-crypto}"
CLICKHOUSE_NAMESPACE="${CLICKHOUSE_NAMESPACE:-storage}"
CLICKHOUSE_CHI="${CLICKHOUSE_CHI:-platform}"
BRONZE_LANDING_TABLE="${BRONZE_LANDING_TABLE:-bronze.crypto_ohlcv}"
GOLD_FEATURES_TABLE="${GOLD_FEATURES_TABLE:-gold.fct_ohlcv_features}"
GOLD_TRAINING_TABLE="${GOLD_TRAINING_TABLE:-gold.fct_training_data}"
PREDICTIONS_TABLE="${PREDICTIONS_TABLE:-gold.crypto_predictions}"
DRIFT_TABLE="${DRIFT_TABLE:-gold.drift_multi_scale}"
PREDICTOR_NAME="${PREDICTOR_NAME:-crypto-predictor}"

# Pipeline stages in run order.
STAGES="ingest process feast train serve drift govern"

# Query the ClickHouse pod.
ch() {
  local pod u p auth=()
  pod=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get pods \
    -l "clickhouse.altinity.com/chi=$CLICKHOUSE_CHI" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -z "$pod" ] && { echo "no ClickHouse pod (ns=$CLICKHOUSE_NAMESPACE)"; return 1; }
  u=$(kubectl get secret -n "$CLICKHOUSE_NAMESPACE" clickhouse-admin \
    -o jsonpath='{.data.CLICKHOUSE_USER}' 2>/dev/null | base64 -d 2>/dev/null || true)
  p=$(kubectl get secret -n "$CLICKHOUSE_NAMESPACE" clickhouse-admin \
    -o jsonpath='{.data.CLICKHOUSE_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$u" ] && auth+=(--user "$u")
  [ -n "$p" ] && auth+=(--password "$p")
  kubectl -n "$CLICKHOUSE_NAMESPACE" exec "$pod" -c clickhouse -- \
    clickhouse-client ${auth[@]+"${auth[@]}"} -q "$1"
}

# Find one service by keyword.
svc_name() {
  kubectl get svc -n "$1" -o name 2>/dev/null | grep -iE "$2" | head -1 | sed 's,^service/,,' || true
}

# Find one deployment by keyword.
deploy_name() {
  kubectl get deploy -n "$1" -o name 2>/dev/null | grep -iE "$2" | head -1 | sed 's,^deployment.apps/,,' || true
}

# Print one wiring row.
row() { printf '  %-32s %s\n' "$1" "$2"; }

# Service presence and readiness.
check_svc() {
  local ns="$1" re="$2" label="$3" name ep
  name=$(svc_name "$ns" "$re")
  [ -z "$name" ] && { row "$label" "MISSING, no service"; return 0; }
  ep=$(kubectl get endpoints -n "$ns" "$name" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  [ -n "$ep" ] && row "$label" "ready ($name)" || row "$label" "wired, no ready pod ($name)"
}

# Deployment presence and readiness.
check_deploy() {
  local ns="$1" re="$2" label="$3" name avail
  name=$(deploy_name "$ns" "$re")
  [ -z "$name" ] && { row "$label" "MISSING, no deployment"; return 0; }
  avail=$(kubectl get deploy -n "$ns" "$name" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
  case "${avail:-0}" in ''|*[!0-9]*) avail=0 ;; esac
  [ "$avail" -gt 0 ] && row "$label" "running ($name)" || row "$label" "deployed, 0 ready ($name)"
}

# Report presence of a CronJob.
check_cronjob() {
  local ns="$1" re="$2" label="$3"
  kubectl get cronjob -n "$ns" -o name 2>/dev/null | grep -qiE "$re" \
    && row "$label" "present" || row "$label" "MISSING"
}

# Report presence of a ConfigMap.
check_configmap() {
  local ns="$1" re="$2" label="$3"
  kubectl get configmap -n "$ns" -o name 2>/dev/null | grep -qiE "$re" \
    && row "$label" "present" || row "$label" "MISSING"
}

# Report a ClickHouse table exists.
check_table() {
  local t="$1" label="$2" r
  r=$(ch "EXISTS TABLE $t" 2>/dev/null || true)
  [ "$r" = "1" ] && row "$label" "exists" || row "$label" "MISSING or unreachable"
}

# Report a KServe InferenceService.
check_isvc() {
  local ns="$1" name="$2" label="$3" url
  kubectl get inferenceservice -n "$ns" "$name" >/dev/null 2>&1 \
    || { row "$label" "MISSING, no InferenceService"; return 0; }
  url=$(kubectl get inferenceservice -n "$ns" "$name" \
    -o jsonpath='{.status.url}' 2>/dev/null || true)
  [ -n "$url" ] && row "$label" "ready ($url)" || row "$label" "applied, not ready"
}

# Report an Argo Rollout.
check_rollout() {
  local ns="$1" re="$2" label="$3" name
  name=$(kubectl get rollout -n "$ns" -o name 2>/dev/null | grep -iE "$re" | head -1 || true)
  [ -n "$name" ] && row "$label" "present ($name)" || row "$label" "MISSING, no rollout"
}

# Run one experiment script.
run_script() {
  local rel="$1"; shift || true
  [ -f "$HERE/$rel" ] || { echo "missing script $rel"; return 1; }
  bash "$HERE/$rel" "$@"
}

# Background port-forward, print pid.
pf_bg() {
  local ns="$1" name="$2" lp="$3" tp="$4"
  kubectl port-forward -n "$ns" "svc/$name" "$lp:$tp" >/dev/null 2>&1 &
  echo $!
}

verify_ingest() {
  echo "ingest wiring"
  kubectl get kafka -n data-ingestion -o name >/dev/null 2>&1 \
    && row "kafka cluster (strimzi)" "present" || row "kafka cluster (strimzi)" "MISSING"
  check_deploy "$USE_CASE_NAMESPACE" 'collector|ingest|websocket|rest' "source collector"
  check_table "$BRONZE_LANDING_TABLE" "bronze landing table"
}

verify_process() {
  echo "process wiring"
  check_svc "$CLICKHOUSE_NAMESPACE" 'clickhouse' "clickhouse warehouse"
  check_deploy "$USE_CASE_NAMESPACE" 'stream-processor|flink|processor' "stream processor (flink)"
  check_table "$GOLD_FEATURES_TABLE" "gold features table"
}

verify_feast() {
  echo "feast wiring"
  check_svc model-lifecycle 'feast' "feast feature server"
  check_svc storage 'valkey|redis' "online store"
  check_configmap "$USE_CASE_NAMESPACE" 'feast-feature-repo|feast' "feast feature repo"
}

verify_train() {
  echo "train wiring"
  check_svc model-lifecycle 'mlflow' "mlflow tracking"
  [ -f "$ROOT/use-case-crypto/pipelines/retraining_pipeline.py" ] \
    && row "kfp pipeline source" "present" || row "kfp pipeline source" "MISSING"
  check_table "$GOLD_TRAINING_TABLE" "training data mart"
}

verify_serve() {
  echo "serve wiring"
  check_isvc "$USE_CASE_NAMESPACE" "$PREDICTOR_NAME" "predictor inferenceservice"
  check_rollout "$USE_CASE_NAMESPACE" 'ml-bridge|bridge' "ml-bridge rollout"
  check_table "$PREDICTIONS_TABLE" "predictions table"
}

verify_drift() {
  echo "drift wiring"
  check_cronjob "$USE_CASE_NAMESPACE" 'drift' "drift detector cronjob"
  kubectl get cronworkflow -n model-lifecycle -o name 2>/dev/null | grep -qiE 'retrain' \
    && row "retrain cronworkflow" "present" || row "retrain cronworkflow" "MISSING"
  check_table "$DRIFT_TABLE" "drift scores table"
}

verify_govern() {
  echo "govern wiring"
  check_svc data-governance 'datahub-gms|gms' "datahub gms"
  check_svc data-governance 'datahub-frontend|frontend' "datahub frontend"
}

show_ingest() {
  echo "ingest evidence, medallion landing and freshness"
  run_script etl/data-landed-check.sh || true
}

show_process() {
  echo "process evidence, medallion rows"
  run_script etl/data-landed-check.sh || true
  echo
  echo "batch vs stream feature parity (KF-11)"
  run_script parity/parity-check.sh || true
}

show_feast() {
  echo "feast evidence, online non-null features (KF-02)"
  command -v uv >/dev/null 2>&1 || { echo "uv not installed, skipping"; return 0; }
  local name pid
  name=$(svc_name model-lifecycle 'feast')
  [ -z "$name" ] && { echo "feast service not found"; return 0; }
  pid=$(pf_bg model-lifecycle "$name" 6566 6566); sleep 4
  FEAST_URL="http://127.0.0.1:6566" uv run "$HERE/feast/online-serving-check.py" || true
  kill "$pid" 2>/dev/null || true
}

show_train() {
  echo "train evidence, input readiness and last job"
  ch "SELECT count() AS training_rows FROM $GOLD_TRAINING_TABLE FORMAT PrettyCompact" || true
  kubectl get job -n "$USE_CASE_NAMESPACE" 2>/dev/null | grep -iE 'train' \
    || echo "no training job yet, trigger with make provision help"
}

show_serve() {
  echo "serve evidence, latest predictions"
  ch "SELECT symbol, round(predicted_price,2) AS predicted_price,
             predicted_direction AS direction, round(confidence,3) AS confidence, model_type
      FROM $PREDICTIONS_TABLE ORDER BY created_at DESC LIMIT 8 FORMAT PrettyCompact" || true
}

show_drift() {
  echo "drift evidence, multi-scale PSI and KS (KF-07)"
  ch "SELECT scale, feature_name, round(psi_value,3) AS PSI, round(ks_statistic,3) AS KS,
             drift_detected, trigger_retrain
      FROM $DRIFT_TABLE ORDER BY psi_value DESC LIMIT 6 FORMAT PrettyCompact" || true
  echo
  kubectl get workflow -n model-lifecycle 2>/dev/null | grep -i retrain \
    || echo "no retrain workflow run yet"
}

show_govern() {
  echo "govern evidence, DataHub lineage graph (KF-08)"
  if [ -z "${DATAHUB_TOKEN:-}" ]; then
    echo "set DATAHUB_TOKEN first (Bearer PAT); see experiments/lineage/lineage-walk.sh header"
    return 0
  fi
  local name pid
  name=$(svc_name data-governance 'datahub-gms|gms')
  [ -z "$name" ] && { echo "datahub-gms service not found"; return 0; }
  pid=$(pf_bg data-governance "$name" 8080 8080); sleep 4
  DATAHUB_GMS_URL="http://127.0.0.1:8080" run_script lineage/lineage-walk.sh discover || true
  kill "$pid" 2>/dev/null || true
}

# Qdrant vector-search latency (KF-04).
scenario_vector() {
  echo "vector search latency (KF-04)"
  local name pid key
  name=$(svc_name storage 'qdrant')
  [ -z "$name" ] && { echo "qdrant service not found"; return 0; }
  pid=$(pf_bg storage "$name" 6333 6333); sleep 4
  if command -v k6 >/dev/null 2>&1; then
    k6 run "$HERE/load/vector-search-latency.js" || echo "k6 run failed, check Qdrant"
  else
    key=$(kubectl get secret -n "$USE_CASE_NAMESPACE" pipeline-secrets \
      -o jsonpath='{.data.QDRANT_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)
    echo "k6 absent, timing 50 API calls"
    for _ in $(seq 1 50); do
      curl -s -o /dev/null -w "%{time_total}\n" -H "api-key: $key" \
        http://127.0.0.1:6333/collections
    done | awk '{ ms=$1*1000; s+=ms; if(ms>mx)mx=ms; n++ } END{ printf "avg=%.2fms max=%.2fms n=%d\n", s/n, mx, n }'
  fi
  kill "$pid" 2>/dev/null || true
}

# Inject synthetic drift into Kafka.
drift_inject() {
  command -v uv >/dev/null 2>&1 || { echo "uv not installed"; return 1; }
  local user pass ca_b64 ca_file own_ca=0
  user="${KAFKA_USER:-admin}"
  pass="${KAFKA_PASSWORD:-}"
  [ -z "$pass" ] && pass=$(kubectl get secret -n data-ingestion "$user" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -z "$pass" ] && { echo "no SCRAM password for KafkaUser $user; export KAFKA_PASSWORD"; return 1; }
  ca_file="${KAFKA_CA:-}"
  if [ -z "$ca_file" ]; then
    ca_b64=$(kubectl get secret -n data-ingestion platform-kafka-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
    [ -n "$ca_b64" ] && { ca_file=$(mktemp); echo "$ca_b64" | base64 -d > "$ca_file"; own_ca=1; }
  fi
  echo "injecting drift into ${DRIFT_TOPIC:-crypto.validated} as $user; needs Kafka bootstrap reachable"
  KAFKA_USER="$user" KAFKA_PASSWORD="$pass" ${ca_file:+KAFKA_CA="$ca_file"} \
    uv run "$HERE/drift/inject_drift.py" "$@" || true
  [ "$own_ca" = 1 ] && rm -f "$ca_file" 2>/dev/null || true
}

verify_one() {
  case "$1" in
    ingest) verify_ingest ;; process) verify_process ;; feast) verify_feast ;;
    train)  verify_train  ;; serve)   verify_serve   ;; drift) verify_drift ;;
    govern) verify_govern ;;
    *) echo "unknown stage: $1"; return 2 ;;
  esac
}

show_one() {
  case "$1" in
    ingest) show_ingest ;; process) show_process ;; feast) show_feast ;;
    train)  show_train  ;; serve)   show_serve   ;; drift) show_drift ;;
    govern) show_govern ;;
    *) echo "unknown stage: $1"; return 2 ;;
  esac
}

# True for a known stage.
valid_stage() { case " $STAGES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Walk stages, optional slice.
cmd_walk() {
  local from="${FROM:-}" to="${TO:-}" show="${SHOW:-0}" list="" inrange=0
  [ -n "$from" ] && ! valid_stage "$from" && { echo "bad FROM=$from; stages: $STAGES"; return 2; }
  [ -n "$to" ] && ! valid_stage "$to" && { echo "bad TO=$to; stages: $STAGES"; return 2; }
  if [ -z "$from" ] && [ -z "$to" ]; then
    list="$STAGES"
  else
    [ -z "$from" ] && from="${STAGES%% *}"
    for s in $STAGES; do
      [ "$s" = "$from" ] && inrange=1
      [ "$inrange" = 1 ] && list="$list $s"
      [ -n "$to" ] && [ "$s" = "$to" ] && inrange=0
    done
  fi
  for s in $list; do
    echo "stage: $s"
    verify_one "$s"
    [ "$show" = 1 ] && { echo; show_one "$s"; }
    echo
  done
}

# Decode one secret value.
secret_val() {
  local v; v=$(kubectl get secret -n "$1" "$2" -o jsonpath="{.data.$3}" 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "check secret $1/$2"
}

creds() {
  echo "UI login details, read from live cluster secrets"
  echo
  printf '%-11s %-30s %s\n' TOOL URL LOGIN
  printf '%-11s %-30s %s\n' grafana    "http://${ADDR}:3000" "$(secret_val observability grafana-admin GF_SECURITY_ADMIN_USER) / $(secret_val observability grafana-admin GF_SECURITY_ADMIN_PASSWORD)"
  printf '%-11s %-30s %s\n' datahub    "http://${ADDR}:9002" "datahub / datahub"
  printf '%-11s %-30s %s\n' superset   "http://${ADDR}:8088" "admin / $(secret_val data-processing superset-admin ADMIN_PASSWORD)"
  printf '%-11s %-30s %s\n' argocd     "http://${ADDR}:8081" "admin / $(secret_val gitops argocd-initial-admin-secret password)"
  printf '%-11s %-30s %s\n' minio      "http://${ADDR}:9001" "$(secret_val storage minio MINIO_ROOT_USER) / $(secret_val storage minio MINIO_ROOT_PASSWORD)"
  printf '%-11s %-30s %s\n' mlflow     "http://${ADDR}:5000" "no login"
  printf '%-11s %-30s %s\n' kafka-ui   "http://${ADDR}:8080" "no login"
  printf '%-11s %-30s %s\n' prometheus "http://${ADDR}:9090" "no login"
  printf '%-11s %-30s %s\n' trino      "http://${ADDR}:8082" "any username, no password"
  printf '%-11s %-30s %s\n' airflow    "http://${ADDR}:8085" "admin / $(secret_val data-processing airflow-admin password)"
  printf '%-11s %-30s %s\n' qdrant     "http://${ADDR}:6333/dashboard" "api-key header (pipeline-secrets QDRANT_API_KEY)"
}

# Port-forward a UI service.
pf() {
  local ns="$1" re="$2" local_port="$3" want="${4:-}" path="${5:-}"
  local name port ep
  name=$(svc_name "$ns" "$re")
  [ -z "$name" ] && { echo "no service matching '$re' in namespace $ns"; return 1; }
  if [ -n "$want" ]; then
    port=$(kubectl get "svc/$name" -n "$ns" -o jsonpath="{.spec.ports[?(@.name=='$want')].port}" 2>/dev/null || true)
    [ -z "$port" ] && port=$(kubectl get "svc/$name" -n "$ns" -o jsonpath="{.spec.ports[?(@.port==$want)].port}" 2>/dev/null || true)
  fi
  [ -z "${port:-}" ] && port=$(kubectl get "svc/$name" -n "$ns" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ -z "$port" ] && { echo "could not resolve a port for $name"; return 1; }
  ep=$(kubectl get endpoints -n "$ns" "$name" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  [ -z "$ep" ] && { echo "$name has no ready pod yet, it is starting or restarting; retry when node load is low"; return 1; }
  echo "$name in $ns  ->  http://${ADDR}:${local_port}${path}"
  echo "Press Ctrl-C to stop the port-forward"
  kubectl port-forward --address "$ADDR" -n "$ns" "svc/$name" "${local_port}:${port}"
}

usage() {
  echo "usage: bash demo.sh <command>"
  echo "  verify [stage|all]   read-only wiring check per stage"
  echo "  show <stage>         read-only evidence for one stage"
  echo "  walk                 verify every stage (FROM/TO/SHOW env slice it)"
  echo "  <stage>              verify then show one stage"
  echo "  stages: $STAGES"
  echo "  ui: grafana datahub superset argocd minio mlflow kafka-ui prometheus trino airflow qdrant"
  echo "  creds vector core drift-inject"
}

case "${1:-help}" in
  verify)
    if [ "${2:-all}" = all ]; then
      for s in $STAGES; do echo "stage: $s"; verify_one "$s"; echo; done
    else
      verify_one "$2"
    fi
    ;;
  show)     show_one "${2:?stage required}" ;;
  walk)     cmd_walk ;;
  ingest|process|feast|train|serve|drift|govern) verify_one "$1"; echo; show_one "$1" ;;
  data)     show_one process ;;
  predict)  show_one serve ;;
  lineage)  verify_one govern; echo; show_one govern ;;
  vector)   scenario_vector ;;
  drift-inject) shift; drift_inject "$@" ;;
  core)     show_one process; echo; show_one serve; echo; show_one drift ;;
  creds)    creds ;;
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
  *)          usage ;;
esac
