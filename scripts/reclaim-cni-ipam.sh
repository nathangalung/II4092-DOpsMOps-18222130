#!/usr/bin/env bash
# =============================================================================
# reclaim-cni-ipam.sh — reclaim leaked flannel host-local IPAM lease files.
# =============================================================================
# k3s flannel + host-local IPAM writes one file per allocated pod IP under
# /var/lib/cni/networks/cbr0/<10.42.x.y>. The file contains the container ID
# and pod metadata. Release happens via CNI DEL when a sandbox tears down.
#
# Under churn (nuke cycles, ImagePullBackOff loops, force-deleted pods,
# operator-driven pod recreations), some DEL calls race with sandbox removal
# and silently no-op. Each leak burns one IP from the /24 range. After
# enough churn, all new pod sandboxes fail with:
#     failed to allocate for range 0: no IP addresses available in
#     range set: 10.42.0.1-10.42.0.254
#
# This script: enumerate live pod IPs (apiserver), enumerate lease files
# (host disk), delete any lease whose IP is NOT in the live set. Idempotent.
#
# Usage:
#   sudo scripts/reclaim-cni-ipam.sh           # reconcile + delete leaks
#   sudo scripts/reclaim-cni-ipam.sh --dry-run # report only, no changes
# =============================================================================
set -euo pipefail

CNI_DIR=/var/lib/cni/networks/cbr0
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root (CNI dir is root-owned). Re-run with sudo." >&2
  exit 1
fi

if [[ ! -d "$CNI_DIR" ]]; then
  echo "$CNI_DIR not present — non-flannel CNI or clean host. Nothing to do."
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not on PATH." >&2
  exit 1
fi

live_tmp=$(mktemp)
lease_tmp=$(mktemp)
trap 'rm -f "$live_tmp" "$lease_tmp"' EXIT

kubectl get pod -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' \
  | awk '/^10\.42\./' | sort -u > "$live_tmp"

ls "$CNI_DIR" 2>/dev/null | awk '/^10\.42\./' | sort -u > "$lease_tmp"

total_leases=$(wc -l < "$lease_tmp")
total_live=$(wc -l < "$live_tmp")
stale_count=$(comm -23 "$lease_tmp" "$live_tmp" | wc -l)

echo "lease_files=$total_leases live_pod_ips=$total_live stale_leases=$stale_count"

if [[ $stale_count -eq 0 ]]; then
  echo "No leaks. Exiting clean."
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "--dry-run: would delete the following lease files:"
  comm -23 "$lease_tmp" "$live_tmp" | sed "s|^|  $CNI_DIR/|"
  exit 0
fi

deleted=0
while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  if rm -f "$CNI_DIR/$ip"; then
    deleted=$((deleted + 1))
  fi
done < <(comm -23 "$lease_tmp" "$live_tmp")

echo "reclaimed=$deleted lease files"
