#!/usr/bin/env bash
# =============================================================================
# cnpg/post-apply.sh — block until CNPG operator + barman-cloud plugin are
# fully registered with the operator's plugin discovery loop.
# =============================================================================
# Why this exists:
#   CNPG 1.30+ removed in-tree barman backup support (`Cluster.spec.backup.
#   barmanObjectStore`). Backups now go through the CNPG-I plugin
#   `barman-cloud.cloudnative-pg.io`, registered to the operator via a
#   Service labelled `cnpg.io/pluginName=barman-cloud.cloudnative-pg.io`.
#
#   Field-observed 2026-05-10 against CNPG 1.29 + plugin chart 0.6.0:
#   `kubectl apply --server-side` returns 0 immediately, but the plugin
#   Service can take several minutes to appear in the live API while
#   cert-manager issues its mTLS certs and the chart's wait/retry loop
#   completes. Meanwhile the next atom (storage/postgresql) applies a
#   Cluster CR with `spec.plugins[]={name: barman-cloud.cloudnative-pg.io}`.
#   The operator parses the CR, fails plugin discovery (Service missing),
#   sets phase = "Cluster cannot proceed to reconciliation due to an
#   unknown plugin being required", and the Cluster STAYS BLOCKED until
#   the operator's next plugin-discovery refresh AFTER the Service appears
#   — which can be 20+ minutes on a cold start. Every downstream consumer
#   (Airflow, Superset, MLflow, DataHub, LakeFS, Lakekeeper, Kubeflow,
#   Trino, datahub-ingestion) waits on `secret/postgresql-app`, which is
#   only created post-initdb, so the entire phase-full graph stalls.
#
# What this hook does:
#   1. Wait `cnpg-cloudnative-pg` operator Deployment Available — webhook
#      must serve before Cluster admits.
#   2. Wait `barman-cloud-plugin-barman-cloud` plugin Deployment Available.
#   3. Wait `Service/barman-cloud` exists in cnpg-system AND carries the
#      `cnpg.io/pluginName` label — this is the signal the operator's
#      plugin loader uses to register the plugin gRPC endpoint.
#   4. Trip the operator's plugin re-discovery once by patching the
#      Deployment with a no-op annotation, so subsequent Cluster applies
#      see the plugin without waiting for the operator's next periodic
#      refresh tick.
#
# Idempotent: on a healthy cluster every wait returns instantly.
# =============================================================================
set -euo pipefail

NS=cnpg-system

echo "    [post-apply] waiting Deployment/cnpg-cloudnative-pg Available (timeout 300s)"
kubectl -n "$NS" rollout status deployment/cnpg-cloudnative-pg --timeout=300s

echo "    [post-apply] waiting Deployment/barman-cloud-plugin-barman-cloud Available (timeout 300s)"
kubectl -n "$NS" rollout status deployment/barman-cloud-plugin-barman-cloud --timeout=300s

# -----------------------------------------------------------------------------
# Service/barman-cloud is delete-prone after `make nuke`: K8s GC may finalise
# the prior Service AFTER apply-component.sh's defense window, leaving a
# `PluginCleanup: Removing plugin barman-cloud.cloudnative-pg.io from pool due
# to service deletion` event in cnpg-system right after re-apply. The chart's
# Helm hook does not retry, so the Service stays missing forever, every
# Cluster CR with spec.plugins[] = barman-cloud stalls with "unknown plugin",
# and postgresql/storage initdb never starts. Field-observed 2026-05-11 fresh
# nuke + phase-full. Fix via idempotent re-extract from the rendered
# manifest and re-apply.
# -----------------------------------------------------------------------------
: "${REPO_ROOT:=$(cd "$(dirname "$0")/../../../.." && pwd)}"
RENDER="${CACHE_DIR:-$REPO_ROOT/.cache}/renders/component-storage-cnpg-rendered.yaml"

recreate_barman_svc() {
  local reason=$1
  echo "        Service/barman-cloud ${reason} — force-recreating from ${RENDER}"
  if [[ ! -f "$RENDER" ]]; then
    echo "        FATAL: rendered manifest absent at $RENDER" >&2
    return 1
  fi
  yq eval-all 'select(.kind == "Service" and .metadata.name == "barman-cloud")' "$RENDER" \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
}

echo "    [post-apply] waiting Service/barman-cloud with cnpg.io/pluginName label (timeout 240s)"
deadline=$(( $(date +%s) + 240 ))
recreated=0
while (( $(date +%s) < deadline )); do
  plugin_name=$(kubectl -n "$NS" get svc barman-cloud \
    -o jsonpath='{.metadata.labels.cnpg\.io/pluginName}' 2>/dev/null || echo "")
  if [[ "$plugin_name" == "barman-cloud.cloudnative-pg.io" ]]; then
    echo "        Service/barman-cloud registered (cnpg.io/pluginName=$plugin_name)"
    break
  fi
  # After 90s without Service appearing organically — past the typical chart
  # Helm-hook wait window — assume Service was deleted by GC race or chart
  # gave up. Re-extract from render. 90s (not 60s) avoids a harmless SSA
  # conflict warning when chart legitimately takes 60-80s to issue mTLS certs
  # and create the Service.
  if (( $(date +%s) - deadline + 240 > 90 )) && (( recreated == 0 )); then
    recreate_barman_svc "absent past 90s of post-apply wait" || true
    recreated=1
  fi
  sleep 5
done
if [[ "${plugin_name:-}" != "barman-cloud.cloudnative-pg.io" ]]; then
  echo "        FATAL: Service/barman-cloud missing cnpg.io/pluginName label after 240s" >&2
  kubectl -n "$NS" get svc barman-cloud -o yaml 2>&1 | head -40 >&2 || true
  exit 2
fi

echo "    [post-apply] kicking operator plugin re-discovery (annotation bump)"
kubectl -n "$NS" patch deployment cnpg-cloudnative-pg \
  --type merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"cnpg.io/plugin-rediscover\":\"$(date +%s)\"}}}}}" \
  >/dev/null
kubectl -n "$NS" rollout status deployment/cnpg-cloudnative-pg --timeout=180s
