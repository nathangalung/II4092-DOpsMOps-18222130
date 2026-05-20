#!/usr/bin/env bash
# =============================================================================
# chaos-mesh pre-apply: bootstrap ArgoCD Application + block on CRD Established.
# =============================================================================
# Race condition (without this hook):
#   `make install-chaos-mesh` → kustomize emits four manifests in one render:
#     1. helm-release.yaml — Namespace `chaos-mesh`.
#     2. helm-release.yaml — ArgoCD Application that installs the chart
#        (chart provides `chaos-mesh.org/v1alpha1` CRDs:
#         PodChaos, NetworkChaos, IOChaos, StressChaos, TimeChaos,
#         Schedule, Workflow, etc.).
#     3. helm-release.yaml — Kyverno PolicyException for privileged DaemonSet.
#     4. experiments.yaml — `Schedule` and `Workflow` CRs that consume the
#        chart-installed CRDs.
#   ArgoCD reconciles the Application asynchronously. A single-shot apply
#   lands the experiment CRs too early and crashes with:
#     `no matches for kind "Schedule" in version "chaos-mesh.org/v1alpha1"`
#
# Fix: pre-apply only the helm-release.yaml manifests (Namespace + Application
# + PolicyException — all idempotent), force ArgoCD refresh, block until CRD
# `schedules.chaos-mesh.org` is Established, flush kubectl discovery cache so
# the next apply sees the new CRDs, then exit.
# Main apply re-applies helm-release.yaml (idempotent under SSA) plus the
# now-resolvable Schedule + Workflow CRs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=chaos-mesh
APP_NS=gitops
APP_NAME=chaos-mesh
CRD_NAME=schedules.chaos-mesh.org
WAIT_SECS=900
SLEEP=5

echo "    pre-apply: applying chaos-mesh helm-release (Namespace + Application + PolicyException)"
kubectl apply --server-side --force-conflicts \
  -f "$SCRIPT_DIR/helm-release.yaml" >/dev/null 2>&1 || true

# Trigger immediate ArgoCD refresh — skip default 3-min poll.
kubectl annotate -n "$APP_NS" "application/${APP_NAME}" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

echo "    pre-apply: waiting up to ${WAIT_SECS}s for CRD ${CRD_NAME}"
ATTEMPTS=$((WAIT_SECS / SLEEP))
for i in $(seq 1 "$ATTEMPTS"); do
  if kubectl get crd "$CRD_NAME" >/dev/null 2>&1; then
    EST=$(kubectl get crd "$CRD_NAME" \
      -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)
    if [[ "$EST" == "True" ]]; then
      # Flush kubectl discovery cache so the next `kubectl apply` recognizes
      # the newly-Established CRD; without this the main step still emits
      # `no matches for kind Schedule` against a 10-min-old cache.
      rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true
      echo "    pre-apply: CRD Established (discovery cache flushed)"
      break
    fi
  fi
  if (( i == ATTEMPTS )); then
    echo "    pre-apply: ERROR CRD ${CRD_NAME} not Established within ${WAIT_SECS}s" >&2
    kubectl get application -n "$APP_NS" "$APP_NAME" \
      -o jsonpath='sync={.status.sync.status} health={.status.health.status} conds={.status.conditions}{"\n"}' >&2 || true
    kubectl get crd 2>/dev/null | grep -i chaos >&2 || true
    exit 1
  fi
  sleep "$SLEEP"
done

# Wait for chaos-mesh-controller-manager Deployment Available + webhook
# endpoints populated — required because Schedule/Workflow CRs in the main
# render trigger admission via mschedule.kb.io / mworkflow.kb.io webhooks
# (failurePolicy=Fail). If main apply lands before controller pod is Ready,
# Webhook returns "no endpoints available" → 502 → apply fails.
# Note: chart Deployment is `chaos-controller-manager` (no `-mesh-` prefix)
# but the Service it backs is `chaos-mesh-controller-manager` (which the
# admission webhook clientConfig points at). Wait on the Deployment name.
#
# CRD Established does NOT mean ArgoCD has synced the chart's workload
# manifests. The chart's Helm pre-install hook lands CRDs first; the
# Deployment/DaemonSet apply happens later in the same sync. `kubectl wait`
# errors immediately on a non-existent object (no `--for=create` semantics),
# so we must poll for existence first. Field-observed 2026-05-11
# `make phase-full`: CRD landed at T+30s, controller Deployment landed at
# T+90s, but pre-apply hit `kubectl wait` at T+35s → "deployments.apps
# 'chaos-controller-manager' not found" → install-chaos-mesh exited 1.
echo "    pre-apply: waiting Deployment/chaos-controller-manager to exist (timeout 600s)"
i=0
MAX_I=120  # 120 × 5s = 600s
while (( i < MAX_I )); do
  if kubectl -n "$NS" get deployment/chaos-controller-manager >/dev/null 2>&1; then
    echo "    pre-apply: Deployment/chaos-controller-manager present (after ${i}×5s)"
    break
  fi
  # Nudge ArgoCD refresh every 30s — initial refresh annotation at line 41
  # primes the application controller, but on cold boot the controller pod
  # itself may be starting; re-annotating keeps the reconciliation loop tight.
  if (( i > 0 && i % 6 == 0 )); then
    kubectl annotate -n "$APP_NS" "application/${APP_NAME}" \
      argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  fi
  sleep 5
  i=$((i+1))
done
if ! kubectl -n "$NS" get deployment/chaos-controller-manager >/dev/null 2>&1; then
  echo "    pre-apply: ERROR Deployment/chaos-controller-manager not created within 600s" >&2
  kubectl get application -n "$APP_NS" "$APP_NAME" \
    -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}' >&2 || true
  kubectl -n "$NS" get all >&2 2>&1 | head -40 || true
  exit 1
fi

echo "    pre-apply: waiting chaos-controller-manager Deployment Available"
kubectl -n "$NS" wait --for=condition=Available --timeout=600s \
  deployment/chaos-controller-manager 2>&1 | tail -3

echo "    pre-apply: waiting chaos-mesh webhook endpoints populated"
ENDPOINTS_OK=0
for i in $(seq 1 60); do
  ep=$(kubectl -n "$NS" get endpoints chaos-mesh-controller-manager \
       -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ep" ]]; then
    echo "    pre-apply: webhook endpoint(s): $ep"
    ENDPOINTS_OK=1
    break
  fi
  if (( i == 60 )); then
    echo "    pre-apply: WARN chaos-mesh webhook endpoint not populated after 300s — continuing with softened webhooks" >&2
    break
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# Soften chaos-mesh webhooks: failurePolicy=Ignore so transient controller
# pod evictions (CPU pressure on saturated single-node) don't block main
# apply of Schedule/Workflow CRs. Defaults: failurePolicy=Fail. On a
# saturated node the controller pod can be evicted/restarted between
# pre-apply readiness check and main apply, leaving webhook calls failing
# with "no endpoints available". Ignore lets CR apply succeed without
# webhook mutation; chart-installed defaults already populate required
# fields. Webhook resumes mutating once pod returns. Idempotent under SSA.
# ---------------------------------------------------------------------------
soften_chaos_webhook() {
  local kind=$1 name=$2
  if ! kubectl get "$kind" "$name" >/dev/null 2>&1; then
    echo "    skip ${kind}/${name} (not present)"
    return 0
  fi
  echo "    softening ${kind}/${name} (failurePolicy=Ignore)"
  kubectl get "$kind" "$name" -o json \
    | jq '.webhooks |= map(.failurePolicy = "Ignore")
        | del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation)' \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
}
soften_chaos_webhook MutatingWebhookConfiguration chaos-mesh-mutation
soften_chaos_webhook ValidatingWebhookConfiguration chaos-mesh-validation
soften_chaos_webhook ValidatingWebhookConfiguration chaos-mesh-validation-auth

echo "    pre-apply: chaos-mesh ready (webhooks softened, endpoints_ok=${ENDPOINTS_OK})"
exit 0
