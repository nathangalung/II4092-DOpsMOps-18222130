#!/usr/bin/env bash
# =============================================================================
# ClickHouse pre-apply: wait for Altinity operator CRDs before applying the CHI.
# =============================================================================
# Race condition (without this hook):
#   `kubectl apply -k components/storage/clickhouse/` ships
#   ClickHouseInstallation + ClickHouseKeeperInstallation CRs. The CRDs that
#   define those kinds are installed by the Altinity operator chart from
#   components/storage/clickhouse-operator (separate Argo Application). Argo
#   chart sync is async, so the operator pod + CRDs land ~1-2 min after the
#   Application CR. First apply errors with
#   `no matches for kind "ClickHouseInstallation"` /
#   `no matches for kind "ClickHouseKeeperInstallation"`.
#
# Fix: block until both CRDs are Established. Caller (apply-component.sh)
# applies the CR documents on next attempt against ready CRDs.
# =============================================================================
set -euo pipefail

WAIT_SECS=600
SLEEP_INTERVAL=10
REQUIRED_CRDS=(
  clickhouseinstallations.clickhouse.altinity.com
  clickhousekeeperinstallations.clickhouse-keeper.altinity.com
)

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
