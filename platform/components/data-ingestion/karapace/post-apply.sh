#!/usr/bin/env bash
# =============================================================================
# karapace/post-apply.sh — auto-roll on Strimzi cluster CA rotation
# =============================================================================
# Why this exists:
#   Karapace (aiokafka python client) loads `KARAPACE_SSL_CAFILE` ONCE at
#   process start, materialising an in-memory ssl.SSLContext.  When Strimzi
#   rotates the `platform-kafka-cluster-ca-cert` Secret (annual default, or
#   manual rotate-on-incident), kubelet atomically swaps the projected
#   `/etc/kafka-ca/ca.crt` file behind karapace, but the running process keeps
#   the OLD trust anchor in its ssl_context.  Result: every subsequent
#   connection attempt to broker:9093 fails with
#     [SSL: CERTIFICATE_VERIFY_FAILED] self-signed certificate in certificate
#     chain
#   even though the file on disk now contains the NEW correct cluster CA.
#   Master coordinator never elects, /subjects returns "Not Found", and every
#   DataHub SystemUpdate that needs to register a schema fails with
#     RestClientException: Error while forwarding the request to the master.;
#     error code: 50003
#   which cascades into `Failed to produce MCLs` in datahub-upgrade-job.
#
#   Field-observed 2026-05-20: karapace pod up 5d16h on May-14 cluster CA;
#   Strimzi rotated to May-18 cluster CA on May 18 10:49:34; karapace kept
#   failing for ~2 days (26 CrashLoop restarts) until manual rollout restart.
#
# What this hook does (idempotent, runs after the main apply succeeds):
#   1. Hash the live cluster CA cert.
#   2. Stamp the hash as a pod-template annotation
#      `checksum/kafka-cluster-ca-cert` on the karapace Deployment.
#   3. If the hash differs from what's already stamped, K8s rolls the
#      Deployment automatically (pod template spec mutated) and the new
#      karapace pod loads the fresh CA at process start.  If the hash
#      matches, the patch is a no-op (every `make phase-full` re-checks
#      but only rolls when the cluster CA has actually rotated).
#
#   Same pattern as datahub/post-apply.sh does for `datahub-frontend-secret`
#   — k8s-native solution to "Secret rotates but consuming pod doesn't
#   notice" without bolting on a sidecar reloader.
# =============================================================================
set -euo pipefail

NS=data-ingestion
SECRET=platform-kafka-cluster-ca-cert
DEPLOY=karapace
ANN=checksum/kafka-cluster-ca-cert

echo "    [post-apply] checksum-stamping $DEPLOY for auto-roll on Strimzi cluster CA rotation"

# Strimzi creates this Secret post-Kafka-CR; wait until it materialises so the
# first `make phase-full` after a `make nuke` doesn't FATAL.  Kafka cluster CA
# is generated within the first ~60s of Kafka CR admission.
deadline=$(( $(date +%s) + 300 ))
while (( $(date +%s) < deadline )); do
  if kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then break; fi
  sleep 5
done
if ! kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
  echo "        FATAL: $NS/$SECRET missing after 300s — Strimzi Kafka CR didn't materialise its cluster CA" >&2
  exit 2
fi

ca_hash=$(kubectl -n "$NS" get secret "$SECRET" \
  -o jsonpath='{.data.ca\.crt}' | sha256sum | awk '{print $1}')
# sha256 of empty = e3b0c44298…; guard so we never stamp the empty digest
# (would cause a roll on the next real CA too — and any karapace pod that
# started on an empty CA would 100% fail SSL).
if [[ -z "$ca_hash" || "$ca_hash" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
  echo "        FATAL: $NS/$SECRET .data.ca.crt empty — Strimzi cluster CA not populated" >&2
  exit 2
fi
echo "        cluster CA sha256=${ca_hash:0:12}…"

if ! kubectl -n "$NS" get deployment "$DEPLOY" >/dev/null 2>&1; then
  echo "        $DEPLOY Deployment absent — first apply will create it; next post-apply will stamp"
  exit 0
fi

current_hash=$(kubectl -n "$NS" get deployment "$DEPLOY" \
  -o jsonpath="{.spec.template.metadata.annotations['checksum/kafka-cluster-ca-cert']}" 2>/dev/null || echo "")
if [[ "$current_hash" == "$ca_hash" ]]; then
  echo "        $DEPLOY annotation already current (${current_hash:0:12}…) — no roll"
  exit 0
fi

echo "        $DEPLOY annotation stale (${current_hash:0:12}… → ${ca_hash:0:12}…) — patching, K8s will roll"
kubectl -n "$NS" patch deployment "$DEPLOY" --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"$ANN\":\"$ca_hash\"}}}}}" >/dev/null

# Wait for the roll to complete so downstream consumers (datahub-upgrade-job
# in particular) see a fresh karapace before they try to register schemas.
echo "        waiting for $DEPLOY rollout (timeout 180s)"
if ! kubectl -n "$NS" rollout status deployment "$DEPLOY" --timeout=180s; then
  echo "        FATAL: $DEPLOY did not roll in 180s after CA-checksum patch" >&2
  kubectl -n "$NS" describe deployment "$DEPLOY" >&2 || true
  exit 2
fi
echo "        $DEPLOY rolled to new CA"
