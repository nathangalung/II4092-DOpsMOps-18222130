#!/usr/bin/env bash
# =============================================================================
# wait-component.sh — wait for all pods labelled app=<component> to be Ready
# =============================================================================
# Usage:
#   wait-component.sh <component-name> [timeout-seconds]
#
# On timeout, runs scripts/prune-stuck-sandboxes.sh against the component's
# namespace to clear containerd CRI sandbox-name reservation cascades
# (#160 / #166 / #169 / #209), then retries the wait once. The prune is
# scoped to the single namespace already known to be stuck, so blast-radius
# stays bounded.
# =============================================================================
set -euo pipefail

NAME="${1:-}"
TIMEOUT="${2:-300}"

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <component-name> [timeout-seconds]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Try common label keys
for sel in "app=$NAME" "app.kubernetes.io/name=$NAME" "app.kubernetes.io/instance=$NAME"; do
  if kubectl get pods -A -l "$sel" --no-headers 2>/dev/null | grep -q .; then
    SEL="$sel"
    NS="$(kubectl get pods -A -l "$sel" --no-headers -o custom-columns=NS:.metadata.namespace 2>/dev/null | head -1)"
    break
  fi
done

if [[ -z "${SEL:-}" ]]; then
  echo "ERROR: no pods found matching app=$NAME (or app.kubernetes.io/name=$NAME)" >&2
  exit 1
fi

echo "==> wait $SEL in $NS (timeout ${TIMEOUT}s)"
if kubectl wait --for=condition=Ready pods -l "$SEL" -n "$NS" --timeout="${TIMEOUT}s"; then
  exit 0
fi

# Wait timed out. The most common single cause under IO pressure on a
# converged single-node cluster is a containerd CRI sandbox-name reservation
# cascade: every retry mints a new container ID that takes the same
# reservation slot, and containerd refuses to start the sandbox while any of
# them remain held. Force-deleting the live pod makes the controller recreate
# it with a NEW UID (= new sandbox name = no reservation collision). See
# scripts/prune-stuck-sandboxes.sh for the full pattern + safeguards.
#
# Single retry only. If the second wait also fails, something else is wrong
# (image pull failure, scheduler unschedulable, init-container crash, etc.)
# and we surface the failure to the caller instead of hiding it under
# unbounded retries.
echo "==> wait timed out — pruning stuck-sandbox pods in $NS and retrying once"
bash "$SCRIPT_DIR/prune-stuck-sandboxes.sh" "$NS" 60 || true
kubectl wait --for=condition=Ready pods -l "$SEL" -n "$NS" --timeout="${TIMEOUT}s"
