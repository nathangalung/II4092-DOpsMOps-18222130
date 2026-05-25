#!/usr/bin/env bash
# =============================================================================
# datahub-ingestion pre-apply: ensure `datahub-feast-deps:1.5.0.1` is present
# in platform-registry before the feast CronJob's initContainer tries to
# pull it.
# =============================================================================
# Background (full rationale in build-resources.yaml header):
#   `acryldata/datahub-ingestion:v1.5.0.3` ships the DataHub feast SOURCE
#   plugin but not the `feast` python package itself. We sidecar-overlay
#   the missing deps via PYTHONPATH; the deps are baked into a tiny image
#   built fresh into the in-cluster CNCF Distribution registry.
#
# Run order:
#   1. Ensure data-governance namespace exists (caller may have invoked
#      `make install-datahub-ingestion` directly without phase-full).
#   2. Wait for platform-registry rollout (Deployment in `platform-registry`
#      namespace; common/registry).
#   3. Skip-if-present: query /v2/datahub-feast-deps/tags/list. If 1.5.0.1
#      is already there (re-apply without nuke), exit clean.
#   4. Otherwise: drop any stale build Job, apply build-resources.yaml
#      directly, wait up to 900s for the kaniko Job to complete.
# =============================================================================
set -euo pipefail

NS=data-governance
REGISTRY_NS=platform-registry
IMAGE_REPO=datahub-feast-deps
IMAGE_TAG=1.5.0.1
JOB_NAME=datahub-feast-deps-build

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "    pre-apply: ensure namespace ${NS} exists"
kubectl apply -f "${DIR}/../namespace.yaml" >/dev/null

echo "    pre-apply: wait for platform-registry rollout"
kubectl -n "${REGISTRY_NS}" rollout status deploy/registry --timeout=180s

echo "    pre-apply: check ${IMAGE_REPO}:${IMAGE_TAG} in platform-registry"
# wget is the only HTTP client guaranteed on the busybox-based CNCF
# Distribution image. /v2/<repo>/tags/list returns JSON
# {"name":"<repo>","tags":["1.5.0.1",...]} when the repo exists, or 404
# when it doesn't. grep the literal tag substring (with quotes) so a
# 404 body (which is just "404 page not found") never accidentally
# matches a different tag substring.
if kubectl -n "${REGISTRY_NS}" exec deploy/registry -- \
    wget -qO- "http://localhost:5000/v2/${IMAGE_REPO}/tags/list" 2>/dev/null \
    | grep -q "\"${IMAGE_TAG}\""; then
  echo "    pre-apply: ${IMAGE_REPO}:${IMAGE_TAG} already present — skipping kaniko build"
  exit 0
fi

echo "    pre-apply: ${IMAGE_REPO}:${IMAGE_TAG} missing — running kaniko build"

# Drop any stale Job from a previous failed run. ttlSecondsAfterFinished
# usually reaps within 30 min but pre-apply can fire much sooner on a
# retry. --wait=false because kubectl apply does its own readiness check
# below; we just need the OBJECT gone so apply doesn't conflict on the
# immutable Job spec.
kubectl -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found
kubectl -n "${NS}" wait --for=delete "job/${JOB_NAME}" --timeout=60s 2>/dev/null || true

# Apply the build bundle. server-side+force-conflicts matches what
# apply-component.sh uses for the main render, so SSA field ownership
# stays consistent if this same component later updates the bundle.
# Direct -f apply (no kustomize layer): single file, no transforms needed,
# and parent kustomization.yaml intentionally excludes this bundle to keep
# `kubectl apply -k ../` from blowing up on partial-namespace state.
kubectl apply --server-side --force-conflicts -f "${DIR}/build-resources.yaml"

# Wait for build by polling the registry for the published tag, NOT by
# `kubectl wait --for=condition=complete job/...`. Field-observed in this
# k3s cluster (2026-05-11, task #201): a kaniko build Job's only container
# can reach exitCode=0 and a final `Pushed registry.../tag@sha256:...`
# log line, while the pod's `.status.phase` remains "Running" for >10 min
# afterwards (containerStatuses show Terminated/Completed but the phase
# field never advances). Job controller derives `Complete` condition from
# pod phase=Succeeded, so condition=complete never fires and the wait
# eventually times out — even though the image is already in the registry
# and downstream pulls would succeed. Polling the registry directly
# decouples this hook from the cluster's phase-reporting latency.
#
# Fast-fail still works: if the pod genuinely fails (kaniko errors,
# OOM, etc.) the Job controller bumps `.status.failed`, and we surface
# that in <10s.
echo "    pre-apply: waiting up to 900s for ${IMAGE_REPO}:${IMAGE_TAG} to appear in platform-registry"
deadline=$(( $(date +%s) + 900 ))
while (( $(date +%s) < deadline )); do
  if kubectl -n "${REGISTRY_NS}" exec deploy/registry -- \
      wget -qO- "http://localhost:5000/v2/${IMAGE_REPO}/tags/list" 2>/dev/null \
      | grep -q "\"${IMAGE_TAG}\""; then
    echo "    pre-apply: ${IMAGE_REPO}:${IMAGE_TAG} now in platform-registry — build succeeded"
    # Best-effort cleanup of the (likely phase-wedged) Job. ttlSecondsAfterFinished
    # would eventually reap, but on phase-wedged pods the controller never
    # observes Succeeded so the TTL clock doesn't start. Force-delete here
    # so a subsequent pre-apply re-run sees a clean ns.
    kubectl -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false
    exit 0
  fi
  failed=$(kubectl -n "${NS}" get job "${JOB_NAME}" -o jsonpath='{.status.failed}' 2>/dev/null || echo 0)
  if [[ "${failed:-0}" -gt 0 ]]; then
    echo "    pre-apply: kaniko Job reported status.failed=${failed} — dumping logs" >&2
    kubectl -n "${NS}" logs -l job-name="${JOB_NAME}" --tail=200 >&2 || true
    exit 1
  fi
  sleep 10
done

echo "    pre-apply: timed out waiting for ${IMAGE_REPO}:${IMAGE_TAG} in registry — dumping logs" >&2
kubectl -n "${NS}" logs -l job-name="${JOB_NAME}" --tail=200 >&2 || true
exit 1
