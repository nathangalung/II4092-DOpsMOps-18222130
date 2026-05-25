#!/bin/bash
# =============================================================================
# seed-openbao.sh
# =============================================================================
# Reads a crypto `.env` file and creates a K8s Secret `openbao-crypto-seed` in
# namespace `security`. The crypto bootstrap Job
# (use-case-crypto/manifests/base/openbao/bootstrap.yaml) consumes
# this Secret on first run. Missing keys fall back to `REPLACE_ME` so pods
# crash-loop loudly rather than silently authenticating with empty tokens.
#
# Usage:
#   ./use-case-crypto/scripts/seed-openbao.sh [path/to/use-case-crypto/.env]
#
# Default: use-case-crypto/.env at repo root.
#
# Idempotent: overwrites `openbao-crypto-seed` on each run. The bootstrap Job
# only consumes the Secret the FIRST time it seeds each KV path; subsequent
# rotations go through `bao kv put` directly.
#
# Key mapping (.env -> seed key -> OpenBao KV path):
#
#   CRYPTO_JWT_SECRET            -> SEED_CRYPTO_JWT_SECRET            -> usecases/crypto/pipeline#jwt_secret
#   CRYPTO_MLFLOW_TRACKING_PASSWORD -> SEED_CRYPTO_MLFLOW_TRACKING_PASSWORD -> usecases/crypto/pipeline#mlflow_password
#   COINBASE_API_KEY             -> SEED_COINBASE_API_KEY             -> usecases/crypto/api-keys#coinbase
#   COINBASE_API_SECRET          -> SEED_COINBASE_API_SECRET          -> usecases/crypto/api-keys#coinbase_secret
#   COINGECKO_API_KEY            -> SEED_COINGECKO_API_KEY            -> usecases/crypto/api-keys#coingecko
#   CRYPTOPANIC_API_KEY          -> SEED_CRYPTOPANIC_API_KEY          -> usecases/crypto/api-keys#cryptopanic
#   NEWSAPI_KEY                  -> SEED_NEWSAPI_KEY                  -> usecases/crypto/api-keys#newsapi
#   CRYPTO_DASHBOARD_DATAENG_PASS  -> SEED_CRYPTO_DASHBOARD_DATAENG_PASS  -> usecases/crypto/dashboard#dataeng_password
#   CRYPTO_DASHBOARD_DATASCI_PASS  -> SEED_CRYPTO_DASHBOARD_DATASCI_PASS  -> usecases/crypto/dashboard#datasci_password
#   CRYPTO_DASHBOARD_MLENG_PASS    -> SEED_CRYPTO_DASHBOARD_MLENG_PASS    -> usecases/crypto/dashboard#mleng_password
#   CRYPTO_DASHBOARD_BUSUSER_PASS  -> SEED_CRYPTO_DASHBOARD_BUSUSER_PASS  -> usecases/crypto/dashboard#bususer_password
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-security}"
SECRET_NAME="${SECRET_NAME:-openbao-crypto-seed}"

if [ "$#" -eq 0 ]; then
  set -- "${REPO_ROOT}/use-case-crypto/.env"
fi

declare -A seeds

mapped_keys=(
  CRYPTO_JWT_SECRET CRYPTO_MLFLOW_TRACKING_PASSWORD
  COINBASE_API_KEY COINBASE_API_SECRET
  COINGECKO_API_KEY CRYPTOPANIC_API_KEY NEWSAPI_KEY
  CRYPTO_DASHBOARD_DATAENG_PASS CRYPTO_DASHBOARD_DATASCI_PASS
  CRYPTO_DASHBOARD_MLENG_PASS CRYPTO_DASHBOARD_BUSUSER_PASS
)

for envfile in "$@"; do
  if [ ! -f "$envfile" ]; then
    echo "[skip] $envfile (not found)"
    continue
  fi
  echo "[load] $envfile"
  # shellcheck disable=SC1090
  set -a; . "$envfile"; set +a
done

for key in "${mapped_keys[@]}"; do
  val="${!key:-}"
  if [ -n "$val" ] && [ "$val" != "your-${key,,}" ] && [ "$val" != "REPLACE_ME" ]; then
    seeds["SEED_${key}"]="$val"
  fi
done

if [ "${#seeds[@]}" -eq 0 ]; then
  echo "[warn] no crypto seed values found. API keys will be set to REPLACE_ME."
  echo "[info] nothing to write; delete any existing $SECRET_NAME to reset."
  exit 0
fi

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "apiVersion: v1"
  echo "kind: Secret"
  echo "metadata:"
  echo "  name: $SECRET_NAME"
  echo "  namespace: $NAMESPACE"
  echo "  labels:"
  echo "    app.kubernetes.io/part-of: use-case-crypto"
  echo "    usecase: crypto"
  echo "type: Opaque"
  echo "data:"
  for k in "${!seeds[@]}"; do
    v_b64=$(printf '%s' "${seeds[$k]}" | base64 -w0)
    printf '  %s: %s\n' "$k" "$v_b64"
  done
} > "$tmp"

kubectl apply -f "$tmp"

echo "[ok] wrote $SECRET_NAME in namespace $NAMESPACE with ${#seeds[@]} key(s)"
echo "[next] kubectl apply -k use-case-crypto/manifests/overlays/local  # triggers crypto-openbao-bootstrap-crypto Job"
