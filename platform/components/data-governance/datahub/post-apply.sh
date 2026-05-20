#!/usr/bin/env bash
# =============================================================================
# datahub/post-apply.sh — heal the ESO-source race that wedges the upgrade Job
# =============================================================================
# Why this exists:
#   datahub-upgrade-job is created by the same `kubectl apply --server-side`
#   that lays down the three ExternalSecret CRs it depends on
#   (platform-postgresql-secret, datahub-kafka, datahub-frontend-secret).
#   Order of materialisation under SSA:
#     1. SSA accepts every doc and exits 0 — both Job and ExternalSecret CRs
#        are admitted simultaneously.
#     2. kube-scheduler immediately schedules the Job pod.
#     3. kubelet pulls the image, starts the sandbox, then resolves env-from
#        secrets — one of platform-postgresql-secret / datahub-kafka /
#        datahub-frontend-secret may not yet exist as a real `Secret` because
#        ESO hasn't completed its first reconcile against the upstream
#        ClusterSecretStore.
#     4. kubelet sets pod phase `Pending` with reason
#        `CreateContainerConfigError: secret "X" not found`. This counts
#        toward Job.spec.backoffLimit (5).
#     5. ESO's first fetch may fail if the upstream source secret is itself
#        not yet present — e.g. CNPG `postgresql-app` is generated only AFTER
#        the storage/postgresql component finishes initdb. After a failed
#        fetch ESO retries on `refreshInterval` (1h here), so the second
#        attempt is an hour away — long after the Job has burned through its
#        backoffLimit and entered terminal Failed state.
#     6. Once Failed (BackoffLimitExceeded), the Job will not retry on its
#        own; ttlSecondsAfterFinished=3600 GCs it. Without SystemUpdate ever
#        running, the OpenSearch indices DataHub GMS expects
#        (datahubpolicyindex_v2, datahubingestionsourceindex_v2, etc.) never
#        get created. GMS comes up, sees no indices, returns 503 from /health,
#        liveness probe fails forever. datahub-actions waits on GMS /health,
#        times out, CrashLoopBackOff. Cascade.
#
#   Field-observed 2026-05-10: 5 successive datahub-upgrade-job pods (-mt7bb,
#   -56p8f, ...) failed at 08:12 with
#     CreateContainerConfigError: secret "platform-postgresql-secret" not found
#   while the platform-postgresql-secret ExternalSecret sat unreconciled.
#
# What this hook does (idempotent, runs after the main apply succeeds):
#   1. Wait for the upstream CNPG `postgresql-app` Secret in `storage` to
#      exist — that's the source of truth for the platform-postgresql-secret
#      ExternalSecret. CNPG generates it post-initdb on the first replica.
#   2. Wait for the upstream Strimzi `admin` SCRAM Secret + cluster-CA Secret
#      in `data-ingestion` to exist (datahub-kafka source). These come from
#      the strimzi KafkaUser+Kafka resources applied in atom-ingest-stream.
#   3. Force ESO to re-reconcile each ExternalSecret in `data-governance` by
#      bumping the standard `force-sync` annotation. ESO watches this exact
#      key and triggers an immediate fetch regardless of refreshInterval.
#   4. Wait for the three target Secrets to materialise.
#   5. If `datahub-upgrade-job` is in terminal Failed state (its backoff was
#      consumed during the race window), delete it and re-create from the
#      rendered manifest so SystemUpdate actually runs.
#   6. Wait for the Job to reach Complete (SystemUpdate runs Liquibase DDL +
#      OpenSearch index bootstraps; 5–15 min on a cold cluster).
#
#   On a healthy cluster every wait returns instantly and step 5/6 short-
#   circuits because the Job already Completed once.
# =============================================================================
set -euo pipefail

NS=data-governance
RENDER="${CACHE_DIR:-$REPO_ROOT/.cache}/renders/component-${NS}-datahub-rendered.yaml"

echo "    [post-apply] waiting source Secret storage/postgresql-app (CNPG initdb, timeout 600s)"
deadline=$(( $(date +%s) + 600 ))
while (( $(date +%s) < deadline )); do
  if kubectl -n storage get secret postgresql-app >/dev/null 2>&1; then
    echo "        storage/postgresql-app present"
    break
  fi
  sleep 5
done
if ! kubectl -n storage get secret postgresql-app >/dev/null 2>&1; then
  echo "        FATAL: storage/postgresql-app missing after 600s — CNPG initdb not done" >&2
  exit 2
fi

echo "    [post-apply] waiting source Secrets data-ingestion/{admin,platform-kafka-cluster-ca-cert} (timeout 300s)"
deadline=$(( $(date +%s) + 300 ))
while (( $(date +%s) < deadline )); do
  if kubectl -n data-ingestion get secret admin >/dev/null 2>&1 \
     && kubectl -n data-ingestion get secret platform-kafka-cluster-ca-cert >/dev/null 2>&1; then
    echo "        data-ingestion Kafka source secrets present"
    break
  fi
  sleep 5
done

echo "    [post-apply] force-refreshing ExternalSecrets (annotation bump triggers immediate ESO reconcile)"
ts=$(date +%s)
# Belt-and-suspenders: annotate with both legacy `force-sync` and the
# fully-qualified `external-secrets.io/force-sync`. ESO 0.9+ watches the
# qualified key; older builds watched the bare one. Setting both is safe.
for es in platform-postgresql-secret datahub-kafka datahub-frontend-secret; do
  kubectl -n "$NS" annotate externalsecret "$es" \
    "force-sync=$ts" \
    "external-secrets.io/force-sync=$ts" \
    --overwrite >/dev/null 2>&1 || true
done

echo "    [post-apply] waiting target Secrets to materialise (timeout 300s)"
deadline=$(( $(date +%s) + 300 ))
missing=""
while (( $(date +%s) < deadline )); do
  missing=""
  for s in platform-postgresql-secret datahub-kafka datahub-frontend-secret; do
    kubectl -n "$NS" get secret "$s" >/dev/null 2>&1 || missing+=" $s"
  done
  if [[ -z "$missing" ]]; then
    echo "        all target Secrets present"
    break
  fi
  sleep 5
done
if [[ -n "$missing" ]]; then
  echo "        FATAL: ESO did not materialise:$missing" >&2
  kubectl -n "$NS" get externalsecret -o wide >&2 || true
  exit 2
fi

# -----------------------------------------------------------------------------
# Auto-roll datahub-gms + datahub-frontend on DATAHUB_SECRET rotation.
# -----------------------------------------------------------------------------
# Why: DATAHUB_TOKEN_SERVICE_SIGNING_KEY is the HMAC key both GMS (validates)
# and frontend (mints) use against the same PAT.  When `make nuke` wipes
# OpenBao, openbao-bootstrap regenerates `platform/datahub/admin.secret` with
# a fresh value.  ESO's `datahub-frontend-secret` ExternalSecret picks that up
# on next refresh (1h refreshInterval, or via force-sync above).  But neither
# Deployment auto-rolls on Secret mutation — kubelet only re-reads env vars
# on container start.  Result: in-pod env stays on the pre-nuke key for the
# lifetime of the pod (days).  Every PAT minted by frontend with the new key
# is rejected by GMS validating with the old key → all datahub-ingest jobs
# fail with 401 Unauthorized.  Symptom field-observed 2026-05-17 (3-day window
# of silent 401s after a nuke cycle).
#
# Fix: hash the live DATAHUB_SECRET value, stamp it as a pod-template
# annotation on both Deployments.  If the hash differs from what's already
# there, the pod template spec changes → K8s rolls the Deployment, new pod
# reads fresh env.  If the hash matches, patch is a no-op (idempotent — every
# `make phase-full` re-checks but only rolls when needed).
# -----------------------------------------------------------------------------
echo "    [post-apply] checksum-stamping datahub-gms + datahub-frontend for auto-roll on secret rotation"
secret_hash=$(kubectl -n "$NS" get secret datahub-frontend-secret \
  -o jsonpath='{.data.DATAHUB_SECRET}' | sha256sum | awk '{print $1}')
# sha256 of empty string is e3b0c44…; that's what you'd hash if the key is
# missing during a partial-apply window.  Guard so we never stamp the empty
# digest onto the Deployments (would cause a roll on the next real value too,
# but worse: any GMS pod that started with an empty key would 401 every PAT).
if [[ -z "$secret_hash" || "$secret_hash" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
  echo "        FATAL: datahub-frontend-secret.DATAHUB_SECRET empty — ESO hasn't populated DATAHUB_SECRET key" >&2
  kubectl -n "$NS" get secret datahub-frontend-secret -o yaml >&2 || true
  exit 2
fi
echo "        current datahub-frontend-secret.DATAHUB_SECRET sha256=${secret_hash:0:12}…"
for d in datahub-gms datahub-frontend; do
  if ! kubectl -n "$NS" get deployment "$d" >/dev/null 2>&1; then
    echo "        $d Deployment absent — skipping (first apply will create it with no stamp; next post-apply will stamp)"
    continue
  fi
  current_hash=$(kubectl -n "$NS" get deployment "$d" \
    -o jsonpath="{.spec.template.metadata.annotations['checksum/datahub-frontend-secret']}" 2>/dev/null || echo "")
  if [[ "$current_hash" == "$secret_hash" ]]; then
    echo "        $d annotation already current (${current_hash:0:12}…) — no roll"
  else
    echo "        $d annotation stale (${current_hash:0:12}… → ${secret_hash:0:12}…) — patching, K8s will roll"
    kubectl -n "$NS" patch deployment "$d" --type=merge \
      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"checksum/datahub-frontend-secret\":\"$secret_hash\"}}}}}" >/dev/null
  fi
done

echo "    [post-apply] checking datahub-upgrade-job state"
job_status=$(kubectl -n "$NS" get job datahub-upgrade-job \
  -o jsonpath='{.status.conditions[?(@.type=="Failed")].status} {.status.conditions[?(@.type=="Complete")].status}' \
  2>/dev/null || echo "")
job_failed=$(echo "$job_status" | awk '{print $1}')
job_complete=$(echo "$job_status" | awk '{print $2}')

if [[ "$job_failed" == "True" ]]; then
  echo "        datahub-upgrade-job Failed during ESO race — deleting + recreating"
  kubectl -n "$NS" delete job datahub-upgrade-job --ignore-not-found
  if [[ -f "$RENDER" ]]; then
    yq eval-all 'select(.kind == "Job" and .metadata.name == "datahub-upgrade-job")' "$RENDER" \
      | kubectl apply --server-side --force-conflicts -f -
  else
    echo "        FATAL: rendered manifest absent at $RENDER — cannot recreate Job" >&2
    echo "        (apply-component.sh writes this; missing means render step was skipped)" >&2
    exit 2
  fi
elif [[ "$job_complete" == "True" ]]; then
  echo "        datahub-upgrade-job already Complete — idempotent no-op"
  exit 0
fi

# Job sets activeDeadlineSeconds=1800. Wait must exceed that, plus headroom
# for backoff between retries — 2400s gives ~10 min slack so we don't FATAL
# while the Job is still legitimately running.
echo "    [post-apply] waiting datahub-upgrade-job Complete (timeout 2400s — SystemUpdate runs DDL + index bootstrap)"
if ! kubectl -n "$NS" wait --for=condition=Complete job/datahub-upgrade-job --timeout=2400s; then
  echo "        FATAL: datahub-upgrade-job did not Complete in 2400s" >&2
  kubectl -n "$NS" describe job datahub-upgrade-job >&2 || true
  kubectl -n "$NS" logs job/datahub-upgrade-job --tail=80 >&2 || true
  exit 2
fi
echo "        datahub-upgrade-job Complete"
