#!/usr/bin/env bash
# =============================================================================
# metrics-server/pre-apply.sh — install upstream metrics-server with k3s flags
# =============================================================================
# This k3s server was started with `--disable=metrics-server`, so the bundled
# Deployment is absent. We install upstream components.yaml ourselves and patch
# it for k3s compatibility:
#
#   - `--kubelet-insecure-tls` — k3s kubelet presents a self-signed cert that
#     metrics-server cannot validate against the in-cluster bundle without
#     this flag. Without it /readyz returns 500 and every HPA fails.
#
# After install we wait for Deployment Available so HPAs created later can
# fetch CPU/memory metrics on first reconcile.
# =============================================================================
set -euo pipefail

VERSION="${METRICS_SERVER_VERSION:-v0.8.1}"
URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${VERSION}/components.yaml"
# Repo-local cache (env-agnostic; survives /tmp wipes). REPO_ROOT exported by
# scripts/apply-component.sh; fall back to walking up so the hook is also
# runnable standalone (4 levels: metrics-server → common → components → platform → repo).
: "${REPO_ROOT:=$(cd "$(dirname "$0")/../../../.." && pwd)}"
CACHE_DIR="${CACHE_DIR:-$REPO_ROOT/.cache}/downloads"
mkdir -p "$CACHE_DIR"
SRC="$CACHE_DIR/metrics-server-${VERSION}-components.yaml"
OUT="$CACHE_DIR/metrics-server-${VERSION}-patched.yaml"

if [[ ! -f "$SRC" ]]; then
  echo "    fetching ${URL}"
  curl -fsSL "$URL" -o "$SRC"
fi

# Inject `--kubelet-insecure-tls` + `--kubelet-request-timeout=60s` into the
# metrics-server container args list. Idempotent: skip if already present.
#
# `--kubelet-request-timeout=60s` (default 10s) — k3s kubelet on a single-node
# 32-core box hosting 200+ pods routinely needs 30-50s to serve
# `/metrics/resource` during reconciliation bursts.  20s was insufficient
# (verified 2026-05-07 — `Failed to scrape node, timeout to access kubelet
# 167.205.88.202:10250: context deadline exceeded` at 20s; readiness probe
# stays at HTTP 500 "metric-storage-ready: no metrics to serve" → every HPA
# returns `FailedGetResourceMetric`).  60s gives the kubelet a fair window.
#
# `--metric-resolution=90s` — metrics-server v0.8.x enforces
# `metric-resolution > kubelet-request-timeout` at startup; with timeout=60s
# the prior 30s value crashes the pod with `panic: metric-resolution should
# be larger than kubelet-request-timeout`. 90s also halves kubelet scrape
# load vs the 15s default and matches prometheus' 60s scrape tier.
if grep -q -- '--kubelet-insecure-tls' "$SRC"; then
  cp "$SRC" "$OUT"
else
  awk '
    /^[[:space:]]+- --metric-resolution=/ {
      match($0, /^[[:space:]]+/)
      indent = substr($0, 1, RLENGTH)
      sub(/--metric-resolution=15s/, "--metric-resolution=90s")
      print
      print indent "- --kubelet-insecure-tls"
      print indent "- --kubelet-request-timeout=60s"
      next
    }
    { print }
  ' "$SRC" > "$OUT"
fi

echo "    applying upstream metrics-server ${VERSION} (with --kubelet-insecure-tls)"
kubectl apply --server-side --force-conflicts -f "$OUT" 2>&1 | tail -10

echo "    waiting metrics-server Available (timeout 300s)"
kubectl -n kube-system wait --for=condition=Available --timeout=300s \
  deployment/metrics-server 2>&1 | tail -3

echo "    metrics-server ${VERSION} ready"
