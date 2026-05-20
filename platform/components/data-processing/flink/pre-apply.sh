#!/usr/bin/env bash
# =============================================================================
# Flink pre-apply: install Argo Application for flink-kubernetes-operator,
# trigger sync (the Application has automated.selfHeal=false, so first-install
# requires an explicit sync), then wait for operator CRDs to be Established.
# =============================================================================
# Race condition (without this hook):
#   Main `kubectl apply -k components/data-processing/flink/` ships:
#     - Argo Application 'flink-kubernetes-operator' (installs the chart →
#       FlinkDeployment / FlinkSessionJob CRDs)
#     - FlinkDeployment 'session-cluster' (CR — needs CRDs to exist)
#   Argo chart sync is async; on a fresh apply the FlinkDeployment lands
#   before the CRDs and kubectl errors with `no matches for kind
#   "FlinkDeployment"`.
#
# Fix: pre-apply lands ONLY the Argo Application first, asks Argo to sync it,
# then blocks until both operator CRDs are Established. The main apply then
# lands the FlinkDeployment against established CRDs on first attempt. Same
# pattern as components/observability/opentelemetry/pre-apply.sh.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT_SECS=600
SLEEP_INTERVAL=10
REQUIRED_CRDS=(
  flinkdeployments.flink.apache.org
  flinksessionjobs.flink.apache.org
)
APP_NAME=flink-kubernetes-operator
ARGO_NS=gitops

# Pre-create destination namespace BEFORE triggering Argo sync. Argo's
# `syncOptions: CreateNamespace=true` is unreliable with helm-chart sources
# under ServerSideApply: in observed runs the chart's CRDs apply (cluster-
# scoped → no namespace needed) but namespaced resources fail with
# `namespaces "flink-operator" not found`. The Argo controller's namespace-
# creation step appears to race with the parallel resource creation phase,
# leaving the sync in `Failed` state with the namespace never created.
# Forcing the namespace into existence ourselves removes that race.
# Field-validated 2026-05-03 against flink-kubernetes-operator chart 1.14.0.
echo "    pre-apply: ensuring flink-operator namespace exists"
kubectl get ns flink-operator >/dev/null 2>&1 || kubectl create ns flink-operator
kubectl label ns flink-operator app.kubernetes.io/part-of=mlops-platform --overwrite >/dev/null

echo "    pre-apply: applying Argo Application for flink-kubernetes-operator"
kubectl apply --server-side --force-conflicts -f "$SCRIPT_DIR/helm-release.yaml"

# Argo's automated.selfHeal=false means the Application sits in OutOfSync after
# create. Trigger sync explicitly via patch (avoids dependency on argocd CLI).
echo "    pre-apply: triggering Argo sync for $APP_NAME"
kubectl -n "$ARGO_NS" patch application "$APP_NAME" --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"apply-component.sh"},"sync":{"prune":false,"syncStrategy":{"apply":{"force":true}}}}}' \
  >/dev/null 2>&1 || true

echo "    pre-apply: waiting up to ${WAIT_SECS}s for CRDs: ${REQUIRED_CRDS[*]}"
ATTEMPTS=$((WAIT_SECS / SLEEP_INTERVAL))
for i in $(seq 1 "$ATTEMPTS"); do
  MISSING=()
  for crd in "${REQUIRED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" >/dev/null 2>&1; then
      MISSING+=("$crd")
    fi
  done
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "    pre-apply: all required CRDs Established"
    break
  fi
  if [[ "$i" -eq "$ATTEMPTS" ]]; then
    echo "    pre-apply: ERROR CRDs not Established in ${WAIT_SECS}s: ${MISSING[*]}" >&2
    exit 1
  fi
  echo "    pre-apply: waiting on ${MISSING[*]} (attempt ${i}/${ATTEMPTS}); sleep ${SLEEP_INTERVAL}s"
  sleep "$SLEEP_INTERVAL"
done

# After CRDs are Established the operator pod is still booting (image pull
# + cert-manager cert issuance). The chart ships
# Mutating/ValidatingWebhookConfiguration with failurePolicy=Fail pointing
# at Service flink-operator/flink-operator-webhook-service. Until that
# Service has at least one Ready endpoint, applying the FlinkDeployment CR
# fails with `failed calling webhook ... service "flink-operator-webhook-
# service" not found`. Wait for the endpoint to populate.
WEBHOOK_NS=flink-operator
WEBHOOK_SVC=flink-operator-webhook-service
echo "    pre-apply: waiting up to ${WAIT_SECS}s for webhook endpoint ${WEBHOOK_NS}/${WEBHOOK_SVC}"
for i in $(seq 1 "$ATTEMPTS"); do
  ADDRS=$(kubectl get endpoints -n "$WEBHOOK_NS" "$WEBHOOK_SVC" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ADDRS" ]]; then
    echo "    pre-apply: webhook endpoint ready (${ADDRS})"
    exit 0
  fi
  echo "    pre-apply: webhook not ready (attempt ${i}/${ATTEMPTS}); sleep ${SLEEP_INTERVAL}s"
  sleep "$SLEEP_INTERVAL"
done

echo "    pre-apply: ERROR webhook endpoint ${WEBHOOK_NS}/${WEBHOOK_SVC} did not become ready in ${WAIT_SECS}s" >&2
exit 1
