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
from airflow.providers.standard.operators.python import PythonOperator
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
# DAGS_FOLDER is the git-sync worktree ROOT (domain-agnostic recursive scan),
# not this dags/ dir, so Airflow 3.x's subprocess parser does not put this
# directory on sys.path — `from _observability import …` then raises
# ModuleNotFoundError at parse time. Register this file's own directory first
# so the shared sibling module resolves regardless of where DAGS_FOLDER points.
import sys  # noqa: E402
from pathlib import Path  # noqa: E402

sys.path.append(str(Path(__file__).resolve().parent))

from _observability import push_on_failure, push_on_success  # noqa: E402
from _config import (  # noqa: E402
    USE_CASE, NAMESPACE, REGISTRY, IMAGE_TAG, IMAGE_PREFIX, ENV_FROM_SOURCES,
)

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────
# Configuration — USE_CASE-derived names come from _config.py (single source).
# DAG-local additions: OpenLineage namespace/producer for this quality gate.
# ─────────────────────────────────────────────────────────────
OPENLINEAGE_NAMESPACE = Variable.get(
    "OPENLINEAGE_NAMESPACE", default_var=f"{USE_CASE}-pipeline"
)
OPENLINEAGE_PRODUCER = Variable.get(
    "OPENLINEAGE_PRODUCER_QUALITY_GATE",
    default_var=f"airflow-{USE_CASE}-quality-gate",
)

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
        # DataHub GMS PAT for the OpenLineage Bearer header. Supplied by the
        # platform airflow-secrets Secret (envFrom on the worker base container);
        # empty on a platform that pushes to an unauthenticated collector.
        "openlineage_api_key": os.getenv("OPENLINEAGE_API_KEY", ""),
        "feature_table": os.getenv(
            "TABLE_BRONZE_FEATURES", _FEATURE_TABLE_DEFAULT
        ).split(".")[-1],
    }


DEFAULT_ARGS = {
    "owner": "mlops-platform",
    "depends_on_past": False,
    # 2 retries (was 1) is the residual self-heal for exogenous single-node
    # IO storms that the platform Airflow concurrency cap can't throttle;
    # matches lakehouse/data_pipeline (both retries=2).
    "retries": 2,
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

    headers = {"Content-Type": "application/json"}
    # DataHub GMS runs METADATA_SERVICE_AUTH_ENABLED=true: the OpenLineage POST
    # is HTTP 401 without a PAT. OPENLINEAGE_API_KEY is the same token the
    # provider transport's auth.apiKey uses (platform airflow-secrets). Optional
    # so the DAG still parses/runs against an unauthenticated collector.
    if cfg["openlineage_api_key"]:
        headers["Authorization"] = f"Bearer {cfg['openlineage_api_key']}"

    try:
        req = Request(
            f"{cfg['openlineage_url']}/api/v1/lineage",
            data=json.dumps(event).encode(),
            headers=headers,
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
    # Auto-activate on first git-sync load (platform pauses new DAGs by
    # default via DAGS_ARE_PAUSED_AT_CREATION=True). Safe — catchup=False.
    is_paused_upon_creation=False,
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
        cmds=["uv", "run", "--no-sync", "main.py"],
        env_from=ENV_FROM_SOURCES,
        # The analyzer builds GE ExpectationSuites in code (gx.get_context() +
        # suite.add_expectation), parameterised entirely by env vars from the
        # pipeline ConfigMap/Secret — it never reads a great_expectations.yaml
        # file. The prior `great-expectations-config` ConfigMap volume +
        # GE_CONFIG_PATH were vestigial: the ConfigMap was never created, so the
        # mount failed every run. Removed — no file to mount.
        env_vars={"ANALYSIS_MODE": "expectations"},
        # Always-pull off the in-cluster registry: `:latest` + IfNotPresent pins a
        # stale node-cached digest forever, silently running old analyzer code
        # after a rebuild. In-cluster registry → cheap re-pull, air-gap-safe
        # (mirrors #301/#459/#291).
        image_pull_policy="Always",
        on_finish_action="delete_pod",
        get_logs=True,
        # 600 (not 300) to match dags/_config.py:k8s_pod() — a cold pull of a
        # freshly-rebuilt platform-analyzer:latest measured 4m33s on the single
        # spinning HDD; 300s marked the task up_for_retry even when the child
        # pod itself succeeded. The KPO child keeps image_pull_policy=Always
        # above (rebuilt analyzer code must not run stale); only the start
        # deadline widens to absorb the cold-pull window.
        startup_timeout_seconds=600,
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": "100m", "memory": "256Mi"},
            limits={"cpu": "500m", "memory": "1Gi"},
        ),
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
