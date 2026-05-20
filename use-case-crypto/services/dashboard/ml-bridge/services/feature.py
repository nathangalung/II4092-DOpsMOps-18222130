"""Feature service for Feast queries."""

import os
from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

FEAST_REPO = os.getenv("FEAST_REPO_PATH", "/app/feature_store")
FEATURE_VIEW_NAME = os.getenv("FEATURE_VIEW_NAME", "features")


class FeatureRequest(BaseModel):
    """Feature request model."""

    symbol: str
    features: list[str]
    timestamp: datetime | None = None


class FeatureResponse(BaseModel):
    """Feature response model."""

    symbol: str
    timestamp: datetime
    features: dict[str, Any]


@router.post("/online")
async def get_online_features(request: FeatureRequest) -> FeatureResponse:
    """Get online features from Feast."""
    try:
        from feast import FeatureStore

        store = FeatureStore(repo_path=FEAST_REPO)

        entity_rows = [{"symbol": request.symbol}]
        feature_refs = [f"{FEATURE_VIEW_NAME}:{f}" for f in request.features]

        result = store.get_online_features(
            features=feature_refs,
            entity_rows=entity_rows,
        )

        features = result.to_dict()
        return FeatureResponse(
            symbol=request.symbol,
            timestamp=datetime.now(),
            features={k: v[0] for k, v in features.items() if k != "symbol"},
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/definitions")
async def get_feature_definitions() -> dict[str, list[dict[str, Any]]]:
    """Get feature definitions."""
    try:
        from feast import FeatureStore

        store = FeatureStore(repo_path=FEAST_REPO)
        views = store.list_feature_views()

        definitions = []
        for view in views:
            for feature in view.features:
                definitions.append(
                    {
                        "name": feature.name,
                        "view": view.name,
                        "dtype": str(feature.dtype),
                        "tags": dict(view.tags) if view.tags else {},
                    }
                )

        return {"features": definitions}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/latest/{symbol}")
async def get_latest_features(symbol: str) -> dict[str, Any]:
    """Get latest features for symbol.

    Feature list is configured via FEAST_LATEST_FEATURES env var (comma-separated).
    Falls back to discovering all features from the Feast feature view.
    """
    try:
        from feast import FeatureStore

        store = FeatureStore(repo_path=FEAST_REPO)

        # Read feature list from env var (use-case configures this)
        features_env = os.getenv("FEAST_LATEST_FEATURES", "")
        if features_env:
            feature_names = [f.strip() for f in features_env.split(",") if f.strip()]
        else:
            # Auto-discover features from the feature view
            views = store.list_feature_views()
            feature_names = []
            for view in views:
                if view.name == FEATURE_VIEW_NAME:
                    feature_names = [f.name for f in view.features]
                    break

        if not feature_names:
            return {
                "symbol": symbol,
                "timestamp": datetime.now().isoformat(),
                "features": {},
            }

        entity_rows = [{"symbol": symbol}]
        feature_refs = [f"{FEATURE_VIEW_NAME}:{f}" for f in feature_names]

        result = store.get_online_features(
            features=feature_refs,
            entity_rows=entity_rows,
        )

        features = result.to_dict()
        return {
            "symbol": symbol,
            "timestamp": datetime.now().isoformat(),
            "features": {k: v[0] for k, v in features.items() if k != "symbol"},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
