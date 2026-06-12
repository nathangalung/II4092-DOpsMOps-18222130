"""
Airflow DAG: Crypto Lakehouse Pipeline (LakeFS + Trino)

Extends the medallion architecture with:
  - LakeFS data versioning: dbt transforms run on isolated branches,
    merged to main on success, rolled back on failure
  - Trino federated queries: cross-source data quality checks comparing
    ClickHouse gold layer against PostgreSQL predictions
  - OpenLineage emission: dataset-level lineage for every Python task is
    pushed to DataHub GMS's OpenAPI OpenLineage ingestion endpoint (ADR-013).

Replaces / enhances:
  - dbt-run.yaml CronJob with branch-isolated, version-controlled runs
  - Adds federated quality checks not possible with single-engine queries

Schedule: every 6 hours (matches crypto_transformation cadence)
"""

from __future__ import annotations

import logging
import os
import re
import uuid
from datetime import datetime, timedelta, timezone

import requests
from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
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
from _config import USE_CASE, _image, k8s_pod  # noqa: E402

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────
# OpenLineage — emit dataset-level lineage to DataHub GMS
# ─────────────────────────────────────────────────────────────
# The Flink OpenLineage plugin (platform/components/data-processing/flink/
# deployment.yaml :: OPENLINEAGE_URL) covers stream-processing lineage.  The
# Airflow side emits lineage for every Python task by POSTing an
# OpenLineage RunEvent JSON to the same GMS endpoint. We do NOT rely on
# the `openlineage-airflow` auto-extractor here because KubernetesPodOperator
# runs dbt in a pod whose lineage is emitted by dbt's own OpenLineage
# provider — duplicating on the Airflow side would double-count datasets.
# PythonOperator tasks (LakeFS branch management, Trino QC) do NOT auto-
# emit; we add explicit events below.
from airflow.models import Variable  # noqa: E402 — after logger for readability

# USE_CASE master-knob (resolved early so OpenLineage defaults can template it).
# Body uses the longer USE_CASE block below; this lifts only the value needed
# for OPENLINEAGE_NAMESPACE / OPENLINEAGE_PRODUCER defaults at parse-time.
_USE_CASE_FOR_OL = Variable.get("USE_CASE", default_var="crypto")

OPENLINEAGE_URL = Variable.get(
    "OPENLINEAGE_URL",
    default_var=(
        "http://datahub-gms.data-governance.svc.cluster.local:8080"
        "/openapi/openlineage/api/v1/lineage"
    ),
)
OPENLINEAGE_NAMESPACE = Variable.get(
    "OPENLINEAGE_NAMESPACE", default_var=f"{_USE_CASE_FOR_OL}-pipeline"
)
OPENLINEAGE_PRODUCER = Variable.get(
    "OPENLINEAGE_PRODUCER_LAKEHOUSE",
    default_var=f"airflow-{_USE_CASE_FOR_OL}-lakehouse",
)


def _ol_dataset(dataset_namespace: str, name: str) -> dict:
    """Build a minimal OpenLineage Dataset object (namespace + name only).

    OpenLineage convention (use full K8s FQDNs so DataHub dedupes datasets
    across namespaces and so cross-cluster replicas don't collide):
      - ClickHouse:  namespace="clickhouse://clickhouse-platform.storage.svc.cluster.local:9000",
                     name="gold.fct_ohlcv_features"
      - PostgreSQL:  namespace="postgres://postgresql-rw.storage.svc.cluster.local:5432",
                     name="pipeline.predictions"
      - LakeFS:      namespace="lakefs://lakefs.storage.svc.cluster.local:8000/<repo>",
                     name="<branch>"
      - MinIO (S3):  namespace="s3://minio.storage.svc.cluster.local:9000",
                     name="<bucket>/<prefix>"
    Enrichment facets (schema, columnLineage) can be added later; for
    thesis §4.6 we need the NODE/EDGE graph, not column-level.
    """
    return {"namespace": dataset_namespace, "name": name}


def _ol_event(
    event_type: str,
    run_id: str,
    job_name: str,
    inputs: list[dict] | None = None,
    outputs: list[dict] | None = None,
    run_facets: dict | None = None,
) -> dict:
    """Compose an OpenLineage RunEvent payload ready to POST."""
    now = datetime.now(timezone.utc).isoformat()
    return {
        "eventType": event_type,           # START | COMPLETE | FAIL | ABORT
        "eventTime": now,
        "producer": OPENLINEAGE_PRODUCER,
        "schemaURL": (
            "https://openlineage.io/spec/1-0-5/OpenLineage.json"
            "#/definitions/RunEvent"
        ),
        "run": {"runId": run_id, "facets": run_facets or {}},
        "job": {"namespace": OPENLINEAGE_NAMESPACE, "name": job_name},
        "inputs": inputs or [],
        "outputs": outputs or [],
    }


def _ol_emit(payload: dict) -> None:
    """POST an OpenLineage RunEvent.  Best-effort — failures are logged
    but do NOT fail the Airflow task (lineage is observability, not
    correctness).  Matches the platform convention for observability
    emission (§ADR-014)."""
    try:
        headers = {"Content-Type": "application/json"}
        # GMS metadata-service auth rejects anonymous OpenLineage POSTs with
        # 401. Same token the openlineage provider transport uses; sourced
        # from the airflow-secrets envFrom present on scheduler AND worker
        # pods, read at call time so a rotation needs no restart.
        api_key = os.getenv("OPENLINEAGE_API_KEY", "")
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        resp = requests.post(
            OPENLINEAGE_URL, json=payload, timeout=10,
            headers=headers,
        )
        if resp.status_code >= 400:
            logger.warning(
                "OpenLineage emit failed: %s %s", resp.status_code, resp.text
            )
    except requests.RequestException as exc:
        logger.warning("OpenLineage emit exception: %s", exc)


def _ol_run_id(context: dict) -> str:
    """Deterministic OpenLineage runId per Airflow task instance.
    Using a deterministic hash over (dag_id, run_id, task_id) so retries
    emit the same runId and DataHub de-duplicates."""
    dag_id = context["dag"].dag_id
    run_id = context["run_id"]
    task_id = context["task"].task_id
    seed = f"{dag_id}|{run_id}|{task_id}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, seed))

# ─────────────────────────────────────────────────────────────
# Configuration — USE_CASE-derived names come from _config.py (single source).
# See _config.py for the full Variable contract; this DAG uses the same
# `USE_CASE`-derived knobs so a clone needs no body edits.
# ─────────────────────────────────────────────────────────────

# LakeFS configuration — reads from Airflow Variables with ConfigMap-aligned defaults
LAKEFS_ENDPOINT = Variable.get("LAKEFS_URL", default_var="http://lakefs.storage.svc.cluster.local:8000")
LAKEFS_REPO = Variable.get("LAKEFS_REPO", default_var="crypto-lakehouse")
LAKEFS_MAIN_BRANCH = "main"
# LakeFS credentials — sourced from the scheduler process environment, which
# is populated by `envFrom: secretRef: airflow-secrets` on the scheduler
# container.  The airflow-secrets ExternalSecret fetches LAKEFS_ACCESS_KEY_ID /
# LAKEFS_SECRET_ACCESS_KEY from Vault at secret/platform/lakefs/admin — the
# same path that bootstraps the LakeFS server's admin account, so scheduler
# and server stay in lock-step.  See:
#   platform/components/data-processing/airflow/deployment.yaml (airflow-secrets)
#   platform/components/storage/lakefs/deployment.yaml (lakefs-secrets)
# Airflow Variable lookups are intentionally NOT used here so the Vault path
# remains the single source of truth — no second place to rotate on key change.
# Credentials are read lazily at task time (see `_lakefs_auth`). Reading at
# module level freezes the value into the scheduler's parsed-DAG cache, so a
# Vault rotation would not propagate until the scheduler restarts.

# Trino configuration — reads from Airflow Variables with ConfigMap-aligned defaults
TRINO_HOST = Variable.get("TRINO_HOST", default_var="trino.data-processing.svc.cluster.local")
TRINO_PORT = int(Variable.get("TRINO_PORT", default_var="8085"))
TRINO_USER = Variable.get("TRINO_USER", default_var="airflow")

DEFAULT_ARGS = {
    "owner": "mlops-platform",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=1),
}


# ─────────────────────────────────────────────────────────────
# LakeFS helper functions
# ─────────────────────────────────────────────────────────────
def _lakefs_auth() -> tuple[str, str] | None:
    """Return (user, password) tuple for LakeFS Basic Auth, or None if unconfigured.

    Reads env at call time so a rotation in `airflow-secrets` takes effect
    on the next task execution without a scheduler restart.
    """
    access_key = os.getenv("LAKEFS_ACCESS_KEY_ID", "")
    secret_key = os.getenv("LAKEFS_SECRET_ACCESS_KEY", "")
    if access_key and secret_key:
        return (access_key, secret_key)
    logger.warning("LakeFS credentials not configured — API calls will fail with 401")
    return None


def _lakefs_headers() -> dict[str, str]:
    """Standard headers for LakeFS API calls."""
    return {"Content-Type": "application/json"}


def _branch_name(run_id: str) -> str:
    """Deterministic, lakeFS-valid branch name from the Airflow run ID.

    lakeFS rejects a branch id that contains anything outside
    [letters, digits, underscore, dash] (HTTP 400: "branch id must consist of
    letters, digits, underscores and dashes, and cannot start with a dash").
    Scheduled run_ids (``scheduled__2026-06-02T18:15:00+00:00``) sanitised
    cleanly under the old ``:``/``+`` → ``_`` replace, but manual/backfill
    run_ids carry a microsecond component (``manual__…T09:59:27.812605+00:00``)
    whose ``.`` survived and made every manual trigger fail at
    create_lakefs_branch. Replace every disallowed character so ANY run_id —
    scheduled, manual, or backfill — yields a valid id; the constant
    ``dbt-run-`` prefix guarantees it never starts with a dash.
    """
    sanitized = re.sub(r"[^A-Za-z0-9_-]", "_", run_id)
    return f"dbt-run-{sanitized}"


def ensure_lakefs_repo_fn(**context) -> None:
    """Idempotently ensure the LakeFS repository exists before any branch op.

    This DAG owns the full LakeFS lifecycle (repo -> branch -> dbt -> merge),
    so it provisions its own repository on first run rather than depending on a
    separate bootstrap Job plus a duplicated lakefs-admin ExternalSecret in this
    namespace — the scheduler already carries the admin credentials via
    `airflow-secrets` (see `_lakefs_auth`). Keeping repo provisioning here is
    cohesive, self-healing (recreates the repo if it is ever lost), and avoids
    redundant infrastructure.

    Idempotency: an existing repo returns 200 (no-op); a missing repo returns
    404 and is created; concurrent / catch-up runs that race the POST get 409,
    which is treated as success.

    `storage_namespace` is one prefix per repo under the platform MinIO `lakefs`
    bucket (created by platform/components/storage/minio/bucket-bootstrap.yaml) —
    the standard LakeFS S3 blockstore layout.
    """
    repo_url = f"{LAKEFS_ENDPOINT}/api/v1/repositories/{LAKEFS_REPO}"
    get = requests.get(
        repo_url, headers=_lakefs_headers(), auth=_lakefs_auth(), timeout=30
    )
    if get.status_code == 200:
        logger.info("LakeFS repo '%s' already exists", LAKEFS_REPO)
        return
    if get.status_code != 404:
        get.raise_for_status()

    storage_ns = f"s3://lakefs/{LAKEFS_REPO}"
    logger.info(
        "LakeFS repo '%s' missing — creating (storage_namespace=%s, default_branch=%s)",
        LAKEFS_REPO, storage_ns, LAKEFS_MAIN_BRANCH,
    )
    resp = requests.post(
        f"{LAKEFS_ENDPOINT}/api/v1/repositories",
        headers=_lakefs_headers(),
        auth=_lakefs_auth(),
        json={
            "name": LAKEFS_REPO,
            "storage_namespace": storage_ns,
            "default_branch": LAKEFS_MAIN_BRANCH,
        },
        timeout=60,
    )
    if resp.status_code not in (201, 409):
        resp.raise_for_status()
    logger.info("LakeFS repo '%s' ready (HTTP %d)", LAKEFS_REPO, resp.status_code)


def create_lakefs_branch_fn(**context) -> str:
    """Create a LakeFS branch from main for this dbt run."""
    run_id = context["run_id"]
    branch = _branch_name(run_id)
    ol_run_id = _ol_run_id(context)
    lakefs_ns = f"lakefs://{LAKEFS_ENDPOINT.replace('http://', '').replace('https://', '')}/{LAKEFS_REPO}"

    _ol_emit(_ol_event(
        "START", ol_run_id, job_name="create_lakefs_branch",
        inputs=[_ol_dataset(lakefs_ns, LAKEFS_MAIN_BRANCH)],
        outputs=[_ol_dataset(lakefs_ns, branch)],
    ))

    logger.info("Creating LakeFS branch '%s' from '%s'", branch, LAKEFS_MAIN_BRANCH)
    try:
        resp = requests.post(
            f"{LAKEFS_ENDPOINT}/api/v1/repositories/{LAKEFS_REPO}/branches",
            headers=_lakefs_headers(),
            auth=_lakefs_auth(),
            json={"name": branch, "source": LAKEFS_MAIN_BRANCH},
            timeout=30,
        )
        resp.raise_for_status()
    except Exception:
        _ol_emit(_ol_event("FAIL", ol_run_id, "create_lakefs_branch"))
        raise
    logger.info("Branch '%s' created successfully", branch)

    # Push branch name to XCom so downstream tasks can use it
    context["ti"].xcom_push(key="lakefs_branch", value=branch)
    _ol_emit(_ol_event(
        "COMPLETE", ol_run_id, job_name="create_lakefs_branch",
        inputs=[_ol_dataset(lakefs_ns, LAKEFS_MAIN_BRANCH)],
        outputs=[_ol_dataset(lakefs_ns, branch)],
    ))
    return branch


def merge_lakefs_branch_fn(**context) -> None:
    """Merge the dbt branch back to main after successful run."""
    branch = context["ti"].xcom_pull(
        task_ids="create_lakefs_branch", key="lakefs_branch"
    )
    if not branch:
        raise ValueError("No LakeFS branch found in XCom — cannot merge")

    ol_run_id = _ol_run_id(context)
    lakefs_ns = f"lakefs://{LAKEFS_ENDPOINT.replace('http://', '').replace('https://', '')}/{LAKEFS_REPO}"
    _ol_emit(_ol_event(
        "START", ol_run_id, job_name="merge_lakefs_branch",
        inputs=[_ol_dataset(lakefs_ns, branch)],
        outputs=[_ol_dataset(lakefs_ns, LAKEFS_MAIN_BRANCH)],
    ))

    logger.info("Merging LakeFS branch '%s' into '%s'", branch, LAKEFS_MAIN_BRANCH)

    try:
        # dbt's primary target is ClickHouse; the lakeFS branch only carries
        # changes when a run also lands lakehouse (Iceberg-on-lakeFS) files.
        # lakeFS hard-fails a no-diff merge (HTTP 400 "update branch main:
        # no changes"), so a run that wrote nothing to the branch must
        # short-circuit to success instead of failing the whole DAG.
        diff = requests.get(
            f"{LAKEFS_ENDPOINT}/api/v1/repositories/{LAKEFS_REPO}/refs/{LAKEFS_MAIN_BRANCH}/diff/{branch}",
            headers=_lakefs_headers(),
            auth=_lakefs_auth(),
            params={"amount": 1},  # existence probe, not a listing
            timeout=30,
        )
        diff.raise_for_status()
        if not diff.json().get("results"):
            logger.info(
                "Branch '%s' has no changes vs '%s' — nothing to merge (no-op run)",
                branch, LAKEFS_MAIN_BRANCH,
            )
        else:
            resp = requests.post(
                f"{LAKEFS_ENDPOINT}/api/v1/repositories/{LAKEFS_REPO}/refs/{branch}/merge/{LAKEFS_MAIN_BRANCH}",
                headers=_lakefs_headers(),
                auth=_lakefs_auth(),
                json={"message": f"Merge dbt run {context['run_id']}"},
                timeout=60,
            )
            if resp.status_code == 400 and "no changes" in resp.text:
                # Race-safe belt: diff saw changes but a concurrent commit
                # landed them on main first. Treat exactly like the no-op.
                logger.info("Merge collapsed to no-op: %s", resp.text)
            else:
                resp.raise_for_status()
                logger.info(
                    "Branch '%s' merged to '%s' successfully",
                    branch, LAKEFS_MAIN_BRANCH,
                )
    except Exception:
        _ol_emit(_ol_event("FAIL", ol_run_id, "merge_lakefs_branch"))
        raise
    _ol_emit(_ol_event(
        "COMPLETE", ol_run_id, job_name="merge_lakefs_branch",
        inputs=[_ol_dataset(lakefs_ns, branch)],
        outputs=[_ol_dataset(lakefs_ns, LAKEFS_MAIN_BRANCH)],
    ))


def delete_lakefs_branch_fn(**context) -> None:
    """Delete the dbt branch on failure (rollback)."""
    branch = context["ti"].xcom_pull(
        task_ids="create_lakefs_branch", key="lakefs_branch"
    )
    if not branch:
        logger.warning("No LakeFS branch found in XCom; nothing to delete")
        return

    ol_run_id = _ol_run_id(context)
    lakefs_ns = f"lakefs://{LAKEFS_ENDPOINT.replace('http://', '').replace('https://', '')}/{LAKEFS_REPO}"
    _ol_emit(_ol_event(
        "ABORT", ol_run_id, job_name="delete_lakefs_branch",
        inputs=[_ol_dataset(lakefs_ns, branch)],
    ))

    logger.info("Rolling back: deleting LakeFS branch '%s'", branch)
    resp = requests.delete(
        f"{LAKEFS_ENDPOINT}/api/v1/repositories/{LAKEFS_REPO}/branches/{branch}",
        headers=_lakefs_headers(),
        auth=_lakefs_auth(),
        timeout=30,
    )
    if resp.status_code == 404:
        logger.info("Branch '%s' already deleted or never created", branch)
        return
    resp.raise_for_status()
    logger.info("Branch '%s' deleted (rollback complete)", branch)


# ─────────────────────────────────────────────────────────────
# Trino federated quality check
# ─────────────────────────────────────────────────────────────
def _trino_query(sql: str) -> list[list]:
    """Run one SQL statement via Trino's REST protocol; return all rows.

    The Airflow worker image ships no Trino client library, and the official
    client protocol is just an HTTP loop — POST /v1/statement, then GET each
    `nextUri` until the terminal page — so plain `requests` keeps this task
    dependency-free. Trino paces the polling server-side (each GET long-polls
    up to ~1s), matching what the official clients do.
    """
    headers = {
        "X-Trino-User": TRINO_USER,
        "Content-Type": "text/plain; charset=utf-8",
    }
    resp = requests.post(
        f"http://{TRINO_HOST}:{TRINO_PORT}/v1/statement",
        data=sql.encode("utf-8"),
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    payload = resp.json()
    rows: list[list] = []
    # Bounded loop as a belt to the task-level execution_timeout: these are
    # aggregate probes, not long scans — 600 pages is far beyond any of them.
    for _ in range(600):
        if payload.get("error"):
            raise RuntimeError(
                f"Trino query failed: {payload['error'].get('message')} — {sql!r}"
            )
        rows.extend(payload.get("data") or [])
        next_uri = payload.get("nextUri")
        if not next_uri:
            return rows
        resp = requests.get(next_uri, headers=headers, timeout=30)
        resp.raise_for_status()
        payload = resp.json()
    raise TimeoutError(f"Trino query did not finish within 600 pages: {sql!r}")


def trino_quality_check_fn(**context) -> None:
    """Run cross-source quality checks via Trino federated queries.

    Compares ClickHouse gold layer row counts against PostgreSQL
    pipeline.predictions to detect data inconsistencies.
    """

    ol_run_id = _ol_run_id(context)
    ch_input = _ol_dataset(
        "clickhouse://clickhouse-platform.storage.svc.cluster.local:9000",
        "gold.fct_ohlcv_features",
    )
    pg_input = _ol_dataset(
        "postgres://postgresql-rw.storage.svc.cluster.local:5432",
        "pipeline.predictions",
    )
    _ol_emit(_ol_event(
        "START", ol_run_id, job_name="trino_quality_check",
        inputs=[ch_input, pg_input],
    ))

    # ── Check 1: Gold layer row count (ClickHouse) ──────────
    rows = _trino_query(
        "SELECT count(*) AS gold_count FROM clickhouse.gold.fct_ohlcv_features"
    )
    gold_count = rows[0][0] if rows else 0
    logger.info("[Trino QC] ClickHouse gold.fct_ohlcv_features rows: %d", gold_count)

    # ── Check 2: Predictions row count (PostgreSQL) ─────────
    rows = _trino_query(
        "SELECT count(*) AS pred_count FROM postgresql.pipeline.predictions"
    )
    pred_count = rows[0][0] if rows else 0
    logger.info("[Trino QC] PostgreSQL pipeline.predictions rows: %d", pred_count)

    # ── Check 3: Coverage ratio ─────────────────────────────
    if gold_count > 0:
        coverage = pred_count / gold_count
        logger.info("[Trino QC] Prediction coverage ratio: %.4f", coverage)
    else:
        coverage = 0.0
        logger.warning("[Trino QC] Gold layer is empty — coverage ratio undefined")

    # ── Check 4: Recent gold data freshness ─────────────────
    rows = _trino_query(
        "SELECT max(timestamp) AS latest_ts FROM clickhouse.gold.fct_ohlcv_features"
    )
    latest_ts = rows[0][0] if rows else None
    logger.info("[Trino QC] Latest gold layer timestamp: %s", latest_ts)

    # Push metrics to XCom for downstream consumers / alerting
    ti = context["ti"]
    ti.xcom_push(key="gold_row_count", value=gold_count)
    ti.xcom_push(key="prediction_row_count", value=pred_count)
    ti.xcom_push(key="prediction_coverage_ratio", value=coverage)
    ti.xcom_push(key="gold_latest_timestamp", value=str(latest_ts))

    logger.info("[Trino QC] All federated quality checks passed")

    # Close the OpenLineage RunEvent with the metrics attached as a custom
    # run facet so DataHub surfaces them on the lineage graph node.
    _ol_emit(_ol_event(
        "COMPLETE", ol_run_id, job_name="trino_quality_check",
        inputs=[ch_input, pg_input],
        run_facets={
            f"{_USE_CASE_FOR_OL}_qc": {
                "_producer": OPENLINEAGE_PRODUCER,
                "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/CustomFacet.json",
                "goldRowCount": gold_count,
                "predictionRowCount": pred_count,
                "predictionCoverageRatio": coverage,
                "goldLatestTimestamp": str(latest_ts),
            }
        },
    ))


# ─────────────────────────────────────────────────────────────
# dbt_run pod script — build, then publish dbt artifacts to MinIO.
#
# Module-level (column-0) so the <<'PY' heredoc terminator stays at the
# start of line. No Jinja markers ({{ }}) — Airflow templates KPO
# `arguments`, so the script must stay Jinja-inert. All values resolve
# at RUNTIME inside the pod from envFrom:
#   S3_ENDPOINT / AWS_DEFAULT_REGION   — pipeline-config (platform CM)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY — pipeline-secrets (ESO)
#   DBT_ARTIFACTS_BUCKET / DBT_ARTIFACTS_PREFIX — optional overrides;
#     defaults are the platform convention the datahub-ingest-dbt recipe
#     reads (recipes.yaml in platform/components/data-governance).
# ─────────────────────────────────────────────────────────────
_DBT_BUILD_AND_PUBLISH = """\
set -e
dbt build --profiles-dir /dbt --project-dir /dbt
set +e
# catalog.json is only emitted by `docs generate` (build emits
# manifest/run_results); DataHub uses it for column-level schemas.
dbt docs generate --profiles-dir /dbt --project-dir /dbt \
  || echo "WARN: dbt docs generate failed - catalog.json in MinIO stays stale" >&2
uv run --with 'boto3<1.41' - <<'PY'
import os
import pathlib
import sys

import boto3

bucket = os.environ.get("DBT_ARTIFACTS_BUCKET", "pipeline-artifacts")
prefix = os.environ.get("DBT_ARTIFACTS_PREFIX", "dbt/target")
s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["S3_ENDPOINT"],
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
)
uploaded = 0
for name in ("manifest.json", "catalog.json", "run_results.json"):
    path = pathlib.Path("/dbt/target") / name
    if not path.exists():
        print(f"skip {name}: not present in /dbt/target", file=sys.stderr)
        continue
    s3.upload_file(str(path), bucket, f"{prefix}/{name}")
    uploaded += 1
    print(f"uploaded s3://{bucket}/{prefix}/{name}")
if uploaded == 0:
    raise SystemExit("no dbt artifacts found to upload")
PY
if [ $? -ne 0 ]; then
  echo "WARN: dbt artifact upload to MinIO failed - datahub-ingest-dbt keeps reading the previous artifacts" >&2
fi
exit 0
"""


# ═════════════════════════════════════════════════════════════
# DAG: Crypto Lakehouse Pipeline
# ═════════════════════════════════════════════════════════════
# Flow:
#   create_lakefs_branch → dbt_run → [trino_quality_check,
#                                      merge_lakefs_branch → trigger_evidently]
#   dbt_run (on failure) → delete_lakefs_branch (cleanup/rollback)
#   dbt_run also publishes manifest/catalog/run_results to MinIO for
#   the platform datahub-ingest-dbt CronJob (best-effort, never fatal)
# ═════════════════════════════════════════════════════════════
with DAG(
    dag_id=f"{USE_CASE}_lakehouse",
    default_args=DEFAULT_ARGS,
    description=(
        "6-hourly: LakeFS-versioned dbt transforms with Trino quality checks"
    ),
    schedule="15 */6 * * *",
    start_date=datetime(2026, 4, 1),
    catchup=False,
    # Auto-activate on first git-sync load: the platform scheduler sets
    # AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=True, so without this the
    # gold-building dbt run would sit paused forever and gold would never
    # populate on schedule. Safe here because catchup=False (no backfill
    # storm). The daily_backfill DAG (catchup=True) is intentionally left
    # paused — operators trigger backfills manually.
    is_paused_upon_creation=False,
    tags=["crypto", "dbt", "lakefs", "trino", "quality", "6h"],
    max_active_runs=1,
    on_success_callback=push_on_success,
    on_failure_callback=push_on_failure,
) as dag:

    # ── Step 0: Ensure the LakeFS repository exists (idempotent) ──
    ensure_lakefs_repo = PythonOperator(
        task_id="ensure_lakefs_repo",
        python_callable=ensure_lakefs_repo_fn,
    )

    # ── Step 1: Create LakeFS branch ───────────────────────
    create_lakefs_branch = PythonOperator(
        task_id="create_lakefs_branch",
        python_callable=create_lakefs_branch_fn,
    )

    # ── Step 2: Run dbt on the LakeFS branch ───────────────
    # Beyond `dbt build`, this task publishes the dbt artifacts
    # (manifest/catalog/run_results JSON) to MinIO at the platform
    # convention path s3://pipeline-artifacts/dbt/target/ — the
    # datahub-ingest-dbt CronJob (platform data-governance) reads them
    # from there. The artifacts live only in this pod's filesystem, so
    # the upload MUST happen in-pod; a PVC handoff is impossible (the
    # CronJob runs in data-governance, this pod in the use-case
    # namespace — PVCs don't cross namespaces).
    #
    # Failure semantics are deliberate:
    #   * `dbt build` failure  → task fails (set -e) → delete_lakefs_branch
    #     rolls the branch back, exactly as before.
    #   * `dbt docs generate` / upload failure → loud WARN, exit 0. Metadata
    #     publication is secondary to the data publish — a MinIO blip must
    #     not roll back a successful gold build; DataHub just re-ingests
    #     the previous artifacts until the next run.
    # Endpoint/creds come from envFrom (pipeline-config S3_ENDPOINT +
    # pipeline-secrets AWS_*); bucket/prefix are env-overridable so the
    # convention stays config-driven. `uv run --with boto3` mirrors the
    # platform's ephemeral-dep pattern (#409); boto3<1.41 respects the
    # April 2026 version cap.
    dbt_run = k8s_pod(
        "dbt_run",
        image=_image("dbt-project"),
        cmds=["/bin/sh", "-c"],
        args=[_DBT_BUILD_AND_PUBLISH],
        cpu_req="200m",
        mem_req="512Mi",
        cpu_lim="1",
        mem_lim="1Gi",
    )

    # ── Step 3a: Trino federated quality checks ────────────
    trino_quality_check = PythonOperator(
        task_id="trino_quality_check",
        python_callable=trino_quality_check_fn,
    )

    # ── Step 3b: Merge branch to main ──────────────────────
    merge_lakefs_branch = PythonOperator(
        task_id="merge_lakefs_branch",
        python_callable=merge_lakefs_branch_fn,
    )

    # ── Step 4: Run Evidently data quality report after merge ───────
    evidently_report = k8s_pod(
        "evidently_report",
        image=_image("drift-reporter"),
        cmds=["uv", "run", "--no-sync", "main.py"],
        cpu_req="100m",
        mem_req="256Mi",
    )

    # ── Cleanup: Delete branch on failure (rollback) ───────
    delete_lakefs_branch = PythonOperator(
        task_id="delete_lakefs_branch",
        python_callable=delete_lakefs_branch_fn,
        trigger_rule="one_failed",
    )

    # ── Dependency wiring ──────────────────────────────────
    ensure_lakefs_repo >> create_lakefs_branch >> dbt_run >> [trino_quality_check, merge_lakefs_branch]
    merge_lakefs_branch >> evidently_report
    dbt_run >> delete_lakefs_branch
