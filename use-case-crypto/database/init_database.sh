#!/bin/bash
# ============================================================================
# Use Case — Database Initialization Script
# ============================================================================
# Initializes both ClickHouse (OLAP) and PostgreSQL (OLTP) databases.
# ClickHouse: Medallion architecture (bronze/silver/gold)
# PostgreSQL: Pipeline OLTP entities (runs, quality checks, predictions)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DB_DIR="${SCRIPT_DIR}/../../platform/services/base/database"

echo "=== Database Initialization ==="

# ============================================================================
# ClickHouse (OLAP — Medallion Layers)
# ============================================================================
echo ""
echo "--- ClickHouse (Medallion: bronze/silver/gold) ---"

if kubectl get pods -n storage 2>/dev/null | grep -q clickhouse; then
    kubectl exec -i -n storage clickhouse-0 -- clickhouse-client --multiquery < "${SCRIPT_DIR}/init_clickhouse.sql"
    echo "ClickHouse initialization completed!"
    kubectl exec -n storage clickhouse-0 -- clickhouse-client --query "SHOW DATABASES"
else
    echo "Error: ClickHouse pod not found"
    exit 1
fi

# ============================================================================
# PostgreSQL (OLTP — Pipeline Entities)
# ============================================================================
echo ""
echo "--- PostgreSQL (OLTP: pipeline schema) ---"

PG_POD=$(kubectl get pods -n storage -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$PG_POD" ]; then
    # Create pipeline database (idempotent)
    kubectl exec -n storage "$PG_POD" -- psql -U postgres -c "CREATE DATABASE pipeline" 2>/dev/null || true

    # Apply generic pipeline schema (from platform)
    if [ -f "${PLATFORM_DB_DIR}/init_postgres.sql" ]; then
        kubectl exec -i -n storage "$PG_POD" -- psql -U postgres -d pipeline < "${PLATFORM_DB_DIR}/init_postgres.sql"
        echo "Platform PostgreSQL schema applied!"
    fi

    # Apply use-case-specific extensions
    if [ -f "${SCRIPT_DIR}/init_postgres.sql" ]; then
        kubectl exec -i -n storage "$PG_POD" -- psql -U postgres -d pipeline < "${SCRIPT_DIR}/init_postgres.sql"
        echo "Use-case PostgreSQL extensions applied!"
    fi

    kubectl exec -n storage "$PG_POD" -- psql -U postgres -d pipeline -c "\dt pipeline.*"
else
    echo "Error: PostgreSQL pod not found"
    exit 1
fi

echo ""
echo "=== Database Initialization Complete ==="
