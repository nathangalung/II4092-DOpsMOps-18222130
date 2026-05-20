# Quality analyzer Dockerfile using UV
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV UV_NO_DEV=1
ENV UV_HTTP_TIMEOUT=120

# Install dependencies (cached layer via bind mount)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project

# Copy source and sync project
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen

RUN useradd -u 1000 -m -s /usr/sbin/nologin app && chown -R 1000:1000 /app
USER 1000:1000

CMD ["uv", "run", "main.py"]
