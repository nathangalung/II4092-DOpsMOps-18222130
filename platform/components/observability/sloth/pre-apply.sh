#!/usr/bin/env bash
# =============================================================================
# sloth pre-apply: bootstrap ArgoCD Application + block on CRD Established.
# =============================================================================
# Race condition (without this hook):
#   `make install-sloth` → kustomize emits two manifests in one render:
#     1. helm-release.yaml — ArgoCD Application that installs the sloth chart
#        (chart provides `prometheusservicelevels.sloth.slok.dev` CRD).
#     2. platform-slos.yaml — `PrometheusServiceLevel` CRs.
#   ArgoCD reconciles the Application asynchronously. A single-shot apply
#   lands the CRs too early and crashes with:
#     `no matches for kind "PrometheusServiceLevel" in version "sloth.slok.dev/v1"`
#
# Fix: pre-apply only the Application, force ArgoCD refresh, block until
# CRD `prometheusservicelevels.sloth.slok.dev` is Established, flush kubectl
# discovery cache so the next apply sees the new CRD, then exit.
# Main apply re-applies the Application (idempotent under SSA) plus the
# now-resolvable PrometheusServiceLevel CRs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NS=gitops
APP_NAME=sloth
CRD_NAME=prometheusservicelevels.sloth.slok.dev
WAIT_SECS=900
SLEEP=5

echo "    pre-apply: applying sloth ArgoCD Application (kicks chart install)"
awk '/^---$/{exit} {print}' "$SCRIPT_DIR/helm-release.yaml" \
  | kubectl apply --server-side --force-conflicts -f - >/dev/null 2>&1 || true

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
      # `no matches for kind PrometheusServiceLevel` against a 10-min-old cache.
      rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true
      echo "    pre-apply: CRD Established (discovery cache flushed)"
      exit 0
    fi
  fi
  sleep "$SLEEP"
done

echo "    pre-apply: ERROR CRD ${CRD_NAME} not Established within ${WAIT_SECS}s" >&2
kubectl get application -n "$APP_NS" "$APP_NAME" \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} conds={.status.conditions}{"\n"}' >&2 || true
kubectl get crd 2>/dev/null | grep -i sloth >&2 || true
exit 1
