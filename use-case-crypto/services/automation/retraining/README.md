# crypto-retraining

Drift-triggered KFP retraining launcher.  Invoked by Airflow task
`trigger_retrain_if_drift` in `dags/crypto_data_pipeline.py`.

## Inputs (env)

| Name | Default |
|---|---|
| `REDIS_URL` | `redis://redis.storage.svc.cluster.local:6379/0` |
| `KFP_HOST` | `http://ml-pipeline.model-lifecycle.svc.cluster.local:8888` |
| `MLFLOW_TRACKING_URI` | `http://mlflow.model-lifecycle.svc.cluster.local:5000` |
| `PIPELINE_PATH` | `/app/pipelines/retraining_pipeline.yaml` (baked in image) |
| `SYMBOL` | `BTC-USD` |
| `TRAINING_TABLE` | `gold.fct_training_data` |
| `KFP_EXPERIMENT` | `crypto-retraining` |

## Flow

1. Drift detector writes `crypto:drift:triggered=1` to Redis on detection.
2. Airflow calls this container with `--check-and-retrain`.
3. Script submits KFP run, blocks until terminal state.
4. On SUCCEEDED, clears the flag.  On FAILED, leaves the flag so the next
   scheduled DAG run will retry.

## Image build

Built by the Tekton `crypto-build-pipeline` from
`use-case-crypto/Dockerfile`-prefixed tag pushed as
`localhost:5000/crypto-retraining:${TAG}`.
