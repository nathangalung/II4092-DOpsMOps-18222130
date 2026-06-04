"""Feature service for Feast queries."""

import os
from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

FEAST_REPO = os.getenv("FEAST_REPO_PATH", "/app/feature_store")


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


def _online_views(store: Any) -> list[Any]:
    """Feature views materialized to the online store (online=True)."""
    return [v for v in store.list_feature_views() if getattr(v, "online", True)]


def _resolve_refs(store: Any, names: list[str]) -> list[str]:
    """Map bare feature names to fully-qualified ``view:feature`` refs.

    A name already containing ':' passes through untouched. A bare name is
    resolved against every online view's feature set: unknown → error (a typo
    fails loud instead of silently serving null), ambiguous (owned by >1 view)
    → error asking the caller to qualify it. This replaces the old hardcoded
    single-view assumption (``FEATURE_VIEW_NAME``) which returned 0 features
    once the repo grew past one view (the train/serve "Feast returns 0" seam).
    """
    bare_to_view: dict[str, list[str]] = {}
    for v in _online_views(store):
        for f in v.features:
            bare_to_view.setdefault(f.name, []).append(v.name)
    refs: list[str] = []
    for name in names:
        if ":" in name:
            refs.append(name)
            continue
        owners = bare_to_view.get(name)
        if not owners:
            raise ValueError(
                f"feature '{name}' not found in any online feature view "
                f"(known: {sorted(bare_to_view)})"
            )
        if len(owners) > 1:
            raise ValueError(
                f"feature '{name}' is ambiguous across views {owners}; "
                f"qualify it as '<view>:{name}'"
            )
        refs.append(f"{owners[0]}:{name}")
    return refs


@router.post("/online")
async def get_online_features(request: FeatureRequest) -> FeatureResponse:
    """Get online features from Feast."""
    try:
        from feast import FeatureStore

        store = FeatureStore(repo_path=FEAST_REPO)

        entity_rows = [{"symbol": request.symbol}]
        feature_refs = _resolve_refs(store, request.features)

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

    Feature list is configured via FEAST_LATEST_FEATURES (comma-separated bare
    or ``view:feature`` names). When unset, every feature of every online view
    is served (fully qualified), so a fresh use-case gets output with no env.
    """
    try:
        from feast import FeatureStore

        store = FeatureStore(repo_path=FEAST_REPO)

        features_env = os.getenv("FEAST_LATEST_FEATURES", "")
        if features_env:
            names = [f.strip() for f in features_env.split(",") if f.strip()]
            feature_refs = _resolve_refs(store, names)
        else:
            # Auto-discover: every feature of every online view, fully qualified.
            feature_refs = [
                f"{v.name}:{f.name}" for v in _online_views(store) for f in v.features
            ]

        if not feature_refs:
            return {
                "symbol": symbol,
                "timestamp": datetime.now().isoformat(),
                "features": {},
            }

        entity_rows = [{"symbol": symbol}]
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
