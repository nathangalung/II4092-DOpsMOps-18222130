#!/bin/bash
set +e

KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"
NAMESPACE="${1:-core-storage}"

BUCKETS=(
    "mlflow"
    "airflow-logs"
    "dags"
    "pipeline-artifacts"
    "loki-data"
)

echo "--------------------------------------------------"
echo "Initializing MinIO Buckets in namespace: $NAMESPACE"
echo "--------------------------------------------------"

echo "⏳ Waiting for MinIO to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=minio -n "$NAMESPACE" --timeout=120s

echo "🚀 Creating buckets..."

for BUCKET in "${BUCKETS[@]}"; do
    # In standalone MinIO, creating a folder in /data creates a bucket
    SUCCESS=false
    for attempt in 1 2 3; do
        if $KUBECTL_CMD exec -n "$NAMESPACE" deploy/minio -- mkdir -p /data/$BUCKET 2>/dev/null; then
            echo "✅ Bucket '$BUCKET' created."
            SUCCESS=true
            break
        fi
        echo "   Retry $attempt/3 for '$BUCKET'..."
        sleep 5
    done
    if [ "$SUCCESS" = false ]; then
        echo "⚠️  Failed to create '$BUCKET' after 3 attempts (might already exist)."
    fi
done

echo "--------------------------------------------------"
echo "🎉 Bucket initialization complete."
echo "--------------------------------------------------"