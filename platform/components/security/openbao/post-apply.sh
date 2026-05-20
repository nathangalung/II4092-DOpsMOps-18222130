#!/usr/bin/env bash
# =============================================================================
# openbao/post-apply.sh — wait for openbao-bootstrap Job to seed KV
# =============================================================================
# Why this exists:
#   The openbao-bootstrap Job runs once per cluster lifecycle and seeds every
#   secret/platform/* KV path that ExternalSecrets downstream consume (Airflow,
#   MLflow, DataHub, Grafana, LakeFS, Lakekeeper, MinIO, Valkey, MySQL, …).
#   If `make install-openbao` returns BEFORE the Job completes, every later
#   `make install-*` step lands ExternalSecrets that go SecretSyncedError =
#   "Secret does not exist" against still-empty KV paths, which then cascades
#   into pods stuck in CreateContainerConfigError waiting on those Secrets.
#
# What this does:
#   1. Wait openbao-0 Pod Ready (StatefulSet rollout — covers fresh install
#      image pull + raft init + initial seal handshake).
#   2. Wait until openbao-0 reports Sealed=false (the openbao-unsealer
#      Deployment in the same namespace re-runs the unseal cycle every loop;
#      `bao status` against openbao-0 is the source of truth for unseal
#      readiness, not the Job's exit status).
#   3. Wait for the openbao-bootstrap Job's Complete condition. If the Job
#      hits BackoffLimitExceeded BEFORE the wait timeout (the Job ran while
#      openbao-0 was still racing through init/unseal — the failure mode
#      that motivated this hook), delete + re-apply the Job from the
#      rendered manifest and resume waiting. Job spec.template is immutable
#      so a delete-recreate cycle is the only K8s-native re-trigger.
#
# Idempotency: post-apply.sh re-running on a healthy cluster:
#   - openbao-0 already Ready    → step 1 returns instantly.
#   - openbao-0 already unsealed → step 2 returns instantly.
#   - bootstrap Job Complete     → step 3 returns instantly.
#   - bootstrap Job Failed       → delete-recreate + wait Complete.
#
# This hook is the bridge between OpenBao install and every downstream
# ESO-consuming component; phase-full reproducibility depends on it.
# =============================================================================
set -euo pipefail

NS=security
STS=openbao
JOB=openbao-bootstrap
RENDER="${REPO_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}/.cache/renders/component-${NS}-openbao-rendered.yaml"

echo "    [post-apply] waiting StatefulSet/${STS} Ready (timeout 600s)"
kubectl -n "$NS" rollout status "statefulset/${STS}" --timeout=600s

echo "    [post-apply] waiting openbao-0 unsealed (timeout 300s)"
deadline=$(( $(date +%s) + 300 ))
while (( $(date +%s) < deadline )); do
  status=$(kubectl -n "$NS" exec "${STS}-0" -c openbao -- bao status 2>&1 || true)
  if echo "$status" | grep -q 'Sealed[[:space:]]*false'; then
    echo "        openbao-0 unsealed"
    break
  fi
  sleep 5
done
if ! echo "$status" | grep -q 'Sealed[[:space:]]*false'; then
  echo "        FATAL: openbao-0 still sealed after 300s" >&2
  echo "$status" >&2
  exit 2
fi

reapply_job() {
  echo "    [post-apply] re-applying ${JOB} from render"
  kubectl -n "$NS" delete job "$JOB" --ignore-not-found --wait=true
  if [[ -f "$RENDER" ]]; then
    yq eval-all 'select(.kind == "Job" and .metadata.name == "openbao-bootstrap")' "$RENDER" \
      | kubectl apply --server-side --force-conflicts -f -
  else
    echo "        WARN: render file not found at $RENDER — cannot re-apply" >&2
    return 1
  fi
}

echo "    [post-apply] waiting Job/${JOB} Complete (timeout 900s)"
deadline=$(( $(date +%s) + 900 ))
while (( $(date +%s) < deadline )); do
  if ! kubectl -n "$NS" get job "$JOB" >/dev/null 2>&1; then
    echo "        Job/${JOB} missing — applying from render"
    reapply_job
    sleep 5
    continue
  fi
  # K8s 1.31+ adds `SuccessCriteriaMet` condition (KEP-3998 JobSuccessPolicy)
  # which lands BEFORE `Complete` on a successful Job. Both have status=True,
  # so we cannot use `head -1` on True-only conditions — that grabs whichever
  # comes first in `.status.conditions[]` and silently misses the terminal
  # state we actually want.  Test for Complete + Failed/FailureTarget
  # explicitly with jq `any()`.
  conds=$(kubectl -n "$NS" get job "$JOB" -o json 2>/dev/null)
  if echo "$conds" | jq -e '.status.conditions[]? | select(.type=="Complete" and .status=="True")' >/dev/null; then
    echo "        Job/${JOB} Complete"
    exit 0
  fi
  failed=$(echo "$conds" | jq -r '.status.conditions[]? | select(.status=="True" and (.type=="Failed" or .type=="FailureTarget")) | .type' | head -1)
  if [[ -n "$failed" ]]; then
    echo "        Job/${JOB} ${failed} — re-applying"
    reapply_job
  fi
  sleep 5
done

echo "        FATAL: Job/${JOB} did not complete within 900s" >&2
kubectl -n "$NS" describe job "$JOB" 2>&1 | tail -30 >&2 || true
exit 2
