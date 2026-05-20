#!/usr/bin/env bash
# =============================================================================
# render-scalability.sh — render an HPA / VPA / KEDA ScaledObject from template
# =============================================================================
# Usage:
#   render-scalability.sh hpa <component> <ns> <min> <max>
#   render-scalability.sh vpa <component> <ns>
#   render-scalability.sh keda <component> <ns> <trigger>
#
# Env knobs (all optional with sane defaults):
#   KIND            Deployment (default) | StatefulSet
#   CPU_TARGET=70 MEM_TARGET=80
#   MODE=Off|Initial|Auto
#   CPU_MIN=100m CPU_MAX=2 MEM_MIN=128Mi MEM_MAX=4Gi
#   TRIGGER_META='...'
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL_DIR="$ROOT/platform/scalability"

KIND_TYPE="${1:-}"
COMPONENT="${2:-}"
NS="${3:-}"

if [[ -z "$KIND_TYPE" || -z "$COMPONENT" || -z "$NS" ]]; then
  echo "Usage: $0 hpa|vpa|keda <component> <ns> [extra...]" >&2
  exit 1
fi

KIND="${KIND:-Deployment}"

case "$KIND_TYPE" in
  hpa)
    MIN="${4:-1}"; MAX="${5:-5}"
    CPU_TARGET="${CPU_TARGET:-70}"; MEM_TARGET="${MEM_TARGET:-80}"
    sed \
      -e "s|{{COMPONENT}}|$COMPONENT|g" \
      -e "s|{{NAMESPACE}}|$NS|g" \
      -e "s|{{KIND}}|$KIND|g" \
      -e "s|{{MIN}}|$MIN|g" \
      -e "s|{{MAX}}|$MAX|g" \
      -e "s|{{CPU_TARGET}}|$CPU_TARGET|g" \
      -e "s|{{MEM_TARGET}}|$MEM_TARGET|g" \
      "$TPL_DIR/hpa-template.yaml" | kubectl apply -f -
    ;;
  vpa)
    MODE="${MODE:-Off}"
    CPU_MIN="${CPU_MIN:-100m}"; CPU_MAX="${CPU_MAX:-2}"
    MEM_MIN="${MEM_MIN:-128Mi}"; MEM_MAX="${MEM_MAX:-4Gi}"
    sed \
      -e "s|{{COMPONENT}}|$COMPONENT|g" \
      -e "s|{{NAMESPACE}}|$NS|g" \
      -e "s|{{KIND}}|$KIND|g" \
      -e "s|{{MODE}}|$MODE|g" \
      -e "s|{{CPU_MIN}}|$CPU_MIN|g" \
      -e "s|{{CPU_MAX}}|$CPU_MAX|g" \
      -e "s|{{MEM_MIN}}|$MEM_MIN|g" \
      -e "s|{{MEM_MAX}}|$MEM_MAX|g" \
      "$TPL_DIR/vpa-template.yaml" | kubectl apply -f -
    ;;
  keda)
    TRIGGER="${4:-cpu}"
    MIN="${MIN:-0}"; MAX="${MAX:-5}"
    TRIGGER_META="${TRIGGER_META:-type: Utilization\n        value: \"70\"}"
    sed \
      -e "s|{{COMPONENT}}|$COMPONENT|g" \
      -e "s|{{NAMESPACE}}|$NS|g" \
      -e "s|{{KIND}}|$KIND|g" \
      -e "s|{{MIN}}|$MIN|g" \
      -e "s|{{MAX}}|$MAX|g" \
      -e "s|{{TRIGGER}}|$TRIGGER|g" \
      -e "s|{{TRIGGER_META}}|$TRIGGER_META|g" \
      "$TPL_DIR/keda-scaledobject-template.yaml" | kubectl apply -f -
    ;;
  *)
    echo "ERROR: unknown type '$KIND_TYPE' (expected: hpa|vpa|keda)" >&2
    exit 1
    ;;
esac
