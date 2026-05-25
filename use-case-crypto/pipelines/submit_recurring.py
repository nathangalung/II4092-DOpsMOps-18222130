"""
Submit FLAML AutoML retraining pipeline as recurring runs to Kubeflow Pipelines.

Creates two scheduled runs:
  1. Weekly full training — Sundays 2AM
  2. 6-hourly drift-triggered retraining

Also uploads the compiled pipeline as a named KFP Pipeline resource so the
Argo CronWorkflow `retrain-on-drift` can resolve its UUID at trigger time
(see manifests/base/workflows/retrain-on-drift.yaml). Upload is idempotent —
existing pipeline of the same display_name is reused; a new pipeline_version
is created on bytes-change.

All config is read from env vars (set by pipeline-config ConfigMap).

Usage:
  cd use-case-crypto
  uv run --with 'kfp[kubernetes]==2.16.0' pipelines/submit_recurring.py

The `[kubernetes]` extra is required because this module imports
retraining_pipeline.py, which does `from kfp import kubernetes` to declare
`use_secret_as_env` mounts on the drift + train tasks. Pin matches the
kfp-launcher/driver image deployed at platform/.../pipelines.yaml.
"""

import os
import time

import kfp
from retraining_pipeline import retraining_pipeline

KFP_HOST = os.getenv(
    "KFP_HOST",
    "http://ml-pipeline.model-lifecycle.svc.cluster.local:8888",
)

# USE_CASE master-knob — derives experiment + recurring-job names so cloning
# to a new use-case requires no body edits, only env exports / ConfigMap edits.
USE_CASE = os.getenv("USE_CASE", "crypto")
PIPELINE_DISPLAY_NAME = os.getenv(
    "KFP_PIPELINE_DISPLAY_NAME", f"{USE_CASE}-retraining_pipeline"
)

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


def upload_or_replace_pipeline(client: kfp.Client, pipeline_path: str) -> str:
    """Idempotent upload — reuse existing pipeline_id, push new version on change.

    Returns the pipeline_id UUID so retrain-on-drift can reference it via
    pipeline_version_reference at trigger time.
    """
    existing = client.list_pipelines(
        filter=(
            '{"predicates":[{"operation":"EQUALS","key":"display_name",'
            f'"stringValue":"{PIPELINE_DISPLAY_NAME}"}}]}}'
        )
    )
    pipelines = getattr(existing, "pipelines", None) or []
    if pipelines:
        pipeline_id = pipelines[0].pipeline_id
        version_name = f"v{int(time.time())}"
        client.upload_pipeline_version(
            pipeline_package_path=pipeline_path,
            pipeline_version_name=version_name,
            pipeline_id=pipeline_id,
            description=f"Auto-uploaded by submit_recurring.py @ {version_name}",
        )
        print(f"Pipeline updated: {PIPELINE_DISPLAY_NAME} ({pipeline_id}) -> {version_name}")
        return pipeline_id

    uploaded = client.upload_pipeline(
        pipeline_package_path=pipeline_path,
        pipeline_name=PIPELINE_DISPLAY_NAME,
        description=(
            f"{USE_CASE} retraining pipeline — FLAML AutoML on ClickHouse "
            f"gold.fct_training_data, MLflow registry, Feast online sync."
        ),
    )
    pipeline_id = uploaded.pipeline_id
    print(f"Pipeline uploaded: {PIPELINE_DISPLAY_NAME} ({pipeline_id})")
    return pipeline_id


def upsert_recurring_run(
    client: kfp.Client,
    *,
    experiment_id: str,
    job_name: str,
    pipeline_path: str,
    cron_expression: str,
    params: dict,
    service_account: str,
) -> None:
    """Idempotent recurring-run create — delete prior copies, then create.

    KFP backend allows multiple recurring runs with identical display_name
    and embeds the pipeline_spec at create time (frozen — uploading a new
    pipeline version does NOT update existing recurring runs). Without this
    delete-before-create, repeat invocations leak stale recurring runs that
    keep firing workflows against the old IR (e.g. lacking secretAsEnv
    additions).
    """
    existing = client.list_recurring_runs(
        filter=(
            '{"predicates":[{"operation":"EQUALS","key":"display_name",'
            f'"stringValue":"{job_name}"}}]}}'
        )
    )
    for rr in getattr(existing, "recurring_runs", None) or []:
        client.delete_recurring_run(rr.recurring_run_id)
        print(f"Deleted stale recurring run: {job_name} ({rr.recurring_run_id})")
    client.create_recurring_run(
        experiment_id=experiment_id,
        job_name=job_name,
        pipeline_package_path=pipeline_path,
        cron_expression=cron_expression,
        params=params,
        enabled=True,
        service_account=service_account,
    )
    print(f"Created: {job_name} (cron={cron_expression!r})")


def main() -> None:
    client = kfp.Client(host=KFP_HOST)

    pipeline_path = "/tmp/retraining_pipeline.yaml"
    kfp.compiler.Compiler().compile(retraining_pipeline, pipeline_path)

    pipeline_id = upload_or_replace_pipeline(client, pipeline_path)

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

    # KFP server defaults `service_account=default-editor` (Kubeflow profile
    # convention). We don't deploy Kubeflow profiles on this single-node setup,
    # so explicitly bind both recurring runs to the `pipeline-runner` SA which
    # already has the KFP-runner ClusterRoleBinding (see manifests/base/rbac/
    # kfp-runner.yaml). Without this every ScheduledWorkflow firing dies with
    # `serviceaccount "default-editor" not found` at root-driver pod creation.
    sa = "pipeline-runner"

    # Weekly full training — Sundays 2:01 AM UTC
    upsert_recurring_run(
        client,
        experiment_id=experiment.experiment_id,
        job_name=weekly_job,
        pipeline_path=pipeline_path,
        cron_expression="1 2 * * 7",
        params=common_params,
        service_account=sa,
    )

    # Drift-triggered retraining — every 6 hours
    upsert_recurring_run(
        client,
        experiment_id=experiment.experiment_id,
        job_name=drift_job,
        pipeline_path=pipeline_path,
        cron_expression="1 */6 * * *",
        params={**common_params, "drift_threshold": DRIFT_THRESHOLD},
        service_account=sa,
    )
    print(f"PIPELINE_ID={pipeline_id}  EXPERIMENT_ID={experiment.experiment_id}")


if __name__ == "__main__":
    main()
