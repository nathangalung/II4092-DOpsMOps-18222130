# =============================================================================
# AIRFLOW — Production image built with uv sync
# =============================================================================
# Installs Apache Airflow (open source) + all required providers via uv sync
# with a locked pyproject.toml for reproducible builds.
#
# Multi-stage build following uv Docker best practices:
#   https://docs.astral.sh/uv/guides/integration/docker/
#
# Providers:
#   - cncf-kubernetes: KubernetesPodOperator for DAG task execution on K8s
#   - postgres: PostgreSQL hook/operator + psycopg2 for metadata DB
#   - amazon: S3 support for remote logging + MinIO artifact storage
#   - fab: FabAuthManager — DB-backed users/roles + BasicAuth REST API
#     backend.  Required by Airflow 3.x (SimpleAuthManager default is
#     incompatible with our Vault-sourced admin credential and DataHub's
#     BasicAuth ingestion recipe).
#
# Build: `uv lock` first if pyproject.toml was edited, then
#        `docker build -t localhost:5000/platform-airflow:latest .`
#        (the builder stage runs `uv sync --locked`, which fails if
#        uv.lock is out of date — this is a loud failure by design).
# =============================================================================

# --- Stage 1: Build dependencies ---
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim AS builder

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1
ENV UV_COMPILE_BYTECODE_TIMEOUT=600
ENV UV_LINK_MODE=copy

# Install all dependencies (Airflow + providers) from locked pyproject.toml
# --no-install-project: this is a dependency aggregator, not a Python package
COPY pyproject.toml uv.lock /app/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project


# --- Stage 2: Production runtime (minimal, no uv/build tools) ---
FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

# Copy the virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Place venv at front of PATH so airflow CLI is available
ENV PATH="/app/.venv/bin:$PATH"
ENV AIRFLOW_HOME=/opt/airflow

# Create Airflow user and directory structure.
#
# UID 50000 is the Apache Airflow community's canonical numeric UID
# (documented in the official Airflow Dockerfile and Helm chart).  The
# Kubernetes deployments in this repo (data-processing/airflow/deployment.yaml)
# pin `runAsUser: 50000` and `fsGroup: 50000`.  Pinning the UID inside the
# image avoids two classes of runtime failure:
#   1. `/opt/airflow/airflow.cfg` PermissionError on first run when airflow
#      tries to write a default config file to a directory owned by a
#      different UID.
#   2. `getpass.getuser()` / `pwd.getpwuid(50000)` KeyError in airflow CLI's
#      _build_metrics path when /etc/passwd has no entry for the effective
#      UID.  The CLI calls this in every subcommand, including `airflow db
#      migrate` and `airflow api-server`, so the error is not optional.
# Keeping the UID explicit here is the root-cause fix; the ConfigMap
# `AIRFLOW_HOME` override in the deployment is kept as belt-and-suspenders.
RUN useradd -m -d /home/airflow -u 50000 airflow && \
    mkdir -p /opt/airflow/dags /opt/airflow/logs /opt/airflow/plugins && \
    chown -R airflow:root /opt/airflow && \
    chmod -R g+rwX /opt/airflow

USER airflow
