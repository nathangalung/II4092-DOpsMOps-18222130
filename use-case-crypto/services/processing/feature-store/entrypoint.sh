#!/bin/sh
# Feast feature-store entrypoint — renders feature_store.yaml from its
# envsubst template at container start, then exec's into the feast CLI
# with whatever arguments the Pod spec / CMD provided. Runs as `feast`
# (uid 1000), so the rendered file stays inside /app/feature_repo
# which the user already owns.
set -eu

REPO=/app/feature_repo
TEMPLATE="${REPO}/feature_store.yaml"
RENDERED="${REPO}/feature_store.rendered.yaml"

# envsubst reads from stdin; write to a side file then swap atomically.
# `${VALKEY_PASSWORD:-}` pattern is NOT expanded by envsubst — we rely on
# the caller to export VALKEY_PASSWORD (empty string acceptable in dev).
envsubst < "${TEMPLATE}" > "${RENDERED}"
mv "${RENDERED}" "${TEMPLATE}"

exec /opt/venv/bin/feast "$@"
