#!/usr/bin/env bash
# =============================================================================
# OpenTelemetry pre-apply: install operator first, wait for webhook endpoint.
# =============================================================================
# Race condition (without this hook):
#   `kubectl apply -k components/observability/opentelemetry/` ships both
#   helm-release.yaml (Argo Application that installs the operator chart) AND
#   collectors.yaml (OpenTelemetryCollector + Instrumentation CRs that go
#   through the operator's mutating webhook). When applied in one shot, the
#   CRs hit the webhook before the operator pod is Ready, and kubectl errors
#   with `no endpoints available for service
#   "otel-operator-opentelemetry-operator-webhook"`. Argo's chart sync is
#   async so the operator pod boots ~1–2 min after the Application CR lands
#   (image pull ~1m17s on slow networks).
#
# Fix: pre-apply the Argo Application + namespace-level RBAC, then block until
# the webhook endpoint has at least one address. Main apply then lands the
# collectors against a Ready webhook on first attempt.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=observability
WEBHOOK_SVC=otel-operator-webhook
WAIT_SECS=600
SLEEP_INTERVAL=10

echo "    pre-apply: applying Argo Application + ESO + RBAC for OTel operator"
kubectl apply --server-side --force-conflicts -f "$SCRIPT_DIR/helm-release.yaml"

# CRITICAL — break chicken-egg conversion-webhook deadlock.
#
# The OTel chart ships `opentelemetrycollectors.opentelemetry.io` with
# `spec.conversion.strategy=Webhook` pointing to the operator's own service
# (`otel-operator-webhook`). On a fresh install, while the operator pod is
# still starting (image pull + cert-manager cert issuance + istio sidecar
# init), the conversion webhook has no endpoints. kube-apiserver's CRD cacher
# reflector hammers the unreachable webhook in a tight retry loop (every
# ~100ms — see `cacher.go: unexpected ListAndWatch error: ... no endpoints
# available for service "otel-operator-webhook"; reinitializing...`).
#
# That loop saturates the single-node CPU (observed load avg 17+ on a 16-core
# box, 100% CPU on apiserver). containerd's CreateContainer hits its 4-min
# default timeout under that pressure → kubelet retries with a NEW container
# UID → containerd still holds the OLD container in `Created` state under
# the same name → "failed to reserve container name ... is reserved for
# <hash>" cascade across every pod trying to start (otel-operator itself,
# istio sidecar inits, anything new). Cluster-wide deadlock.
#
# Fix: patch the CRD's conversion strategy to `None` immediately after the
# chart deploys it. We exclusively author v1beta1 CRs in collectors.yaml so
# version conversion is never needed; setting strategy=None makes the cacher
# loop short-circuit (returns the stored object directly). Operator pod can
# then actually start, webhook endpoint populates, main apply lands cleanly.
# Field-validated 2026-05-02 — observed load avg 17.96 → 9.06 within 90s of
# patching, otel-operator pod transitioned from CreateContainerError →
# Running within 3 min.
echo "    pre-apply: waiting for OTel CRDs to exist before disabling conversion webhook"
CRD_WAIT_DEADLINE=$(( $(date +%s) + 120 ))
while [[ $(date +%s) -lt $CRD_WAIT_DEADLINE ]]; do
  if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
if ! kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
  echo "    pre-apply: ERROR opentelemetrycollectors CRD did not appear in 120s" >&2
  exit 1
fi

echo "    pre-apply: patching OTel CRDs to conversion.strategy=None (no v1alpha1 CRs in this repo)"
for crd in opentelemetrycollectors.opentelemetry.io \
           instrumentations.opentelemetry.io \
           opampbridges.opentelemetry.io \
           targetallocators.opentelemetry.io; do
  kubectl get crd "$crd" >/dev/null 2>&1 || continue
  current=$(kubectl get crd "$crd" -o jsonpath='{.spec.conversion.strategy}' 2>/dev/null || echo "")
  if [[ "$current" == "Webhook" ]]; then
    # JSON Patch `replace` on /spec/conversion fully clears webhookClientConfig
    # + conversionReviewVersions (CRD validation rejects merge patches that
    # leave those fields set when strategy != Webhook).
    kubectl patch crd "$crd" --type=json \
      -p '[{"op":"replace","path":"/spec/conversion","value":{"strategy":"None"}}]' >/dev/null
    echo "    pre-apply: patched ${crd} conversion → None"
  fi
done

echo "    pre-apply: waiting up to ${WAIT_SECS}s for webhook endpoint ${NS}/${WEBHOOK_SVC}"
ATTEMPTS=$((WAIT_SECS / SLEEP_INTERVAL))
for i in $(seq 1 "$ATTEMPTS"); do
  ADDRS=$(kubectl get endpoints -n "$NS" "$WEBHOOK_SVC" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ADDRS" ]]; then
    echo "    pre-apply: webhook endpoint ready (${ADDRS})"
    exit 0
  fi
  echo "    pre-apply: webhook not ready (attempt ${i}/${ATTEMPTS}); sleep ${SLEEP_INTERVAL}s"
  sleep "$SLEEP_INTERVAL"
done

echo "    pre-apply: ERROR webhook endpoint ${NS}/${WEBHOOK_SVC} did not become ready in ${WAIT_SECS}s" >&2
exit 1
