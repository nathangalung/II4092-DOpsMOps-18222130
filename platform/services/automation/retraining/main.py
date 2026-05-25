"""
Auto-retraining triggered by drift detection events.

Checks Valkey for recent drift events. If severe drift detected,
creates a K8s Job to retrain the model with fresh data.

Flow:
  Drift Detector → Valkey pub/sub (drift-events; redis-py client over RESP)
  → Retraining Service (this) → K8s Job API → Trainer pod
  → MLflow (new model logged)
"""

import argparse
import logging
import os
import time

import redis
from kubernetes import client, config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Config:
    """Configuration from environment."""

    VALKEY_HOST = os.getenv("VALKEY_HOST", "valkey.storage.svc.cluster.local")
    VALKEY_PORT = int(os.getenv("VALKEY_PORT", "6379"))
    VALKEY_PASSWORD = os.getenv("VALKEY_PASSWORD", "")
    NAMESPACE = os.getenv(
        "NAMESPACE",
        os.getenv("TRAINER_NAMESPACE", "model-lifecycle"),
    )
    TRAINER_IMAGE = os.getenv("TRAINER_IMAGE", "trainer:latest")
    VALID_SYMBOLS = [
        s.strip()
        for s in os.getenv(
            "VALID_SYMBOLS", "SAMPLE-001"
        ).split(",")
        if s.strip()
    ]
    # Drift threshold: only retrain if PSI exceeds this
    DRIFT_PSI_THRESHOLD = float(os.getenv("DRIFT_PSI_THRESHOLD", "0.20"))
    # Cooldown: don't retrain same symbol within this many seconds
    RETRAIN_COOLDOWN_SECONDS = int(os.getenv("RETRAIN_COOLDOWN_SECONDS", "3600"))


def get_valkey_client() -> redis.Redis:
    """Create Valkey client (redis-py over RESP)."""
    return redis.Redis(
        host=Config.VALKEY_HOST,
        port=Config.VALKEY_PORT,
        password=Config.VALKEY_PASSWORD or None,
    )


def get_k8s_batch_api() -> client.BatchV1Api:
    """Get K8s batch API client."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.BatchV1Api()


def check_recent_drift_events(valkey_client: redis.Redis) -> list[dict]:
    """Check Valkey for recent drift events via pub/sub.

    Drift events are published as: {scale}:{feature}:{psi_value}
    Returns list of events that exceed the threshold.
    """
    # Use SUBSCRIBE with timeout to check for events
    pubsub = valkey_client.pubsub()
    pubsub.subscribe("drift-events")

    events = []
    deadline = time.time() + 10  # Wait max 10 seconds for events

    while time.time() < deadline:
        message = pubsub.get_message(timeout=1.0)
        if message and message["type"] == "message":
            raw = message["data"]
            data = raw.decode("utf-8") if isinstance(raw, bytes) else str(raw)
            try:
                parts = data.split(":")
                if len(parts) >= 3:
                    scale, feature, psi_str = parts[0], parts[1], parts[2]
                    psi = float(psi_str)
                    if psi >= Config.DRIFT_PSI_THRESHOLD:
                        events.append({
                            "scale": scale,
                            "feature": feature,
                            "psi": psi,
                        })
                        logger.info(f"Drift event: {scale}/{feature} PSI={psi:.4f}")
            except (ValueError, IndexError) as e:
                logger.warning(f"Failed to parse drift event: {data} ({e})")

    pubsub.unsubscribe()
    pubsub.close()
    return events


def create_retrain_job(batch_api: client.BatchV1Api, symbol: str, reason: str) -> str:
    """Create K8s Job to retrain model for a symbol."""
    job_name = f"retrain-{symbol.lower().replace('-', '')}-{int(time.time())}"

    # Build env vars from current ConfigMap values
    env_vars = [
        client.V1EnvVar(name="SYMBOL", value=symbol),
        client.V1EnvVar(name="VALID_SYMBOLS", value=symbol),
        client.V1EnvVar(name="MODE", value="retrain"),
        client.V1EnvVar(
            name="MLFLOW_EXPERIMENT",
            value=os.getenv(
                "MLFLOW_EXPERIMENT", "generic-pipeline"
            ),
        ),
        client.V1EnvVar(
            name="MODEL_TYPE",
            value=os.getenv("MODEL_TYPE", "lightgbm"),
        ),
        client.V1EnvVar(
            name="TASK_TYPE",
            value=os.getenv("TASK_TYPE", "regression"),
        ),
        client.V1EnvVar(
            name="TARGET_COLUMN",
            value=os.getenv("TARGET_COLUMN", "value"),
        ),
        client.V1EnvVar(
            name="FEATURES_TABLE",
            value=os.getenv(
                "FEATURES_TABLE", "data_features"
            ),
        ),
        client.V1EnvVar(
            name="EXCLUDE_COLUMNS",
            value=os.getenv("EXCLUDE_COLUMNS", ""),
        ),
        client.V1EnvVar(
            name="CLICKHOUSE_HOST",
            value=os.getenv(
                "CLICKHOUSE_HOST",
                "clickhouse-platform.storage.svc.cluster.local",
            ),
        ),
        client.V1EnvVar(
            name="CLICKHOUSE_PORT",
            value=os.getenv("CLICKHOUSE_PORT", "8123"),
        ),
        client.V1EnvVar(
            name="CLICKHOUSE_DB",
            value=os.getenv("CLICKHOUSE_DB", "features"),
        ),
        client.V1EnvVar(
            name="MLFLOW_TRACKING_URI",
            value=os.getenv(
                "MLFLOW_TRACKING_URI",
                "http://mlflow.model-lifecycle.svc.cluster.local:5000",
            ),
        ),
        client.V1EnvVar(
            name="MLFLOW_S3_ENDPOINT_URL",
            value=os.getenv(
                "MLFLOW_S3_ENDPOINT_URL",
                "http://minio.storage.svc.cluster.local:9000",
            ),
        ),
        # S3 credentials: read from platform-agnostic S3_* env vars,
        # but pass as AWS_* to the trainer (MLflow uses AWS SDK internally).
        # The retraining deployment mounts the `pipeline-secrets` ExternalSecret
        # (see services/overlays/secrets.yaml), so S3_* is guaranteed
        # to be set at runtime.  Fail fast if missing rather than falling back
        # to a plaintext default (ADR-008: no embedded credentials).
        client.V1EnvVar(
            name="AWS_ACCESS_KEY_ID",
            value=os.environ["S3_ACCESS_KEY_ID"],
        ),
        client.V1EnvVar(
            name="AWS_SECRET_ACCESS_KEY",
            value=os.environ["S3_SECRET_ACCESS_KEY"],
        ),
    ]

    # Use recent 7 days for retraining
    env_vars.append(client.V1EnvVar(name="START_DATE", value=os.getenv("START_DATE", "2026-03-01")))
    env_vars.append(client.V1EnvVar(name="END_DATE", value=os.getenv("END_DATE", "2026-03-31")))

    job = client.V1Job(
        metadata=client.V1ObjectMeta(
            name=job_name,
            namespace=Config.NAMESPACE,
            labels={
                "app": "retraining",
                "symbol": symbol.lower().replace("-", ""),
                "trigger": "drift",
            },
        ),
        spec=client.V1JobSpec(
            ttl_seconds_after_finished=3600,
            backoff_limit=1,
            template=client.V1PodTemplateSpec(
                metadata=client.V1ObjectMeta(
                    labels={"app": "retraining", "job-type": "retrain"},
                ),
                spec=client.V1PodSpec(
                    containers=[
                        client.V1Container(
                            name="trainer",
                            image=Config.TRAINER_IMAGE,
                            image_pull_policy="IfNotPresent",
                            command=["uv", "run", "main.py"],
                            args=["--train-all"],
                            env=env_vars,
                            resources=client.V1ResourceRequirements(
                                requests={"cpu": "500m", "memory": "1Gi"},
                                limits={"cpu": "2", "memory": "4Gi"},
                            ),
                        )
                    ],
                    restart_policy="Never",
                ),
            ),
        ),
    )

    batch_api.create_namespaced_job(namespace=Config.NAMESPACE, body=job)
    logger.info(f"Retrain job '{job_name}' created for {symbol} (reason: {reason})")
    return job_name


def check_existing_retrain_jobs(batch_api: client.BatchV1Api) -> set[str]:
    """Check for recently created retrain jobs to avoid duplicates."""
    recent_symbols = set()
    try:
        jobs = batch_api.list_namespaced_job(
            namespace=Config.NAMESPACE,
            label_selector="app=retraining,trigger=drift",
        )
        now = time.time()
        for job in jobs.items:
            if job.metadata.creation_timestamp:
                job_age = now - job.metadata.creation_timestamp.timestamp()
                if job_age < Config.RETRAIN_COOLDOWN_SECONDS:
                    # Extract symbol from labels
                    symbol = job.metadata.labels.get("symbol", "")
                    recent_symbols.add(symbol)
    except Exception as e:
        logger.warning(f"Failed to check existing jobs: {e}")
    return recent_symbols


def main() -> None:
    """Check drift events and trigger retraining if needed."""
    parser = argparse.ArgumentParser(description="Auto-retraining service")
    parser.add_argument("--check-and-retrain", action="store_true", help="Check drift and retrain")
    parser.parse_args()

    valkey_client = get_valkey_client()
    batch_api = get_k8s_batch_api()

    # Check for recent drift events
    logger.info("Checking for drift events...")
    events = check_recent_drift_events(valkey_client)

    if not events:
        logger.info("No drift events detected. No retraining needed.")
        return

    threshold = Config.DRIFT_PSI_THRESHOLD
    logger.info(
        f"Found {len(events)} drift events exceeding threshold ({threshold})"
    )

    # Check for recently created retrain jobs (cooldown)
    recent_symbols = check_existing_retrain_jobs(batch_api)

    # Trigger retraining for affected symbols
    for symbol in Config.VALID_SYMBOLS:
        symbol_key = symbol.lower().replace("-", "")
        if symbol_key in recent_symbols:
            logger.info(f"Skipping {symbol} — retrain job already running (cooldown)")
            continue

        # Check if any drift event affects this symbol's features
        relevant_events = [e for e in events if e["psi"] >= Config.DRIFT_PSI_THRESHOLD]
        if relevant_events:
            reason = ", ".join(f"{e['feature']}(PSI={e['psi']:.3f})" for e in relevant_events[:3])
            create_retrain_job(batch_api, symbol, reason)

    logger.info("Retraining check complete")


if __name__ == "__main__":
    main()
