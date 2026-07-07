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
    # Substitute per line, skipping full-line `#` comments (mirrors the
    # materialization writer): a documentation note like `# creds via ${VAR}`
    # must not be mistaken for a real placeholder. Config-line `${VAR}` still
    # fails loud when unset.
    rendered = "".join(
        line if line.lstrip().startswith("#") else re.sub(r"\$\{(\w+)\}", _sub, line)
        for line in tmpl.splitlines(keepends=True)
    )

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

    Reuses the EXACT online-serving path (``services.prediction._infer`` +
    ``_feature_order``) so a batch-scored prediction is byte-identical to what
    ``GET /api/predictions/latest`` returns - one feature-selection rule, one
    KServe V2 inference contract, no second code path to drift. (The previous
    implementation POSTed a ``{features}`` dict to ``{predictor}/predict`` - a
    legacy custom route that does not exist on the V2-only MLServer predictor,
    so every batch run 404'd and ``gold.crypto_predictions`` never advanced.)
    Reads the latest feature row per symbol from the training table (so the
    scored feature set matches training), runs one inference, writes to
    ClickHouse ``gold.crypto_predictions``. Tables/symbols are env-driven.
    """
    import logging
    from datetime import UTC, datetime, timedelta

    from services.prediction import (
        FEATURES_TABLE,
        MODEL_VERSION,
        TARGET_COLUMN,
        _ch_client,
        _feature_order,
        _infer,
        _signal,
    )

    logging.basicConfig(level=logging.INFO)
    log = logging.getLogger("batch-score")

    symbols = [
        s.strip()
        for s in os.getenv("SYMBOLS", "BTC-USD,ETH-USD,SOL-USD").split(",")
        if s.strip()
    ]
    predictions_table = os.getenv("PREDICTIONS_TABLE", "gold.crypto_predictions")
    model_type = os.getenv("MODEL_TYPE", "lightgbm")
    horizon_h = int(os.getenv("PREDICTION_HORIZON_HOURS", "1"))

    ch = _ch_client()
    written = 0
    try:
        for symbol in symbols:
            res = ch.query(
                f"SELECT * FROM {FEATURES_TABLE} WHERE symbol = %(s)s "
                "ORDER BY timestamp DESC LIMIT 1",
                parameters={"s": symbol},
            )
            if not res.result_rows:
                log.warning("no features for %s in %s", symbol, FEATURES_TABLE)
                continue
            row = dict(zip(res.column_names, res.result_rows[0], strict=False))
            # Column-type feature selection + V2 inference - identical to the
            # online /api/predictions/latest route (single source of truth);
            # NULL to 0.0 mirrors the trainer's fillna(0).
            order = _feature_order(res.column_names, res.column_types)
            vector = [float(row[c]) if row.get(c) is not None else 0.0 for c in order]
            try:
                predicted = _infer(vector)
            except Exception as e:  # noqa: BLE001 - skip one symbol, keep the batch going
                log.error("inference failed for %s: %s", symbol, e)
                continue
            current = float(row.get(TARGET_COLUMN) or 0.0)
            signal, confidence = _signal(predicted, current)
            now = datetime.now(tz=UTC)
            ch.insert(
                table=predictions_table,
                data=[
                    [
                        symbol,
                        now,
                        now + timedelta(hours=horizon_h),
                        predicted,
                        signal,
                        0.0,  # predicted_volatility - point regressor, no σ head
                        confidence,
                        MODEL_VERSION,
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
    finally:
        ch.close()
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
