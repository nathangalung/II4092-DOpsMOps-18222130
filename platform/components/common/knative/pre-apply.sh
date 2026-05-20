#!/usr/bin/env bash
# =============================================================================
# Knative Serving pre-apply: wait for webhook Deployment Available + endpoint.
# =============================================================================
# Race condition (without this hook):
#   `kubectl apply -k components/common/knative/` ships
#   ValidatingWebhookConfiguration / MutatingWebhookConfiguration AND the
#   Service/Deployment that backs the webhook all in one shot. kustomize emits
#   them in alphabetical+kind order, so the webhook configurations land before
#   the webhook Deployment Pods are Ready. Subsequent CR applies (e.g.
#   knative-serving's own ConfigMap reconciliations or downstream KServe
#   InferenceService that goes through `webhook.serving.knative.dev`) fail
#   with `no endpoints available for service "webhook"`.
#
# Fix: pre-create namespace + Deployments + Service, then block until the
# webhook Deployment is Available AND its Service has at least one endpoint.
# Main apply lands the rest (CRDs already Established, webhooks already
# serving) on first attempt.
#
# Note: gcr.io/knative-releases image-pull on cold cluster has been observed
# to take 11+ minutes (24MB controller, ~22MB autoscaler/webhook), so the
# wait window is sized for slow registry / single-node clusters.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=knative-serving
WEBHOOK_DEPLOY=webhook
WEBHOOK_SVC=webhook
ROLLOUT_TIMEOUT=1500s
ENDPOINT_WAIT_SECS=120
ENDPOINT_SLEEP=5

echo "    pre-apply: applying knative-serving manifests (idempotent first pass)"
kubectl apply --server-side --force-conflicts \
  -f "$SCRIPT_DIR/knative-serving.yaml" >/dev/null 2>&1 || true

# Strip stale knative.dev/example-checksum annotation from CMs whose manifest
# now hoists customizations to top-level data and removed the annotation.
# Without this strip, SSA leaves the legacy annotation in place, which makes
# the config.webhook.serving.knative.dev validator compare an upstream-only
# checksum against modified content and reject every Update.
for cm in config-observability; do
  kubectl annotate -n "$NS" "configmap/${cm}" \
    "knative.dev/example-checksum-" --overwrite >/dev/null 2>&1 || true
done

echo "    pre-apply: waiting up to ${ROLLOUT_TIMEOUT} for ${NS}/${WEBHOOK_DEPLOY} rollout"
if ! kubectl rollout status -n "$NS" "deploy/${WEBHOOK_DEPLOY}" --timeout="${ROLLOUT_TIMEOUT}"; then
  echo "    pre-apply: ERROR ${WEBHOOK_DEPLOY} Deployment did not become Available" >&2
  kubectl get pods -n "$NS" -l app=webhook -o wide >&2 || true
  exit 1
fi

echo "    pre-apply: waiting up to ${ENDPOINT_WAIT_SECS}s for ${NS}/${WEBHOOK_SVC} endpoint"
ATTEMPTS=$((ENDPOINT_WAIT_SECS / ENDPOINT_SLEEP))
for i in $(seq 1 "$ATTEMPTS"); do
  ADDRS=$(kubectl get endpoints -n "$NS" "$WEBHOOK_SVC" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ADDRS" ]]; then
    echo "    pre-apply: webhook endpoint ready (${ADDRS})"
    exit 0
  fi
  sleep "$ENDPOINT_SLEEP"
done

echo "    pre-apply: ERROR webhook endpoint ${NS}/${WEBHOOK_SVC} not populated within ${ENDPOINT_WAIT_SECS}s after rollout" >&2
exit 1
