"""
Deploy a trained MLflow-format model to an existing KServe InferenceService.

This script does NOT create or re-declare the InferenceService; GitOps
(ArgoCD applying the use-case's base manifests) owns the spec, labels,
serviceAccountName, and resources. This script is the ONLY hand-off
between the training pipeline and the serving plane, and it touches
exactly one field: ``spec.predictor.model.storageUri``.

Flow:
  1. Query MLflow for the latest FINISHED run in the given experiment.
  2. Build the s3:// artifact URI for that run's model subdir.
  3. Send a JSON Merge Patch to the InferenceService containing only
     the storageUri change — so the rest of the spec stays under the
     sole ownership of the GitOps-applied manifest.

If the InferenceService does not exist yet the script fails loudly
rather than creating it out of band: that's a GitOps sync issue and
must be resolved by ArgoCD, not by the pipeline.

Usage (generic; use-case substitutes its own values):
  uv run src/deploy_kserve.py \\
    --model-name <inferenceservice-name> \\
    --namespace  <use-case-namespace> \\
    --experiment <mlflow-experiment-name>
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time

import kubernetes
import mlflow

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def get_latest_run(experiment_name: str) -> tuple[str, str]:
    """Return (experiment_id, run_id) for the latest FINISHED MLflow run."""
    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    experiment = mlflow.get_experiment_by_name(experiment_name)
    if experiment is None:
        logger.error("Experiment '%s' not found in MLflow", experiment_name)
        sys.exit(1)

    runs = mlflow.search_runs(
        experiment_ids=[experiment.experiment_id],
        filter_string="status = 'FINISHED'",
        max_results=1,
        order_by=["start_time DESC"],
    )

    if len(runs) == 0:
        logger.error("No successful runs in experiment '%s'", experiment_name)
        sys.exit(1)

    run_id = runs.iloc[0]["run_id"]
    estimator = runs.iloc[0].get("params.flaml_best_estimator", "unknown")
    metrics = {
        k.replace("metrics.", ""): v
        for k, v in runs.iloc[0].items()
        if k.startswith("metrics.")
    }
    logger.info(
        "Latest run: experiment_id=%s run_id=%s estimator=%s metrics=%s",
        experiment.experiment_id,
        run_id,
        estimator,
        metrics,
    )
    return experiment.experiment_id, run_id


def patch_storage_uri(
    model_name: str,
    namespace: str,
    storage_uri: str,
    retries: int = 5,
    backoff_seconds: float = 3.0,
) -> None:
    """Patch only ``spec.predictor.model.storageUri`` on the InferenceService.

    Uses JSON Merge Patch so fields owned by the GitOps manifest
    (serviceAccountName, labels, resources, …) remain untouched.
    """
    kubernetes.config.load_incluster_config()
    api = kubernetes.client.CustomObjectsApi()

    body = {
        "spec": {
            "predictor": {
                "model": {"storageUri": storage_uri},
            },
        },
    }

    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            api.patch_namespaced_custom_object(
                group="serving.kserve.io",
                version="v1beta1",
                namespace=namespace,
                plural="inferenceservices",
                name=model_name,
                body=body,
            )
            logger.info(
                "Patched InferenceService '%s/%s' storageUri → %s",
                namespace,
                model_name,
                storage_uri,
            )
            return
        except kubernetes.client.exceptions.ApiException as exc:
            last_error = exc
            if exc.status == 404:
                logger.error(
                    "InferenceService '%s/%s' not found. "
                    "This script only patches an already-synced manifest — "
                    "ensure ArgoCD has reconciled the use-case base layer first.",
                    namespace,
                    model_name,
                )
                sys.exit(2)
            if exc.status in (409, 500, 502, 503, 504) and attempt < retries:
                logger.warning(
                    "Transient API error (status=%s) on attempt %s/%s — retrying in %ss",
                    exc.status,
                    attempt,
                    retries,
                    backoff_seconds * attempt,
                )
                time.sleep(backoff_seconds * attempt)
                continue
            raise

    if last_error is not None:
        raise last_error


def deploy(model_name: str, namespace: str, experiment_name: str) -> None:
    experiment_id, run_id = get_latest_run(experiment_name)
    storage_uri = f"s3://mlflow/artifacts/{experiment_id}/{run_id}/artifacts/model/"
    logger.info("Deploying model from %s", storage_uri)
    patch_storage_uri(model_name, namespace, storage_uri)


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch KServe InferenceService storageUri")
    parser.add_argument("--model-name", required=True, help="InferenceService name")
    parser.add_argument("--namespace", required=True, help="Target namespace")
    parser.add_argument("--experiment", required=True, help="MLflow experiment name")
    args = parser.parse_args()

    deploy(args.model_name, args.namespace, args.experiment)


if __name__ == "__main__":
    main()
