#!/usr/bin/env bash
# =============================================================================
# prune-stuck-sandboxes.sh — recover pods wedged by containerd CRI sandbox-name
# reservation cascade (#160 / #166 / #169 / #209).
# =============================================================================
# Usage:
#   prune-stuck-sandboxes.sh <namespace> [min-stuck-seconds]
#
# Root pattern, observed every prior incident:
#   FailedCreatePodSandBox: failed to reserve sandbox name
#     "<pod>_<ns>_<UID>_0": is reserved for "<container-id-A>"
#       ... is reserved for "<container-id-B>"  (after kubelet retry)
#       ... is reserved for "<container-id-C>"  (after another retry)
#       ... up to N container IDs all holding the same reservation slot
#
# The sandbox name is keyed on the pod UID, which kubelet preserves across
# retries. Each retry under IO pressure creates a NEW container ID, each of
# which now also takes the reservation slot. Containerd refuses to mint a new
# sandbox while the slot is reserved. Cascade is self-perpetuating.
#
# Mitigation: force-delete the LIVE pod. ReplicaSet/StatefulSet/DaemonSet
# controller mints a REPLACEMENT pod with a NEW UID. New UID = new sandbox
# name = no matching reservation = containerd accepts. The old reservations
# are eventually garbage-collected by containerd's stale-sandbox cleanup, but
# we don't block on that — the new pod proceeds immediately.
#
# Scope: ONE namespace. Caller (wait-component.sh) only fires this on its own
# component's namespace after wait-timeout, so blast-radius is bounded to the
# component that's already known-stuck. Bare pods (no ownerRef) are skipped
# because force-deleting them is destructive — the user must reconcile by hand.
#
# Threshold: default 60s of stuck-time. Caller already waited its own timeout
# (typically 300–900s), so any matching pod has by definition been Pending for
# at least the wait duration. The 60s gate filters out pods that legitimately
# started during the wait window's tail.
# =============================================================================
set -euo pipefail

NS="${1:-}"
MIN_AGE_SEC="${2:-60}"

if [[ -z "$NS" ]]; then
  echo "Usage: $0 <namespace|--all> [min-stuck-seconds]" >&2
  exit 1
fi

# --all → iterate every namespace. Useful as a phase-full tail safety net.
# Per-namespace scope still applies inside the loop, so a wedge in one ns
# can't block work on another.
if [[ "$NS" == "--all" || "$NS" == "-A" ]]; then
  rc=0
  for ns in $(kubectl get ns -o name 2>/dev/null | cut -d/ -f2); do
    bash "$0" "$ns" "$MIN_AGE_SEC" || rc=$?
  done
  exit "$rc"
fi

if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "    prune-stuck-sandboxes: namespace $NS not found, skipping"
  exit 0
fi

now=$(date +%s)
deleted=0
skipped_owner=0
checked=0

# Collect Pending pods with their creation timestamp + ownerKind so we can
# decide which are safe to force-delete (must have a controller that will
# recreate them with a new UID).
while IFS=$'\t' read -r name created owner_kind; do
  [[ -z "$name" ]] && continue
  checked=$((checked + 1))

  start_epoch=$(date -d "$created" +%s 2>/dev/null || echo "$now")
  age=$(( now - start_epoch ))
  (( age < MIN_AGE_SEC )) && continue

  if [[ -z "$owner_kind" || "$owner_kind" == "null" ]]; then
    skipped_owner=$((skipped_owner + 1))
    continue
  fi

  # Confirm the symptom before acting. We only act on pods whose recent events
  # show a sandbox-name reservation failure — other Pending reasons (image
  # pull, scheduler unschedulable, init-container crash) are NOT fixable by
  # this script and force-deleting would just churn the workload.
  if kubectl -n "$NS" get events \
        --field-selector "involvedObject.name=$name,reason=FailedCreatePodSandBox" \
        --sort-by=.lastTimestamp -o name 2>/dev/null | grep -q . \
     || kubectl -n "$NS" describe pod "$name" 2>/dev/null \
        | grep -qE 'reserved for "[0-9a-f]{8,}'; then
    echo "    prune $NS/$name (stuck ${age}s, sandbox reserved, owner=$owner_kind)"
    kubectl -n "$NS" delete pod "$name" \
        --grace-period=0 --force --wait=false >/dev/null 2>&1 \
      && deleted=$((deleted + 1)) || true
  fi
done < <(
  kubectl -n "$NS" get pods \
    -o jsonpath='{range .items[?(@.status.phase=="Pending")]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\t"}{.metadata.ownerReferences[0].kind}{"\n"}{end}' \
    2>/dev/null
)

# Only print summary when something interesting happened. Empty namespaces are
# the common case (every install-% call invokes --all); silencing them keeps
# phase-full logs readable while preserving forensic output when pods are
# actually pending or got pruned.
if (( checked > 0 || deleted > 0 )); then
  echo "    prune-stuck-sandboxes: ns=$NS checked=$checked deleted=$deleted skipped_no_owner=$skipped_owner"
fi
exit 0
