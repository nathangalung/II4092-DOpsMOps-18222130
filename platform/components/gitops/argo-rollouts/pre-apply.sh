#!/usr/bin/env bash
# =============================================================================
# argo-rollouts pre-apply: bootstrap ArgoCD Application + block on CRD/NS.
# =============================================================================
# Race condition (without this hook):
#   `make install-argo-rollouts` → kustomize emits 3 docs in one render:
#     1. ArgoCD `Application` (CR for argoproj.io ArgoCD)
#     2. `AnalysisTemplate` (CR for argoproj.io argo-rollouts CRD)
#     3. `PodDisruptionBudget` in `argo-rollouts` namespace
#   ArgoCD reconciles the Application asynchronously to install the chart
#   (CRDs + `argo-rollouts` namespace + controller). A single-shot apply
#   lands docs (2) + (3) too early and crashes with:
#     - `no matches for kind "AnalysisTemplate" in version "argoproj.io/v1alpha1"`
#     - `namespaces "argo-rollouts" not found`
#
# Fix: pre-apply only the Application, force ArgoCD refresh, block until
# CRD `analysistemplates.argoproj.io` is Established AND namespace exists.
# Main apply re-applies the Application (idempotent under SSA) plus the
# now-resolvable AnalysisTemplate + PDB.
#
# Note: cold image pull + helm install on a fresh cluster takes minutes; the
# wait window is sized for slow registry / single-node clusters.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=argo-rollouts
APP_NS=gitops
APP_NAME=argo-rollouts
CRD_NAME=analysistemplates.argoproj.io
WAIT_SECS=900
SLEEP=5

echo "    pre-apply: applying argo-rollouts ArgoCD Application (kicks chart install)"
awk '/^---$/{exit} {print}' "$SCRIPT_DIR/helm-release.yaml" \
  | kubectl apply --server-side --force-conflicts -f - >/dev/null 2>&1 || true

# Trigger immediate ArgoCD refresh so we don't wait the default 3-min poll.
kubectl annotate -n "$APP_NS" "application/${APP_NAME}" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

echo "    pre-apply: waiting up to ${WAIT_SECS}s for CRD ${CRD_NAME} + ns ${NS}"
ATTEMPTS=$((WAIT_SECS / SLEEP))
for i in $(seq 1 "$ATTEMPTS"); do
  CRD_OK=0; NS_OK=0
  if kubectl get crd "$CRD_NAME" >/dev/null 2>&1; then
    EST=$(kubectl get crd "$CRD_NAME" \
      -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)
    [[ "$EST" == "True" ]] && CRD_OK=1
  fi
  kubectl get ns "$NS" >/dev/null 2>&1 && NS_OK=1
  if [[ "$CRD_OK" == 1 && "$NS_OK" == 1 ]]; then
    # Flush kubectl discovery cache: the next `kubectl apply` in the main
    # step would otherwise reuse a 10-min-old cache that predates the
    # newly-Established CRD and emit `no matches for kind AnalysisTemplate`.
    rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true
    echo "    pre-apply: CRD Established + namespace ready (discovery cache flushed)"
    exit 0
  fi
  sleep "$SLEEP"
done

echo "    pre-apply: ERROR CRD/namespace not ready within ${WAIT_SECS}s" >&2
kubectl get application -n "$APP_NS" "$APP_NAME" \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} conds={.status.conditions}{"\n"}' >&2 || true
kubectl get crd 2>/dev/null | grep -i rollout >&2 || true
exit 1
