"""Drift-triggered KFP retraining launcher.

Invoked by Airflow DAG task `trigger_retrain_if_drift`.  Flow:
    1. Read drift flag from Redis (`crypto:drift:triggered`).
    2. If True, submit a KFP run of `crypto_retraining_pipeline`.
    3. Block until the KFP run reaches a terminal state; exit 0 on success,
       non-zero on failure — Airflow surfaces that as task failure.

The pipeline YAML is shipped alongside this script; KFP SDK accepts a
compiled YAML via `kfp.Client.create_run_from_pipeline_package`.
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

import redis

LOG = logging.getLogger("crypto-retraining")


def _env(name: str, default: Optional[str] = None, *, required: bool = False) -> str:
    v = os.environ.get(name, default)
    if required and not v:
        raise RuntimeError(f"missing required env var {name}")
    return v  # type: ignore[return-value]


def _configure_logging() -> None:
    from pythonjsonlogger import jsonlogger

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(jsonlogger.JsonFormatter(
        "%(asctime)s %(name)s %(levelname)s %(message)s"
    ))
    logging.root.handlers = [handler]
    logging.root.setLevel(_env("LOG_LEVEL", "INFO"))


def _check_drift(r: redis.Redis) -> bool:
    flag = r.get("crypto:drift:triggered")
    LOG.info("drift flag", extra={"value": flag})
    return flag in (b"1", b"true", b"True")


def _submit_kfp(pipeline_path: str, experiment_name: str) -> str:
    from kfp.client import Client

    kfp_host = _env("KFP_HOST", "http://ml-pipeline.model-lifecycle.svc.cluster.local:8888")
    client = Client(host=kfp_host)

    # Rolling training window: last N days, computed at submit time so each
    # run trains on a fresh slice instead of the hard-coded pipeline default.
    window_days = int(_env("TRAINING_WINDOW_DAYS", "30"))
    now = datetime.now(timezone.utc)
    start_date = (now - timedelta(days=window_days)).strftime("%Y-%m-%d")

    run = client.create_run_from_pipeline_package(
        pipeline_file=pipeline_path,
        arguments={
            "symbol": _env("SYMBOL", "BTC-USD"),
            "features_table": _env("TRAINING_TABLE", "gold.fct_training_data"),
            "start_date": start_date,
            "mlflow_tracking_uri": _env(
                "MLFLOW_TRACKING_URI",
                "http://mlflow.model-lifecycle.svc.cluster.local:5000",
            ),
            "mlflow_experiment": experiment_name,
        },
        experiment_name=experiment_name,
        run_name=f"drift-retrain-{int(time.time())}",
        enable_caching=False,
    )
    LOG.info("submitted KFP run", extra={"run_id": run.run_id})
    return run.run_id


def _await_run(run_id: str, *, timeout_s: int = 3600) -> str:
    from kfp.client import Client

    client = Client(host=_env("KFP_HOST", "http://ml-pipeline.model-lifecycle.svc.cluster.local:8888"))
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        run = client.get_run(run_id)
        state = run.state
        LOG.info("kfp run state", extra={"run_id": run_id, "state": state})
        if state in {"SUCCEEDED", "FAILED", "SKIPPED", "CANCELED"}:
            return state
        time.sleep(30)
    return "TIMEOUT"


def main() -> int:
    _configure_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-and-retrain", action="store_true")
    parser.add_argument(
        "--pipeline-path",
        default=_env("PIPELINE_PATH", "/app/pipelines/retraining_pipeline.yaml"),
    )
    parser.add_argument(
        "--experiment-name",
        default=_env("KFP_EXPERIMENT", "crypto-retraining"),
    )
    args = parser.parse_args()

    if not args.check_and_retrain:
        LOG.info("nothing to do (pass --check-and-retrain)")
        return 0

    r = redis.from_url(_env("VALKEY_URL", "redis://valkey.storage.svc.cluster.local:6379/0"))
    if not _check_drift(r):
        LOG.info("no drift detected; skipping retraining")
        return 0

    run_id = _submit_kfp(args.pipeline_path, args.experiment_name)
    state = _await_run(run_id)
    LOG.info("kfp run complete", extra={"run_id": run_id, "state": state})

    if state == "SUCCEEDED":
        # Clear drift flag only on success so failures remain signalled.
        r.delete("crypto:drift:triggered")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
