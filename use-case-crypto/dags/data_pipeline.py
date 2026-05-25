"""
Airflow DAGs: Crypto Data & Feature Pipeline

Replaces bare K8s CronJobs with Airflow-orchestrated DAGs that provide:
  - Dependency management (batch-features → dbt → materialization)
  - Retry with exponential backoff
  - Backfill support for historical reprocessing
  - Observability via Airflow UI
  - OpenLineage integration with DataHub

CronJobs that STAY as CronJobs (independent, high-frequency):
  - supplementary-source (*/5 * * * *)
  - supplementary-feargreed, coingecko, defillama
  - vector-embedding (*/5 * * * *)

CronJobs REPLACED by these DAGs:
  - batch-features.yaml       → crypto_hourly_features
  - batch-sentiment.yaml       → crypto_hourly_features
  - materialization.yaml       → crypto_hourly_features
  - dbt-run.yaml              → crypto_lakehouse (in lakehouse.py)
  - evidently-report.yaml     → crypto_lakehouse (in lakehouse.py)
  - backfill.yaml             → crypto_daily_backfill
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import (
    KubernetesPodOperator,
)
# k8s.V1* models — KubernetesPodOperator rejects dict forms on the
# cncf.kubernetes provider shipped with Airflow 2.8+ (V1VolumeMount /
# V1ResourceRequirements API-call failure). Use typed models here.
from kubernetes.client import models as k8s

# Pushgateway DAG-outcome callbacks — emits one `crypto_job_*` series per
# DagRun so SLO panels render Airflow alongside CronJob + Tekton runs.
from _observability import push_on_failure, push_on_success

# ─────────────────────────────────────────────────────────────
# Configuration — read from Airflow Variables (declarative, not hardcoded).
#
# Single knob `USE_CASE` derives every domain-coupled name (namespace,
# image prefix, ConfigMap, Secret). Cloning this file to a new use-case
# means: rename the file + dag_id strings and set `USE_CASE=<name>` in
# Airflow Variables — the rest of the body stays identical.
#
# Setup:
#   airflow variables set USE_CASE                    crypto
#   airflow variables set USE_CASE_NAMESPACE          use-case-crypto
#   airflow variables set USE_CASE_REGISTRY           localhost:5000
#   airflow variables set USE_CASE_IMAGE_TAG          v1.0.0
#   # optional overrides (defaults derive from USE_CASE):
#   airflow variables set USE_CASE_PIPELINE_CONFIGMAP crypto-pipeline-config
#   airflow variables set USE_CASE_PIPELINE_SECRET    crypto-pipeline-secrets
#   airflow variables set USE_CASE_IMAGE_PREFIX       crypto
# ─────────────────────────────────────────────────────────────
from airflow.models import Variable

USE_CASE = Variable.get("USE_CASE", default_var="crypto")
NAMESPACE = Variable.get(
    "USE_CASE_NAMESPACE", default_var=f"use-case-{USE_CASE}"
)
REGISTRY = Variable.get("USE_CASE_REGISTRY", default_var="localhost:5000")
IMAGE_TAG = Variable.get("USE_CASE_IMAGE_TAG", default_var="latest")
IMAGE_PREFIX = Variable.get("USE_CASE_IMAGE_PREFIX", default_var=USE_CASE)
PIPELINE_CONFIGMAP = Variable.get(
    "USE_CASE_PIPELINE_CONFIGMAP", default_var=f"{USE_CASE}-pipeline-config"
)
PIPELINE_SECRET = Variable.get(
    "USE_CASE_PIPELINE_SECRET", default_var=f"{USE_CASE}-pipeline-secrets"
)

ENV_FROM_SOURCES = [
    k8s.V1EnvFromSource(
        config_map_ref=k8s.V1ConfigMapEnvSource(name=PIPELINE_CONFIGMAP),
    ),
    k8s.V1EnvFromSource(
        secret_ref=k8s.V1SecretEnvSource(name=PIPELINE_SECRET),
    ),
]

DEFAULT_ARGS = {
    "owner": "mlops-platform",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=1),
}


def _image(name: str) -> str:
    """Build full image reference from service name."""
    return f"{REGISTRY}/{IMAGE_PREFIX}-{name}:{IMAGE_TAG}"


def k8s_pod(
    task_id: str,
    image: str,
    cmds: list[str],
    args: list[str] | None = None,
    cpu_req: str = "100m",
    mem_req: str = "256Mi",
    cpu_lim: str = "500m",
    mem_lim: str = "1Gi",
    **kwargs,
) -> KubernetesPodOperator:
    """Factory for KubernetesPodOperator with standard config."""
    return KubernetesPodOperator(
        task_id=task_id,
        name=f"airflow-{task_id}",
        namespace=NAMESPACE,
        image=image,
        cmds=cmds,
        arguments=args or [],
        env_from=ENV_FROM_SOURCES,
        image_pull_policy="IfNotPresent",
        is_delete_operator_pod=True,
        get_logs=True,
        startup_timeout_seconds=300,
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": cpu_req, "memory": mem_req},
            limits={"cpu": cpu_lim, "memory": mem_lim},
        ),
        **kwargs,
    )


# ═════════════════════════════════════════════════════════════
# DAG 1: Hourly Feature Pipeline
# ═════════════════════════════════════════════════════════════
# Dependency chain: batch_features → feast_materialize → sentiment
#
# batch_features computes technical indicators from raw OHLCV
# feast_materialize pushes features to Redis online store
# sentiment aggregates sentiment scores into windowed features
# ═════════════════════════════════════════════════════════════
with DAG(
    dag_id=f"{USE_CASE}_hourly_features",
    default_args=DEFAULT_ARGS,
    description=(
        "Hourly: batch features → Feast materialize → sentiment"
    ),
    schedule="30 * * * *",
    start_date=datetime(2026, 4, 1),
    catchup=False,
    tags=["crypto", "features", "hourly"],
    max_active_runs=1,
    on_success_callback=push_on_success,
    on_failure_callback=push_on_failure,
) as hourly_dag:

    batch_features = k8s_pod(
        "batch_features",
        image=_image("batch-processing"),
        cmds=["uv", "run", "main.py"],
        args=["--mode", "features"],
        cpu_req="250m",
        mem_req="512Mi",
        cpu_lim="1",
        mem_lim="2Gi",
    )

    feast_materialize = k8s_pod(
        "feast_materialize",
        image=_image("materialization"),
        cmds=["uv", "run", "main.py"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    batch_sentiment = k8s_pod(
        "batch_sentiment",
        image=_image("batch-processing"),
        cmds=["uv", "run", "main.py"],
        args=["--mode", "sentiment"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    # Drift detection runs AFTER features are computed. PSI/KS scores are
    # written to ClickHouse `gold.drift_metrics`; the Argo CronWorkflow
    # `retrain-on-drift` (model-lifecycle) polls that table on its own
    # schedule and triggers KFP retraining when thresholds are exceeded —
    # the DAG fans out and exits without waiting on retrain.
    drift_check = k8s_pod(
        "drift_check",
        image=_image("drift-detector"),
        cmds=["uv", "run", "main.py"],
        args=["--scale", "hour", "--once"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    # Scoring: run batch inference via ml-bridge (proxies to KServe InferenceService)
    # The ml-bridge reads features from ClickHouse, calls KServe, writes predictions back
    scoring = k8s_pod(
        "scoring",
        image=_image("ml-bridge"),
        cmds=["uv", "run", "main.py"],
        args=["--mode", "batch-score"],
        cpu_req="100m",
        mem_req="256Mi",
        cpu_lim="500m",
        mem_lim="1Gi",
    )

    # Pipeline: features → materialize → [sentiment, drift, scoring]
    # Retrain-on-drift is decoupled (Argo CronWorkflow polls ClickHouse).
    batch_features >> feast_materialize
    feast_materialize >> batch_sentiment
    feast_materialize >> drift_check
    feast_materialize >> scoring


# crypto_transformation DAG removed — fully superseded by crypto_lakehouse
# (LakeFS-versioned dbt + Trino quality checks in lakehouse.py).


# ═════════════════════════════════════════════════════════════
# DAG 2: Daily Backfill
# ═════════════════════════════════════════════════════════════
# Runs daily at 4AM to backfill any missing data gaps.
# catchup=True enables historical backfill via Airflow CLI.
# ═════════════════════════════════════════════════════════════
with DAG(
    dag_id=f"{USE_CASE}_daily_backfill",
    default_args={
        **DEFAULT_ARGS,
        "execution_timeout": timedelta(hours=4),
    },
    description="Daily 4AM: incremental backfill of missing data",
    schedule="0 4 * * *",
    start_date=datetime(2026, 4, 1),
    catchup=True,
    tags=["crypto", "backfill", "daily"],
    max_active_runs=1,
    on_success_callback=push_on_success,
    on_failure_callback=push_on_failure,
) as backfill_dag:

    backfill = k8s_pod(
        "incremental_backfill",
        image=_image("rest-collector"),
        cmds=["/app/rest-collector"],
        args=["--mode", "backfill"],
        cpu_req="100m",
        mem_req="256Mi",
        cpu_lim="500m",
        mem_lim="1Gi",
    )
