#!/usr/bin/env bash
# =============================================================================
# list-components.sh — print every installable component grouped by namespace
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPONENTS="$ROOT/platform/components"

declare -a NAMESPACES=(
  common security storage data-ingestion data-processing
  data-governance model-lifecycle model-serving observability gitops
)

for ns in "${NAMESPACES[@]}"; do
  if [[ -d "$COMPONENTS/$ns" ]]; then
    echo ""
    echo "[$ns]"
    for d in "$COMPONENTS/$ns"/*/; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      echo "  - $name"
    done
  fi
done
