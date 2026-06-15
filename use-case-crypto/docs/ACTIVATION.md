# Activation runbook — post-build (2026-05-29)

All images rebuilt + pushed to `localhost:5000` (incl. the dbt-image fix
`crypto-dbt-project` digest `166655ebb10e`, `crypto-websocket-collector`,
`crypto-validator`). Source fixes are complete; the cluster now needs the
ordered **activation** below. Each step has a **verify** gate — do not move on
until it passes. Steps marked **[gated]** are live mutations the assistant
cannot run under the auto-mode classifier; run them yourself (or add the noted
Bash permission rule and the assistant will run them).

Run from repo root `~/documents/ta`. ClickHouse pod is `chi-platform-main-0-0-0`
in ns `storage`; CH creds live in secret `storage/clickhouse-credentials`
(`username`/`password`).

---

## 0. Push latest source into Gitea (so app-of-apps + crypto app read it)

Manifest-level source fixes (kserve post-apply heal, falco webui:false+prune,
overlays) are read by ArgoCD from Gitea, not from the image. Re-seed first.

```bash
make seed-gitea
```

**Verify:** command exits 0; prints the platform + use-case-crypto force-push
refs to `gitea.gitops.svc.cluster.local`.

---

## 1. #477 — re-apply the use-case AppProject  (CRITICAL PATH, do first) [gated]

`crypto-use-case-local` is `OutOfSync / Missing` because the **live** AppProject
`use-case-crypto` lacks the `storage` destination, so its sync of the
`clickhouse-kafka-sasl` ExternalSecret into `storage` is rejected
("one or more synchronization tasks are not valid"). The source file already
has `storage` (line 60) but the AppProject is **applied manually**, not
Argo-managed — nothing reconciles it. Re-apply it:

```bash
kubectl apply -f use-case-crypto/argocd/application.yaml
kubectl apply -f use-case-crypto/argocd/applicationset.yaml   # if Application missing
```

**Verify:**
```bash
kubectl get appproject use-case-crypto -n gitops \
  -o jsonpath='{range .spec.destinations[*]}{.namespace}{"\n"}{end}' | grep -x storage
# expect: storage
kubectl get application crypto-use-case-local -n gitops \
  -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# expect eventually: Synced  Healthy   (Progressing first is fine)
```

This also makes the bronze Kafka-SASL secret **reproducible** (replaces the
manual secret copy that has been propping up #464).

---

## 2. Gold / training — populate `gold.fct_training_data`  [gated]

The dbt-image blocker was removed (uv tool install + pinned dbt-clickhouse
1.10.0 now puts a real `dbt` on PATH). Gold is produced by the Airflow
`crypto_lakehouse` DAG — the single canonical gold producer — which runs
`dbt build` (no selector → every model, bronze→silver→gold). This step is
**run-but-unverified** until the dbt job completes against live silver. Trigger
the medallion build:

```bash
# Airflow crypto_lakehouse DAG (orchestrates bronze→silver→gold; `dbt build`, all models)
kubectl exec -n data-processing deploy/airflow-scheduler -- \
  airflow dags trigger crypto_lakehouse
```

**Verify (decisive):**
```bash
u=$(kubectl get secret -n storage clickhouse-credentials -o jsonpath='{.data.username}' | base64 -d)
p=$(kubectl get secret -n storage clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n storage chi-platform-main-0-0-0 -c clickhouse -- \
  clickhouse-client --user "$u" --password "$p" -q \
  "SELECT count() FROM gold.fct_training_data"
# expect: > 0
```
If 0: check the dbt pod logs for CH auth, the `secure:false` profile, mart SQL,
or empty `silver.stg_ohlcv` (which would point back at the ingest→bronze→silver
path, not dbt).

---

## 3. #468/#469 — roll producers onto new images  [gated]

`crypto-websocket-collector` + `crypto-validator` rebuilt with
`message.timeout.ms` 5000→120000 and lz4→zstd. Pods carry
`imagePullPolicy: Always`, so a restart pulls fresh:

```bash
kubectl rollout restart deploy/crypto-websocket-collector -n use-case-crypto
kubectl rollout restart deploy/crypto-validator           -n use-case-crypto
```

**Verify:** producer logs show no `MessageTimedOut` / compression-mismatch for
2–3 min; `bronze.crypto_ohlcv` count keeps climbing (query as in step 2).

---

## 4. #473 — predictor storage-init heal  [gated]

`platform-health-check-predictor` CrashLoops (`InvalidModelURI /mnt/models`):
its pod was created in a webhook-down window, so the storage-init initContainer
was never injected (`failurePolicy: Ignore`). The source self-heal already
exists in `platform/components/model-serving/kserve/post-apply.sh` (deletes
predictor pods lacking `storage-initializer` so the ReplicaSet recreates them
against the now-live webhook). Run the model-serving apply (which invokes it):

```bash
make apply-component COMPONENT=model-serving      # or: bash platform/scripts/apply-component.sh model-serving
```

**Pre-check the model bundle survived the data wipes** (else heal yields a
download failure, not a fix). The bundle is reproducible via the
`train-iris-model` init container in `platform/components/storage/minio/bucket-bootstrap.yaml`:
```bash
kubectl exec -n storage deploy/minio -- mc ls local/platform-models/sklearn/iris/ 2>/dev/null || \
  echo "bundle missing → re-run: make apply-component COMPONENT=storage  (re-runs bucket-bootstrap)"
```

**Verify:**
```bash
p=$(kubectl get pods -n model-serving -l serving.kserve.io/inferenceservice=platform-health-check \
  --no-headers | awk '{print $1; exit}')
kubectl get pod -n model-serving "$p" \
  -o jsonpath='init=[{range .spec.initContainers[*]}{.name} {end}] {.status.phase}{"\n"}'
# expect: init=[storage-initializer ...]  Running
```

---

## 5. Final state check

```bash
kubectl get applications -n gitops | grep -vE 'Synced.*Healthy'   # expect: only header
kubectl get pods -A | grep -vE 'Running|Completed|Succeeded'      # expect: empty
```

---

## Remaining (design / out-of-band, not blockers)

- **#476** Flink → `crypto.features.v1`: StreamJob sinks features to Valkey only
  (online serving works); a Kafka sink to `crypto.features.v1` is a design choice,
  not a training blocker (training reads gold from dbt). Decide: wire `KafkaSink`,
  enrich the dbt mart, or remove the unused `bronze.crypto_ohlcv_features` path.
- **#475** Flink operator status `RECONCILING` while the job is healthy — cosmetic
  (#349-class operator/informer lag).
- **#347** rotate `pipeline-secrets` `POSTGRES_PASSWORD` (post-leak hygiene).
- **#331** k3s embedded-etcd migration (user-executed, infra).
