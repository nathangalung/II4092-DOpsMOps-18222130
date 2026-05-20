"""Metrics service for MLflow and monitoring."""

import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

MLFLOW_URL = os.getenv("MLFLOW_TRACKING_URI", "http://mlflow:5000")


class ModelMetrics(BaseModel):
    """Model metrics response."""

    model_name: str
    version: str
    accuracy: float | None = None
    precision: float | None = None
    recall: float | None = None
    f1_score: float | None = None
    mae: float | None = None
    rmse: float | None = None


@router.get("/models")
async def list_models() -> dict[str, Any]:
    """List registered models."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(
                f"{MLFLOW_URL}/api/2.0/mlflow/registered-models/list",
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e


@router.get("/models/{name}")
async def get_model(name: str) -> dict[str, Any]:
    """Get model details."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(
                f"{MLFLOW_URL}/api/2.0/mlflow/registered-models/get",
                params={"name": name},
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e


@router.get("/models/{name}/metrics")
async def get_model_metrics(name: str, version: str | None = None) -> ModelMetrics:
    """Get model metrics from MLflow."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(
                f"{MLFLOW_URL}/api/2.0/mlflow/registered-models/get",
                params={"name": name},
                timeout=10.0,
            )
            resp.raise_for_status()
            data = resp.json()

            model = data.get("registered_model", {})
            versions = model.get("latest_versions", [])

            if not versions:
                raise HTTPException(status_code=404, detail="No versions found")

            target_version = versions[0]
            if version:
                for v in versions:
                    if v.get("version") == version:
                        target_version = v
                        break

            run_id = target_version.get("run_id")
            if run_id:
                metrics_resp = await client.get(
                    f"{MLFLOW_URL}/api/2.0/mlflow/runs/get",
                    params={"run_id": run_id},
                    timeout=10.0,
                )
                metrics_resp.raise_for_status()
                run_data = metrics_resp.json()
                metrics = run_data.get("run", {}).get("data", {}).get("metrics", [])

                metrics_dict = {m["key"]: m["value"] for m in metrics}

                return ModelMetrics(
                    model_name=name,
                    version=target_version.get("version", "unknown"),
                    accuracy=metrics_dict.get("accuracy"),
                    precision=metrics_dict.get("precision"),
                    recall=metrics_dict.get("recall"),
                    f1_score=metrics_dict.get("f1_score"),
                    mae=metrics_dict.get("mae"),
                    rmse=metrics_dict.get("rmse"),
                )

            return ModelMetrics(
                model_name=name,
                version=target_version.get("version", "unknown"),
            )
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e


@router.get("/experiments")
async def list_experiments() -> dict[str, Any]:
    """List MLflow experiments."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(
                f"{MLFLOW_URL}/api/2.0/mlflow/experiments/search",
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e
