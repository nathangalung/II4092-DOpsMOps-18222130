"""Prediction service — KServe V2 inference proxy.

The serving plane is a KServe ``InferenceService`` (``crypto-predictor``) running
MLServer with an MLflow model. MLServer exposes ONLY the V2 inference protocol —
``POST /v2/models/{name}/infer`` — so the previous custom routes
(``/predict``, ``/predictions/latest``) 404'd against it.

This module bridges the use-case API to that protocol:

  * ``POST /predict`` — caller supplies a ``{name: value}`` feature dict; we order
    it into the model's training feature vector and run one V2 inference.
  * ``GET  /latest``  — pull the newest row from the gold training table
    (ClickHouse), build the same vector, infer, and derive a trading signal.

Feature-vector contract (train/serve parity — see platform trainer
``trainer.py::_get_feature_columns``):
  The model was trained on ``df[feature_cols].values`` — a positional NumPy
  matrix with NO column names and NO MLflow signature — so MLServer expects a
  positional tensor whose column order matches training exactly. ``feature_cols``
  is "every NUMERIC column of the gold table, minus EXCLUDE_COLUMNS, minus the
  TARGET_COLUMN, in table order". We reproduce that selection here from the same
  env vars the trainer reads, so the served vector can never silently skew from
  the trained one. Critically the TARGET column (crypto: ``close``) is EXCLUDED —
  it is the label, not a feature.
"""

import os
from datetime import UTC, datetime
from typing import Any

import clickhouse_connect
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

# KServe predictor base; V2 endpoint is `${INFERENCE_URL}/v2/models/${MODEL_NAME}/infer`.
INFERENCE_URL = os.getenv(
    "INFERENCE_URL",
    "http://crypto-predictor-predictor.use-case-crypto.svc.cluster.local",
)
# MLServer model name == InferenceService name (MLSERVER_MODEL_NAME={{.Name}}).
MODEL_NAME = os.getenv("MODEL_NAME", "crypto-predictor")
MODEL_VERSION = os.getenv("MODEL_VERSION", "latest")

FEATURES_TABLE = os.getenv("FEATURES_TABLE", "gold.fct_training_data")
TARGET_COLUMN = os.getenv("TARGET_COLUMN", "close")
# Identifier / metadata columns that are not model inputs — must mirror the
# trainer's EXCLUDE_COLUMNS. The TARGET_COLUMN is unioned in below.
_EXCLUDE = {
    c.strip()
    for c in os.getenv(
        "EXCLUDE_COLUMNS",
        "symbol,timestamp,date,hour,data_type,created_at,computed_at",
    ).split(",")
    if c.strip()
} | {TARGET_COLUMN}

# Signal thresholds on predicted vs current close (fractional move).
_SIGNAL_EPS = float(os.getenv("SIGNAL_EPS", "0.001"))


class PredictionRequest(BaseModel):
    """Prediction request: a feature dict for one symbol."""

    symbol: str
    features: dict[str, float]


class PredictionResponse(BaseModel):
    """Prediction response — next-period close forecast + derived signal."""

    symbol: str
    predicted_price: float
    signal: str
    confidence: float
    model_version: str


def _ch_client() -> Any:
    return clickhouse_connect.get_client(
        host=os.getenv("CLICKHOUSE_HOST", "localhost"),
        port=int(os.getenv("CLICKHOUSE_PORT", "8123")),
        username=os.getenv("CLICKHOUSE_USER", "default"),
        password=os.getenv("CLICKHOUSE_PASSWORD", ""),
    )


# ClickHouse numeric type families (matched against ClickHouseType.base_type).
_NUMERIC_BASE = ("Int", "UInt", "Float", "Decimal")


def _feature_order(column_names: list[str], column_types: list[Any]) -> list[str]:
    """Training feature columns, in table order: numeric-TYPED, minus exclude∪target.

    Selection is by column *type* (mirroring the trainer's
    ``pd.api.types.is_numeric_dtype`` over the same ``SELECT *`` projection), NOT
    by the sampled row's value type. A NULL in the newest row must never silently
    drop a column and shrink the served vector below the trained width — the
    positional, no-signature model would then receive a misaligned tensor. NULLs
    are zero-filled at vector-build time, matching the trainer's ``fillna(0)``.
    """
    cols: list[str] = []
    for name, ctype in zip(column_names, column_types, strict=False):
        if name in _EXCLUDE:
            continue
        base = getattr(ctype, "base_type", "") or ""
        if base.startswith(_NUMERIC_BASE):
            cols.append(name)
    return cols


def _infer(vector: list[float]) -> float:
    """One KServe V2 inference; returns the scalar model output."""
    # Request-level content_type=np: MLServer's mlflow runtime reshapes the flat
    # data per `shape` into a 2D ndarray [1, N] before calling model.predict —
    # without it the runtime hands lightgbm a 1D/scalar array and 500s
    # ("Expected 2D array"). Verified against mlserver 1.7.1 + the mlflow-lightgbm
    # flavor (single positional tensor; the model has no column-named signature).
    payload = {
        "parameters": {"content_type": "np"},
        "inputs": [
            {
                "name": "input-0",
                "shape": [1, len(vector)],
                "datatype": "FP64",
                "data": vector,
            }
        ],
    }
    url = f"{INFERENCE_URL}/v2/models/{MODEL_NAME}/infer"
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.post(url, json=payload)
            resp.raise_for_status()
            body = resp.json()
    except httpx.HTTPError as e:
        raise HTTPException(status_code=503, detail=f"predictor unreachable: {e}") from e
    try:
        return float(body["outputs"][0]["data"][0])
    except (KeyError, IndexError, TypeError, ValueError) as e:
        raise HTTPException(
            status_code=502, detail=f"unexpected V2 response: {body!r}"
        ) from e


def _signal(predicted: float, current: float) -> tuple[str, float]:
    """Derive BUY/SELL/HOLD + a heuristic confidence from the forecast move."""
    if current <= 0:
        return "HOLD", 0.0
    move = (predicted - current) / current
    if move > _SIGNAL_EPS:
        sig = "BUY"
    elif move < -_SIGNAL_EPS:
        sig = "SELL"
    else:
        sig = "HOLD"
    # Confidence: magnitude of the move, saturating at 1.0 (~10% move ⇒ ~1.0).
    confidence = min(1.0, abs(move) * 10.0)
    return sig, round(confidence, 4)


@router.post("/predict")
def predict(request: PredictionRequest) -> PredictionResponse:
    """Run inference on a caller-supplied feature dict (ordered to training)."""
    client = _ch_client()
    try:
        res = client.query(f"SELECT * FROM {FEATURES_TABLE} LIMIT 0")
        order = _feature_order(res.column_names, res.column_types)
    finally:
        client.close()
    if not order:
        raise HTTPException(status_code=400, detail="no feature columns in table")
    # Full trained-width vector in table order: caller value per feature, else 0.0
    # (mirrors the trainer's fillna(0)). Guarantees the model's expected width
    # regardless of which features the caller chose to supply.
    vector = [float(request.features.get(c, 0.0)) for c in order]
    predicted = _infer(vector)
    current = float(request.features.get(TARGET_COLUMN, 0.0))
    sig, conf = _signal(predicted, current)
    return PredictionResponse(
        symbol=request.symbol,
        predicted_price=predicted,
        signal=sig,
        confidence=conf,
        model_version=MODEL_VERSION,
    )


@router.get("/latest")
def get_latest(symbol: str = "BTC-USD") -> dict[str, Any]:
    """Latest live prediction: newest gold row → inference → signal."""
    client = _ch_client()
    try:
        res = client.query(
            f"SELECT * FROM {FEATURES_TABLE} WHERE symbol = %(s)s "
            "ORDER BY timestamp DESC LIMIT 1",
            parameters={"s": symbol},
        )
        if not res.result_rows:
            raise HTTPException(status_code=404, detail=f"no features for {symbol}")
        row = dict(zip(res.column_names, res.result_rows[0], strict=False))
    finally:
        client.close()

    order = _feature_order(res.column_names, res.column_types)
    vector = [float(row[c]) if row.get(c) is not None else 0.0 for c in order]
    predicted = _infer(vector)
    current = float(row.get(TARGET_COLUMN) or 0.0)
    sig, conf = _signal(predicted, current)
    ts = row.get("timestamp")
    return {
        "symbol": symbol,
        "timestamp": (ts.isoformat() if hasattr(ts, "isoformat") else str(ts)),
        "current_price": current,
        "predicted_price": predicted,
        "signal": sig,
        "confidence": conf,
        "model_version": MODEL_VERSION,
        "feature_count": len(vector),
        "served_at": datetime.now(tz=UTC).isoformat(),
    }
