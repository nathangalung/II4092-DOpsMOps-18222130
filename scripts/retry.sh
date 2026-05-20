#!/usr/bin/env bash
# =============================================================================
# retry.sh — generic command retry wrapper
# =============================================================================
# Wraps any command in an attempt loop. Used by:
#   - apply-component.sh (single component apply)
#   - Makefile install-ns-* (per-namespace bulk apply)
#   - any caller that needs CRD-before-CR / webhook-not-ready resilience
#
# Usage:
#   retry.sh <max-attempts> <delay-sec> -- <cmd> [args...]
#
# Exit codes:
#   0  command succeeded within max-attempts
#   2  command failed every attempt
# =============================================================================
set -euo pipefail

MAX="${1:?max-attempts required (e.g. 10)}"
DELAY="${2:?delay-sec required (e.g. 10)}"
shift 2
if [[ "${1:-}" == "--" ]]; then
  shift
fi
if [[ $# -eq 0 ]]; then
  echo "ERROR: no command supplied after -- separator" >&2
  exit 2
fi

attempt=1
while (( attempt <= MAX )); do
  echo "    attempt ${attempt}/${MAX}: $*"
  if "$@"; then
    echo "    OK on attempt ${attempt}"
    exit 0
  fi
  if (( attempt == MAX )); then
    echo "    FAILED after ${MAX} attempts (last error above)" >&2
    exit 2
  fi
  echo "    retrying in ${DELAY}s..."
  sleep "${DELAY}"
  attempt=$(( attempt + 1 ))
done
