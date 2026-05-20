#!/usr/bin/env bash
# =============================================================================
# apply-namespaces.sh — create every platform namespace upfront
# =============================================================================
# Phases install components in series; some components reference resources in
# adjacent namespaces (e.g. ESO ClusterSecretStore reads `storage/postgresql-app`)
# so it's safer to declare every namespace first.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPONENTS="$ROOT/platform/components"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
DELAY="${DELAY:-10}"

declare -a NS_FILES=(
  "$COMPONENTS/common/namespace.yaml"
  "$COMPONENTS/security/namespace.yaml"
  "$COMPONENTS/storage/namespace.yaml"
  "$COMPONENTS/data-ingestion/namespace.yaml"
  "$COMPONENTS/data-processing/namespace.yaml"
  "$COMPONENTS/data-governance/namespace.yaml"
  "$COMPONENTS/model-lifecycle/namespace.yaml"
  "$COMPONENTS/model-serving/namespace.yaml"
  "$COMPONENTS/observability/namespace.yaml"
  "$COMPONENTS/gitops/namespace.yaml"
)

for f in "${NS_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo "==> apply $f"
    bash "$ROOT/scripts/retry.sh" "$MAX_ATTEMPTS" "$DELAY" -- kubectl apply -f "$f"
  else
    echo "WARN: $f missing — skipping" >&2
  fi
done
