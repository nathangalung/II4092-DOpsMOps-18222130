"""Crypto-specific prediction service — uses predicted_price and signal fields."""

import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

INFERENCE_URL = os.getenv("INFERENCE_URL", "http://crypto-predictor-predictor.use-case-crypto.svc.cluster.local")


class PredictionRequest(BaseModel):
    """Prediction request model."""

    symbol: str
    features: dict[str, Any]


class PredictionResponse(BaseModel):
    """Crypto prediction response with trading signal."""

    symbol: str
    predicted_price: float
    signal: str
    confidence: float
    model_version: str


@router.post("/predict")
async def predict(request: PredictionRequest) -> PredictionResponse:
    """Get prediction for symbol."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                f"{INFERENCE_URL}/predict",
                json=request.model_dump(),
                timeout=10.0,
            )
            resp.raise_for_status()
            return PredictionResponse(**resp.json())
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e


@router.get("/latest")
async def get_latest(symbol: str | None = None) -> dict[str, Any]:
    """Get latest predictions."""
    async with httpx.AsyncClient() as client:
        try:
            params = {"symbol": symbol} if symbol else {}
            resp = await client.get(
                f"{INFERENCE_URL}/predictions/latest",
                params=params,
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e


@router.get("/history/{symbol}")
async def get_history(symbol: str, limit: int = 100) -> dict[str, Any]:
    """Get prediction history for symbol."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(
                f"{INFERENCE_URL}/predictions/{symbol}",
                params={"limit": limit},
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=str(e)) from e
