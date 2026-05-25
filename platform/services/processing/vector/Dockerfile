# Vector Processing Service Dockerfile using UV
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

ENV UV_COMPILE_BYTECODE=1
ENV UV_COMPILE_BYTECODE_TIMEOUT=600
ENV UV_LINK_MODE=copy
ENV UV_NO_DEV=1
ENV UV_HTTP_TIMEOUT=120
ENV UV_CACHE_DIR=/home/app/.cache/uv

# curl required by push-helper script (push_job_metrics.sh) which the
# vector-embedding CronJob wraps `uv run main.py` with for pushgateway
# emit. Without curl the script logs "neither curl nor wget available;
# cannot push" and metrics are silently dropped.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user BEFORE any COPY/sync so every file lands owned by
# uid 1000. Avoids post-hoc `chown -R /app` over the multi-GB uv venv
# (PyTorch+transformers+sentence-transformers) — recursive chown on that
# tree under IO pressure stalls the build for tens of minutes.
RUN useradd -u 1000 -m -s /usr/sbin/nologin app
WORKDIR /app
RUN chown 1000:1000 /app
USER 1000:1000

# Install dependencies (cached layer via bind mount). Cache dir is owned
# by uid 1000 so the unprivileged user can write to it.
RUN --mount=type=cache,target=/home/app/.cache/uv,uid=1000,gid=1000 \
    --mount=type=bind,source=uv.lock,target=uv.lock,readonly \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml,readonly \
    uv sync --locked --no-install-project

# Bake the sentence-transformers model into the image so each CronJob
# fire starts hot. Without this step, every fresh pod must fetch ~440 MB
# from HuggingFace and, under sda write pressure, that fetch routinely
# overran activeDeadlineSeconds and tripped the backoff loop.
# Layered before the full source COPY so the (large) model layer is not
# busted by ordinary code changes — only EMBEDDING_MODEL or this script
# invalidate it.
#
# HF_HOME lives at /home/app/hf-cache (NOT under /home/app/.cache/) so it
# does not collide with the uv cache BuildKit mount at
# /home/app/.cache/uv. When HF_HOME was /home/app/.cache/huggingface the
# parent `.cache` was the mount overlay and the sibling mkdir failed with
# EACCES even as uid 1000.
ENV HF_HOME=/home/app/hf-cache
COPY --chown=1000:1000 download_model.py /app/download_model.py
RUN --mount=type=cache,target=/home/app/.cache/uv,uid=1000,gid=1000 \
    --mount=type=bind,source=uv.lock,target=uv.lock,readonly \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml,readonly \
    mkdir -p "${HF_HOME}" && uv run --no-sync download_model.py

# Copy source with correct ownership baked in (no post-hoc chown).
COPY --chown=1000:1000 . /app
RUN --mount=type=cache,target=/home/app/.cache/uv,uid=1000,gid=1000 \
    uv sync --locked

EXPOSE 8000

# Per uv docs: invoke baked venv directly. `uv run` at runtime triggers
# an editable rebuild needing hatchling from PyPI — fails air-gapped.
# Single-stage image: PATH above (/app/.venv/bin) is enough for python
# to find deps. CronJob may wrap this with push_job_metrics.sh.
ENTRYPOINT []
CMD ["python", "main.py"]
