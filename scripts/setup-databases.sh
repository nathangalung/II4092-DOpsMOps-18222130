#!/bin/bash
# =============================================================================
# setup-databases.sh — one-shot database bootstrap helper (operator utility)
# =============================================================================
# Idempotent: create any logical databases that CNPG's postInitApplicationSQL
# or MySQL's init.sql didn't cover (pg_trgm/btree_gin extensions, extra MySQL
# schemas for MLMD/KServe).
#
# Credentials are ALWAYS pulled from the ESO-managed Secrets at run-time; no
# passwords are ever embedded in this script.  Requires:
#   - kubectl with read access to `storage` namespace secrets
#   - CNPG cluster `postgresql` reachable at postgresql-rw.storage:5432
#   - mysql Deployment in storage (for Katib/MLMD)
#
# Usage:
#   ./setup-databases.sh [storage]
#
# If you need to run this before OpenBao/ESO is up, bootstrap the Secrets
# manually (see platform/REMEDIATION_RUNBOOK.md §Bootstrap-Order).
# =============================================================================
set -euo pipefail

KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"
NAMESPACE="${1:-storage}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Resolve passwords from the ExternalSecret-managed Secrets.
# -- Postgres: CNPG publishes the app-user credential as `postgresql-app`
#    in the same namespace as the Cluster (keys: `username`, `password`,
#    `uri`, `jdbc-uri`, `host`, `port`, `dbname`, `pgpass`).  That is the
#    only PG credential with working password auth — CNPG defaults
#    `enableSuperuserAccess: false`, so the `postgres` role has no usable
#    password.  The `platform` role in `postgresql-app` has CREATEROLE +
#    CREATEDB + REPLICATION (granted by cluster.yaml's postInitApplicationSQL),
#    which is the exact surface this script exercises.
read_secret() {
    local ns="$1" name="$2" key="$3"
    "$KUBECTL_CMD" -n "$ns" get secret "$name" \
        -o "jsonpath={.data.$key}" 2>/dev/null | base64 -d
}

PG_USER="$(read_secret "$NAMESPACE" postgresql-app username 2>/dev/null || true)"
PG_PASS="$(read_secret "$NAMESPACE" postgresql-app password 2>/dev/null || true)"
[ -n "${PG_USER:-}" ] || die "Could not resolve postgres app username from 'postgresql-app' Secret in $NAMESPACE (CNPG Cluster bootstrap may not be complete)"
[ -n "${PG_PASS:-}" ] || die "Could not resolve postgres app password from 'postgresql-app' Secret in $NAMESPACE (CNPG Cluster bootstrap may not be complete)"

MYSQL_USER="$(read_secret "$NAMESPACE" mysql-root-secret MYSQL_ROOT_USERNAME 2>/dev/null || echo root)"
MYSQL_PASS="$(read_secret "$NAMESPACE" mysql-root-secret MYSQL_ROOT_PASSWORD 2>/dev/null)"
[ -n "${MYSQL_PASS:-}" ] || die "Could not resolve mysql root password from mysql-root-secret"

PG_HOST="postgresql-rw.$NAMESPACE.svc.cluster.local"
MYSQL_HOST="mysql.$NAMESPACE.svc.cluster.local"

# CNPG postInitApplicationSQL already creates these; re-running is a no-op.
# Kept here so that a fresh MySQL / a detached PG recovery gets the same set.
PG_DATABASES=(
    mlflow airflow superset datahub lakefs growthbook
    feast spicedb lakekeeper
    airbyte
)

PG_TRGM_DATABASES=(
    datahub
)

MYSQL_DATABASES=(
    platform katib mlpipeline cachedb metadb kserve
)

echo "--------------------------------------------------"
echo "Initialising databases (ns=$NAMESPACE, pg=$PG_HOST, mysql=$MYSQL_HOST)"
echo "--------------------------------------------------"

# Wait for both operator-managed endpoints to be reachable.
echo "Waiting for CNPG primary..."
"$KUBECTL_CMD" -n "$NAMESPACE" wait --for=condition=ready pod \
    -l cnpg.io/cluster=postgresql,role=primary --timeout=300s

echo "Waiting for MySQL..."
"$KUBECTL_CMD" -n "$NAMESPACE" wait --for=condition=ready pod \
    -l app=mysql --timeout=300s

# One-shot psql runner (networked, not kubectl exec — the CNPG pod only
# ships the server, not a Swiss-army client).
pg_client() {
    "$KUBECTL_CMD" -n "$NAMESPACE" run pg-client-$$-$RANDOM \
        --rm -i --restart=Never --image=postgres:18-alpine \
        --env="PGPASSWORD=$PG_PASS" \
        -- psql -h "$PG_HOST" -U "$PG_USER" -tAc "$1"
}

mysql_client() {
    "$KUBECTL_CMD" -n "$NAMESPACE" exec deploy/mysql -- \
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "$1"
}

# -----------------------------------------------------------------------------
# Align the `platform` app user's role attributes on EXISTING clusters.
# Fresh clusters get REPLICATION + CREATEROLE + CREATEDB directly from
# postInitApplicationSQL in cluster.yaml; pre-existing clusters provisioned
# before that block was added need a one-time ALTER ROLE.  We run it as the
# internal `postgres` role via local peer auth inside the CNPG primary pod:
# `enableSuperuserAccess: false` only disables password auth for postgres,
# peer auth over the unix socket is still available.  Idempotent — setting
# an already-set role attribute is a no-op at the PG level.
# -----------------------------------------------------------------------------
PRIMARY_POD="$("$KUBECTL_CMD" -n "$NAMESPACE" get pod \
    -l cnpg.io/cluster=postgresql,role=primary \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -n "${PRIMARY_POD:-}" ]; then
    echo "Aligning platform role attributes on ${PRIMARY_POD}..."
    "$KUBECTL_CMD" -n "$NAMESPACE" exec "$PRIMARY_POD" -c postgres -- \
        psql -U postgres -v ON_ERROR_STOP=1 -tAc \
        "ALTER ROLE platform WITH REPLICATION CREATEROLE CREATEDB;" \
        >/dev/null \
        && echo "  platform role aligned (REPLICATION + CREATEROLE + CREATEDB)"
else
    echo "WARN: CNPG primary pod not found; skipping platform role attribute alignment."
    echo "      Fresh clusters get these via postInitApplicationSQL; if this is an"
    echo "      upgraded cluster the subsequent ALTER USER loop will fail without CREATEROLE."
fi

echo "Creating PostgreSQL databases..."
for DB in "${PG_DATABASES[@]}"; do
    if pg_client "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1; then
        echo "  $DB - already exists"
    else
        pg_client "CREATE DATABASE $DB" && echo "  $DB - created"
    fi
done

echo "Creating PostgreSQL extensions..."
for DB in "${PG_TRGM_DATABASES[@]}"; do
    "$KUBECTL_CMD" -n "$NAMESPACE" run pg-ext-$$-$RANDOM \
        --rm -i --restart=Never --image=postgres:18-alpine \
        --env="PGPASSWORD=$PG_PASS" \
        -- psql -h "$PG_HOST" -U "$PG_USER" -d "$DB" \
        -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;' \
        -c 'CREATE EXTENSION IF NOT EXISTS btree_gin;' \
        && echo "  $DB extensions - OK"
done

# Align the passwords of bootstrap-created roles (`spicedb`, `feast`) with
# their OpenBao values.  CNPG postInitApplicationSQL creates these with a
# placeholder (`'set-by-eso'`) that never matches OpenBao; this step fixes
# that.  The role names match the OpenBao KV keys
# (secret/platform/postgres/<role>).
for ROLE in feast spicedb airbyte; do
    ROLE_SECRET="postgres-${ROLE}"
    ROLE_PASS="$(read_secret "$NAMESPACE" "$ROLE_SECRET" password 2>/dev/null || true)"
    if [ -z "${ROLE_PASS:-}" ]; then
        echo "  $ROLE - skipping (no $ROLE_SECRET Secret; ExternalSecret not synced yet)"
        continue
    fi
    # Use dollar-quoting so any special character in the password is safe.
    pg_client "ALTER USER $ROLE WITH PASSWORD \$ROLE_PW_TAG\$${ROLE_PASS}\$ROLE_PW_TAG\$" >/dev/null \
        && echo "  $ROLE - password aligned with OpenBao"
done

echo "Creating MySQL databases..."
for DB in "${MYSQL_DATABASES[@]}"; do
    mysql_client "CREATE DATABASE IF NOT EXISTS $DB;" \
        && echo "  $DB - OK"
done

echo "--------------------------------------------------"
echo "Database initialisation complete."
echo "--------------------------------------------------"
