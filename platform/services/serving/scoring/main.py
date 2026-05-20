"""
Scheduled scoring service.
Loads the latest ONNX model from MLflow, fetches features from the online
store (Valkey via Feast — RESP wire protocol) or offline store (ClickHouse), runs inference,
and writes predictions to ClickHouse gold layer.

Usage:
  uv run main.py              # Score all symbols once (CronJob mode)
  uv run main.py --symbol X   # Score specific symbol
"""

import logging
import os
from datetime import UTC, datetime, timedelta

import clickhouse_connect
import mlflow
import numpy as np
import onnxruntime as ort
import pandas as pd

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Config:
    """Configuration from environment variables."""

    CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "localhost")
    CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
    CLICKHOUSE_DB = os.getenv("CLICKHOUSE_DB", "gold")
    MLFLOW_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
    EXPERIMENT = os.getenv("MLFLOW_EXPERIMENT", "ml-pipeline")
    FEATURES_TABLE = os.getenv(
        "SCORING_FEATURES_TABLE",
        os.getenv("FEATURES_TABLE", "data_features"),
    )
    PREDICTIONS_TABLE = os.getenv(
        "PREDICTIONS_TABLE", "predictions"
    )
    VALID_SYMBOLS = os.getenv("VALID_SYMBOLS", "")
    SYMBOL = os.getenv("SYMBOL", "")
    MODEL_TYPE = os.getenv("MODEL_TYPE", "lightgbm")
    TARGET_COLUMN = os.getenv("TARGET_COLUMN", "value")
    EXCLUDE_COLUMNS = os.getenv(
        "EXCLUDE_COLUMNS",
        "symbol,timestamp,date,hour,data_type,created_at,computed_at",
    )
    FEATURE_COLUMNS = os.getenv("FEATURE_COLUMNS", "")


def get_clickhouse_client():
    return clickhouse_connect.get_client(
        host=Config.CLICKHOUSE_HOST,
        port=Config.CLICKHOUSE_PORT,
    )


def get_latest_model_path() -> str | None:
    """Find latest successful run's ONNX artifact from MLflow."""
    mlflow.set_tracking_uri(Config.MLFLOW_URI)
    experiment = mlflow.get_experiment_by_name(Config.EXPERIMENT)
    if not experiment:
        logger.error(f"Experiment '{Config.EXPERIMENT}' not found")
        return None

    runs = mlflow.search_runs(
        experiment_ids=[experiment.experiment_id],
        filter_string="status = 'FINISHED'",
        order_by=["start_time DESC"],
        max_results=1,
    )

    if runs.empty:
        logger.error("No successful runs found")
        return None

    run_id = runs.iloc[0]["run_id"]
    artifact_uri = runs.iloc[0]["artifact_uri"]
    logger.info(f"Using model from run {run_id}")

    # List artifacts to find ONNX file
    client = mlflow.tracking.MlflowClient(Config.MLFLOW_URI)
    artifacts = client.list_artifacts(run_id)
    onnx_files = [a.path for a in artifacts if a.path.endswith(".onnx")]

    if not onnx_files:
        logger.error(f"No ONNX artifacts in run {run_id}")
        return None

    local_path = mlflow.artifacts.download_artifacts(
        artifact_uri=f"{artifact_uri}/{onnx_files[0]}"
    )
    logger.info(f"Downloaded model: {local_path}")
    return local_path


def load_features(client, symbol: str) -> pd.DataFrame | None:
    """Load latest features from ClickHouse for scoring."""
    query = f"""
    SELECT *
    FROM {Config.FEATURES_TABLE}
    WHERE symbol = '{symbol}'
    ORDER BY timestamp DESC
    LIMIT 1
    """
    df = client.query_df(query)
    if df.empty:
        logger.warning(f"No features found for {symbol}")
        return None
    return df


def prepare_input(df: pd.DataFrame) -> np.ndarray:
    """Prepare feature vector for ONNX inference."""
    exclude = {
        c.strip()
        for c in Config.EXCLUDE_COLUMNS.split(",")
        if c.strip()
    }

    if Config.FEATURE_COLUMNS:
        feature_cols = [
            c.strip()
            for c in Config.FEATURE_COLUMNS.split(",")
            if c.strip()
        ]
    else:
        feature_cols = [
            c for c in df.columns
            if c not in exclude and c != Config.TARGET_COLUMN
        ]

    # Select only columns that exist in the dataframe
    available_cols = [c for c in feature_cols if c in df.columns]
    if not available_cols:
        msg = "No feature columns available for inference"
        raise ValueError(msg)

    features = df[available_cols].values.astype(np.float32)
    # Replace NaN with 0
    features = np.nan_to_num(features, nan=0.0)
    return features


def run_inference(model_path: str, features: np.ndarray) -> float:
    """Run ONNX inference and return prediction."""
    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    result = session.run(None, {input_name: features})
    prediction = float(result[0].flatten()[0])
    return prediction


def write_prediction(
    client,
    symbol: str,
    timestamp: datetime,
    current_value: float,
    predicted_value: float,
    model_version: str,
) -> None:
    """Write prediction to ClickHouse gold layer.

    Matches existing predictions schema:
    symbol, prediction_timestamp, target_timestamp, predicted_price,
    predicted_direction, predicted_volatility, confidence, model_version,
    model_type, created_at
    """
    pct_change = (predicted_value - current_value) / current_value
    if pct_change > 0.01:
        direction = "UP"
    elif pct_change < -0.01:
        direction = "DOWN"
    else:
        direction = "STABLE"

    confidence = min(abs(pct_change) * 10, 1.0)
    volatility = abs(pct_change)
    now = datetime.now(tz=UTC)
    # Target is 1 hour ahead of the prediction timestamp
    target_ts = timestamp + timedelta(hours=1)

    client.insert(
        Config.PREDICTIONS_TABLE,
        [[
            symbol,
            now,
            target_ts,
            predicted_value,
            direction,
            volatility,
            confidence,
            model_version,
            Config.MODEL_TYPE,
            now,
        ]],
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
            "created_at",
        ],
    )
    logger.info(
        f"Prediction for {symbol}: current={current_value:.2f}, "
        f"predicted={predicted_value:.2f}, direction={direction}, "
        f"confidence={confidence:.4f}"
    )


def score_symbol(
    ch_client, model_path: str, symbol: str, model_version: str
) -> bool:
    """Score a single symbol. Returns True on success."""
    df = load_features(ch_client, symbol)
    if df is None:
        return False

    timestamp = pd.Timestamp(df["timestamp"].iloc[0])
    current_value = float(df[Config.TARGET_COLUMN].iloc[0])

    features = prepare_input(df)
    predicted_value = run_inference(model_path, features)

    write_prediction(
        ch_client,
        symbol,
        timestamp.to_pydatetime().replace(tzinfo=UTC),
        current_value,
        predicted_value,
        model_version,
    )
    return True


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Scheduled Scoring")
    parser.add_argument("--symbol", type=str, default=None)
    args = parser.parse_args()

    # Determine symbols
    if args.symbol:
        symbols = [args.symbol]
    elif Config.VALID_SYMBOLS:
        symbols = [s.strip() for s in Config.VALID_SYMBOLS.split(",") if s.strip()]
    elif Config.SYMBOL:
        symbols = [Config.SYMBOL]
    else:
        logger.error("No symbols configured. Set VALID_SYMBOLS or SYMBOL.")
        return

    # Load model
    model_path = get_latest_model_path()
    if not model_path:
        logger.error("Could not load model from MLflow. Exiting.")
        return

    # Determine model version from MLflow run
    mlflow.set_tracking_uri(Config.MLFLOW_URI)
    experiment = mlflow.get_experiment_by_name(Config.EXPERIMENT)
    runs = mlflow.search_runs(
        experiment_ids=[experiment.experiment_id],
        filter_string="status = 'FINISHED'",
        order_by=["start_time DESC"],
        max_results=1,
    )
    model_version = runs.iloc[0]["run_id"][:8] if not runs.empty else "unknown"

    # Score
    ch_client = get_clickhouse_client()
    success_count = 0
    for symbol in symbols:
        try:
            if score_symbol(ch_client, model_path, symbol, model_version):
                success_count += 1
        except Exception as e:
            logger.error(f"Scoring failed for {symbol}: {e}")

    logger.info(f"Scoring complete: {success_count}/{len(symbols)} symbols")


if __name__ == "__main__":
    main()
