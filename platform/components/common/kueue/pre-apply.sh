#!/usr/bin/env bash
# =============================================================================
# kueue/pre-apply.sh — install upstream Kueue (CRDs + Controller + Webhooks)
# =============================================================================
# Strategy:
#   1. Apply full upstream manifest bundle (CRDs + Deployment + Service +
#      Webhook configs + RBAC, all in `kueue-system`).
#   2. IMMEDIATELY patch Deployment resources (cpu req 500m→100m, mem 512Mi
#      →256Mi) AND strategy (maxSurge=0, maxUnavailable=1). Upstream defaults
#      deadlock on >85%-saturated single-node k3s: maxSurge=25% needs new pod
#      Ready before evicting old, but new (500m) can't fit until old (500m)
#      dies. Done before slow waits to minimize bad-state window.
#   3. Wait for CRDs Established.
#   4. Patch `kueue-manager-config` Configuration to extend leader-election
#      deadlines — k3s apiserver under load takes >10s to update Lease, and
#      controller-runtime's default 10s renewDeadline causes self-eviction
#      → CrashLoopBackOff. Extending lease/renew/retry to 60s/40s/5s keeps
#      the controller leader through transient apiserver latency.
#   5. Soften the cluster-wide Pod / Deployment / StatefulSet webhooks:
#        - failurePolicy=Ignore so kueue downtime never blocks unrelated
#          Deployment applies cluster-wide (the original config sets
#          failurePolicy=Fail; if the controller pod crashes, every
#          Deployment apply in every namespace fails admission).
#        - objectSelector requiring `kueue.x-k8s.io/queue-name` label so
#          the webhook only fires on workloads that have explicitly opted
#          into kueue queue management. Other workloads bypass kueue.
#   6. Clean up orphan ReplicaSets (desired=0) accumulated from prior
#      rollout-restart calls — they consume listing/cache memory.
#   7. Wait for rollout complete + webhook endpoint populated. Step 2's
#      template change already triggered new RS rollout; new pod picks up
#      the updated ConfigMap from step 4 on startup.
#
# Local kustomization.yaml only contributes queues.yaml (ResourceFlavor +
# ClusterQueue) — runs after this hook returns.
# =============================================================================
set -euo pipefail

KUEUE_VERSION="${KUEUE_VERSION:-v0.17.1}"
URL="https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml"
# Repo-local cache (env-agnostic; survives /tmp wipes). REPO_ROOT exported by
# scripts/apply-component.sh; fall back to walking up from this script's dir
# so the hook is also runnable standalone.
: "${REPO_ROOT:=$(cd "$(dirname "$0")/../../../.." && pwd)}"
CACHE_DIR="${CACHE_DIR:-$REPO_ROOT/.cache}/downloads"
mkdir -p "$CACHE_DIR"
TMP="$CACHE_DIR/kueue-${KUEUE_VERSION}-manifests.yaml"
NS=kueue-system
DEPLOY=kueue-controller-manager
CFGMAP=kueue-manager-config
CFG_KEY="controller_manager_config.yaml"
MWC=kueue-mutating-webhook-configuration
VWC=kueue-validating-webhook-configuration

if [[ ! -f "$TMP" ]]; then
  echo "    fetching ${URL}"
  curl -fsSL "$URL" -o "$TMP"
fi

# Post-restart, CoreDNS may take 30-60s to settle; image pulls from
# registry.k8s.io fail with "Try again" lookups during that window. Wait for
# CoreDNS Ready first so the deployment's initial pull lands clean instead of
# entering 5-minute backoff cycles that blow the rollout timeout below.
echo "    waiting CoreDNS Ready (kube-system)"
kubectl -n kube-system rollout status deployment/coredns --timeout=120s >/dev/null

# Retry the bundle SSA. The Kueue manifests file is large (~30 resources: 5
# CRDs + RBAC + Service + Deployment + 2 webhook configs + APIService + more).
# On a single-node k3s the datastore is kine-on-SQLite; concurrent writes from
# one big SSA can return `rpc error: code = Unknown desc = database is locked`
# when SQLite's busy_timeout expires before all writes serialize. Field-
# observed 2026-05-11: phase-full hit this error after the visibility
# APIService apply, abrupting the run. The error is transient — a fresh apply
# 10s later succeeds because the prior writes drained. Wrap with retry.sh
# (10 attempts × 10s) for parity with scripts/apply-component.sh main SSA.
# tail -20 dropped: retry.sh's per-attempt log already truncates noise and
# we want full apply stderr visible for diagnosis.
echo "    applying upstream Kueue bundle (CRDs + controller + webhooks)"
bash "$REPO_ROOT/scripts/retry.sh" 10 10 -- \
  kubectl apply --server-side --force-conflicts -f "$TMP"

# IMMEDIATELY patch resources + strategy so the rollout triggered by upstream
# apply uses k3s-fit values (100m cpu, maxSurge=0). Done before slower waits to
# minimize the window where deployment has 500m+maxSurge=25% (deadlocks on
# saturated single-node). Idempotent: already-100m re-patches to 100m.
echo "    patching ${DEPLOY} resources (cpu req 500m→100m, maxSurge=0, IfNotPresent for k3s fit)"
# imagePullPolicy: Always (upstream default) → IfNotPresent: in air-gapped
# lab the 51MB registry.k8s.io/kueue/kueue:v0.17.1 image is cached after
# the first pull; Always forces re-pull on every restart, then DNS lookup
# to registry.k8s.io fails → ImagePullBackOff loop even though image is
# present locally. IfNotPresent uses cache and skips registry hit.
kubectl -n "$NS" patch "deployment/${DEPLOY}" --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"100m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"256Mi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"},
  {"op":"replace","path":"/spec/strategy","value":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}
]' >/dev/null

CRDS=(
  clusterqueues.kueue.x-k8s.io
  resourceflavors.kueue.x-k8s.io
  localqueues.kueue.x-k8s.io
  workloads.kueue.x-k8s.io
  admissionchecks.kueue.x-k8s.io
)
echo "    waiting CRDs Established"
for crd in "${CRDS[@]}"; do
  for i in 1 2 3 4 5 6; do
    if kubectl wait --for=condition=Established --timeout=15s "crd/${crd}" 2>/dev/null; then
      break
    fi
    if (( i == 6 )); then
      echo "    CRD ${crd} not Established after 6 attempts" >&2
      exit 2
    fi
    sleep 5
  done
done

# ---------------------------------------------------------------------------
# (4) Extend leader-election deadlines via kueue Configuration ConfigMap.
# ---------------------------------------------------------------------------
echo "    extending leader-election deadlines (lease=60s renew=40s retry=5s)"
CUR_CFG=$(kubectl -n "$NS" get configmap "$CFGMAP" -o json \
  | jq -r --arg k "$CFG_KEY" '.data[$k]')
NEW_CFG=$(printf '%s' "$CUR_CFG" | yq '
  .leaderElection.leaderElect = true |
  .leaderElection.leaseDuration = "60s" |
  .leaderElection.renewDeadline = "40s" |
  .leaderElection.retryPeriod = "5s"
')
PATCH=$(jq -n --arg k "$CFG_KEY" --arg v "$NEW_CFG" '{data: {($k): $v}}')
kubectl -n "$NS" patch configmap "$CFGMAP" --type=merge -p "$PATCH" >/dev/null

# ---------------------------------------------------------------------------
# (5) Soften ALL kueue workload-kind webhooks:
#     failurePolicy=Ignore + objectSelector requires opt-in queue-name label.
#     Workload kinds are widely created by other components (Job, CronJob, Pod,
#     Deployment, StatefulSet, plus kubeflow training operators & ray/spark
#     workloads). With upstream failurePolicy=Fail and no objectSelector, kueue
#     pod downtime blocks ALL such creates cluster-wide. Solution: opt-in only
#     (label kueue.x-k8s.io/queue-name=<queue> on workloads that want kueue).
#     Kueue-own kinds (clusterqueue, resourceflavor, workload, cohort) keep
#     upstream failurePolicy=Fail — they only exist when kueue is in use.
# ---------------------------------------------------------------------------
soften_webhook() {
  local kind=$1 name=$2
  if ! kubectl get "$kind" "$name" >/dev/null 2>&1; then
    echo "    skip ${kind}/${name} (not present)"
    return 0
  fi
  echo "    softening ${kind}/${name}"
  kubectl get "$kind" "$name" -o json \
    | jq '
        .webhooks |= map(
          if (.name | test("^[mv](clusterqueue|resourceflavor|workload|cohort|multikueue|provisioningrequestconfig|topology|admissioncheck|localqueue)\\.kb\\.io$")) then
            .  # kueue-own resource — keep failurePolicy=Fail
          elif (.name | test("^[mv][a-z]+\\.kb\\.io$")) then
            .failurePolicy = "Ignore" |
            .objectSelector = {
              "matchExpressions": [
                {"key": "kueue.x-k8s.io/queue-name", "operator": "Exists"}
              ]
            }
          else . end)
        | del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation)
      ' \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
}
soften_webhook MutatingWebhookConfiguration "$MWC"
soften_webhook ValidatingWebhookConfiguration "$VWC"

# ---------------------------------------------------------------------------
# (6) Clean up old ReplicaSets so /spec.replicas=1 doesn't leak into multiple
#     stale RSes consuming scheduling slots after repeated rollout-restarts.
#     `kubectl delete rs -l ... --field-selector` would be cleaner but the
#     Deployment owner-ref cascade only triggers on RS deletion when desired=0.
# ---------------------------------------------------------------------------
kubectl -n "$NS" get rs -l "app.kubernetes.io/component=controller" \
  --no-headers 2>/dev/null \
  | awk '$2=="0" && $3=="0" && $4=="0" {print $1}' \
  | xargs -r kubectl -n "$NS" delete rs >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# (7) Wait for rollout. Step 2's resource+strategy patch already triggered a
#     new RS (template change → new pod), and that pod mounts the updated
#     ConfigMap from step 4. No explicit `rollout restart` needed (it would
#     trigger ANOTHER new RS, doubling rollout time on saturated node).
#     Timeout 1800s: cold pull of registry.k8s.io/kueue/kueue v0.17.1 (51 MB)
#     on slow upstream + DNS retries + post-restart sandbox-name reservation
#     race observed at 12-18min in real runs. 1800s leaves headroom; if CoreDNS
#     is healthy and image cached, rollout completes in <30s and exits early.
# ---------------------------------------------------------------------------
echo "    waiting ${DEPLOY} rollout complete (timeout 1800s)"
kubectl -n "$NS" rollout status "deployment/${DEPLOY}" --timeout=1800s 2>&1 | tail -5

echo "    waiting webhook endpoints populated"
for i in 1 2 3 4 5 6 7 8 9 10; do
  ep=$(kubectl -n "$NS" get endpoints kueue-webhook-service \
       -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ep" ]]; then
    echo "    webhook endpoint(s): $ep"
    break
  fi
  if (( i == 10 )); then
    echo "    WARN: webhook endpoint never populated after 100s" >&2
    exit 2
  fi
  sleep 10
done

echo "    Kueue control plane ready"
