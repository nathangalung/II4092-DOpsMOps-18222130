"""
Submit FLAML AutoML retraining pipeline as recurring runs to Kubeflow Pipelines.

Creates two scheduled runs:
  1. Weekly full training — Sundays 2AM
  2. 6-hourly drift-triggered retraining

All config is read from env vars (set by pipeline-config ConfigMap).

Usage:
  cd use-case-crypto
  uv run --with kfp pipelines/submit_recurring.py
"""

import os

import kfp
from retraining_pipeline import retraining_pipeline

KFP_HOST = os.getenv(
    "KFP_HOST",
    "http://ml-pipeline.model-lifecycle.svc.cluster.local:8888",
)

# USE_CASE master-knob — derives experiment + recurring-job names so cloning
# to a new use-case requires no body edits, only env exports / ConfigMap edits.
USE_CASE = os.getenv("USE_CASE", "crypto")

# Config from env (pipeline-config ConfigMap)
SYMBOL = os.getenv("SYMBOL", "BTC-USD")
TASK_TYPE = os.getenv("TASK_TYPE", "regression")
DRIFT_THRESHOLD = float(os.getenv("DRIFT_THRESHOLD", "0.20"))
FLAML_TIME_BUDGET = os.getenv("FLAML_TIME_BUDGET", "300")
FLAML_ESTIMATOR_LIST = os.getenv(
    "FLAML_ESTIMATOR_LIST", "lgbm,xgboost,catboost,rf,extra_tree,elastic_net,sgd"
)
MLFLOW_EXPERIMENT = os.getenv("MLFLOW_EXPERIMENT", f"{USE_CASE}-default")
DRIFT_FEATURES = os.getenv(
    "DRIFT_FEATURES_TO_MONITOR",
    "close,volume,sma_20,sma_50,return_1h,return_24h,volatility_24h",
)

# S3/MinIO credentials
S3_ACCESS_KEY_ID = os.getenv("S3_ACCESS_KEY_ID", os.getenv("AWS_ACCESS_KEY_ID", "minioadmin"))
S3_SECRET_ACCESS_KEY = os.getenv(
    "S3_SECRET_ACCESS_KEY", os.getenv("AWS_SECRET_ACCESS_KEY", "minioadmin123")
)


def main() -> None:
    client = kfp.Client(host=KFP_HOST)

    pipeline_path = "/tmp/retraining_pipeline.yaml"
    kfp.compiler.Compiler().compile(retraining_pipeline, pipeline_path)

    experiment = client.create_experiment(
        name=f"{USE_CASE}-retraining",
        description="FLAML AutoML retraining — drift-triggered and scheduled",
    )

    common_params = {
        "symbol": SYMBOL,
        "task_type": TASK_TYPE,
        "flaml_time_budget": FLAML_TIME_BUDGET,
        "flaml_estimator_list": FLAML_ESTIMATOR_LIST,
        "mlflow_experiment": MLFLOW_EXPERIMENT,
        "clickhouse_db": "gold",
        "features_table": "gold.fct_training_data",
        "drift_features": DRIFT_FEATURES,
        "end_date": "",  # empty = use current timestamp (auto-expanding window)
        "s3_access_key_id": S3_ACCESS_KEY_ID,
        "s3_secret_access_key": S3_SECRET_ACCESS_KEY,
    }

    weekly_job = f"{USE_CASE}-weekly-flaml"
    drift_job = f"{USE_CASE}-drift-flaml"

    # Weekly full training — Sundays 2:01 AM UTC
    client.create_recurring_run(
        experiment_id=experiment.experiment_id,
        job_name=weekly_job,
        pipeline_package_path=pipeline_path,
        cron_expression="1 2 * * 7",
        params=common_params,
        enabled=True,
    )
    print(f"Created: {weekly_job} (Sun 2AM, estimators={FLAML_ESTIMATOR_LIST})")

    # Drift-triggered retraining — every 6 hours
    client.create_recurring_run(
        experiment_id=experiment.experiment_id,
        job_name=drift_job,
        pipeline_package_path=pipeline_path,
        cron_expression="1 */6 * * *",
        params={**common_params, "drift_threshold": DRIFT_THRESHOLD},
        enabled=True,
    )
    print(f"Created: {drift_job} (every 6h, threshold={DRIFT_THRESHOLD})")


if __name__ == "__main__":
    main()
