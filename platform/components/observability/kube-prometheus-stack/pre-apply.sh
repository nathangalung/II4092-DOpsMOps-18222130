#!/usr/bin/env bash
# =============================================================================
# kube-prometheus-stack pre-apply: install operator chart first, wait for CRDs.
# =============================================================================
# Race condition (without this hook):
#   `kubectl apply -k components/observability/kube-prometheus-stack/` ships
#   helm-release.yaml (Argo Application that installs the chart, including the
#   monitoring.coreos.com/v1 CRD bundle) AND prometheus-rules.yaml +
#   alertmanager-configs.yaml (PrometheusRule + AlertmanagerConfig CRs). When
#   applied in one shot, the CRs hit a kubectl `resource mapping not found
#   for kind PrometheusRule` because Argo's chart sync (which installs the
#   CRDs) is async and runs after the Application CR lands.
#
# Fix: pre-apply the Argo Application, then block until the relevant CRDs are
# Established. Main apply then lands the PrometheusRule + AlertmanagerConfig
# CRs against ready CRDs on first attempt.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT_SECS=600
SLEEP_INTERVAL=10
REQUIRED_CRDS=(
  prometheusrules.monitoring.coreos.com
  alertmanagerconfigs.monitoring.coreos.com
)

echo "    pre-apply: applying Argo Application + ESO for kube-prometheus-stack"
kubectl apply --server-side --force-conflicts -f "$SCRIPT_DIR/helm-release.yaml"

echo "    pre-apply: waiting up to ${WAIT_SECS}s for CRDs: ${REQUIRED_CRDS[*]}"
ATTEMPTS=$((WAIT_SECS / SLEEP_INTERVAL))
for i in $(seq 1 "$ATTEMPTS"); do
  MISSING=()
  for crd in "${REQUIRED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" >/dev/null 2>&1; then
      MISSING+=("$crd")
    fi
  done
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "    pre-apply: all required CRDs Established"
    exit 0
  fi
  echo "    pre-apply: waiting on ${MISSING[*]} (attempt ${i}/${ATTEMPTS}); sleep ${SLEEP_INTERVAL}s"
  sleep "$SLEEP_INTERVAL"
done

echo "    pre-apply: ERROR CRDs not Established in ${WAIT_SECS}s: ${MISSING[*]}" >&2
exit 1
