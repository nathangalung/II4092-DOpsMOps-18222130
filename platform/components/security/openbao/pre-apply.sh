#!/usr/bin/env bash
# =============================================================================
# openbao pre-apply: delete any prior `openbao-bootstrap` Job
# =============================================================================
# A Kubernetes Job's spec.template is immutable once created. The platform
# applies openbao-bootstrap.yaml on every `make install-openbao` so the
# bootstrap script (apk add, init/unseal, KV seeding) re-runs idempotently —
# but server-side apply rejects template mutations with `field is immutable`,
# making the second `install-openbao` invocation fatal.
#
# Pre-apply hook removes the prior Job (and its Pods) before kustomize re-renders
# it. The bootstrap script itself is idempotent (bao status check, ensure_kv,
# bao kv get-before-put), so re-running the Job on a healthy cluster is a
# no-op against OpenBao state.
#
# `--ignore-not-found` makes the hook safe on first install.
# =============================================================================
set -euo pipefail

NS=security
JOB=openbao-bootstrap

if kubectl -n "$NS" get job "$JOB" >/dev/null 2>&1; then
  echo "    [pre-apply] deleting prior $NS/$JOB Job (immutable spec.template)"
  kubectl -n "$NS" delete job "$JOB" --ignore-not-found --wait=true
fi
