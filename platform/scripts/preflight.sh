#!/usr/bin/env bash
# =============================================================================
# preflight.sh — verify required tools + kubectl context
# =============================================================================
set -euo pipefail

PASS=0
FAIL=0

check() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver="$($cmd version --client --short 2>/dev/null \
        || $cmd version --short 2>/dev/null \
        || $cmd --version 2>/dev/null | head -1 \
        || echo "(version unknown)")"
    echo "  [PASS] $name: $ver"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name: not found in PATH"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Tooling ==="
check "kubectl" kubectl
check "helm" helm
check "kustomize" kustomize
check "jq" jq
check "yq" yq

echo ""
echo "=== Kubernetes context ==="
if kubectl config current-context >/dev/null 2>&1; then
  echo "  context: $(kubectl config current-context)"
  if kubectl version --short 2>/dev/null | grep -q Server; then
    kubectl version --short 2>/dev/null | grep Server | sed 's/^/  /'
  fi
  echo "  cluster reachable: yes"
else
  echo "  [FAIL] no current kubectl context"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
