"""
Airflow DAG: Data Quality Gate

Validates data quality using three layers:
  1. Great Expectations (via quality-analyzer service) — statistical validation
     against ClickHouse feature tables with expectations stored in MinIO
  2. SQL checks — freshness, ranges, duplicates, completeness
  3. OpenLineage emission — data quality metadata to DataHub

Architecture:
  - Great Expectations runs in a KubernetesPodOperator (quality-analyzer image)
  - SQL checks run inline via PythonOperator (lightweight, fast)
  - Results emitted to DataHub via OpenLineage API

Components used:
  - Great Expectations (data quality validation library in quality-analyzer)
  - ClickHouse (data source — features database)
  - MinIO (GE expectation/validation results storage)
  - DataHub/OpenLineage (lineage + quality metadata)
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.providers.cncf.kubernetes.operators.pod import (
    KubernetesPodOperator,
)
# KubernetesPodOperator typed-model contract: volumes / volume_mounts /
# container_resources / env_from must be k8s client model instances, not
# dicts. Airflow used to silently accept dicts on older providers and
# raises AttributeError on `.to_dict()` otherwise, which is the
# V1VolumeMount API-call failure recorded in AUDIT §2.1 stage-5.
from kubernetes.client import models as k8s

# Pushgateway DAG-outcome callbacks (shared module).
from _observability import push_on_failure, push_on_success

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────
# Configuration — from Airflow Variables with USE_CASE-derived defaults.
# See data_pipeline.py for the full Variable contract.
# ─────────────────────────────────────────────────────────────
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
OPENLINEAGE_NAMESPACE = Variable.get(
    "OPENLINEAGE_NAMESPACE", default_var=f"{USE_CASE}-pipeline"
)
OPENLINEAGE_PRODUCER = Variable.get(
    "OPENLINEAGE_PRODUCER_QUALITY_GATE",
    default_var=f"airflow-{USE_CASE}-quality-gate",
)

ENV_FROM_SOURCES = [
    k8s.V1EnvFromSource(
        config_map_ref=k8s.V1ConfigMapEnvSource(name=PIPELINE_CONFIGMAP),
    ),
    k8s.V1EnvFromSource(
        secret_ref=k8s.V1SecretEnvSource(name=PIPELINE_SECRET),
    ),
]

# Runtime config — resolved lazily inside task callables. Reading os.getenv
# at module level freezes the values into the scheduler's parsed-DAG cache;
# rolling the pipeline-config ConfigMap would not propagate until the
# DagFileProcessor evicts its cache (~30 s) or the scheduler restarts.
_CH_HOST_DEFAULT = "clickhouse-platform.storage.svc.cluster.local"
_CH_PORT_DEFAULT = 8123
_CH_DB_DEFAULT = "bronze"
_OPENLINEAGE_URL_DEFAULT = (
    "http://datahub-gms.data-governance.svc.cluster.local:8080/openapi/openlineage"
)
_FEATURE_TABLE_DEFAULT = "bronze.crypto_ohlcv_features"


def _runtime_config() -> dict[str, str | int]:
    """Resolve runtime env at task execution (not at DAG parse)."""
    return {
        "ch_host": os.getenv("CLICKHOUSE_HOST", _CH_HOST_DEFAULT),
        "ch_port": int(os.getenv("CLICKHOUSE_PORT", str(_CH_PORT_DEFAULT))),
        "ch_db": os.getenv("CLICKHOUSE_DB", _CH_DB_DEFAULT),
        "openlineage_url": os.getenv("OPENLINEAGE_URL", _OPENLINEAGE_URL_DEFAULT),
        "feature_table": os.getenv(
            "TABLE_BRONZE_FEATURES", _FEATURE_TABLE_DEFAULT
        ).split(".")[-1],
    }


DEFAULT_ARGS = {
    "owner": "mlops-platform",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=3),
    "execution_timeout": timedelta(minutes=30),
}


def run_sql_quality_checks(**context):
    """Run SQL-based quality checks against ClickHouse feature tables.

    Complements Great Expectations with fast SQL checks for:
    freshness, nulls, ranges, duplicates, row count.
    """
    import clickhouse_connect

    cfg = _runtime_config()
    ch = clickhouse_connect.get_client(
        host=cfg["ch_host"], port=cfg["ch_port"], database=cfg["ch_db"]
    )
    feature_table = cfg["feature_table"]
    checks = []

    def _scalar(result, default=0):
        """Safely extract scalar value from ClickHouse query result."""
        return result.result_rows[0][0] if result.result_rows else default

    def _row(result, ncols, defaults=None):
        """Safely extract a row tuple from ClickHouse query result."""
        if result.result_rows:
            return result.result_rows[0]
        return defaults or tuple(0 for _ in range(ncols))

    try:
        # Check 1: Data freshness
        result = ch.query(
            f"SELECT count() FROM {feature_table} "
            "WHERE timestamp >= now() - INTERVAL 2 HOUR"
        )
        recent = _scalar(result)
        checks.append({"name": "data_freshness", "passed": recent > 0, "value": recent})

        # Check 2: No nulls in critical columns
        result = ch.query(
            "SELECT countIf(symbol = '' OR symbol IS NULL), "
            "countIf(timestamp IS NULL), "
            "countIf(close IS NULL OR isNaN(close)) "
            f"FROM {feature_table} WHERE timestamp >= now() - INTERVAL 24 HOUR"
        )
        null_sym, null_ts, null_close = _row(result, 3)
        checks.append({"name": "no_null_symbols", "passed": null_sym == 0, "value": null_sym})
        checks.append({"name": "no_null_timestamps", "passed": null_ts == 0, "value": null_ts})
        checks.append({"name": "no_null_close", "passed": null_close == 0, "value": null_close})

        # Check 3: Positive prices
        result = ch.query(
            "SELECT countIf(close <= 0 OR open <= 0 OR high <= 0 OR low <= 0) "
            f"FROM {feature_table} WHERE timestamp >= now() - INTERVAL 24 HOUR"
        )
        neg = _scalar(result)
        checks.append({"name": "positive_prices", "passed": neg == 0, "value": neg})

        # Check 4: No duplicates
        result = ch.query(
            "SELECT count() - uniq(symbol, timestamp) "
            f"FROM {feature_table} WHERE timestamp >= now() - INTERVAL 24 HOUR"
        )
        dupes = _scalar(result)
        checks.append({"name": "no_duplicates", "passed": dupes == 0, "value": dupes})
    finally:
        ch.close()

    passed = all(c["passed"] for c in checks)
    for c in checks:
        s = "PASS" if c["passed"] else "FAIL"
        logger.info(f"  [{s}] {c['name']}: {c['value']}")

    context["ti"].xcom_push(key="quality_passed", value=passed)
    context["ti"].xcom_push(key="quality_report", value=json.dumps(checks))

    if not passed:
        raise ValueError(f"SQL quality checks FAILED: {sum(not c['passed'] for c in checks)} checks failed")


def emit_openlineage_event(**context):
    """Emit OpenLineage event to DataHub for data governance tracking."""
    from urllib.request import Request, urlopen

    cfg = _runtime_config()
    quality_report = json.loads(
        context["ti"].xcom_pull(task_ids="sql_quality_checks", key="quality_report") or "[]"
    )

    event = {
        "eventType": "COMPLETE",
        "eventTime": datetime.utcnow().isoformat() + "Z",
        "run": {
            "runId": context["run_id"],
            "facets": {
                "dataQuality": {
                    "_producer": OPENLINEAGE_PRODUCER,
                    "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DataQualityMetricsInputDatasetFacet.json",
                    "rowCount": {
                        "checks": len(quality_report),
                        "passed": sum(1 for c in quality_report if c["passed"]),
                    },
                },
            },
        },
        "job": {"namespace": OPENLINEAGE_NAMESPACE, "name": "data-quality-gate"},
        "inputs": [
            {
                "namespace": f"clickhouse://{cfg['ch_host']}",
                "name": f"{cfg['ch_db']}.{cfg['feature_table']}",
            }
        ],
        "outputs": [],
    }

    try:
        req = Request(
            f"{cfg['openlineage_url']}/api/v1/lineage",
            data=json.dumps(event).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urlopen(req, timeout=10)
        logger.info("OpenLineage event emitted to DataHub")
    except Exception as e:
        logger.warning(f"Failed to emit OpenLineage event: {e}")


with DAG(
    dag_id=f"{USE_CASE}_data_quality_gate",
    default_args=DEFAULT_ARGS,
    description="Hourly: Great Expectations validation + SQL checks + OpenLineage",
    schedule="45 * * * *",
    start_date=datetime(2026, 4, 1),
    catchup=False,
    tags=["crypto", "quality", "great-expectations", "openlineage"],
    max_active_runs=1,
    on_success_callback=push_on_success,
    on_failure_callback=push_on_failure,
) as dag:

    # Task 1: Great Expectations validation via quality-analyzer container
    # Runs GE expectations against ClickHouse, stores results in MinIO,
    # and reports via Prometheus metrics
    ge_validation = KubernetesPodOperator(
        task_id="great_expectations_validation",
        name="airflow-ge-validation",
        namespace=NAMESPACE,
        image=f"{REGISTRY}/{IMAGE_PREFIX}-analyzer:{IMAGE_TAG}",
        cmds=["uv", "run", "main.py"],
        env_from=ENV_FROM_SOURCES,
        env_vars={
            "ANALYSIS_MODE": "expectations",
            "GE_CONFIG_PATH": "/app/ge/great_expectations.yaml",
        },
        image_pull_policy="IfNotPresent",
        is_delete_operator_pod=True,
        get_logs=True,
        startup_timeout_seconds=300,
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": "100m", "memory": "256Mi"},
            limits={"cpu": "500m", "memory": "1Gi"},
        ),
        volumes=[
            k8s.V1Volume(
                name="ge-config",
                config_map=k8s.V1ConfigMapVolumeSource(
                    name="great-expectations-config",
                ),
            ),
        ],
        volume_mounts=[
            k8s.V1VolumeMount(name="ge-config", mount_path="/app/ge"),
        ],
    )

    # Task 2: SQL-based quality checks (fast, lightweight)
    sql_checks = PythonOperator(
        task_id="sql_quality_checks",
        python_callable=run_sql_quality_checks,
    )

    # Task 3: Emit OpenLineage event to DataHub
    emit_lineage = PythonOperator(
        task_id="emit_openlineage",
        python_callable=emit_openlineage_event,
        trigger_rule="all_done",
    )

    # Run GE and SQL checks in parallel, then emit lineage
    [ge_validation, sql_checks] >> emit_lineage
