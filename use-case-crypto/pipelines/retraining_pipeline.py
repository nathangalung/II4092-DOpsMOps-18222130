"""
KFP v2 Retraining Pipeline — Drift Detection → FLAML AutoML → Deploy to KServe.

Integration:
  Kubeflow Pipelines  — orchestrates the pipeline as Argo Workflows
  FLAML AutoML        — automatic model selection (LightGBM, XGBoost, CatBoost, RF, etc.)
  MLflow              — experiment tracking + model artifact storage (MinIO S3)
  KServe              — model serving via kserve-mlflowserver (mlflow format, model-agnostic)

Usage:
  uv run --with 'kfp[kubernetes]==2.16.0' retraining_pipeline.py     # compile
  uv run --with 'kfp[kubernetes]==2.16.0' submit_recurring.py        # submit recurring runs

The `[kubernetes]` extra ships `kfp.kubernetes` (imported above) — without it,
`from kfp import kubernetes` fails at module load. Version is pinned to match
the kfp-launcher / kfp-driver image deployed by platform/.../pipelines.yaml so
the compiled spec stays compatible with what runs it.

Notes on container_component:
  KFP v2 container_component passes args as positional parameters to `sh -c`.
  In `sh -c 'script' arg0 arg1 ...`, arg0=$0, arg1=$1 inside the script.
  This avoids the ConcatPlaceholder bug where JSON is passed as literal strings.
"""

import os

from kfp import compiler, dsl, kubernetes

# =============================================================================
# USE_CASE master-knob (matches DAG pattern in dags/crypto_*.py).
# Compile-time env vars; the compiled pipeline YAML bakes them in, so re-run
# `kfp compile` after changing USE_CASE / USE_CASE_REGISTRY / USE_CASE_IMAGE_TAG.
# Defaults keep the local overlay (k3d-registry) working with no env exports.
# =============================================================================
USE_CASE = os.getenv("USE_CASE", "crypto")
REGISTRY = os.getenv("USE_CASE_REGISTRY", "localhost:5000")
IMAGE_PREFIX = os.getenv("USE_CASE_IMAGE_PREFIX", USE_CASE)
IMAGE_TAG = os.getenv("USE_CASE_IMAGE_TAG", "latest")
NAMESPACE = os.getenv("USE_CASE_NAMESPACE", f"use-case-{USE_CASE}")


def _image(name: str) -> str:
    return f"{REGISTRY}/{IMAGE_PREFIX}-{name}:{IMAGE_TAG}"


# =============================================================================
# Step 1: Drift Detection
# =============================================================================
@dsl.container_component
def detect_drift(
    clickhouse_host: str,
    clickhouse_port: str,
    clickhouse_db: str,
    features_table: str,
    drift_threshold: float,
    drift_features: str,
    valkey_host: str,
):
    """Run drift detection against ClickHouse feature data."""
    return dsl.ContainerSpec(
        image=_image("drift-detector"),
        command=["sh", "-c"],
        args=[
            # $0=CH_HOST $1=CH_PORT $2=CH_DB $3=TABLE $4=REDIS $5=THRESHOLD $6=FEATURES
            'export CLICKHOUSE_HOST="$0" '
            'CLICKHOUSE_PORT="$1" '
            'CLICKHOUSE_DB="$2" '
            'CLICKHOUSE_TABLE="$3" '
            'VALKEY_HOST="$4" '
            'DRIFT_THRESHOLD="$5" '
            'DRIFT_FEATURES_TO_MONITOR="$6" '
            "&& python main.py --scale daily --once",
            clickhouse_host,
            clickhouse_port,
            clickhouse_db,
            features_table,
            valkey_host,
            drift_threshold,
            drift_features,
        ],
    )


# =============================================================================
# Step 2: FLAML AutoML Training → MLflow
# =============================================================================
@dsl.container_component
def train_and_register(
    symbol: str,
    task_type: str,
    target_column: str,
    features_table: str,
    start_date: str,
    end_date: str,
    flaml_time_budget: str,
    flaml_estimator_list: str,
    clickhouse_host: str,
    clickhouse_port: str,
    clickhouse_db: str,
    mlflow_tracking_uri: str,
    mlflow_experiment: str,
    mlflow_s3_endpoint_url: str,
    s3_access_key_id: str,
    s3_secret_access_key: str,
):
    """Run FLAML AutoML training, log model + metrics to MLflow."""
    return dsl.ContainerSpec(
        image=_image("trainer"),
        command=["sh", "-c"],
        args=[
            # Positional: $0=SYMBOL $1=TASK $2=TARGET $3=TABLE $4=START $5=END
            #   $6=BUDGET $7=ESTIMATORS $8=CH_HOST $9=CH_PORT
            # Shift trick: after consuming $0-$8 via shift 9, remaining become $1+
            'export SYMBOL="$0" '
            'VALID_SYMBOLS="$0" '
            'TASK_TYPE="$1" '
            'TARGET_COLUMN="$2" '
            'FEATURES_TABLE="$3" '
            'START_DATE="$4" '
            'END_DATE="$5" '
            'FLAML_TIME_BUDGET="$6" '
            'FLAML_ESTIMATOR_LIST="$7" '
            'CLICKHOUSE_HOST="$8" '
            'CLICKHOUSE_PORT="$9" '
            "&& shift 10 "
            '&& export CLICKHOUSE_DB="$0" '
            'MLFLOW_TRACKING_URI="$1" '
            'MLFLOW_EXPERIMENT="$2" '
            'MLFLOW_S3_ENDPOINT_URL="$3" '
            'AWS_ACCESS_KEY_ID="$4" '
            'AWS_SECRET_ACCESS_KEY="$5" '
            '&& python main.py --symbol "$SYMBOL"',
            symbol,
            task_type,
            target_column,
            features_table,
            start_date,
            end_date,
            flaml_time_budget,
            flaml_estimator_list,
            clickhouse_host,
            clickhouse_port,
            clickhouse_db,
            mlflow_tracking_uri,
            mlflow_experiment,
            mlflow_s3_endpoint_url,
            s3_access_key_id,
            s3_secret_access_key,
        ],
    )


# =============================================================================
# Step 3: Deploy to KServe (mlflow format — model-agnostic)
# =============================================================================
@dsl.container_component
def deploy_to_kserve(
    model_name: str,
    namespace: str,
    mlflow_tracking_uri: str,
    mlflow_experiment: str,
    mlflow_s3_endpoint_url: str,
    s3_access_key_id: str,
    s3_secret_access_key: str,
):
    """Query MLflow for latest run, patch KServe InferenceService.

    Uses deploy_kserve.py script baked into the trainer image —
    proper error handling, logging, and no shell escaping issues.
    """
    return dsl.ContainerSpec(
        image=_image("trainer"),
        command=["sh", "-c"],
        args=[
            # $0=MODEL $1=NS $2=MLFLOW_URI $3=EXPERIMENT $4=S3_URL $5=KEY $6=SECRET
            'export MLFLOW_TRACKING_URI="$2" '
            'MLFLOW_S3_ENDPOINT_URL="$4" '
            'AWS_ACCESS_KEY_ID="$5" '
            'AWS_SECRET_ACCESS_KEY="$6" '
            '&& python src/deploy_kserve.py '
            '--model-name "$0" '
            '--namespace "$1" '
            '--experiment "$3"',
            model_name,
            namespace,
            mlflow_tracking_uri,
            mlflow_experiment,
            mlflow_s3_endpoint_url,
            s3_access_key_id,
            s3_secret_access_key,
        ],
    )


# =============================================================================
# Pipeline
# =============================================================================
@dsl.pipeline(
    name=f"{USE_CASE}-retraining-pipeline",
    description=(
        "Drift detection → FLAML AutoML → MLflow → KServe. "
        "Model selection controlled via FLAML_ESTIMATOR_LIST config."
    ),
)
def retraining_pipeline(
    symbol: str = "BTC-USD",
    task_type: str = "regression",
    target_column: str = "close",
    features_table: str = "gold.fct_training_data",
    # start_date is overridden by the retraining launcher
    # (services/retraining/app.py) to a rolling N-day window; the
    # value below is only used for manual one-off compile+submit runs.
    start_date: str = "",
    end_date: str = "",  # empty = use current timestamp (auto-expanding window)
    drift_threshold: float = 0.20,
    drift_features: str = "close,volume,sma_20,sma_50,return_1h,return_24h,volatility_24h",
    flaml_time_budget: str = "300",
    flaml_estimator_list: str = "lgbm,xgboost,catboost,rf,extra_tree,elastic_net,sgd",
    clickhouse_host: str = "clickhouse-platform.storage.svc.cluster.local",
    clickhouse_port: str = "8123",
    clickhouse_db: str = "gold",
    valkey_host: str = "valkey.storage.svc.cluster.local",
    mlflow_tracking_uri: str = "http://mlflow.model-lifecycle.svc.cluster.local:5000",
    mlflow_experiment: str = f"{USE_CASE}-default",
    mlflow_s3_endpoint_url: str = "http://minio.storage.svc.cluster.local:9000",
    s3_access_key_id: str = "",
    s3_secret_access_key: str = "",
    kserve_namespace: str = NAMESPACE,
):
    # Step 1: Drift detection
    drift_task = detect_drift(
        clickhouse_host=clickhouse_host,
        clickhouse_port=clickhouse_port,
        clickhouse_db=clickhouse_db,
        features_table=features_table,
        drift_threshold=drift_threshold,
        drift_features=drift_features,
        valkey_host=valkey_host,
    )
    # ClickHouse basic-auth creds for drift-detector + Valkey AUTH password.
    # The CHI installation.yaml seeds `users.default.password_sha256_hex`, so
    # clickhouse_connect (http) demands a password; without these env vars
    # the pod exits with Code: 194 ("Authentication failed: password is
    # incorrect, or there is no user with such name"). Source secret keys
    # are declared by use-case-crypto/manifests/base/external-secrets.yaml
    # (pipeline-secrets ExternalSecret, properties:
    # CLICKHOUSE_USER / CLICKHOUSE_PASSWORD / VALKEY_PASSWORD).
    kubernetes.use_secret_as_env(
        drift_task,
        secret_name="pipeline-secrets",
        secret_key_to_env={
            "CLICKHOUSE_USER": "CLICKHOUSE_USER",
            "CLICKHOUSE_PASSWORD": "CLICKHOUSE_PASSWORD",
            "VALKEY_PASSWORD": "VALKEY_PASSWORD",
        },
    )
    # Drift signal changes per run — never reuse a cached Succeeded shell.
    drift_task.set_caching_options(enable_caching=False)

    # Step 2: FLAML AutoML training → MLflow
    train_task = train_and_register(
        symbol=symbol,
        task_type=task_type,
        target_column=target_column,
        features_table=features_table,
        start_date=start_date,
        end_date=end_date,
        flaml_time_budget=flaml_time_budget,
        flaml_estimator_list=flaml_estimator_list,
        clickhouse_host=clickhouse_host,
        clickhouse_port=clickhouse_port,
        clickhouse_db=clickhouse_db,
        mlflow_tracking_uri=mlflow_tracking_uri,
        mlflow_experiment=mlflow_experiment,
        mlflow_s3_endpoint_url=mlflow_s3_endpoint_url,
        s3_access_key_id=s3_access_key_id,
        s3_secret_access_key=s3_secret_access_key,
    )
    train_task.after(drift_task)
    # Trainer reads gold.fct_training_data via clickhouse_connect — same
    # ClickHouse default user with sha256 password as drift_task above.
    # MLflow server has no basic-auth (mlflow-config carries only S3 +
    # HOST/PORT/ARTIFACT vars), so we deliberately do NOT mount
    # MLFLOW_TRACKING_PASSWORD — the mlflow client would otherwise send
    # an Authorization header with an empty username and 401.
    kubernetes.use_secret_as_env(
        train_task,
        secret_name="pipeline-secrets",
        secret_key_to_env={
            "CLICKHOUSE_USER": "CLICKHOUSE_USER",
            "CLICKHOUSE_PASSWORD": "CLICKHOUSE_PASSWORD",
        },
    )
    # KFP v2 defaults enableCache=true — a previously-Succeeded train shell
    # (e.g. silent exit-0 from <50-row dataset) would otherwise be reused on
    # the next workflow run, skipping the impl pod and never writing to
    # MLflow. Deploy then fresh-fails with "Experiment '<usecase>-default' not
    # found". Disable caching so every retrain attempt actually runs train.
    train_task.set_caching_options(enable_caching=False)

    # Step 3: Deploy to KServe (mlflow format)
    deploy_task = deploy_to_kserve(
        model_name=f"{USE_CASE}-predictor",
        namespace=kserve_namespace,
        mlflow_tracking_uri=mlflow_tracking_uri,
        mlflow_experiment=mlflow_experiment,
        mlflow_s3_endpoint_url=mlflow_s3_endpoint_url,
        s3_access_key_id=s3_access_key_id,
        s3_secret_access_key=s3_secret_access_key,
    )
    deploy_task.after(train_task)
    # Deploy mutates a live InferenceService — never cache the result.
    deploy_task.set_caching_options(enable_caching=False)


if __name__ == "__main__":
    compiler.Compiler().compile(
        retraining_pipeline,
        "retraining_pipeline.yaml",
    )
    print("Pipeline compiled to retraining_pipeline.yaml")
