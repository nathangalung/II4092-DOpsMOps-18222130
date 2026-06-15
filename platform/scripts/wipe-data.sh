#!/usr/bin/env bash
# =============================================================================
# wipe-data.sh — DESTRUCTIVE: drop every PVC + PV in platform data namespaces
# =============================================================================
# Resets all stateful storage (Postgres data, MinIO objects, Kafka logs,
# ClickHouse parts, etc.). Use after `scale-zero-all` to ensure no pods are
# holding the PVCs.
#
# Usage:
#   wipe-data.sh                     # default: storage + data-ingestion + observability
#   wipe-data.sh ns1 ns2 ns3 ...     # explicit namespace list
#   FORCE=1 wipe-data.sh ...         # skip confirmation
# =============================================================================
set -euo pipefail

if [[ $# -gt 0 ]]; then
  NSS=("$@")
else
  NSS=(storage data-ingestion data-processing data-governance model-lifecycle observability gitops)
fi

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "WARNING: this will delete every PVC in: ${NSS[*]}"
  echo "         Postgres / Kafka / MinIO / ClickHouse data will be lost."
  read -r -p "Type 'YES' to continue: " confirm
  [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

for ns in "${NSS[@]}"; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    continue
  fi
  echo "==> $ns: deleting all PVCs"
  kubectl delete pvc --all -n "$ns" --ignore-not-found --wait=false || true
done

echo ""
echo "==> Cleaning up Released PVs"
kubectl get pv -o json 2>/dev/null \
  | jq -r '.items[] | select(.status.phase=="Released") | .metadata.name' 2>/dev/null \
  | while read -r pv; do
      [[ -z "$pv" ]] && continue
      echo "    delete pv/$pv"
      kubectl delete pv "$pv" --ignore-not-found --wait=false || true
    done

echo ""
echo "Done. PVCs may take a few seconds to fully terminate."
