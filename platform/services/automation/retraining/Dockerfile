# Auto-retraining Dockerfile using UV (multi-stage)
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1
ENV UV_COMPILE_BYTECODE_TIMEOUT=600
ENV UV_LINK_MODE=copy
ENV UV_NO_DEV=1
ENV UV_HTTP_TIMEOUT=120

WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

RUN useradd -u 1000 -m -s /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder --chown=1000:1000 /app /app

USER 1000:1000
ENV PATH="/app/.venv/bin:$PATH"

# Per uv docs: invoke baked venv directly. `uv run` at runtime triggers
# an editable rebuild needing hatchling from PyPI — fails air-gapped.
ENTRYPOINT []
CMD ["python", "main.py"]
