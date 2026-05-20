#!/bin/bash
# ============================================================================
# Lakehouse Initialization (MinIO + Lakekeeper + LakeFS)
# ============================================================================
# Bucket creation uses MinIO root credentials resolved from the ESO-managed
# Secret `minio-credentials` in the `storage` namespace (ADR-008).  No
# plaintext passwords are embedded in this script.
# ============================================================================
set -euo pipefail

echo "=== Lakehouse Initialization ==="

# Resolve MinIO root credentials from the ESO-managed Secret.  Secret name
# aligned with components/storage/minio/deployment.yaml ExternalSecret target.
MINIO_USER="$(kubectl -n storage get secret minio-root \
    -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d)"
MINIO_PASS="$(kubectl -n storage get secret minio-root \
    -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)"

if [ -z "${MINIO_USER:-}" ] || [ -z "${MINIO_PASS:-}" ]; then
    echo "ERROR: could not resolve minio-root Secret. Is ESO synced?" >&2
    exit 1
fi

# ============================================================================
# MinIO: Create buckets using a temporary pod with mc
# ============================================================================
echo ""
echo "--- MinIO Buckets ---"

# Use `mc alias set` with separate args — prevents URL-encoding issues when
# `rand_base64` generates passwords containing `/`, `+`, or `=`.
for BUCKET in warehouse lakefs mlflow; do
    kubectl run "minio-init-$BUCKET" --rm -i --restart=Never \
        --image=minio/mc:latest -n storage \
        --env="MINIO_USER=$MINIO_USER" \
        --env="MINIO_PASS=$MINIO_PASS" \
        -- /bin/sh -c "mc alias set local http://minio.storage:9000 \"\$MINIO_USER\" \"\$MINIO_PASS\" >/dev/null && mc mb --ignore-existing local/$BUCKET" \
        && echo "  Bucket '$BUCKET' ready" \
        || echo "  Bucket '$BUCKET' (already exists or mc failed)"
done

# ============================================================================
# Lakekeeper: Verify catalog
# ============================================================================
echo ""
echo "--- Lakekeeper (Iceberg REST Catalog) ---"
kubectl run lakekeeper-check --rm -i --restart=Never \
    --image=curlimages/curl:8.20.0 -n storage \
    -- curl -sf http://lakekeeper.storage:8181/health 2>/dev/null && \
    echo "  Lakekeeper catalog ready" || echo "  WARNING: Lakekeeper not responding"

# ============================================================================
# LakeFS: Verify
# ============================================================================
echo ""
echo "--- LakeFS (Data Versioning) ---"
kubectl run lakefs-check --rm -i --restart=Never \
    --image=curlimages/curl:8.20.0 -n storage \
    -- curl -sf http://lakefs.storage:8000/api/v1/healthcheck 2>/dev/null && \
    echo "  LakeFS ready" || echo "  WARNING: LakeFS not responding"

echo ""
echo "=== Lakehouse Initialization Complete ==="
