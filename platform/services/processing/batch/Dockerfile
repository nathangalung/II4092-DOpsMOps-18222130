# Batch Processing Service Dockerfile using UV (multi-stage)
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

# Use-case overlay deps (requirements-extra.txt overlaid by Makefile pre-build
# from use-case-*/services/processing/batch/). Install into the existing
# venv without mutating pyproject.toml / uv.lock.
RUN --mount=type=cache,target=/root/.cache/uv \
    if [ -f requirements-extra.txt ]; then \
      uv pip install --python /app/.venv -r requirements-extra.txt; \
    fi

FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

RUN useradd -u 1000 -m -s /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder --chown=1000:1000 /app /app

USER 1000:1000
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

# Per uv docs: invoke baked venv directly. `uv run` at runtime triggers
# an editable rebuild needing hatchling from PyPI — fails air-gapped.
ENTRYPOINT []
CMD ["python", "main.py"]
