#!/bin/bash
# =============================================================================
# seed-openbao-from-env.sh
# =============================================================================
# Dev-only bootstrap helper for PLATFORM secrets. Reads a `.env` file and
# creates a K8s Secret named `openbao-bootstrap-seed` in namespace `security`.
# The platform OpenBao bootstrap Job consumes that Secret on first run: every
# key present is used verbatim for the matching `bao kv put`; missing keys
# are randomised.
#
# USE-CASE SECRETS ARE NOT HANDLED HERE. Each use-case owns its own seed
# script + bootstrap Job at:
#   use-case-<name>/scripts/seed-<name>-openbao.sh
#
# Usage:
#   ./platform/scripts/seed-openbao-from-env.sh [path/to/platform/.env]
#
# With no arguments, defaults to platform/.env.
#
# Safe to re-run: overwrites `openbao-bootstrap-seed` each time. The OpenBao
# bootstrap Job only consumes the Secret on the FIRST run; subsequent
# rotations go through `bao kv put` directly.
#
# Platform key mapping (.env -> seed key -> OpenBao path):
#
#   MINIO_ROOT_USER              -> SEED_MINIO_ROOT_USER              -> platform/minio/root#username
#   MINIO_ROOT_PASSWORD          -> SEED_MINIO_ROOT_PASSWORD          -> platform/minio/root#password
#   MINIO_KMS_KEY                -> SEED_MINIO_KMS_KEY                -> platform/minio/kms#key
#   GRAFANA_ADMIN_PASSWORD       -> SEED_GRAFANA_ADMIN_PASSWORD       -> platform/grafana/admin#password
#   GRAFANA_OIDC_CLIENT_SECRET   -> SEED_GRAFANA_OIDC_CLIENT_SECRET   -> platform/grafana/oidc#client_secret
#   SPICEDB_PRESHARED_KEY        -> SEED_SPICEDB_PRESHARED_KEY        -> platform/spicedb/preshared-key#value
#   SPICEDB_POSTGRES_PASSWORD    -> SEED_SPICEDB_POSTGRES_PASSWORD    -> platform/spicedb/postgres#password
#   FEAST_POSTGRES_PASSWORD      -> SEED_FEAST_POSTGRES_PASSWORD      -> platform/postgres/feast#password
#
# The `platform` PG app user (owner role used by every consumer) is NOT
# listed here — CNPG generates and owns that credential and
# openbao-bootstrap mirrors it into `platform/postgres/app`.  There is no
# seed path because `enableSuperuserAccess: false` leaves the legacy
# `postgres` superuser with no usable password to seed in the first place.
#   CLICKHOUSE_ADMIN_PASSWORD    -> SEED_CLICKHOUSE_ADMIN_PASSWORD    -> platform/clickhouse/admin#password
#   KAFKA_ADMIN_PASSWORD         -> SEED_KAFKA_ADMIN_PASSWORD         -> platform/kafka/admin#password
#   APISIX_ADMIN_KEY             -> SEED_APISIX_ADMIN_KEY             -> platform/apisix/admin#key
#   DATAHUB_ADMIN_SECRET         -> SEED_DATAHUB_ADMIN_SECRET         -> platform/datahub/admin#secret
#   LAKEKEEPER_ENCRYPTION_KEY    -> SEED_LAKEKEEPER_ENCRYPTION_KEY    -> platform/lakekeeper/encryption#key
#   ALERTMANAGER_SLACK_DEFAULT   -> SEED_ALERTMANAGER_SLACK_DEFAULT   -> platform/alertmanager/slack#default
#   ALERTMANAGER_SLACK_PLATFORM  -> SEED_ALERTMANAGER_SLACK_PLATFORM  -> platform/alertmanager/slack#platform
#   ALERTMANAGER_SLACK_ML        -> SEED_ALERTMANAGER_SLACK_ML        -> platform/alertmanager/slack#ml
#   ALERTMANAGER_PAGERDUTY_KEY   -> SEED_ALERTMANAGER_PAGERDUTY_KEY   -> platform/alertmanager/pagerduty#service_key
#
# Any key in the .env not in this list is ignored.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-security}"
SECRET_NAME="${SECRET_NAME:-openbao-bootstrap-seed}"

if [ "$#" -eq 0 ]; then
  set -- "${REPO_ROOT}/platform/.env"
fi

declare -A seeds

# Whitelist. Anything outside this list is ignored. Platform-only; use-case
# secrets go through the use-case's own seed script.
mapped_keys=(
  MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_KMS_KEY
  GRAFANA_ADMIN_PASSWORD GRAFANA_OIDC_CLIENT_SECRET
  SPICEDB_PRESHARED_KEY SPICEDB_POSTGRES_PASSWORD
  FEAST_POSTGRES_PASSWORD
  CLICKHOUSE_ADMIN_PASSWORD KAFKA_ADMIN_PASSWORD
  APISIX_ADMIN_KEY DATAHUB_ADMIN_SECRET LAKEKEEPER_ENCRYPTION_KEY
  ALERTMANAGER_SLACK_DEFAULT ALERTMANAGER_SLACK_PLATFORM
  ALERTMANAGER_SLACK_ML ALERTMANAGER_PAGERDUTY_KEY
)

# Load each .env in the order given. Later files override earlier ones.
for envfile in "$@"; do
  if [ ! -f "$envfile" ]; then
    echo "[skip] $envfile (not found)"
    continue
  fi
  echo "[load] $envfile"
  # shellcheck disable=SC1090
  set -a; . "$envfile"; set +a
done

for key in "${mapped_keys[@]}"; do
  val="${!key:-}"
  if [ -n "$val" ] && [ "$val" != "your-${key,,}" ] && [ "$val" != "REPLACE_ME" ]; then
    seeds["SEED_${key}"]="$val"
  fi
done

if [ "${#seeds[@]}" -eq 0 ]; then
  echo "[warn] no seed values found. The bootstrap Job will randomise everything."
  echo "[info] nothing to write; delete any existing $SECRET_NAME if you want to reset."
  exit 0
fi

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "apiVersion: v1"
  echo "kind: Secret"
  echo "metadata:"
  echo "  name: $SECRET_NAME"
  echo "  namespace: $NAMESPACE"
  echo "type: Opaque"
  echo "data:"
  # base64-encode every value into .data so there is no YAML-escaping
  # hazard for strings containing spaces, $, !, \, quotes, or newlines.
  for k in "${!seeds[@]}"; do
    v_b64=$(printf '%s' "${seeds[$k]}" | base64 -w0)
    printf '  %s: %s\n' "$k" "$v_b64"
  done
} > "$tmp"

kubectl apply -f "$tmp"

echo "[ok] wrote $SECRET_NAME in namespace $NAMESPACE with ${#seeds[@]} key(s)"
echo "[next] kubectl apply -k platform/components/security/openbao  # bootstraps OpenBao and consumes the seed"
