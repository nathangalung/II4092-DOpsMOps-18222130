# FLAML AutoML Trainer Dockerfile using UV (multi-stage)
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

# libgomp1 needed at runtime by LightGBM/XGBoost threading
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -u 1000 -m -s /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder --chown=1000:1000 /app /app
# Ensure the WORKDIR itself (not just its contents) is owned by uid 1000: the
# `COPY --chown` above sets file owners but leaves the root-created /app dir
# root-owned, so a uid-1000 process cannot create NEW entries in it. CatBoost
# (one of FLAML's estimators) mkdir's a per-run train working dir in CWD and
# otherwise dies with "Can't create train working dir". This keeps catboost in
# the AutoML search without a writable-CWD workaround at the call site.
RUN chown 1000:1000 /app

USER 1000:1000
ENV PATH="/app/.venv/bin:$PATH"

# UV mandate: run via `uv run --no-sync`, not bare `python`. `--no-sync`
# uses the baked venv WITHOUT re-syncing, so it never triggers the editable
# rebuild (hatchling from PyPI) that fails air-gapped - and the build now
# installs the project --no-editable (a real wheel), so there is nothing to
# rebuild at runtime anyway. The KFP train step uses this CMD; the deploy
# step overrides with `uv run --no-sync src/deploy_kserve.py`.
ENTRYPOINT []
CMD ["uv", "run", "--no-sync", "main.py"]
