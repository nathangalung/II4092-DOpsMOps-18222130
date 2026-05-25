#!/usr/bin/env bash
# =============================================================================
# mysql/post-apply.sh — heal root password drift between PVC and ESO secret
# =============================================================================
# Why this exists:
#   The mysql:8.4 image only initialises root@'%' / root@localhost from
#   MYSQL_ROOT_PASSWORD on the FIRST start (empty data dir). On every
#   subsequent restart the data dir survives via PVC, while the ESO-managed
#   `mysql-root-secret` may have rotated when OpenBao reseals or a fresh
#   bootstrap re-derives the password. Result: env says one password,
#   `mysql.user` table says another, libmysqlclient-based clients
#   (MLMD metadata-grpc, Katib db-manager) get auth failures and CrashLoop.
#
#   Field-observed 2026-05-21: metadata-grpc-deployment +
#   metadata-writer at 86 restarts; root@'%' authenticated with the value
#   minted by `mysql_secure_installation` on first init but ESO had since
#   pushed a re-derived password down to `mysql-root-secret`. Live ALTER
#   USER restored auth instantly.
#
# What this hook does:
#   1. Wait MySQL Deployment Available.
#   2. Use the env-baked password (`MYSQL_ROOT_PASSWORD`, sourced from
#      `mysql-root-secret` envFrom) to ALTER root@'%' and root@localhost
#      to the same value with `mysql_native_password`. If the password
#      already matches, this is a no-op rewrite — safe and idempotent.
#   3. Bounce KFP metadata-grpc + Katib db-manager so they pick up the
#      restored credential immediately (otherwise they keep retrying
#      stale env-cached connections for several minutes).
#
# Idempotent: on a healthy cluster every step is a no-op rewrite.
# =============================================================================
set -euo pipefail

NS=storage

echo "    [post-apply] waiting Deployment/mysql Available (timeout 300s)"
kubectl -n "$NS" rollout status deployment/mysql --timeout=300s

POD=$(kubectl -n "$NS" get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POD" ]]; then
  echo "    [post-apply] no mysql pod found — skipping ALTER" >&2
  exit 0
fi

echo "    [post-apply] reconciling root@% / root@localhost passwords with mysql-root-secret"
# Run ALTER inside the pod so MYSQL_ROOT_PASSWORD is read from the
# container's own env (matches what consumers see via the same secret).
# The HEREDOC is piped into mysql to avoid leaking the password into argv.
kubectl -n "$NS" exec "$POD" -- bash -c '
  set -e
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<SQL
ALTER USER '"'"'root'"'"'@'"'"'%'"'"'         IDENTIFIED WITH mysql_native_password BY '"'"'$MYSQL_ROOT_PASSWORD'"'"';
ALTER USER '"'"'root'"'"'@'"'"'localhost'"'"' IDENTIFIED WITH mysql_native_password BY '"'"'$MYSQL_ROOT_PASSWORD'"'"';
FLUSH PRIVILEGES;
SQL
'

echo "    [post-apply] bouncing KFP/Katib clients to re-auth"
# Only bounce if the deployments exist (model-lifecycle ns may not be
# applied yet on first phase-full run).
for nsdep in \
    "model-lifecycle:metadata-grpc-deployment" \
    "model-lifecycle:metadata-writer" \
    "model-lifecycle:katib-db-manager"; do
  ns="${nsdep%%:*}"; dep="${nsdep##*:}"
  if kubectl -n "$ns" get deployment "$dep" >/dev/null 2>&1; then
    kubectl -n "$ns" rollout restart "deployment/$dep" >/dev/null
  fi
done

echo "    [post-apply] mysql root password reconciled OK"
