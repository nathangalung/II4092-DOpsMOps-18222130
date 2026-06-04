"""ML Bridge API."""

import os
import re
import shutil
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from services.feature import router as feature_router
from services.metrics import router as metrics_router
from services.prediction import router as prediction_router


def _render_feast_repo() -> None:
    """Render ``feature_store.yaml`` from a ``${VAR}`` template at startup.

    Mirrors the materialization job's renderer (the writer side): reads
    ``$FEAST_TEMPLATE_DIR/feature_store.yaml.tmpl``, substitutes every
    ``${VAR}`` from the pod environment, copies ``definitions.py`` alongside,
    and writes both into ``$FEAST_REPO_PATH`` (default ``/app/feature_store``,
    a writable emptyDir). No-op when FEAST_TEMPLATE_DIR is unset, so local and
    test runs that ship a ready-rendered repo are unaffected.
    """
    template_dir = os.getenv("FEAST_TEMPLATE_DIR")
    if not template_dir:
        return

    def _sub(match: re.Match[str]) -> str:
        key = match.group(1)
        try:
            return os.environ[key]
        except KeyError as exc:
            raise KeyError(
                f"feature_store.yaml.tmpl references ${{{key}}} but it is unset "
                "in the pod environment (check pipeline-config / pipeline-secrets)"
            ) from exc

    repo_path = os.getenv("FEAST_REPO_PATH", "/app/feature_store")
    tmpl = Path(template_dir, "feature_store.yaml.tmpl").read_text()
    rendered = re.sub(r"\$\{(\w+)\}", _sub, tmpl)

    repo = Path(repo_path)
    repo.mkdir(parents=True, exist_ok=True)
    (repo / "feature_store.yaml").write_text(rendered)
    shutil.copy(Path(template_dir, "definitions.py"), repo / "definitions.py")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    # Render the Feast feature repo (writer-mirrored) so the /api/features
    # routes can open a FeatureStore against the S3 registry + Valkey online
    # store. No-op without FEAST_TEMPLATE_DIR (see _render_feast_repo).
    _render_feast_repo()
    yield


app = FastAPI(title="ML Bridge", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, Any]:
    start = time.perf_counter_ns()
    latency = (time.perf_counter_ns() - start) / 1000
    return {"status": "healthy", "latency_us": latency}


app.include_router(prediction_router, prefix="/api/predictions", tags=["predictions"])
app.include_router(feature_router, prefix="/api/features", tags=["features"])
app.include_router(metrics_router, prefix="/api/metrics", tags=["metrics"])


def _run_server() -> None:
    """Run the FastAPI service (default; this is what the Argo Rollout runs)."""
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))


def _run_batch_score() -> None:
    """One-shot batch inference for the Airflow `scoring` task.

    Reads the latest feature row per symbol from the feature table, calls the
    KServe predictor (same contract as the online `/api/predictions/predict`
    route), and writes predictions to ClickHouse `gold.crypto_predictions`.

    The feature table defaults to the *training* table (`gold.fct_training_data`)
    so the scored feature set matches what the model was trained on — no
    train/serve skew on this batch path. All endpoints/tables are env-driven.
    """
    import logging
    from datetime import UTC, datetime, timedelta

    import clickhouse_connect
    import httpx

    logging.basicConfig(level=logging.INFO)
    log = logging.getLogger("batch-score")

    symbols = [
        s.strip()
        for s in os.getenv("SYMBOLS", "BTC-USD,ETH-USD,SOL-USD").split(",")
        if s.strip()
    ]
    features_table = os.getenv("FEATURES_TABLE", "gold.fct_training_data")
    predictions_table = os.getenv("PREDICTIONS_TABLE", "gold.crypto_predictions")
    inference_url = os.getenv(
        "INFERENCE_URL",
        "http://crypto-predictor-predictor.use-case-crypto.svc.cluster.local",
    )
    model_type = os.getenv("MODEL_TYPE", "lightgbm")
    horizon_h = int(os.getenv("PREDICTION_HORIZON_HOURS", "1"))
    # Identifier / label columns that are not model features (mirrors the
    # trainer's EXCLUDE_COLUMNS so the served feature set matches training).
    exclude = {
        c.strip()
        for c in os.getenv(
            "EXCLUDE_COLUMNS",
            "symbol,timestamp,date,hour,data_type,created_at,"
            "computed_at,fear_greed_label",
        ).split(",")
        if c.strip()
    }

    ch = clickhouse_connect.get_client(
        host=os.getenv("CLICKHOUSE_HOST", "localhost"),
        port=int(os.getenv("CLICKHOUSE_PORT", "8123")),
        username=os.getenv("CLICKHOUSE_USER", "default"),
        password=os.getenv("CLICKHOUSE_PASSWORD", ""),
    )

    written = 0
    with httpx.Client(timeout=30.0) as client:
        for symbol in symbols:
            res = ch.query(
                f"SELECT * FROM {features_table} WHERE symbol = %(s)s "
                "ORDER BY timestamp DESC LIMIT 1",
                parameters={"s": symbol},
            )
            if not res.result_rows:
                log.warning("no features for %s in %s", symbol, features_table)
                continue
            row = dict(zip(res.column_names, res.result_rows[0]))
            features = {
                k: float(v)
                for k, v in row.items()
                if k not in exclude and isinstance(v, (int, float))
            }
            try:
                resp = client.post(
                    f"{inference_url}/predict",
                    json={"symbol": symbol, "features": features},
                )
                resp.raise_for_status()
                pred = resp.json()
            except httpx.HTTPError as e:
                log.error("predict failed for %s: %s", symbol, e)
                continue

            now = datetime.now(tz=UTC)
            ch.insert(
                table=predictions_table,
                data=[
                    [
                        symbol,
                        now,
                        now + timedelta(hours=horizon_h),
                        float(pred.get("predicted_price", 0.0)),
                        str(pred.get("signal", "")),
                        float(pred.get("predicted_volatility", 0.0)),
                        float(pred.get("confidence", 0.0)),
                        str(pred.get("model_version", "")),
                        model_type,
                    ]
                ],
                column_names=[
                    "symbol",
                    "prediction_timestamp",
                    "target_timestamp",
                    "predicted_price",
                    "predicted_direction",
                    "predicted_volatility",
                    "confidence",
                    "model_version",
                    "model_type",
                ],
            )
            written += 1
    log.info(
        "batch-score wrote %d/%d predictions to %s",
        written,
        len(symbols),
        predictions_table,
    )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ML Bridge")
    parser.add_argument(
        "--mode",
        choices=["serve", "batch-score"],
        default="serve",
        help=(
            "serve = FastAPI API (default; used by the Rollout). "
            "batch-score = one-shot batch inference (used by the Airflow "
            "scoring task)."
        ),
    )
    args = parser.parse_args()

    if args.mode == "batch-score":
        _run_batch_score()
    else:
        _run_server()
