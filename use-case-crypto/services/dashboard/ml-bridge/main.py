"""ML Bridge API."""

import os
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from services.feature import router as feature_router
from services.metrics import router as metrics_router
from services.prediction import router as prediction_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    yield


app = FastAPI(title="ML Bridge", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, Any]:
    start = time.perf_counter_ns()
    latency = (time.perf_counter_ns() - start) / 1000
    return {"status": "healthy", "latency_us": latency}


app.include_router(prediction_router, prefix="/api/predictions", tags=["predictions"])
app.include_router(feature_router, prefix="/api/features", tags=["features"])
app.include_router(metrics_router, prefix="/api/metrics", tags=["metrics"])


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
