#!/usr/bin/env bash
# ClickHouse post-apply: guarantee the load-balanced `clickhouse-platform`
# Service has live endpoints before the platform declares storage healthy -
# and self-heal the Altinity operator's "Completed with 0 hosts" stall.
# Failure mode this guards against (field-observed 2026-05-31):
#   The Altinity operator owns the `chi-platform-main-0-0` StatefulSet replica
#   count and stamps each ready host with `clickhouse.altinity.com/ready: yes`.
#   The headless Service `clickhouse-platform` (clusterIP: None) selects ONLY
#   pods carrying that label, so its DNS A-record exists ONLY while ≥1 host is
#   operator-ready. EVERY consumer dials `clickhouse-platform.storage` (dbt
#   silver/gold, trainer, feast wait-for-clickhouse init, analyzer, GE,
#   drift) - so zero endpoints = cluster-wide NXDOMAIN, not a slow query.
#
#   If a reconcile is INTERRUPTED mid host-operation (operator OOM / IO-cascade
#   restart - both recur on this single node), the operator can persist a
#   normalized CHI with the host dropped, then on resume reconcile to
#   "0 hosts = done": CHI `.status.status=Completed`, STS `replicas=0`, no pod,
#   no endpoints, no self-heal. The operator is idle and will NOT correct it
#   until its `.metadata.generation` changes again.
#
# Why a plain `kubectl rollout status` / endpoint-wait is not enough:
#   On the stall the operator believes it is DONE, so waiting forever just
#   times out. The only operator-native un-stick is to bump the CHI so it
#   re-normalizes from `.spec` (layout shards=1 replicas=1 becomes 1 host). The
#   canonical force-reconcile knob is `.spec.taskID`: changing it bumps
#   generation AND signals a fresh task, so the operator re-plans 1 host,
#   scales the STS back to 1, boots the pod, health-checks it, sets
#   `ready: yes`, and the Service endpoints repopulate. Proven live 2026-05-31
#   (Aborted, then InProgress, then Completed + endpoints in ~60s after the bump).
#
# What this hook does:
#   1. Wait up to FIRST_WAIT for `clickhouse-platform` to have ≥1 endpoint.
#      Healthy apply: returns in well under a minute, no bump.
#   2. If still empty AND the CHI is in a NON-progressing state (Completed /
#      Aborted - i.e. the operator thinks it is finished), force one reconcile
#      via a fresh `.spec.taskID`. (If status is still InProgress the operator
#      is genuinely working - do NOT interrupt it, just keep waiting; bumping
#      mid-reconcile is what causes the Abort in the first place.)
#   3. Wait up to SECOND_WAIT for endpoints. Exit 0 on success, 2 on failure
#      with diagnostics. Idempotent: a healthy cluster never reaches step 2.
set -euo pipefail

NS=storage
CHI=platform
SVC=clickhouse-platform
FIRST_WAIT=180     # operator scale-up + CH cold start under single-node IO
SECOND_WAIT=240    # post-bump full re-reconcile + pod boot + health check
SLEEP=10

endpoints_present() {
  local ips
  ips=$(kubectl get endpoints "$SVC" -n "$NS" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  [[ -n "$ips" ]]
}

wait_for_endpoints() {
  local deadline=$(( $(date +%s) + $1 ))
  while (( $(date +%s) < deadline )); do
    if endpoints_present; then
      echo "    [post-apply] ${SVC} endpoints live: $(kubectl get endpoints "$SVC" -n "$NS" -o jsonpath='{.subsets[*].addresses[*].ip}')"
      return 0
    fi
    sleep "$SLEEP"
  done
  return 1
}

echo "    [post-apply] waiting for ${SVC}.${NS} endpoints (up to ${FIRST_WAIT}s)"
if wait_for_endpoints "$FIRST_WAIT"; then
  exit 0
fi

# Step 2: endpoints still empty. Only force a reconcile if the operator is
# idle (terminal status); never interrupt an in-flight reconcile.
STATUS=$(kubectl get chi "$CHI" -n "$NS" -o jsonpath='{.status.status}' 2>/dev/null || echo "Unknown")
echo "    [post-apply] no endpoints after ${FIRST_WAIT}s; CHI status=${STATUS}"
if [[ "$STATUS" == "Completed" || "$STATUS" == "Aborted" ]]; then
  NEW_TASK=$(cat /proc/sys/kernel/random/uuid)
  echo "    [post-apply] operator stalled with 0 hosts — forcing reconcile via spec.taskID=${NEW_TASK}"
  kubectl patch chi "$CHI" -n "$NS" --type=merge \
    -p "{\"spec\":{\"taskID\":\"${NEW_TASK}\"}}" >/dev/null 2>&1 || true
else
  echo "    [post-apply] CHI still progressing (${STATUS}); not interrupting, continuing to wait"
fi

echo "    [post-apply] waiting for ${SVC}.${NS} endpoints (up to ${SECOND_WAIT}s)"
if wait_for_endpoints "$SECOND_WAIT"; then
  exit 0
fi

echo "    FATAL: ${SVC}.${NS} has no endpoints after reconcile — data path severed" >&2
kubectl get chi "$CHI" -n "$NS" \
  -o jsonpath='{"    CHI status="}{.status.status}{" hosts="}{.status.hostsCount}{" completed="}{.status.completedHostsCount}{"\n"}' >&2 2>&1 || true
kubectl get sts -n "$NS" -l "clickhouse.altinity.com/chi=${CHI}" \
  -o jsonpath='{range .items[*]}{"    sts/"}{.metadata.name}{" replicas="}{.spec.replicas}{" ready="}{.status.readyReplicas}{"\n"}{end}' >&2 2>&1 || true
exit 2
