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
     the storageUri change - so the rest of the spec stays under the
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


def resolve_latest_model_uri(experiment_name: str) -> str:
    """Resolve the S3 artifact URI of the latest logged model in an experiment.

    MLflow 3.x stores model artifacts under
    ``{artifact_root}/{experiment_id}/models/{model_id}/artifacts`` - NOT the
    2.x ``{run_id}/artifacts/{path}`` layout the previous version constructed
    (that path simply does not exist in MinIO under MLflow 3.x, so the
    storage-initializer would find nothing and the InferenceService never went
    Ready). We query the logged-models API and use the model's own
    ``artifact_location`` when it is already an ``s3://`` URI; otherwise we
    reconstruct the 3.x path from experiment_id + model_id under the configured
    S3 artifact bucket. KServe's storage-initializer pulls this directory (it
    holds ``MLmodel`` + ``model.pkl``); a trailing slash is required.
    """
    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    experiment = mlflow.get_experiment_by_name(experiment_name)
    if experiment is None:
        logger.error("Experiment '%s' not found in MLflow", experiment_name)
        sys.exit(1)

    models = mlflow.search_logged_models(
        experiment_ids=[experiment.experiment_id],
        order_by=[{"field_name": "creation_time", "ascending": False}],
        max_results=1,
        output_format="list",
    )
    if not models:
        logger.error("No logged models in experiment '%s'", experiment_name)
        sys.exit(1)

    model = models[0]
    loc = (getattr(model, "artifact_location", "") or "").rstrip("/")
    if loc.startswith("s3://"):
        storage_uri = loc + "/"
    else:
        bucket = os.getenv("MLFLOW_ARTIFACT_BUCKET", "mlflow")
        storage_uri = (
            f"s3://{bucket}/artifacts/{experiment.experiment_id}"
            f"/models/{model.model_id}/artifacts/"
        )
    logger.info(
        "Latest logged model: id=%s source_run=%s status=%s → %s",
        model.model_id,
        getattr(model, "source_run_id", "?"),
        getattr(model, "status", "?"),
        storage_uri,
    )
    return storage_uri


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
    storage_uri = resolve_latest_model_uri(experiment_name)
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
