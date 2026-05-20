# Platform Remediation Runbook

Execution order, prerequisites, rollback, and verification for the remediation
changes authored in this repo. Follow the phases top-to-bottom; each phase is
idempotent — re-running is safe.

Scope: single-node thesis defense cluster (k3s) → multi-node production. The
manifests are domain-agnostic; use-case specifics live in the use-case repo
(see `<use-case>/docs/RUNBOOK.md` for use-case-specific procedures).

## 0 — Prerequisites

These must be present on the cluster before any phase runs.

- `kubectl` context pointing at the target cluster
- k3s 1.33+ with `--disable=traefik --disable=servicelb`
- Host packages on every node: `open-iscsi`, `nfs-common` (Longhorn)
- cluster DNS working (`kubectl run -it --rm test --image=busybox:1.36 -- nslookup kubernetes.default`)

Bootstrap order of the core dependencies (ArgoCD sync-waves assume this):

1. `cert-manager`          — webhook & mTLS certs (wave -20)
2. `external-secrets`      — ESO operator + ClusterSecretStore (wave -15)
3. `vault`                 — trust root, unsealed by init Job (wave -15)
4. `longhorn`              — default StorageClass (wave -10)
5. `minio`                 — object storage (wave -5)
6. `minio-bucket-bootstrap`— creates every bucket the platform needs (wave 5)
7. everything else         — wave 0

## 1 — Fix WAL archive failure (CNPG)

Symptom: `cnpg_pg_stat_archiver_failed_count` > 0 and alert
`CNPGWALArchiveFailing` firing. Cause: CNPG 1.26+ dropped the in-tree
`.spec.backup.barmanObjectStore` field and requires the Barman Cloud
plugin. The MinIO bucket `cnpg-backups` also did not exist.

### Changes in this repo

- `platform/components/storage/postgresql/cluster.yaml`
  - Removed inline `backup.barmanObjectStore`
  - Added `.spec.plugins[].name=barman-cloud.cloudnative-pg.io`
  - New `ObjectStore` CR `postgresql-backup-store`
  - `ScheduledBackup` now uses `method: plugin`
- `platform/components/storage/cnpg/plugin-barman-cloud.yaml` — ArgoCD
  Application installs the plugin from `cloudnative-pg.github.io/charts`
- `platform/components/storage/minio/bucket-bootstrap.yaml` — Job creates
  every required bucket (`cnpg-backups`, `mlflow`, `warehouse`, …) and
  configures lifecycle

### Apply order

```bash
# 1. Make sure cert-manager is Ready (plugin webhook depends on it)
kubectl wait --for=condition=Available deploy -n cert-manager --all --timeout=300s

# 2. Install the barman-cloud plugin (ArgoCD auto-syncs from GitOps, or:)
kubectl apply -k platform/components/storage/cnpg

# 3. Wait for the plugin Deployment Ready
kubectl wait --for=condition=Available deploy \
  -n cnpg-system -l app.kubernetes.io/name=plugin-barman-cloud --timeout=300s

# 4. Bootstrap MinIO buckets (idempotent)
kubectl apply -k platform/components/storage/minio
kubectl wait --for=condition=Complete job/minio-bucket-bootstrap \
  -n storage --timeout=180s

# 5. Apply the updated Cluster + ObjectStore
kubectl apply -k platform/components/storage/postgresql
```

### Verification

```bash
# Plugin reports the cluster healthy
kubectl cnpg status postgresql -n storage | grep -E '(WAL archiver|Plugins)'

# A backup completes successfully
kubectl cnpg backup postgresql -n storage \
  --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io
kubectl get backup -n storage --sort-by=.metadata.creationTimestamp

# The MinIO bucket now holds base/ and wals/
mc ls platform/cnpg-backups/pg/
```

### Rollback

The old `.spec.backup.barmanObjectStore` field no longer exists in CNPG
≥1.30, so rollback means pinning the operator to 1.25 and reverting
`cluster.yaml` from git. Prefer forward fix.

## 2 — Fix Vault readiness probe

Symptom: `vault` StatefulSet pods never reach Ready; init Job blocks.
Cause: the former `hashicorp/vault:1.21.x` image did not ship `jq`, but the
readiness probe piped `vault status` through it. Probe always returned
exit 1 regardless of Vault state. (Image since migrated to OpenBao 2.5.3.)

### Changes

- `platform/components/security/vault/statefulset.yaml` — readiness probe
  replaced with `httpGet /v1/sys/health?standbyok=true&perfstandbyok=true`

### Apply

```bash
kubectl apply -k platform/components/security/vault
# The rolling update cycles the 3 replicas one at a time.
kubectl rollout status sts/vault -n security --timeout=300s
```

### Verify

```bash
kubectl get pod -n security -l app=vault -w     # all 3 become Ready
kubectl exec -n security vault-0 -- vault status
```

## 3 — Migrate legacy hardcoded secrets to ExternalSecret

Symptom: `data: minioadmin123` literals in `flink/deployment.yaml`,
`spark/deployment.yaml`. Cause: pre-ESO scaffolding.

### Changes

- `platform/components/data-processing/flink/deployment.yaml` — the plain
  `Secret` block replaced with an `ExternalSecret` reading
  `platform/minio/root` from Vault.
- `platform/components/data-processing/spark/deployment.yaml` — same.

### Apply

```bash
kubectl apply -k platform/components/data-processing/flink
kubectl apply -k platform/components/data-processing/spark
# Verify the materialised Secrets
kubectl get secret -n data-processing flink-s3-secret spark-s3-secret
```

## 4 — Install new operators (Flink, Spark, KEDA)

These install alongside the existing plain-Deployment Flink / Spark
submit patterns; nothing is removed yet. Migrate jobs to the CR shape
once the new operators are green.

### Changes

- `platform/components/data-processing/flink/flink-operator.yaml`
  (Apache Flink Kubernetes Operator 1.12 + reference FlinkDeployment)
- `platform/components/data-processing/spark/spark-operator.yaml`
  (Kubeflow Spark Operator 2.3 + reference SparkApplication)
- `platform/components/common/keda/*` (KEDA 2.19)
- `platform/components/data-ingestion/kafka/scaledobject-template.yaml`
  (KEDA TriggerAuthentication + reference ScaledObject for Kafka lag)

### Apply

```bash
kubectl apply -k platform/components/common/keda
kubectl apply -k platform/components/data-processing/flink
kubectl apply -k platform/components/data-processing/spark
kubectl apply -k platform/components/data-ingestion/kafka
```

### Verify

```bash
kubectl get pods -n flink-operator
kubectl get flinkdeployment -n data-processing
kubectl get pods -n spark-operator
kubectl get pods -n keda
kubectl get scaledobjects -A
```

## 5 — Alerting

Symptom: no backup / security / ingestion alerts.

### Changes

- `platform/components/observability/kube-prometheus-stack/prometheus-rules.yaml`
  — 5 new groups, 14 alerts covering: CNPG WAL archive, Velero partial,
  ClickHouse backup staleness, Vault sealed, ESO sync failure, Kyverno
  violations, Cosign verify, Kafka lag/ISR, DataHub ingestion failures,
  MLflow run failures, model staleness, KServe restarts, Evidently drift,
  Longhorn volume degraded, OTel Collector down, Chaos Mesh experiment
  failure. (`PrometheusAdapterDown` retired 2026-04-21 with the adapter
  itself — ADR-026; KEDA's metrics-apiserver is covered by the stock
  `KubeAPIServerErrors` alert via its standard APIService registration.)

### Apply

```bash
kubectl apply -k platform/components/observability/kube-prometheus-stack
# Confirm Prometheus picks them up
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s localhost:9090/api/v1/rules | jq '.data.groups[].name' | sort
```

## 6 — GitOps activation (AppProject + ApplicationSet)

Once every component above is green in manual-apply mode, flip the
cluster to ArgoCD:

```bash
# 1. Push this repo to Gitea
git push gitea main

# 2. Bootstrap ArgoCD (one-time)
kubectl apply -k platform/components/gitops/argo-cd

# 3. Wait, then apply app-of-apps (AppProject + ApplicationSet)
kubectl apply -f platform/components/gitops/argo-cd/app-of-apps.yaml

# 4. Watch ArgoCD reconcile each component
kubectl get application -n gitops -w
```

From this point forward every change is a git commit — do not
`kubectl apply` directly.

## 7 — Use-case post-migration hostname updates

After the platform CHI is reconciling (gated on default StorageClass per §0),
use-case overlays must point their ClickHouse references at the operator-managed
Service DNS (`clickhouse-platform.storage.svc.cluster.local`) instead of the
legacy pre-operator hostname. Pod-specific DNS is fragile to topology changes —
prefer the load-balanced Service DNS.

See `<use-case>/docs/RUNBOOK.md` §7 for the use-case-specific file list and
sed commands.

## 8 — Data migration (only if upgrading from pre-operator single-pod)

This phase is **optional** and applies only to operators upgrading an
existing pre-ADR-011 cluster in which the legacy single-pod
`postgres.data-ingestion`, `clickhouse.storage`, and
`kafka.data-ingestion` workloads still hold production data.

Greenfield installs bootstrap empty schemas from the operator CRs in
phases 1, 4, and the storage kustomization — skip this phase entirely.

The legacy Deployments have already been removed from the repo (Task
#34, see `components/storage/{postgresql,clickhouse}/kustomization.yaml`
comments). If the live cluster still runs them they were deployed
out-of-band; keep them reachable until the corresponding subsection
completes, then delete them manually.

### 8.1 PostgreSQL — legacy pod → CloudNativePG Cluster

Target: CNPG Cluster `postgresql` in namespace `storage` (3 replicas,
PG 18.3, PITR to MinIO). CNPG supports native import only at initdb
time via `bootstrap.initdb.import` — it runs `pg_dump | pg_restore`
inside the bootstrapper.  See
`https://cloudnative-pg.io/documentation/current/database_import/`.

**Preferred — sibling-Cluster import then swap.** Because `postgresql`
is already bootstrapped, provision a new sibling Cluster that imports
from the legacy pod, then cut consumers over by swapping the Service
selector (or Pooler `spec.cluster.name`) to the new Cluster and
decommissioning the old one:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgresql-import
  namespace: storage
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.3-trixie
  storage:
    size: 50Gi
    storageClass: longhorn
  bootstrap:
    initdb:
      # Use `monolith` to copy every database + roles; switch to
      # `microservice` if only a single database must be migrated.
      import:
        type: monolith
        databases: ["*"]
        roles: ["*"]
        source:
          externalCluster: postgres-legacy
  externalClusters:
    - name: postgres-legacy
      connectionParameters:
        host: postgres-legacy.data-ingestion.svc.cluster.local
        user: postgres
        dbname: postgres
        sslmode: prefer
      password:
        name: postgres-legacy-credentials
        key: password
```

**Fallback — `pg_dumpall` into the existing Cluster** when the legacy
pod is already stopped and a sibling-Cluster cutover isn't viable.
Note this mixes imported data with any already-bootstrapped state, so
only run against an otherwise-empty target:

```bash
kubectl -n data-ingestion exec deploy/postgres-legacy -- \
  pg_dumpall --clean --if-exists > /tmp/pg-legacy.sql
PG_PRIMARY=$(kubectl -n storage get pod \
  -l cnpg.io/cluster=postgresql,role=primary -o name)
kubectl -n storage cp /tmp/pg-legacy.sql "$PG_PRIMARY":/tmp/pg-legacy.sql
kubectl -n storage exec "$PG_PRIMARY" -- \
  psql -U postgres -f /tmp/pg-legacy.sql
```

### 8.2 ClickHouse — legacy pod → Altinity CHI

Target: CHI `platform` in `storage` (2-shard × 2-replica, Keeper
quorum). Because every legacy table is re-creatable by the ingest
layer, the pull-replication pattern is preferred over `clickhouse-
backup` dump/restore — it streams without hitting disk:

```sql
-- Run on any CHI replica, once per database/table pair:
INSERT INTO <db>.<table>
SELECT * FROM remote(
  'clickhouse-legacy.storage:9000',
  '<db>.<table>',
  'default', '${CH_LEGACY_PASSWORD}'
);
```

Materialised views must be recreated from DDL after the backfill
(`remote()` does not copy `CREATE MATERIALIZED VIEW` statements).

### 8.3 Kafka — legacy pod → Strimzi cluster (MirrorMaker2)

Target: Strimzi Kafka `platform` in `data-ingestion` (4.2.0, 3-broker
KRaft, bootstrap `platform-kafka-kafka-bootstrap.data-ingestion:9092`). Use
MirrorMaker2 as a transient bridge so producers/consumers can cut over
at their own pace:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaMirrorMaker2
metadata:
  name: kafka-migration
  namespace: data-ingestion
spec:
  version: 4.2.0
  replicas: 1
  connectCluster: target
  clusters:
    - alias: source
      bootstrapServers: kafka-legacy.data-ingestion:9092
    - alias: target
      bootstrapServers: platform-kafka-kafka-bootstrap.data-ingestion:9092
      config:
        replication.factor: 3
        offset-syncs.topic.replication.factor: 3
  mirrors:
    - sourceCluster: source
      targetCluster: target
      topicsPattern: ".*"
      groupsPattern: ".*"
      sourceConnector:
        tasksMax: 3
```

Delete the `KafkaMirrorMaker2` CR once every consumer group reports 0
lag against the target cluster and use-case producers point at
`platform-kafka-bootstrap`.

### 8.4 Verification

| Store       | Check                                                                  |
|-------------|------------------------------------------------------------------------|
| PostgreSQL  | `kubectl cnpg status postgresql -n storage` → `Cluster in healthy state` and `SELECT count(*)` matches per table |
| ClickHouse  | `SELECT count() FROM <db>.<table>` matches on source and target CHIs   |
| Kafka       | `kafka-consumer-groups.sh --describe --all-groups` reports 0 lag on `target` |

### 8.5 Rollback

All three operators coexist with legacy workloads on distinct DNS names
(`postgres-legacy`, `clickhouse-legacy`, `kafka-legacy`), so rollback
is a consumer-side hostname flip:

- Revert use-case ConfigMaps back to the legacy hostnames
  (reverse of Phase 7).
- Leave the operator CRs running — they hold no authoritative data
  until migration completes and do no harm idling.

## 9 — SSE-KMS via KES sidecar

Symptom: MinIO deployment had `MINIO_KMS_AUTO_ENCRYPTION: "on"` but no
KES endpoint wired, so PUTs would have returned `503 Slow Down` with
`kms: key server unreachable`. Cause: SSE-KMS requires a running KES
server — the inert `MINIO_KMS_SECRET_KEY` env alone cannot satisfy it.
ADR-008 calls for Vault as the key store with KES as MinIO's KMS
front-end.

### Architecture

The KES 2025-03 `keystore.vault` backend is strictly K/V-based — no
transit-only variant exists (verified against the official reference
config at `github.com/minio/kes/tree/2025-03-12T09-35-18Z`). We use a
two-tier design:

```
MinIO ──mTLS──▶ KES ──approle──▶ Vault
                                 ├─ kes-kv/ (KV v1)  ← master keys live here
                                 │    kes-kv/kes/minio-master-key = ciphertext
                                 └─ transit/         ← wraps KV entries
                                      transit/keys/kes-wrap  (AES-256-GCM)
```

Master keys referenced by MinIO (`MINIO_KMS_KES_KEY_NAME=minio-master-key`)
are stored *by KES* in `kes-kv/kes/<name>`; each K/V entry is wrapped
with `transit/kes-wrap` before write.  The wrap key `kes-wrap` never
leaves Vault — KES only exercises its `encrypt`/`decrypt` endpoints.

### Changes in this repo

- `platform/components/security/kes/` (new dir)
  - `deployment.yaml` — KES Deployment + ServiceAccount + Service
    (`kes.security.svc.cluster.local:7373`). Two initContainers:
    `wait-for-vault` polls `/v1/sys/health`; `render-config` reads
    the MinIO client cert from the `storage` namespace via cross-ns
    RBAC, computes its SPKI SHA-256 identity with `openssl`, and
    substitutes the three placeholders (`VAULT_APPROLE_ID`,
    `VAULT_APPROLE_SECRET`, `MINIO_CLIENT_IDENTITY`) into the config
    template using `sed` (busybox-core, no gettext dependency).
    readinessProbe + livenessProbe are `tcpSocket` — the KES image
    is `FROM scratch` and ships neither shell nor `wget`.
  - `configmap.yaml` — KES server config template.  Flat TLS schema
    (`tls.auth: "on"` + `tls.ca`, not the pre-2025 nested `tls.client.*`).
    Per-API override disables auth on `/v1/metrics` only (scraped
    by kube-prometheus-stack without a client cert).  Keystore:
    Vault KV v1 at `kes-kv/` with `prefix: "kes"`, transit overlay
    `transit/kes-wrap`.
  - `certificate.yaml` — cert-manager `Certificate` CRs for the KES
    server TLS pair (`kes-server-tls` in `security` ns, 90d duration,
    `rotationPolicy: Always`) and the MinIO→KES client TLS pair
    (`minio-kes-client` in `storage` ns, 2y duration,
    `rotationPolicy: Never` — identity hash must be stable).  Both
    issued by the `platform-ca` ClusterIssuer.
  - `externalsecret.yaml` — pulls `role_id` + `secret_id` from
    `secret/platform/kes/vault-auth`, targeting Secret `kes-vault-auth`
    in `security` ns with `creationPolicy: Merge` (coexists with the
    direct-write from vault-bootstrap for first-boot ordering).
  - `kustomization.yaml` — resource list only.  Deliberately NO
    `namespace:` field — setting it would rewrite the cross-ns
    `minio-kes-client` Certificate and `kes-minio-cert-reader`
    RBAC (both must stay in `storage` ns).
- `platform/components/security/vault/vault-bootstrap.yaml`
  - `vault secrets enable -path=kes-kv -version=1 kv` — dedicated
    KV v1 mount for KES master-key storage.
  - `vault secrets enable -path=transit transit` + `vault write -f
    transit/keys/kes-wrap type=aes256-gcm96` — the wrap key.
  - `vault policy write kes-keystore` granting `create/read/update/
    delete` on `kes-kv/kes/*` (+ `list` on `kes-kv/kes`) and
    `update` on `transit/{encrypt,decrypt}/kes-wrap`.  No access
    to `transit/keys/kes-wrap` itself — KES never rotates or
    destroys the wrap key.
  - `vault auth enable approle` + `vault write auth/approle/role/
    kes-minio policies=kes-keystore token_ttl=1h token_max_ttl=24h
    secret_id_ttl=0`.
  - `role_id` + `secret_id` direct-written to the `kes-vault-auth`
    Secret in the `security` namespace (mirrors the `vault-unseal`
    pattern) and copied to `secret/platform/kes/vault-auth` for
    ESO sync + rotation audit.
- `platform/components/security/kustomization.yaml` — adds `- kes`
  after `- vault`, so the sync order is vault → kes → the rest.
- `platform/components/storage/minio/deployment.yaml`
  - Added env: `MINIO_KMS_KES_ENDPOINT=https://kes.security.svc.cluster.local:7373`,
    `MINIO_KMS_KES_CERT_FILE=/etc/kes/certs/tls.crt`,
    `MINIO_KMS_KES_KEY_FILE=/etc/kes/certs/tls.key`,
    `MINIO_KMS_KES_CAPATH=/etc/kes/certs/ca.crt`,
    `MINIO_KMS_KES_KEY_NAME=minio-master-key`.
  - Added volume + volumeMount for the cert-manager-issued
    `minio-kes-client` Secret at `/etc/kes/certs` (defaultMode 0400).
  - Removed `MINIO_KMS_SECRET_KEY` from the ExternalSecret data[]
    (inert without KES; the master key now lives in Vault KV).

### Apply order

```bash
# 1. Vault must be unsealed (§2) before the keystore block runs
kubectl -n security get pod -l app=vault                  # Running + unsealed
kubectl apply -k platform/components/security/vault
kubectl wait --for=condition=complete job/vault-bootstrap \
  -n security --timeout=300s

# 2. Apply KES manifests (cert-manager must be Ready — §0).
#    The MinIO client Certificate is also created here (storage ns),
#    so KES's render-config initContainer will find it on first boot.
kubectl apply -k platform/components/security/kes
kubectl rollout status deploy/kes -n security --timeout=180s

# 3. Roll MinIO so the new env + TLS volume mount take effect
kubectl apply -k platform/components/storage/minio
kubectl rollout status deploy/minio -n storage --timeout=180s

# 4. One-time: create the KES master key that MinIO references.
#    KES does NOT auto-create keys on first use — MinIO's generate
#    call will 404 until this exists.  The MINIO_KMS_KES_KEY_NAME
#    value (minio-master-key) must match exactly.
kubectl -n storage exec deploy/minio -- \
  mc admin kms key create platform minio-master-key
```

### Verification

The single authoritative check: `mc admin kms key status` must
return Success.  Anything else (pods Ready, cert Ready, Vault
Ready) is necessary-but-not-sufficient — the end-to-end path is
MinIO → KES client TLS → KES → Vault approle → KV write
(`kes-kv/kes/minio-master-key`) wrapped via
`transit/encrypt/kes-wrap`, and every link has to work.

```bash
# 1. Authoritative end-to-end check — MUST return Success
kubectl -n storage exec deploy/minio -- \
  mc admin kms key status platform minio-master-key
# Expected:
#   Key: minio-master-key
#   - Encryption: Success
#   - Decryption: Success

# 2. Bucket-level sanity — encryption marker present on new objects
kubectl -n storage exec deploy/minio -- \
  mc cp /etc/hostname platform/mlflow/.kms-test
kubectl -n storage exec deploy/minio -- \
  mc stat platform/mlflow/.kms-test | grep -i encryption
# X-Amz-Server-Side-Encryption:            aws:kms
# X-Amz-Server-Side-Encryption-Aws-Kms-Key-Id: minio-master-key

# 3. KES ↔ Vault path: provision a second key and repeat (1).
#    Must go through MinIO (mc) rather than `kes` CLI because
#    admin.identity is set to "disabled" — only MinIO's identity
#    is authorised to call /v1/key/create/minio-*.
kubectl -n storage exec deploy/minio -- \
  mc admin kms key create platform minio-master-key-v2
kubectl -n storage exec deploy/minio -- \
  mc admin kms key status platform minio-master-key-v2
```

Triage if step 1 fails:

- `key server unreachable` → KES→Vault approle is broken.  Check
  `kubectl -n security logs deploy/kes | grep -i vault`.  Usual
  cause: approle secret_id expired (shouldn't happen with
  `secret_id_ttl=0`) or rotated out-of-band.
- `access denied` → `kes-keystore` Vault policy is missing a
  path.  Dump with `kubectl -n security exec vault-0 -c vault --
  vault policy read kes-keystore` and compare against
  vault-bootstrap.yaml.
- `x509: certificate signed by unknown authority` → MinIO pod
  does not trust `platform-ca`; confirm `/etc/kes/certs/ca.crt`
  is mounted from Secret `minio-kes-client` and the Certificate
  CR's `issuerRef` points at the `platform-ca` ClusterIssuer.
- `not found: key minio-master-key` → step 4 of the apply order
  was skipped; run `mc admin kms key create` once.

### Rollback

Disabling SSE-KMS on a bucket that holds encrypted objects leaves
them undecryptable — KES, the Vault KV entry, and the transit wrap
key must stay up until every object is rewritten or the bucket is
drained. To roll the feature back safely:

```bash
# 1. Disable auto-encryption so new PUTs don't use KES
kubectl -n storage set env deploy/minio MINIO_KMS_AUTO_ENCRYPTION-
# 2. Rewrite every encrypted object without SSE-KMS
mc cp --recursive --preserve platform/<bucket>/ platform/<bucket>/
# 3. Only then remove the KES env + mounts and delete the kes dir.
#    Leave the Vault KV entries + transit key in place as an audit
#    trail — they're inert once MinIO no longer references them.
```

## 10 — Live-cluster (bucket C) one-off remediations

These are **operational** cleanups for a specific stuck cluster
(the 2026-04-18 audit, disk 88%). They are not file changes —
each fix deletes or patches live state that drifted from the
GitOps desired-state. Re-running is safe; each step is idempotent.

Run top-to-bottom. Stop if any step fails and triage before
continuing — later steps assume earlier ones landed.

### 10.1 Vault-0 readiness (jq-missing probe)

The file fix is §2, but existing pods keep the old probe spec
until they're deleted. Force a rollout:

```bash
kubectl -n security rollout restart sts/vault
kubectl -n security rollout status sts/vault --timeout=300s
kubectl -n security exec vault-0 -- vault status | grep -i sealed
```

### 10.2 MinIO `cnpg-backups` bucket creation (if missing)

`minio-bucket-bootstrap` Job is idempotent and normally covers
this. If the Job was never run (e.g. cluster bootstrapped before
Task #45) the bucket is absent:

```bash
kubectl -n storage get job minio-bucket-bootstrap \
  -o jsonpath='{.status.succeeded}'
# If empty or 0, re-apply:
kubectl -n storage delete job minio-bucket-bootstrap --ignore-not-found
kubectl apply -k platform/components/storage/minio
kubectl wait --for=condition=complete job/minio-bucket-bootstrap \
  -n storage --timeout=180s
# Confirm
kubectl -n storage exec deploy/minio -- mc ls platform/ | grep cnpg-backups
```

### 10.3 Stuck `longhorn-system` namespace (stale APIService)

Deleting the Longhorn chart left the namespace in `Terminating`
because a stale APIService (`v1beta1.longhorn.io`) still pointed
at a now-missing service, blocking the namespace finalizer.

```bash
# Identify stale APIServices
kubectl get apiservice | grep -iE '(longhorn|False)'
# Delete the stuck ones, e.g.:
kubectl delete apiservice v1beta1.longhorn.io v1beta2.longhorn.io
# The ns finalizer unblocks within ~30s
kubectl get ns longhorn-system
```

Do NOT patch the namespace finalizer list directly unless the
APIService deletion does not clear the state — bypassing the
finalizer leaks finalizer-protected CRDs.

### 10.4 Velero CRD-upgrade Job replacement

The `velero-upgrade-crds` Job is Helm-managed and runs once per
chart upgrade; pre-existing failed/partial runs block the next
upgrade.

```bash
kubectl -n velero get job velero-upgrade-crds -o yaml > /tmp/job.yaml
kubectl -n velero delete job velero-upgrade-crds --ignore-not-found
# Helm/ArgoCD will recreate the Job on next sync:
kubectl -n gitops patch application velero \
  --type merge -p '{"operation":{"sync":{}}}'
kubectl -n velero wait --for=condition=complete job/velero-upgrade-crds \
  --timeout=180s
```

### 10.5 workflow-controller (Argo Workflows) dead Deployment

Orphaned Deployment from an older platform attempt. Safe to
delete — not referenced by any current kustomization:

```bash
kubectl -n argo get deploy workflow-controller --ignore-not-found \
  -o jsonpath='{.metadata.ownerReferences}'
# If empty (no ArgoCD owner), delete:
kubectl -n argo delete deploy workflow-controller --ignore-not-found
# If argo ns is otherwise empty:
kubectl delete ns argo --ignore-not-found
```

### 10.6 KServe `llmisvc-*` / `kserve-localmodel-*` scale-to-0

These controllers burn CPU on a thesis cluster that does not use
LLM inference services or local-model caching. Scale to 0 rather
than delete, so re-enabling is a one-liner:

```bash
for d in llmisvc-controller-manager kserve-localmodel-controller-manager; do
  kubectl -n kserve get deploy "$d" --ignore-not-found \
    && kubectl -n kserve scale deploy "$d" --replicas=0
done
```

To re-enable later: `kubectl -n kserve scale deploy <name> --replicas=1`.

### 10.7 SeaweedFS dead Deployment

Not used by any current manifest (Longhorn + MinIO cover block +
object storage). Delete the namespace:

```bash
kubectl get ns seaweedfs --ignore-not-found
kubectl delete ns seaweedfs --ignore-not-found
```

### 10.8 CHI `platform` non-reconciliation

Symptom: `kubectl get chi -n storage platform` shows
`status.status: In progress` indefinitely. Cause: the default
StorageClass was missing (Longhorn not installed yet) or the
Keeper StatefulSet pod cannot resolve its peer DNS.

```bash
# Diagnose
kubectl get sc | grep '(default)'            # longhorn must be default
kubectl -n storage describe chi platform | tail -40
kubectl -n storage logs sts/chi-platform-main-0-0 --tail=50
# If Keeper log shows "Keeper quorum not reached":
kubectl -n storage rollout restart sts/chi-platform-keeper
# If SC is missing, install Longhorn first (§0) and re-apply.
kubectl apply -k platform/components/storage/clickhouse
```

### 10.9 Kafka MirrorMaker2 cutover

Once §8.3 MM2 has been up long enough for every consumer group
to report 0 lag, tear it down:

```bash
# Check lag across all groups
kubectl -n data-ingestion exec -c kafka platform-kafka-kafka-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --all-groups \
  | awk '$5>0{print $0}'
# If empty (no lag): delete MM2
kubectl -n data-ingestion delete kafkamirrormaker2 kafka-migration \
  --ignore-not-found
```

### 10.10 KEDA metrics-apiserver restart

prometheus-adapter retired 2026-04-21 (ADR-026). KEDA 2.19.0 now owns
the `custom.metrics.k8s.io` / `external.metrics.k8s.io` APIService
registrations cluster-wide. If a ScaledObject stops making scaling
decisions, the usual first suspect is the metrics-apiserver Deployment:

```bash
kubectl -n keda get deploy keda-operator-metrics-apiserver
kubectl -n keda rollout restart deploy keda-operator-metrics-apiserver
kubectl -n keda rollout status deploy keda-operator-metrics-apiserver --timeout=120s
# External metrics API must respond (200, empty list OK before ScaledObjects reconcile):
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | head -c 200
# Also check the APIService itself is Available=True:
kubectl get apiservice v1beta1.external.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
```

If the APIService reports `MissingEndpoints`, the keda-operator-metrics-apiserver Service has no ready pods — the restart above recovers. For `FailedDiscoveryCheck`, check for concurrent webhook-timeout errors from the KEDA admission webhook.

### 10.11 KES key-status validation (blocking check for §9)

This is the gate that proves the whole SSE-KMS chain works.
Do not mark the cluster remediated until this returns Success:

```bash
# Pre-requisite: the master key must have been created via §9 step 4
#   kubectl -n storage exec deploy/minio -- \
#     mc admin kms key create platform minio-master-key
kubectl -n storage exec deploy/minio -- \
  mc admin kms key status platform minio-master-key
# Expected:
#   Key: minio-master-key
#   - Encryption: Success
#   - Decryption: Success
```

If this fails after §9 has been applied, triage in this order:

1. `kubectl -n security get pod -l app=kes` — pod Ready.
2. `kubectl -n security logs deploy/kes --tail=50` —
   Vault-login errors (e.g. `403 invalid role or secret_id`)
   point at the approle; TLS errors (`bad certificate`,
   `unknown authority`) point at the cert-manager trust chain.
3. `kubectl -n security exec vault-0 -c vault -- \
       vault read transit/keys/kes-wrap` — the transit wrap key
   must exist (NOT `transit/keys/minio-master-key` — that name
   was retired when KES switched from transit-direct to
   KV + transit-wrap).
4. `kubectl -n security exec vault-0 -c vault -- \
       vault list auth/approle/role` — role `kes-minio` present.
5. `kubectl -n security exec vault-0 -c vault -- \
       vault kv get kes-kv/kes/minio-master-key` — KES master key
   entry present (ciphertext; success just means the path exists).
6. Missing step 4 of §9 apply order is the most common root cause:
   `mc admin kms key create platform minio-master-key` must have
   been run once after KES came up.

### 10.12 Kyverno chart 3.4.0 → 3.7.0 (Kyverno 1.17.1)

Why: chart 3.4.0 shipped the 1.17.0-beta CEL engine with a known
`ImageValidatingPolicy` keyless-attestor issue that returned spurious
`Deny` when the Rekor upstream responded out-of-order
(kyverno/kyverno#10428, fixed in 1.17.1 / chart 3.7.0, released
2026-02-19).

### Changes in this repo

- `platform/components/security/kyverno/helm-release.yaml`
  - `targetRevision: 3.4.0` → `3.7.0`
  - Added explicit resource requests/limits to `cleanupController` and
    `reportsController` so every controller pod satisfies the
    `require-resource-limits` ValidatingPolicy defined in policies.yaml.
    The admissionController + backgroundController already had them; the
    other two inherited an empty block that caused a self-admission
    loop on upgrade.

### Apply order

```bash
# 1. ArgoCD auto-sync (rolling restart, no CRD migration needed).
kubectl -n gitops patch application kyverno --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 2. Wait for controllers at the new version.
for d in kyverno-admission-controller kyverno-background-controller \
         kyverno-cleanup-controller kyverno-reports-controller; do
  kubectl -n kyverno rollout status deploy "$d" --timeout=300s
done

# 3. Verify the CEL engine is live.
kubectl api-resources | grep -E 'policies.kyverno.io/v1'
# Expected: validatingpolicies, mutatingpolicies, imagevalidatingpolicies
```

### Verification

```bash
kubectl -n kyverno get pod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

kubectl get validatingpolicy -o json \
  | jq -r '.items[] | "\(.metadata.name)\t\(.status.conditions[]|select(.type=="Ready")|.status)"'

kubectl get imagevalidatingpolicy verify-platform-images-cosign -o yaml \
  | yq .status.lastGeneration
```

### Rollback

Git-revert the chart bump, then force-sync.  No state change; safe at
any time.

### 10.13 KServe v0.11.0 Kustomize override removal + smoke test

Symptom: `kserve-controller-manager` CrashLoopBackOff with
`failed to generate webhook cert: secret "kserve-webhook-server-cert" not found`
every 60 s.  Root cause: `kustomization.yaml` pinned
`kserve/kserve-controller → v0.11.0` (2023) while the Deployment's
container spec declared v0.17.0 (2026-03-13).  The v0.11.0 controller
did not know how to generate its webhook cert without a cert-manager
Issuer — the v0.17.0 path handles it natively.

### Changes in this repo

- `platform/components/model-serving/kserve/kustomization.yaml`
  - Removed the `images: kserve/kserve-controller → v0.11.0` override so
    the Deployment's declared v0.17.0 wins.
  - Added `demo-health-check.yaml` to `resources:`.
- `platform/components/model-serving/kserve/demo-health-check.yaml`
  — new.  Domain-agnostic sklearn iris InferenceService + 10-minute
  CronJob probe for KF-05 evidence.

### Apply order

```bash
# 1. Force ArgoCD to re-render.
kubectl -n gitops patch application platform-model-serving --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 2. Verify the controller image.
kubectl -n model-serving get deploy kserve-controller-manager \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: kserve/kserve-controller:v0.17.0
kubectl -n model-serving rollout status deploy kserve-controller-manager --timeout=300s

# 3. Exercise the smoke test.
kubectl -n model-serving wait --for=condition=Ready isvc/platform-health-check --timeout=300s
kubectl -n model-serving create job \
  --from=cronjob/platform-health-check-probe probe-manual-$(date +%s)
kubectl -n model-serving logs -l job-name=probe-manual* --tail=20
# Expected: `"predictions":[...]` in the response body
```

### Verification

```bash
kubectl -n model-serving get isvc platform-health-check -o wide

kubectl -n model-serving get jobs -l app.kubernetes.io/purpose=platform-smoke-test \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.succeeded}{"\n"}{end}'
```

### Rollback

```bash
kubectl -n model-serving delete isvc platform-health-check --ignore-not-found
kubectl -n model-serving delete cronjob platform-health-check-probe --ignore-not-found
# Reverting the controller pin is a git revert + ArgoCD sync; the image
# override is gone from the manifests and should stay gone.
```

### 10.14 Vault Shamir → Transit seal migration (DEFERRED)

The platform today runs Vault with a Shamir unseal whose keys are
stored in Secret `security/vault-unseal`.  This is acceptable for a
single-node thesis but fails the production bar because:

1. **Key co-location** — the unseal keys live in the same namespace as
   the Vault pod.  A namespace-scoped compromise reveals both the
   ciphertext (Raft data on the PVC) and the key (Secret).
2. **Manual restart recovery** — the `vault-bootstrap` Job unseals on
   first boot, but subsequent pod restarts require the Job to re-run
   or the operator to `kubectl exec … vault operator unseal` manually.

The proper 2026 fix is Transit seal against a dedicated unseal Vault.
This is an **out-of-band seal migration** (same risk category as the
store migrations in MIGRATION.md §1-3) and is NOT executed from this
commit — see `MIGRATION.md §6` for the detailed procedure, rollback
plan, and safety check-list.

Expected turnaround: ~30 min on a clean cluster; ~2 h on one with
existing Vault data (seal migration is online but requires operator
supervision during `vault operator seal-migrate`).

### 10.15 `kafka-dev` namespace cleanup

Symptom: a `kafka-dev` namespace still runs alongside the authoritative
`data-ingestion` namespace on clusters that were first bootstrapped
before ADR-011 pinned Strimzi as the single Kafka operator. It no
longer serves any workload but may still hold a `Kafka` / `KafkaTopic`
CR with PVCs pinned to the `local-path` StorageClass, wasting node disk
and appearing in cluster audits as undeclared state.

Run top-to-bottom; stop and triage if any step surfaces state you
cannot explain before continuing.

```bash
# 1. Inventory. The authoritative Kafka lives in data-ingestion — this
#    namespace should only contain stale dev scaffolding.
kubectl get all,pvc,kafka,kafkatopic,kafkauser -n kafka-dev

# 2. Optional: back up any CRs you want to keep before deleting.
kubectl -n kafka-dev get kafka,kafkatopic,kafkauser -o yaml \
  > /tmp/kafka-dev-backup-$(date +%F).yaml
```

If the inventory is clean (no production data, no consumer groups
still pointing at this cluster), delete the namespace:

```bash
kubectl delete namespace kafka-dev --ignore-not-found
```

If the namespace hangs in `Terminating`, a Strimzi finalizer on a
`Kafka` or `KafkaTopic` CR is blocking the finalizer chain. Clear the
CRs first, then re-delete the namespace (do NOT patch the namespace's
own finalizer list — that leaks downstream finalizer-protected state):

```bash
# Delete the Kafka CRs first so the Strimzi topic operator drains.
kubectl -n kafka-dev get kafka -o name \
  | xargs -r kubectl -n kafka-dev delete --wait=false
# If the CR itself is stuck, clear its finalizers.
kubectl -n kafka-dev get kafka -o name \
  | xargs -r -I{} kubectl -n kafka-dev patch {} \
      --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl delete namespace kafka-dev --ignore-not-found
```

Reclaim any dangling PersistentVolumes whose `claimRef` still points
at the deleted namespace. Most `local-path` PVs have
`reclaimPolicy: Delete` and go on their own; Longhorn-backed ones
often need a manual push:

```bash
kubectl get pv -o json \
  | jq -r '.items[] | select(.spec.claimRef.namespace=="kafka-dev") | .metadata.name' \
  | xargs -r kubectl delete pv
```

### Verification

```bash
kubectl get ns kafka-dev                           # expect: NotFound
kubectl get pv -A | awk '$6=="kafka-dev" {print}'  # expect: no rows
kubectl -n data-ingestion get kafka platform \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# expected: True — the canonical Kafka cluster is unaffected.
```

### Rollback

None — the canonical Kafka cluster lives in `data-ingestion` and holds
all production state (see ADR-011 and §8.3). If the inventory step
surfaced data that still matters, stop, pivot to §8.3 (MirrorMaker2),
and mirror topics into the canonical cluster before deleting this
namespace. Restoring from the optional YAML backup only recreates the
CRs; it does not recover the underlying PVCs.

## Rollback strategy — general principles

- Each phase writes to one namespace; `kubectl delete -k <dir>` cleanly
  removes the change.
- Never `git revert` the `cluster.yaml` onto CNPG ≥1.30 — the inline
  field is gone. Pin the operator instead if you truly need to roll back.
- Bucket-bootstrap is idempotent; re-apply doesn't destroy data.
- ExternalSecret → Secret materialisation takes up to one
  `refreshInterval` (1h default). `kubectl annotate externalsecret <n>
  force-sync="$(date +%s)"` triggers an immediate refresh.

## Known follow-ups (not yet fixed in this pass)

- CHI `platform` reconciliation is blocked on Longhorn default
  StorageClass availability. Install Longhorn first, then re-apply the
  ClickHouse Installation.
- Service-mesh AuthorizationPolicies per-namespace (current mesh-default-
  deny covers ingress; per-service allows are the next pass).
- **Vault Shamir → Transit seal migration** (see §10.14 above and
  MIGRATION.md §6). Single-node thesis runs on Shamir; production
  deployment must migrate before go-live.
- **KServe demo model artifact in air-gapped clusters**: the default
  `storageUri` is `gs://kfserving-examples` — air-gapped operators must
  copy the model to MinIO and patch `demo-health-check.yaml` via a
  Kustomize overlay. `setup-toolchain.sh OFFLINE_MODE=true` performs
  the one-time copy but is not yet wired into the ArgoCD sync.
- **Kubeflow version lock** (AUDIT_REPORT §2 P0.3): **VALIDATED CLOSED
  2026-04-19.** Verification: KFP 2.15.0, Katib v0.19.0, Trainer v2.1.0,
  JobSet v0.10.1 are internally consistent semver pins. The JobSet CRD
  serves `v1alpha2` (crds.yaml:10498); Trainer RBAC uses unversioned
  `jobset.x-k8s.io` group refs (resources.yaml:140/152/158/271) which
  track the served version, and the single `v1alpha1` token in the tree
  (resources.yaml:494) belongs to the separate `config.jobset.x-k8s.io`
  ControllerConfig group — a distinct API, not a version skew. No
  manifest-rendering CronJob exists; the original thrash description in
  AUDIT_REPORT §2 was a misdiagnosis. Separate hygiene action: two KFP
  upstream Deployments (`cache-server`, `ml-pipeline-viewer-crd`) shipped
  with `imagePullPolicy: Always`; patched to `IfNotPresent` via
  kubeflow-pipelines/kustomization.yaml patch #14 to prevent per-restart
  re-pull storms under ArgoCD self-heal. This is hygiene, not the P0.3
  closure itself.
- **CNPG chart re-verification**: the current cnpg chart pin
  (0.28.0 / operator 1.29.x) is from 2026-01. Before production go-live
  re-verify against https://cloudnative-pg.github.io/charts/ and bump
  to the latest 1.29.x patch release.
- **Bitnami image audit**: spot-check every helm chart for transitive
  `bitnami/*` image refs. Bitnami removed its unlicensed registry on
  2026-02-15; any unpinned chart that still resolves to
  `docker.io/bitnami/*:latest` will ImagePullBackOff.

## 11 — Phase C: Observability completion + progressive delivery + drift automation (2026-04-20)

Closes the LGTM++ observability gap, adds progressive delivery to the
serving plane, wires ADR-017's automated retrain loop, and fixes three
latent bugs uncovered during the final audit.

### 11.1 — Pyroscope continuous profiling (ADR-010 amendment)

New manifests:
- `platform/components/observability/pyroscope/helm-release.yaml` — Argo
  CD Application; chart `grafana/pyroscope:2.0.0` → app 2.0.1 (2026-04-20)
- `platform/components/observability/pyroscope/kustomization.yaml`
- `platform/components/observability/kustomization.yaml` — resources list
  extended with `- pyroscope`

Backend: MinIO `pyroscope-profiles` bucket, 14d retention (matches
Tempo). Credentials from Vault `platform/minio/root` via ExternalSecret.

Verification:

```bash
kubectl -n observability get application pyroscope -o jsonpath='{.status.sync.status}'
kubectl -n observability get pods -l app.kubernetes.io/name=pyroscope
kubectl -n observability logs ds/pyroscope-ebpf-profiler | head -30
# Grafana "Profiles" tab datasource should resolve http://pyroscope.observability.svc:4040
```

### 11.2 — Argo Rollouts progressive delivery (ADR-016 supersedes Flagger)

New manifests:
- `platform/components/gitops/argo-rollouts/helm-release.yaml` — chart
  `argoproj/argo-rollouts:2.40.9` → app v1.9.0 (2026-03-20); Istio
  traffic routing; AnalysisTemplate `success-rate-p99`
- `platform/components/gitops/argo-rollouts/kustomization.yaml`
- `platform/components/gitops/kustomization.yaml` — resources list
  extended with `- argo-rollouts`

Why not Flagger: Flagger v1.42.0 (2025-10-16) is not a 2026 release;
Argo Rollouts is within the argoproj ecosystem already in-tree and
uses a separate CRD (`rollouts.argoproj.io`) from KFP's Argo Workflows
(`workflows.argoproj.io`), so there is no leader-lease contention.

Verification:

```bash
kubectl -n gitops get application argo-rollouts -o jsonpath='{.status.sync.status}'
kubectl -n gitops get deploy argo-rollouts
kubectl get crd rollouts.argoproj.io analysistemplates.argoproj.io
kubectl -n gitops get analysistemplate success-rate-p99
```

### 11.3 — Alloy OTLP receiver (unifies telemetry collector)

Change:
- `platform/components/observability/loki/alloy.yaml`
  - Added `otelcol.receiver.otlp` on `:4317` (gRPC) + `:4318` (HTTP)
  - Pipeline: receiver → `otelcol.processor.k8sattributes` →
    `otelcol.processor.batch` → `otelcol.exporter.otlp` (Tempo) +
    `otelcol.exporter.prometheus` → `prometheus.remote_write` (kps)
  - DaemonSet container ports extended with `otlp-grpc`/`otlp-http`

Alloy becomes the edge telemetry collector for logs + traces + metrics.
The OTel Collector gateway still handles platform-wide sampling / fan-
out; the agent DaemonSet can be retired once every tracer producer is
repointed (separate migration step, not forced here).

Verification:

```bash
kubectl -n observability rollout status ds/alloy
kubectl -n observability port-forward ds/alloy 12345:12345
curl -s http://127.0.0.1:12345/-/ready
# OTLP reception test (requires grpcurl or a traced workload):
kubectl -n observability exec ds/alloy -- nc -vz 127.0.0.1 4317
```

### 11.4 — Drift-driven retrain CronWorkflow (ADR-017, use-case scope)

ADR-017 specifies a 6-hourly CronWorkflow that queries `gold.drift_metrics`
for PSI + KS in a lookback window and triggers KFP retraining when thresholds
are exceeded (`PSI > 0.2` or `KS > 0.15`). Namespace: `model-lifecycle` (KFP's
Argo controller lives there).

The platform supplies the substrate: KFP API at
`http://ml-pipeline.model-lifecycle.svc.cluster.local:8888/apis/v2beta1/runs`,
ExternalSecret-backed ClickHouse creds via the platform Vault, and Pushgateway
for the metric push.

See `<use-case>/docs/RUNBOOK.md` §11.4 for the use-case-specific CronWorkflow
manifest, ExternalSecret name, drift-metric SQL, and verification commands.

### 11.5 — Bug fixes landed

- `platform/services/quality/analyzer/jobs/expectations.py` — writes
  routed via `features.quality_write_buffer` (Null engine) → MV →
  `gold.data_quality_expectations` (Views are read-only; prior code
  INSERTed into a View which fails with error 48)
- `platform/components/model-lifecycle/kubeflow-pipelines/pipelines.yaml`
  — `workflow-controller` Deployment: added `limits: {cpu: 1000m,
  memory: 1Gi}` (Kyverno `require-resource-limits` was blocking admission)
- `platform/components/gitops/argo-cd/app-of-apps.yaml` — added three
  missing chart repos to the `platform` AppProject `sourceRepos`:
  `argoproj/argo-helm`, Apache Flink downloads, Kubeflow Spark Operator

### 11.6 — Items already in-tree (audit closed without code change)

These were flagged by the audit but grep-verified as already landed in
prior passes — no rework needed:

- `platform/components/storage/clickhouse/installation.yaml` — already
  declares 3-node `ClickHouseKeeperInstallation` + 2×2 shard/replica CHI
- `platform/components/data-processing/flink/flink-operator.yaml` —
  Flink Kubernetes Operator 1.14.0 already present
- `platform/components/data-processing/spark/spark-operator.yaml` —
  Kubeflow Spark Operator 2.5.0 already present

### 11.7 — Deferred / dropped from scope

- **Fourkeys**: last release 2023-05-04; community-abandoned. Dropped —
  no 2026-aligned replacement chosen; DORA metrics can be derived from
  Gitea + Tekton events if ever needed.
- **Flagger**: superseded by Argo Rollouts (§11.2).
- **Longhorn / kuberay-operator / label-studio** decisions: surfaced to
  user; see AUDIT_FINAL_2026-04-20.md §Decisions.

### 11.8 — Apply (user-run)

Phase C adds new workloads; ArgoCD will pick them up on next sync once
the manifests land in the tracked branch. For out-of-band apply on the
single-node cluster:

```bash
kubectl apply -k platform/overlays/local       # picks up Pyroscope + Rollouts + Alloy OTLP
kubectl apply -k <use-case>/manifests/overlays/local   # picks up the CronWorkflow
```

Rollback: `kubectl delete -k <same dir>` on each, or revert the commits
that added the directories. Pyroscope + Argo Rollouts are additive
workloads; no existing resource is mutated by their installation.

## 12 — Post-audit closure (2026-04-21) — P0 fixes, P1 security hardening, P2 polish

> Phase naming: the AUDIT §7 action plan reserves "Phase D" for storage
> consolidation (CHK, KafkaNodePool RF=3, CNPG migration, Longhorn
> decision). The work in this section is out-of-phase *audit-recommendation
> closure*, not that storage migration. Tracked as "post-audit closure" to
> avoid the collision.

Closes residual P0 blockers (CNPG Kyverno rejection, Kyverno verify-images
over-scoping, ADR-009 allowlist consistency, expired Katib experiment),
lands use-case domain SLOs / autoscaling / stream-runtime reshape,
tightens the security plane (edge AuthZ + per-pod NetPol), and finishes
audit "polish" items (Argo Rollouts canary, Chaos Mesh game-day, OpenLineage
emission). Formalizes ADR-015 through ADR-024.

### 12.1 — Kyverno P0 fixes (ADR-019, ADR-020)

Changes:
- `platform/components/security/kyverno/policies.yaml`
  - Added `cnpg-system` to `excludeResourceRules.namespaces` in five
    ValidatingPolicies (`require-resource-limits`,
    `require-read-only-root-filesystem`, `disallow-privileged`,
    `require-probes`, `require-runAsNonRoot`).
  - Rewrote `ImageValidatingPolicy verify-platform-images-cosign` with
    `matchImageReferences` scoped to internal Gitea registry paths
    (`gitea.gitops.svc.cluster.local/platform/*`,
    `gitea.gitops.svc.cluster.local/<use-case>/*`,
    `localhost:5000/*`).
  - Added Fulcio signer identity
    `system:serviceaccount:gitops:tekton-cosign-signer`.
  - Use-case namespaces with `istio-injection: disabled` must be added
    to the ADR-009 Istio opt-out allowlist (one-line patch per
    use-case; see use-case RUNBOOK §12.1 for the use-case-specific
    allowlist update).

Verification:

```bash
kubectl -n cnpg-system get pods                  # backup pods should stop restarting
kubectl -n cnpg-system get events --sort-by=.lastTimestamp | grep -i kyverno | head
kubectl get clusterpolicy require-resource-limits -o yaml | yq '.spec.rules[0].exclude'
# Pull a community image in any namespace to confirm it no longer bounces:
kubectl run tmp-bitnami --rm -it --image=bitnami/redis:latest --command -- sh -c 'exit 0'
# Pull a platform image to confirm it DOES require signature:
kubectl run tmp-platform --rm -it \
  --image=gitea.gitops.svc.cluster.local/platform/flink-job:unsigned --command -- sh -c 'exit 0'
# Expect: admission denial with cosign verification failure.
```

Rollback: `git revert` on the kustomization change; CNPG backup pod
restart-loop will return, so keep an exemption ticket open if reverting.

### 12.2 — Katib experiment END_DATE bump (use-case scope)

Use-case Katib `Experiment` CRs must have their `END_DATE` annotation rolled
forward when the prior thesis-viva window expires. The Katib operator (platform
side) installs cleanly; the use-case-side concern is an annotation date bump.

See `<use-case>/docs/RUNBOOK.md` §12.2 for the use-case-specific manifest path
and verification commands.

### 12.3 — Use-case Sloth SLOs (ADR-021)

ADR-021 mandates per-use-case Sloth `PrometheusServiceLevel` CRs (typically
prediction-freshness / pipeline-lag / model-freshness). Sloth compiles each
to 8 MWMBR PrometheusRules labelled `release: kube-prometheus-stack` so the
Prometheus Operator picks them up automatically.

Platform supplies: Sloth controller (already installed in `observability`),
kube-prometheus-stack with the matching `release` label discovery.

See `<use-case>/docs/RUNBOOK.md` §12.3 for the use-case-specific SLO list,
manifest path, and verification commands.

### 12.4 — Use-case KEDA ScaledObjects (ADR-022)

ADR-022 specifies KEDA `ScaledObject` per use-case consumer that subscribes to
Kafka topics, with `type: kafka` triggers driven by per-topic lag thresholds.
HPAs that operate on the same Deployments must be deleted (KEDA-generated HPA
otherwise collides with hand-rolled HPAs and dual controllers fight).

Platform supplies: KEDA operator (already installed), Kafka bootstrap at
`platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092`,
`triggerAuthentication` CR pattern when SASL is required.

See `<use-case>/docs/RUNBOOK.md` §12.4 for the use-case-specific topic list,
deployment names, lag thresholds, and verification commands.

### 12.5 — Use-case FlinkDeployment CR (ADR-023)

ADR-023 replaces the legacy in-pod Flink Deployment with a Flink-Operator-
managed `flink.apache.org/v1beta1 FlinkDeployment` CR (application mode,
Flink 2.2.0). ADR-025 follow-up (2026-04-21) deletes the legacy Deployment
from `platform/services/base/deployments/` and any scale-to-0 patches. The
FlinkDeployment `podTemplate` declares named ports `metrics` (9249) and
`jm-rest` (8081); PDBs, PodMonitors, and NetworkPolicies target those labels.

Metrics reporter pattern: JobManager-only (TM reporter disabled) cuts
cardinality ~10× while keeping job-level metrics.

Platform supplies: Flink Kubernetes Operator 1.14.0 (already installed
in `data-processing`), MinIO `flink-checkpoints` bucket pattern, OpenLineage
endpoint at DataHub GMS.

See `<use-case>/docs/RUNBOOK.md` §12.5 for the use-case-specific
FlinkDeployment manifest (jarURI, entryClass, S3 checkpoint subpath,
ServiceAccount/Role/RoleBinding, ExternalSecret) and verification commands.

Kafka consumer-group integrity: each FlinkDeployment uses a dedicated
consumer group per the application jar's Kafka source config. First-time
apply is safe. For migrations from an older job, drain via savepoint before
switching.

### 12.6 — Security hardening (ADR-024, use-case scope)

ADR-024 mandates two Istio `AuthorizationPolicy` per use-case (a deny-admin-paths
DENY policy + an allow-api-and-dashboard ALLOW policy with CIDR scoping for
`/dashboard/*`). It also rewrites NetworkPolicies from broad
"namespace → all pods" to per-pod allowlists naming the specific consumers.

Required NetPol fixes:
- `allow-istio-system` (too broad) is removed.
- Three prior namespace-wide rules replaced with per-pod allowlists keyed on
  `app:` selectors.
- `allow-ingress-to-gateway` scoped to `app: gateway` + port 8080 only.
- `allow-istio-control-plane-to-gateway` added.
- Port 9249 added to Prometheus scrape (Flink reporter).

Platform supplies: Istio control plane in `istio-system`, `istio:
ingressgateway` selector, kube-prometheus-stack scrape.

See `<use-case>/docs/RUNBOOK.md` §12.6 for the use-case-specific
AuthorizationPolicy CR names, NetworkPolicy per-pod allowlist members,
ingress hostname, and verification curls.

Rollback: `git revert`. With AuthZ removed the gateway admits admin paths;
with per-pod NetPol removed east-west is broadly permitted. Low risk in
single-node dev; schedule carefully in prod.

### 12.7 — Argo Rollouts canary (ADR-016 use-case example)

ADR-016's use-case example demonstrates Argo Rollouts canary on a model-serving
proxy (typically `ml-bridge`): canary steps 20% → analyze → 50% → analyze →
100%, with a local `AnalysisTemplate` querying Istio edge metrics
(`istio_requests_total`, `istio_request_duration_milliseconds_bucket`) for
success-rate ≥ 99% and p99 ≤ 500ms.

ADR-025 follow-up (2026-04-21): the Service-only pattern. Platform
`platform/services/base/deployments/ml-bridge.yaml` ships only the Service —
no Deployment to race the Rollout for pods. Service selector matches the
Rollout's ReplicaSet pods directly.

Platform supplies: Argo Rollouts controller (`gitops` ns), `argoproj.io/v1alpha1
Rollout` CRD, `kubectl argo rollouts` plugin pattern.

See `<use-case>/docs/RUNBOOK.md` §12.7 for the use-case Rollout manifest path,
canary deployment name, image-bump command, and verification commands.

Rollback: revert the image bump (`kubectl argo rollouts undo`).

### 12.8 — Chaos Mesh resilience experiments (use-case scope)

Use-cases declare resilience experiments as Chaos Mesh `Schedule` CRs in
`chaos-mesh` namespace, plus an aggregating `Workflow` for thesis-viva game-day
demonstration. Typical patterns: gateway network-loss, pod-kill on cache tier,
upstream-call latency on the ml-bridge → MLflow path.

Observability hook: experiments labelled `experiment.thesis=KNF-11-<name>`
plot SLO burn before / during / after each experiment window on the
use-case Grafana dashboard.

Platform supplies: Chaos Mesh operator (already installed), Grafana dashboard
infrastructure, SLO burn-rate metrics emitted by Sloth (see §12.3).

See `<use-case>/docs/RUNBOOK.md` §12.8 for the use-case-specific experiment
list, target selectors, schedules, game-day Workflow name, and rollback.

### 12.9 — OpenLineage emission in use-case DAGs (ADR-018)

ADR-018 specifies manual OpenLineage `RunEvent` emission from per-use-case
Airflow DAGs (helpers `_ol_dataset`, `_ol_event`, `_ol_emit`, `_ol_run_id` plus
`OPENLINEAGE_URL` and `OPENLINEAGE_NAMESPACE` Variables). Custom run facets
carry use-case-specific quality metrics (row counts, coverage ratios,
latest-timestamps).

Why manual (not `openlineage-airflow` auto-extractor): dbt's own OL provider
already emits lineage for dbt models; the auto-extractor would double-emit
for any `BashOperator` wrapping `dbt run`. Flink and Spark continue to use
their native OL listeners.

Platform supplies: DataHub GMS at
`http://datahub-gms.data-governance.svc.cluster.local:8080`, OpenLineage API
endpoint `/openapi/openlineage`, Airflow with the DAG-Variable contract.

See `<use-case>/docs/RUNBOOK.md` §12.9 for use-case-specific DAG IDs, custom
facet field schemas, and verification commands.

Rollback: revert the DAG commit. The helpers are no-op if `OPENLINEAGE_URL`
is unset, so a blank env Variable effectively disables emission without a
code change.

### 12.10 — Apply (user-run)

The post-audit closure is a mixture of platform policy changes (Kyverno)
and use-case resource additions. ArgoCD sync picks up everything on next
reconcile. For out-of-band apply on single-node dev:

```bash
kubectl apply -k platform/overlays/local            # Kyverno policy updates
kubectl apply -k <use-case>/manifests/overlays/local  # SLOs, KEDA, FlinkDeployment, AuthZ, NetPol, Rollout, Chaos
```

Order matters on first apply:
1. `platform/overlays/local` FIRST (so the updated Kyverno policies let
   the new use-case resources through admission).
2. `<use-case>/manifests/overlays/local` SECOND.
3. ADR-025 (2026-04-21) retired the legacy in-pod Flink Deployment and
   its scale-to-0 patch outright. First-time cluster brings up the
   FlinkDeployment CR directly; there is no legacy Deployment to drain.

Rollback: `kubectl delete -k <path>` in reverse order; or `git revert` on
the landing commits. ADR-015 through ADR-024 remain in DECISIONS.md as
historical record even if the code is reverted.

## 13 — ADR-025 cleanup (2026-04-21) — delete scale-to-zero placeholders + unused KServe runtimes

ADR-025 retires every scale-to-zero placeholder and the LLM/GPU KServe
runtime templates that never matched an `InferenceService`. The goal is
to make the Git tree reflect what actually runs — no `replicas: 0`
Deployments kept "as inheritance anchors," no patch files against target
Deployments that do not exist, no runtime templates for modalities the
FLAML tabular palette does not use.

### 13.1 — Platform-side files deleted

```
platform/services/base/deployments/flink-job.yaml                           (Deployment)
```

`platform/services/base/deployments/ml-bridge.yaml` is rewritten in place
to ship only the Service (the Deployment block is removed; the use-case
Rollout is the sole pod owner — see use-case RUNBOOK §13).

`platform/components/model-serving/kserve/kserve-serving-runtimes.yaml`
is rewritten to keep only `kserve-mlserver` (MLflow path), plus
`kserve-lgbserver`, `kserve-sklearnserver`, `kserve-xgbserver` fallbacks
aligned with the FLAML palette. Eight runtimes and eight
`LLMInferenceServiceConfig` CRs are deleted. See the file header comment
for the per-runtime rationale.

Use-case-side scale-to-0 patches (`patches/flink-job.yaml`,
`patches/ml-bridge-disable-deployment.yaml`) are deleted from the use-case
repo as part of this same ADR — see use-case RUNBOOK §13.

### 13.2 — Platform-side kustomization references cleaned

| File | Change |
|---|---|
| `platform/services/base/kustomization.yaml` | `- deployments/flink-job.yaml` removed |
| `platform/services/overlays/generic/kustomization.yaml` | `name: flink-job` image override removed |
| `platform/components/model-serving/kserve/kustomization.yaml` | orphan scale-to-0 patches against `llmisvc-controller-manager` and `kserve-localmodel-controller-manager` removed (target Deployments never existed) |

Use-case-side kustomization edits (base, base-phase1, overlays/{local,cloud,
local-phase1}) follow the same removal pattern — see use-case RUNBOOK §13
for the per-overlay edits.

### 13.3 — Resources rescoped to FlinkDeployment pod labels

The Flink Kubernetes Operator labels its pods `app: <deployment-name>` +
`component: jobmanager|taskmanager`. Selectors are NOT rewritten by
kustomize namePrefix, so the `app:` value is the literal FlinkDeployment
metadata.name set by the use-case.

Platform-side change:

| File | Was | Now |
|---|---|---|
| `platform/services/base/hpa/autoscaling.yaml` | `flink-job-pdb` | deleted — generic overlay ships no FlinkDeployment |

Use-case-side rescoped resources (PDB rename, ServiceMonitor → PodMonitor
swap, NetworkPolicy port edits, FlinkDeployment podTemplate named ports)
are listed in use-case RUNBOOK §13.

### 13.4 — Verification

```bash
# Kustomize builds with no errors on every overlay:
kubectl kustomize platform/services/overlays/generic              >/dev/null
kubectl kustomize <use-case>/manifests/overlays/local             >/dev/null
kubectl kustomize <use-case>/manifests/overlays/cloud             >/dev/null
kubectl kustomize <use-case>/manifests/overlays/local-phase1      >/dev/null

# No legacy Deployment references survive:
! grep -rn "deployments/flink-job.yaml" platform <use-case>
! kubectl -n <use-case-namespace> get deploy flink-job 2>/dev/null
! kubectl -n <use-case-namespace> get deploy ml-bridge 2>/dev/null

# KServe runtime surface is the intended four only:
kubectl get clusterservingruntime -o name | sort
# → clusterservingruntime.serving.kserve.io/kserve-lgbserver
# → clusterservingruntime.serving.kserve.io/kserve-mlserver
# → clusterservingruntime.serving.kserve.io/kserve-sklearnserver
# → clusterservingruntime.serving.kserve.io/kserve-xgbserver
```

Use-case-specific verifications (FlinkDeployment + rescoped PDB + PodMonitor)
are in use-case RUNBOOK §13.

### 13.5 — Rollback

`git revert` on the ADR-025 commit restores every deleted file and
re-adds the scale-to-0 patches. The deletion was structural (removed
files, edited kustomizations, renamed PDB, converted ServiceMonitor →
PodMonitor); revert is atomic. After revert, the pre-ADR-025 shape
returns: placeholder Deployments at `replicas: 0`, the PDB on `app:
flink-job`, the ServiceMonitor on port 8083. The runtime behaviour does
not change because none of those placeholders were load-bearing in the
first place — that is the whole reason for ADR-025.
