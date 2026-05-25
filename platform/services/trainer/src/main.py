"""
FLAML AutoML Trainer — automatic model selection and hyperparameter tuning.

FLAML searches across LightGBM, XGBoost, CatBoost, RandomForest, ExtraTree,
and linear models, returning the native best model. This means:
  - kserve-mlserver serves it directly via MLflow format (no custom runtime)
  - MLflow logs it with the correct flavor (lightgbm, xgboost, sklearn)
  - Zero model-specific code needed — FLAML handles everything

All domain-specific configuration comes from environment variables set by
the use-case's ConfigMap. To tune FLAML behavior, set FLAML_* env vars.

References:
  - FLAML: https://arxiv.org/abs/2005.01571 (ICML 2021, Microsoft Research)
  - AMLB Benchmark: rank #5-6 across 104 OpenML datasets, competitive accuracy
  - Cost-frugal: finds good models with 10-100x less compute than grid search
"""

import logging
import os
import sys

import clickhouse_connect
import mlflow
import numpy as np
import pandas as pd
from flaml import AutoML
from prometheus_client import Counter, Histogram
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    r2_score,
    recall_score,
)

from trainer import Trainer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pyroscope continuous profiling — opt-in via PYROSCOPE_SERVER_ADDRESS
# (set by platform pipeline-config ConfigMap). Unset (tests / local dev)
# = profiler disabled, service runs unchanged.
if os.environ.get("PYROSCOPE_SERVER_ADDRESS"):
    import pyroscope

    pyroscope.configure(
        application_name=f"{os.environ.get('USE_CASE', 'platform')}.trainer",
        server_address=os.environ["PYROSCOPE_SERVER_ADDRESS"],
        tags={
            "use_case": os.environ.get("USE_CASE", "platform"),
            "service": "trainer",
        },
    )

TRAIN_COUNTER = Counter("trainer_runs_total", "Training runs")
TRAIN_DURATION = Histogram("trainer_duration_seconds", "Training duration")


# ── Config from env (set by use-case ConfigMap) ─────────────────────────

class Config:
    """All values overridable by use-case ConfigMap."""

    CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "localhost")
    CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
    CLICKHOUSE_DB = os.getenv("CLICKHOUSE_DB", "features")
    CLICKHOUSE_USER = os.getenv("CLICKHOUSE_USER", "default")
    CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "")
    MLFLOW_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
    EXPERIMENT = os.getenv("MLFLOW_EXPERIMENT", "ml-pipeline")
    FEATURES_TABLE = os.getenv("FEATURES_TABLE", "features")


class FLAMLConfig:
    """FLAML-specific config from env vars."""

    TIME_BUDGET = int(os.getenv("FLAML_TIME_BUDGET", "300"))
    MAX_ITER = int(os.getenv("FLAML_MAX_ITER", "0")) or None
    SEED = int(os.getenv("FLAML_SEED", "42"))
    N_SPLITS = int(os.getenv("FLAML_N_SPLITS", "5"))
    EARLY_STOP = os.getenv("FLAML_EARLY_STOP", "true").lower() in ("true", "1", "yes")
    ENSEMBLE = os.getenv("FLAML_ENSEMBLE", "false").lower() in ("true", "1", "yes")
    LOG_LEVEL = int(os.getenv("FLAML_LOG_LEVEL", "1"))
    TASK_TYPE = os.getenv("TASK_TYPE", "regression")

    @staticmethod
    def metric() -> str | None:
        val = os.getenv("FLAML_METRIC", "auto")
        return None if val == "auto" else val

    @staticmethod
    def estimator_list() -> list[str]:
        val = os.getenv("FLAML_ESTIMATOR_LIST", "lgbm,xgboost,catboost,rf,extra_tree")
        return [s.strip() for s in val.split(",") if s.strip()]


# ── FLAML estimator → MLflow flavor mapping ─────────────────────────────

_MLFLOW_FLAVOR = {
    "lgbm": "lightgbm",
    "xgboost": "xgboost",
    "xgb_limitdepth": "xgboost",
    "xgb_sklearn": "xgboost",
    "catboost": "catboost",
    # All others use sklearn flavor:
    #   rf, extra_tree, kneighbor, elastic_net, lasso_lars, sgd, svc
}


def _log_model_to_mlflow(automl: AutoML) -> None:
    """Log the best model using its native MLflow flavor.

    FLAML returns native model objects (LGBMRegressor, XGBClassifier, etc.),
    so we log them with the correct MLflow flavor. This lets kserve-mlserver
    serve ANY model FLAML picks without a custom runtime.
    """
    best = automl.best_estimator
    model = automl.model.estimator if hasattr(automl.model, "estimator") else automl.model
    flavor = _MLFLOW_FLAVOR.get(best, "sklearn")

    if flavor == "lightgbm":
        mlflow.lightgbm.log_model(model, artifact_path="model")
    elif flavor == "xgboost":
        mlflow.xgboost.log_model(model, artifact_path="model")
    elif flavor == "catboost":
        mlflow.catboost.log_model(model, artifact_path="model")
    else:
        mlflow.sklearn.log_model(model, artifact_path="model")

    logger.info("Logged %s model (%s) to MLflow artifact_path='model'", best, flavor)


# ── Data loading ────────────────────────────────────────────────────────

def load_data(symbol: str, start: str, end: str) -> pd.DataFrame:
    """Load training data from ClickHouse.

    Empty start/end strings = no upper/lower timestamp bound. The recurring
    submitter passes empty defaults so the trainer captures whatever the
    feature pipeline has materialised; the retraining launcher overrides
    with a rolling N-day window when invoked via Argo Workflow.
    """
    client = clickhouse_connect.get_client(
        host=Config.CLICKHOUSE_HOST,
        port=Config.CLICKHOUSE_PORT,
        database=Config.CLICKHOUSE_DB,
        username=Config.CLICKHOUSE_USER,
        password=Config.CLICKHOUSE_PASSWORD,
    )

    where_clauses = [f"symbol = '{symbol}'"]
    if start:
        where_clauses.append(f"timestamp >= '{start}'")
    if end:
        where_clauses.append(f"timestamp <= '{end}'")
    where_sql = " AND ".join(where_clauses)

    query = f"""
    SELECT *
    FROM {Config.FEATURES_TABLE}
    WHERE {where_sql}
    ORDER BY timestamp
    """

    df = client.query_df(query)
    df = df.ffill().fillna(0)
    logger.info(
        "Loaded %d rows for %s (window=[%s, %s])",
        len(df), symbol, start or "-inf", end or "+inf",
    )
    return df


# ── Training ────────────────────────────────────────────────────────────

def train(symbol: str, df: pd.DataFrame) -> dict:
    """Run FLAML AutoML and log results to MLflow."""
    mlflow.set_tracking_uri(Config.MLFLOW_URI)
    mlflow.set_experiment(Config.EXPERIMENT)

    task_type = FLAMLConfig.TASK_TYPE
    trainer = Trainer(df)

    # Prepare data based on task type
    if task_type == "regression":
        x_train, x_val, y_train, y_val = trainer.prepare_regression_data()
    else:
        x_train, x_val, y_train, y_val = trainer.prepare_classification_data()

    feature_cols = trainer.feature_cols
    flaml_task = "regression" if task_type == "regression" else "classification"

    # Convert to DataFrames (FLAML works best with named columns)
    x_train_df = pd.DataFrame(x_train, columns=feature_cols)
    x_val_df = pd.DataFrame(x_val, columns=feature_cols)

    logger.info(
        "FLAML AutoML: task=%s, time_budget=%ds, estimators=%s, "
        "train=%d, val=%d, features=%d",
        flaml_task,
        FLAMLConfig.TIME_BUDGET,
        FLAMLConfig.estimator_list(),
        len(x_train),
        len(x_val),
        len(feature_cols),
    )

    # ── Run FLAML AutoML ──────────────────────────────────────────────
    automl = AutoML()

    fit_kwargs = {
        "X_train": x_train_df,
        "y_train": y_train,
        "X_val": x_val_df,
        "y_val": y_val,
        "task": flaml_task,
        "time_budget": FLAMLConfig.TIME_BUDGET,
        "estimator_list": FLAMLConfig.estimator_list(),
        "seed": FLAMLConfig.SEED,
        "n_splits": FLAMLConfig.N_SPLITS,
        "early_stop": FLAMLConfig.EARLY_STOP,
        "ensemble": FLAMLConfig.ENSEMBLE,
        "verbose": FLAMLConfig.LOG_LEVEL,
    }
    if FLAMLConfig.MAX_ITER is not None:
        fit_kwargs["max_iter"] = FLAMLConfig.MAX_ITER
    if FLAMLConfig.metric() is not None:
        fit_kwargs["metric"] = FLAMLConfig.metric()

    automl.fit(**fit_kwargs)

    best_estimator = automl.best_estimator
    logger.info(
        "FLAML result: best=%s, configs_tried=%d, best_loss=%.6f, config=%s",
        best_estimator,
        len(automl.config_history),
        automl.best_loss,
        automl.best_config,
    )

    # ── Evaluate on validation set ────────────────────────────────────
    y_pred = automl.predict(x_val_df)

    if task_type == "regression":
        metrics = {
            "rmse": float(np.sqrt(mean_squared_error(y_val, y_pred))),
            "mae": float(mean_absolute_error(y_val, y_pred)),
            "r2": float(r2_score(y_val, y_pred)),
        }
    else:
        metrics = {
            "accuracy": float(accuracy_score(y_val, y_pred)),
            "f1_score": float(f1_score(y_val, y_pred, average="weighted")),
            "precision": float(precision_score(y_val, y_pred, average="weighted")),
            "recall": float(recall_score(y_val, y_pred, average="weighted")),
        }

    # ── Log to MLflow ─────────────────────────────────────────────────
    with mlflow.start_run(run_name=f"{symbol}_flaml_{best_estimator}"):
        _log_model_to_mlflow(automl)

        for k, v in metrics.items():
            mlflow.log_metric(k, v)
            # Print in Katib-compatible format
            print(f"{k}={v:.6f}")

        mlflow.log_param("symbol", symbol)
        mlflow.log_param("task_type", task_type)
        mlflow.log_param("framework", "flaml")
        mlflow.log_param("flaml_best_estimator", best_estimator)
        mlflow.log_param("flaml_best_loss", automl.best_loss)
        mlflow.log_param("flaml_configs_tried", len(automl.config_history))
        mlflow.log_param("flaml_time_budget", FLAMLConfig.TIME_BUDGET)
        mlflow.log_param("samples", len(df))
        mlflow.log_param("features", len(feature_cols))

        # Log best config as params
        for k, v in automl.best_config.items():
            mlflow.log_param(f"best_{k}", v)

        # Log feature importances if available
        model = automl.model.estimator if hasattr(automl.model, "estimator") else automl.model
        if hasattr(model, "feature_importances_"):
            importances = dict(zip(feature_cols, model.feature_importances_, strict=False))
            top_features = sorted(importances.items(), key=lambda x: x[1], reverse=True)[:20]
            for fname, fimp in top_features:
                mlflow.log_metric(f"importance_{fname}", float(fimp))

    return metrics


# ── Entry point ─────────────────────────────────────────────────────────

def main() -> None:
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="FLAML AutoML Trainer")
    parser.add_argument("--train-all", action="store_true", help="Train all VALID_SYMBOLS")
    parser.add_argument("--symbol", type=str, default=None, help="Train specific symbol")
    args = parser.parse_args()

    start_date = os.getenv("START_DATE", "2025-01-01")
    end_date = os.getenv("END_DATE", "2025-12-31")

    if args.train_all:
        symbols_env = os.getenv("VALID_SYMBOLS", "")
        symbols = [s.strip() for s in symbols_env.split(",") if s.strip()]
        if not symbols:
            symbols = [os.getenv("SYMBOL", "SAMPLE-001")]
    elif args.symbol:
        symbols = [args.symbol]
    else:
        symbols = [os.getenv("SYMBOL", "SAMPLE-001")]

    logger.info("Training symbols: %s, window: %s to %s", symbols, start_date, end_date)

    # Collect failures, then exit non-zero at the end. We avoid raising mid-loop
    # so a single bad symbol doesn't skip the rest, but we MUST surface failure
    # to the orchestrator (KFP / Workflow) — silent exit-0 lets cached
    # Succeeded shells block downstream "Experiment not found" diagnosis.
    failures: list[str] = []
    for symbol in symbols:
        logger.info("Training for %s", symbol)
        with TRAIN_DURATION.time():
            TRAIN_COUNTER.inc()
            try:
                df = load_data(symbol, start_date, end_date)
                if len(df) < 50:
                    failures.append(
                        f"{symbol}: insufficient data ({len(df)} rows, need >= 50)"
                    )
                    logger.error(
                        "Insufficient data for %s (%d rows, need >= 50)",
                        symbol,
                        len(df),
                    )
                    continue
                results = train(symbol, df)
                logger.info("Training complete for %s: %s", symbol, results)
            except Exception as e:
                failures.append(f"{symbol}: {e}")
                logger.exception("Training failed for %s", symbol)

    if failures:
        logger.error(
            "Training run failed for %d/%d symbol(s): %s",
            len(failures),
            len(symbols),
            "; ".join(failures),
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
