"""
Airflow DAGs: Crypto Data & Feature Pipeline

Replaces bare K8s CronJobs with Airflow-orchestrated DAGs that provide:
  - Dependency management (batch-features then dbt then materialization)
  - Retry with exponential backoff
  - Backfill support for historical reprocessing
  - Observability via Airflow UI
  - OpenLineage integration with DataHub

CronJobs that STAY as CronJobs (independent, high-frequency):
  - supplementary-source (*/5 * * * *)
  - supplementary-feargreed, coingecko, defillama
  - vector-embedding (*/5 * * * *)

CronJobs REPLACED by these DAGs:
  - batch-features.yaml       becomes crypto_hourly_features
  - batch-sentiment.yaml       becomes crypto_hourly_features
  - materialization.yaml       becomes crypto_hourly_features
  - dbt-run.yaml              becomes crypto_lakehouse (in lakehouse.py)
  - evidently-report.yaml     becomes crypto_lakehouse (in lakehouse.py)
  - backfill.yaml             becomes crypto_daily_backfill
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
# k8s.V1EnvVar is used directly in this file (batch_features env_vars override).
# KubernetesPodOperator and the pod factory live in _config.py.
from kubernetes.client import models as k8s

# Pushgateway DAG-outcome callbacks - emits one `crypto_job_*` series per
# DagRun so SLO panels render Airflow alongside CronJob + Tekton runs.
# DAGS_FOLDER is the git-sync worktree ROOT (domain-agnostic recursive scan),
# not this dags/ dir, so Airflow 3.x's subprocess parser does not put this
# directory on sys.path - `from _observability import …` then raises
# ModuleNotFoundError at parse time. Register this file's own directory first
# so the shared sibling module resolves regardless of where DAGS_FOLDER points.
import sys  # noqa: E402
from pathlib import Path  # noqa: E402

sys.path.append(str(Path(__file__).resolve().parent))

from _observability import push_on_failure, push_on_success  # noqa: E402
from _config import USE_CASE, FEAST_REPO_CONFIGMAP, _image, k8s_pod  # noqa: E402

DEFAULT_ARGS = {
    "owner": "mlops-platform",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=1),
}


# DAG 1: Hourly Feature Pipeline
# Dependency chain: batch_features then feast_materialize then sentiment
#
# batch_features computes technical indicators from raw OHLCV
# feast_materialize pushes features to the Valkey online store
# sentiment aggregates sentiment scores into windowed features
with DAG(
    dag_id=f"{USE_CASE}_hourly_features",
    default_args=DEFAULT_ARGS,
    description=(
        "Hourly: batch features → Feast materialize → sentiment"
    ),
    schedule="30 * * * *",
    start_date=datetime(2026, 4, 1),
    catchup=False,
    # Auto-activate on first git-sync load (platform default pauses new DAGs
    # via DAGS_ARE_PAUSED_AT_CREATION=True). Safe - catchup=False. The
    # daily_backfill DAG below keeps the default (paused) because catchup=True.
    is_paused_upon_creation=False,
    tags=["crypto", "features", "hourly"],
    max_active_runs=1,
    on_success_callback=push_on_success,
    on_failure_callback=push_on_failure,
) as hourly_dag:

    batch_features = k8s_pod(
        "batch_features",
        image=_image("batch-processing"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        args=["--mode", "features"],
        # Decouple the batch WRITE target from the trainer READ target. The
        # shared pipeline-config sets FEATURES_TABLE=gold.fct_training_data
        # (the dbt-owned mart the trainer reads). The batch job must NOT write
        # there - gold is dbt-materialised, and the computed superset would hit
        # NO_SUCH_COLUMN. It writes the wide bronze feature table instead, which
        # (a) holds all technical-indicator columns and (b) is exactly what the
        # Feast online feature views read - so this also populates online
        # serving (fixes the train/serve "Feast returns 0" seam). An explicit
        # env var overrides the envFrom ConfigMap value for this key only.
        # (Proper long-term: give the trainer a distinct TRAINING_TABLE env so
        # the two concerns never share FEATURES_TABLE.)
        env_vars=[
            k8s.V1EnvVar(
                name="FEATURES_TABLE", value="bronze.crypto_ohlcv_features"
            )
        ],
        cpu_req="250m",
        mem_req="512Mi",
        cpu_lim="1",
        mem_lim="2Gi",
    )

    # feast_materialize renders feature_store.yaml from the feast-feature-repo
    # ConfigMap template at pod start (FEAST_TEMPLATE_DIR to FEAST_REPO_PATH),
    # runs `feast apply`, then materializes bronze (ClickHouse) to Valkey online.
    # The template is mounted read-only; rendering targets a writable emptyDir.
    # CLICKHOUSE_USER/PASSWORD + VALKEY_PASSWORD (template ${VAR}s) and the S3
    # registry creds/endpoint arrive via the pipeline-config + pipeline-secrets
    # envFrom (ENV_FROM_SOURCES) - nothing hardcoded here.
    feast_materialize = k8s_pod(
        "feast_materialize",
        image=_image("materialization"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        cpu_req="100m",
        mem_req="256Mi",
        env_vars=[
            k8s.V1EnvVar(name="FEAST_TEMPLATE_DIR", value="/opt/feast-template"),
            k8s.V1EnvVar(name="FEAST_REPO_PATH", value="/opt/feast-repo"),
        ],
        volumes=[
            k8s.V1Volume(
                name="feast-template",
                config_map=k8s.V1ConfigMapVolumeSource(name=FEAST_REPO_CONFIGMAP),
            ),
            k8s.V1Volume(name="feast-repo", empty_dir=k8s.V1EmptyDirVolumeSource()),
        ],
        volume_mounts=[
            k8s.V1VolumeMount(
                name="feast-template", mount_path="/opt/feast-template", read_only=True
            ),
            k8s.V1VolumeMount(name="feast-repo", mount_path="/opt/feast-repo"),
        ],
    )

    batch_sentiment = k8s_pod(
        "batch_sentiment",
        image=_image("batch-processing"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        args=["--mode", "sentiment"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    # Drift detection runs AFTER features are computed. PSI/KS scores are
    # written to ClickHouse `gold.drift_metrics`; the Argo CronWorkflow
    # `retrain-on-drift` (model-lifecycle) polls that table on its own
    # schedule and triggers KFP retraining when thresholds are exceeded -
    # the DAG fans out and exits without waiting on retrain.
    drift_check = k8s_pod(
        "drift_check",
        image=_image("drift-detector"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        args=["--scale", "hourly", "--once"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    # Scoring: run batch inference via ml-bridge (proxies to KServe InferenceService)
    # The ml-bridge reads features from ClickHouse, calls KServe, writes predictions back
    scoring = k8s_pod(
        "scoring",
        image=_image("ml-bridge"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        args=["--mode", "batch-score"],
        cpu_req="100m",
        mem_req="256Mi",
        cpu_lim="500m",
        mem_lim="1Gi",
    )

    # Pipeline: features then materialize then [sentiment, drift, scoring]
    # Retrain-on-drift is decoupled (Argo CronWorkflow polls ClickHouse).
    batch_features >> feast_materialize
    feast_materialize >> batch_sentiment
    feast_materialize >> drift_check
    feast_materialize >> scoring


# crypto_transformation DAG removed - fully superseded by crypto_lakehouse
# (LakeFS-versioned dbt + Trino quality checks in lakehouse.py).


# DAG 2: Daily Backfill
# Runs daily at 4AM to backfill any missing data gaps.
# catchup=True enables historical backfill via Airflow CLI.
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
