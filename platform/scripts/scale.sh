#!/usr/bin/env bash
# =============================================================================
# scale.sh — scale a single component up/down across known namespaces
# =============================================================================
# Usage:
#   scale.sh <up|down> <component> <replicas> [namespace]
# If namespace is omitted, searches all platform namespaces.
# =============================================================================
set -euo pipefail

DIR="${1:-}"
NAME="${2:-}"
REPLICAS="${3:-1}"
NS="${4:-}"

if [[ -z "$DIR" || -z "$NAME" ]]; then
  echo "Usage: $0 <up|down> <component> <replicas> [namespace]" >&2
  exit 1
fi

if [[ -z "$NS" ]]; then
  # Search every namespace for a Deployment or StatefulSet matching $NAME
  NS="$(kubectl get deploy -A --no-headers -o custom-columns=NS:.metadata.namespace,N:.metadata.name 2>/dev/null \
    | awk -v n="$NAME" '$2==n {print $1; exit}')"
  if [[ -z "$NS" ]]; then
    NS="$(kubectl get sts -A --no-headers -o custom-columns=NS:.metadata.namespace,N:.metadata.name 2>/dev/null \
      | awk -v n="$NAME" '$2==n {print $1; exit}')"
  fi
fi

if [[ -z "$NS" ]]; then
  echo "ERROR: cannot locate Deployment/StatefulSet '$NAME' in any namespace." >&2
  exit 1
fi

# Try Deployment first, fall back to StatefulSet
if kubectl get deploy "$NAME" -n "$NS" >/dev/null 2>&1; then
  KIND=deploy
elif kubectl get sts "$NAME" -n "$NS" >/dev/null 2>&1; then
  KIND=sts
else
  echo "ERROR: '$NAME' is neither Deployment nor StatefulSet in $NS" >&2
  exit 1
fi

echo "==> scale $KIND/$NAME -n $NS → $REPLICAS"
kubectl scale "$KIND" "$NAME" -n "$NS" --replicas="$REPLICAS"
