# Drift Detection Service Dockerfile using UV (multi-stage)
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
    uv sync --locked --no-editable

FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

RUN useradd -u 1000 -m -s /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder --chown=1000:1000 /app /app

USER 1000:1000
ENV PATH="/app/.venv/bin:$PATH"

# UV mandate: run via `uv run --no-sync`. `--no-sync` uses the baked venv
# WITHOUT re-syncing, so it never triggers an editable rebuild (hatchling
# from PyPI) that would fail air-gapped — and the build installs the project
# --no-editable (a real wheel), so there is nothing to rebuild at runtime.
ENTRYPOINT []
CMD ["uv", "run", "--no-sync", "main.py"]
