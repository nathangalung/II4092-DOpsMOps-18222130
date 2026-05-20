#!/usr/bin/env bash
# =============================================================================
# clickhouse-operator/post-apply.sh — wait Argo sync + clear stale CHI/CHK
# =============================================================================
# Why this exists (two distinct concerns folded into one hook):
#
# A) ArgoCD-Application sync race
#   This component is shipped as a single `argoproj.io/Application` CR (see
#   helm-release.yaml). `kubectl apply --server-side` returns 0 the moment the
#   Application CR is accepted by the apiserver. ArgoCD then schedules the
#   initial sync against `https://helm.altinity.com` (chart altinity-clickhouse-
#   operator 0.26.3) which is what materialises Deployment/Service/CRDs/
#   ClusterRole. The sync takes 5-60s on a healthy cluster.
#
#   Field-observed 2026-05-09 on `make nuke && make phase-full`: post-apply
#   ran ~1s after Application apply, hit NotFound on
#   `Deployment/clickhouse-operator-altinity-clickhouse-operator`, exited 2,
#   blew install-clickhouse-operator. Cascade halted phase-full.
#
# B) CHI/CHK stale-finalizer cleanup
#   Altinity operator 0.26.x panics in deleteCHK reconcile path
#   (`(*ClickHouseKeeperInstallation).GetRootServiceTemplates` nil-deref) when
#   a CHK CR has `deletionTimestamp` set but its
#   `finalizer.clickhousekeeperinstallation.altinity.com` finalizer is still
#   present and `.spec.templates.serviceTemplates` is omitted (our case — we
#   only set podTemplates + volumeClaimTemplates). Same path exists for CHI.
#
#   How a stale CR is born:
#     1. `make nuke` tears down ns/storage; K8s sets deletionTimestamp on
#        CHI/CHK; finalizer chain expects operator to clear it.
#     2. nuke deletes ns/clickhouse-system → operator pod gone before it can
#        finalize the CR.
#     3. CRD GC stalls because CR with finalizer is alive; CRD lingers.
#     4. `make phase-full` re-applies CRDs → old CR resurrected with
#        deletionTimestamp still set.
#     5. New operator boots, hits nil-deref on the resurrected CR, CrashLoops.
#        Every downstream component that depends on ClickHouse (feast,
#        observability traces) blocks behind it.
#
# What this hook does, in order:
#   1. Trigger an explicit `argocd.argoproj.io/refresh=hard` annotation on the
#      Application so ArgoCD does NOT wait for its 3-minute reconcile poll
#      before doing the initial sync.
#   2. Block until the operator Deployment exists in the apiserver (Argo sync
#      created it). Deadline 600s — generous for slow chart pulls on a fresh
#      boot, instant on re-apply.
#   3. For every namespace, force-clear CHI/CHK with deletionTimestamp set
#      and non-empty finalizers (B above). Idempotent: no-op on a clean
#      cluster.
#   4. Wait Deployment Available. Now safe — Deployment is guaranteed to
#      exist by step 2.
# =============================================================================
set -euo pipefail

NS=clickhouse-system
DEPLOY=clickhouse-operator-altinity-clickhouse-operator
APP_NS=gitops
APP_NAME=altinity-clickhouse-operator

# Step 1: Force ArgoCD to refresh+sync NOW. The Application has
# `syncPolicy.automated` so it WILL eventually sync, but the controller's
# default app-resync interval is 180s. The hard refresh annotation is
# consumed-and-cleared by the controller, so re-applying it is idempotent.
if kubectl -n "$APP_NS" get application "$APP_NAME" >/dev/null 2>&1; then
  echo "    [post-apply] triggering argocd hard refresh on ${APP_NS}/${APP_NAME}"
  kubectl -n "$APP_NS" annotate application "$APP_NAME" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
fi

# Step 2: Wait for the chart-templated Deployment to materialise. Argo will
# create it during sync; until then `kubectl rollout status` would NotFound
# and exit non-zero (which is what bit phase-full).
echo "    [post-apply] waiting Deployment/${DEPLOY} to exist (Argo sync, timeout 600s)"
deadline=$(( $(date +%s) + 600 ))
while (( $(date +%s) < deadline )); do
  if kubectl -n "$NS" get deployment "$DEPLOY" >/dev/null 2>&1; then
    echo "        Deployment present"
    break
  fi
  sleep 5
done
if ! kubectl -n "$NS" get deployment "$DEPLOY" >/dev/null 2>&1; then
  echo "    FATAL: Deployment/${DEPLOY} not materialised after 600s — Argo sync stuck" >&2
  kubectl -n "$APP_NS" get application "$APP_NAME" \
    -o jsonpath='{"sync="}{.status.sync.status}{" health="}{.status.health.status}{" message="}{.status.conditions[*].message}{"\n"}' >&2 2>&1 || true
  exit 2
fi

# Step 3: Clear stale CHI/CHK finalizers so operator pod doesn't nil-deref
# crash on its first reconcile. Belt-and-suspenders alongside nuke.sh's
# pre-CRD finalizer scrub.
clear_stale() {
  local kind="$1"
  kubectl get "$kind" -A -o json 2>/dev/null \
    | jq -r '.items[] | select(.metadata.deletionTimestamp != null and (.metadata.finalizers // []) != []) | "\(.metadata.namespace) \(.metadata.name)"' \
    | while read -r cr_ns cr_name; do
        [[ -z "${cr_ns:-}" || -z "${cr_name:-}" ]] && continue
        echo "    [post-apply] clearing stale ${kind}/${cr_name} in ${cr_ns} (deletionTimestamp set)"
        kubectl -n "$cr_ns" patch "$kind" "$cr_name" \
          --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
      done
}

if kubectl get crd clickhouseinstallations.clickhouse.altinity.com >/dev/null 2>&1; then
  clear_stale chi
fi
if kubectl get crd clickhousekeeperinstallations.clickhouse-keeper.altinity.com >/dev/null 2>&1; then
  clear_stale chk
fi

# Step 4: Now safe to wait for the operator pod to roll out — Deployment
# object is guaranteed to exist.
echo "    [post-apply] waiting Deployment/${DEPLOY} Available (timeout 300s)"
kubectl -n "$NS" rollout status "deployment/${DEPLOY}" --timeout=300s
