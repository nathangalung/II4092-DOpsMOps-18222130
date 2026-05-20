"""Pushgateway DAG callbacks — shared by every crypto Airflow DAG.

Pure stdlib (urllib) so Airflow workers don't need an extra pip install
for `requests`. Mirrors the metric shape emitted by:
  * the CronJob push-helper ConfigMap (rest-collector + vector-embedding)
  * the Tekton push-pipeline-metrics-task

so every short-lived crypto workload — batch, dbt, stream-trigger,
pipeline, DAG — lands in the SAME `crypto_job_*` Prometheus series and a
single Grafana panel renders the whole pipeline outcome stream.

Wire from a DAG:

    from _observability import push_on_success, push_on_failure

    with DAG(
        ...,
        on_success_callback=push_on_success,
        on_failure_callback=push_on_failure,
    ) as dag:
        ...
"""

from __future__ import annotations

import logging
import os
import socket
import time
import urllib.error
import urllib.request
from typing import Any

logger = logging.getLogger(__name__)

PUSHGATEWAY_URL = os.environ.get(
    "PUSHGATEWAY_URL",
    "http://pushgateway.observability.svc.cluster.local:9091",
)
USE_CASE = os.environ.get("USE_CASE", "crypto")


def _build_payload(rc: int, duration_s: int, rows: int, now: int) -> bytes:
    success = 1 if rc == 0 else 0
    return (
        "# TYPE crypto_job_last_run_timestamp gauge\n"
        f"crypto_job_last_run_timestamp {now}\n"
        "# TYPE crypto_job_last_duration_seconds gauge\n"
        f"crypto_job_last_duration_seconds {duration_s}\n"
        "# TYPE crypto_job_last_exit_code gauge\n"
        f"crypto_job_last_exit_code {rc}\n"
        "# TYPE crypto_job_last_success gauge\n"
        f"crypto_job_last_success {success}\n"
        "# TYPE crypto_job_rows_ingested gauge\n"
        f"crypto_job_rows_ingested {rows}\n"
    ).encode("utf-8")


def _push(job: str, rc: int, *, duration_s: int = 0, rows: int = 0,
          instance: str | None = None) -> None:
    """POST to Pushgateway. Never raises — metrics are best-effort."""
    instance = instance or socket.gethostname()
    now = int(time.time())
    url = (
        f"{PUSHGATEWAY_URL.rstrip('/')}/metrics/job/{job}"
        f"/use_case/{USE_CASE}/instance/{instance}"
    )
    req = urllib.request.Request(
        url,
        data=_build_payload(rc, duration_s, rows, now),
        method="POST",
        headers={"Content-Type": "text/plain; version=0.0.4"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:  # noqa: S310
            if resp.status >= 300:
                logger.warning("pushgateway returned HTTP %s for %s", resp.status, url)
                return
        logger.info("pushed %s (rc=%s dur=%ss) -> %s", job, rc, duration_s, url)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        logger.warning("push to %s failed: %s", url, exc)


def _dag_job_label(context: dict[str, Any]) -> str:
    dag = context.get("dag")
    dag_id = getattr(dag, "dag_id", None) or context.get("dag_id") or "unknown_dag"
    # Pushgateway URL path forbids `/` — replace with `_` defensively.
    return f"airflow_dag_{dag_id}".replace("/", "_")


def _run_duration_seconds(context: dict[str, Any]) -> int:
    """Best-effort wall-clock seconds for the DagRun."""
    dag_run = context.get("dag_run")
    if dag_run is None:
        return 0
    start = getattr(dag_run, "start_date", None)
    end = getattr(dag_run, "end_date", None) or getattr(dag_run, "data_interval_end", None)
    if start is None:
        return 0
    if end is None:
        # Callback fires before end_date is persisted — approximate with now.
        from datetime import datetime, timezone
        end = datetime.now(timezone.utc)
    try:
        return int((end - start).total_seconds())
    except Exception:  # noqa: BLE001 — never let metrics break a DAG callback
        return 0


def push_on_success(context: dict[str, Any]) -> None:
    """Airflow DAG `on_success_callback` — emits rc=0."""
    _push(
        _dag_job_label(context),
        rc=0,
        duration_s=_run_duration_seconds(context),
        instance=getattr(context.get("dag_run"), "run_id", "unknown_run"),
    )


def push_on_failure(context: dict[str, Any]) -> None:
    """Airflow DAG `on_failure_callback` — emits rc=1."""
    _push(
        _dag_job_label(context),
        rc=1,
        duration_s=_run_duration_seconds(context),
        instance=getattr(context.get("dag_run"), "run_id", "unknown_run"),
    )
