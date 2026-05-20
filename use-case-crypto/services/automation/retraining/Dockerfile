# =============================================================================
# crypto-retraining — drift-triggered KFP pipeline launcher
# =============================================================================
# This container is invoked by the Airflow `trigger_retrain_if_drift` task
# (dags/crypto_data_pipeline.py).  It checks Redis for a drift flag set by
# drift-detector; if present, submits the `crypto_retraining_pipeline` KFP
# pipeline and blocks until its KFP RunID reports Succeeded / Failed.
# Replaces the previously undefined image (audit P1 #10).
# =============================================================================
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim AS builder

# UV mandate (project policy): no `uv pip install`. Declare deps in an
# inline pyproject.toml + lock via `uv sync`. UV_PROJECT_ENVIRONMENT pins
# the resolved venv to /opt/venv so the runtime stage can copy it
# directly. Keeping the lockfile in-image (no commit) is fine for this
# throwaway base — `uv sync --no-dev` re-resolves deterministically from
# pinned pyproject pins on rebuild.
WORKDIR /app

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_PROGRESS=1

RUN <<'EOF' cat > pyproject.toml
[project]
name = "crypto-retraining"
version = "0.1.0"
description = "Drift-triggered KFP pipeline launcher (crypto use case)"
requires-python = "==3.13.*"
dependencies = [
    "kfp==2.16.0",
    "kfp-server-api==2.16.0",
    "redis==5.3.3",
    "mlflow-skinny==3.11.1",
    "python-json-logger==3.2.1",
    "opentelemetry-api==1.30.0",
    "opentelemetry-sdk==1.30.0",
    "opentelemetry-exporter-otlp==1.30.0",
]
[tool.uv]
package = false
EOF

RUN uv sync --no-dev

FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

ENV PATH="/opt/venv/bin:${PATH}" \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd --gid 1000 crypto && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash crypto

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/pyproject.toml /app/pyproject.toml

WORKDIR /app
COPY services/automation/retraining/app.py /app/app.py

USER crypto

# UV mandate: launch via `uv run` (resolves against /opt/venv pinned by
# UV_PROJECT_ENVIRONMENT). Avoids invoking the venv's python binary
# directly.
ENTRYPOINT ["uv", "run", "--no-sync", "app.py"]
