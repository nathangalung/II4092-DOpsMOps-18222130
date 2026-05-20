# Platform data migration runbook

This doc covers the one-shot cutover from the pre-audit single-pod stateful
workloads to the HA operator-managed clusters introduced in ADR-011.
Everything here is intentionally **not** codified as a generic script:
each store has different cutover semantics that require human judgement
about read/write windows and consistency.

Run each section after the relevant bootstrap step completes (see
`make phase-full` in the root `Makefile`). Do not start migrations until
the new cluster is fully healthy.

---

## Pre-flight

1. `kubectl get pods -A -o wide` - confirm every new pod is `Running`.
2. `kubectl -n gitops get application` - every Argo Application `Synced/Healthy`.
3. Announce a write-freeze window on the affected stores. On single-node
   k3s this can be <5 minutes per store; on multi-node HA with load it is
   longer (budget 15-30 minutes per store).
4. Back up everything first. `kubectl -n velero create backup pre-migration-$(date +%s)`.

---

## 1. PostgreSQL (legacy Deployment -> CloudNativePG Cluster)

**Legacy pod:** `storage/postgresql-<hash>` (single replica, local-path PV).
**Target:** CNPG `Cluster/postgresql` (1 instance, single-node k3s).

### Export

```bash
LEGACY_POD=$(kubectl -n storage get pod -l app=postgresql -o name | head -n1)
LEGACY_PASS=$(kubectl -n storage get secret postgresql-credentials \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

kubectl -n storage exec "$LEGACY_POD" -- \
  env PGPASSWORD="$LEGACY_PASS" \
  pg_dumpall -h 127.0.0.1 -U postgres --clean --if-exists \
  > /tmp/pg_dumpall.sql
```

### Import

`pg_dumpall --clean --if-exists` emits role-level DDL (DROP/CREATE ROLE …)
that only a superuser can run. The CNPG Cluster defaults
`enableSuperuserAccess: false` so there is no `postgres` password to fetch
from a Secret — but the `postgres` role is still reachable via local
peer auth on the unix socket inside the CNPG primary pod. Exec directly
into the pod so psql authenticates as the local OS user without a
password and without going through the TCP listener:

```bash
kubectl -n storage exec -i postgresql-1 -c postgres -- \
  psql -U postgres < /tmp/pg_dumpall.sql
```

### Point consumers at the new primary

The `postgresql-rw.storage.svc.cluster.local` Service is what CNPG exposes.
Update these references (most are already on `postgresql.storage.svc`):

- `platform/components/model-lifecycle/feast/deployment.yaml` - Feast registry
- `platform/components/data-processing/airflow/deployment.yaml` - Airflow DB
- `platform/components/data-processing/superset/deployment.yaml` - Superset DB
- `platform/components/model-lifecycle/mlflow/deployment.yaml` - MLflow backend
- `platform/components/data-governance/datahub/deployment.yaml` - DataHub GMS DB
- `platform/components/storage/lakefs/deployment.yaml` - lakeFS catalog DB
- `platform/components/storage/spicedb/deployment.yaml` - SpiceDB datastore

### Decommission

After a full day of uptime on the new cluster:

```bash
kubectl -n storage delete deploy postgresql
kubectl -n storage delete pvc -l app=postgresql
```

---

## 2. ClickHouse (legacy StatefulSet -> Altinity CHI)

**Legacy pod:** `storage/clickhouse-0` (single replica, no Keeper).
**Target:** `ClickHouseInstallation/platform` + `ClickHouseKeeperInstallation/platform-keeper`.

Replicated*MergeTree engines declared in use-case schema files did not
actually replicate before because there was no Keeper. After migration
they will, once Keeper is active. Use-case-specific schema-file paths
and re-apply commands live in `<use-case>/docs/MIGRATION.md` §2.

### Export (clickhouse-backup to S3)

```bash
kubectl -n storage exec clickhouse-0 -- clickhouse-backup create legacy-pre-migration
kubectl -n storage exec clickhouse-0 -- clickhouse-backup upload legacy-pre-migration
```

`clickhouse-backup` is configured to target MinIO bucket `clickhouse-backups`.

### Import into the CHI

```bash
CHI_POD=$(kubectl -n storage get pod -l clickhouse.altinity.com/chi=platform \
  -o name | head -n1)
kubectl -n storage exec "$CHI_POD" -- clickhouse-backup download legacy-pre-migration
kubectl -n storage exec "$CHI_POD" -- clickhouse-backup restore legacy-pre-migration
```

### Re-create the schema with Keeper-aware paths

Use-case schema files use the `{shard}` and `{replica}` macros which
Altinity auto-populates from the CHI pod labels. Re-running a schema
file against the CHI is a no-op for existing tables; new tables land
correctly. Concrete schema-file path + re-apply command are
use-case-specific — see `<use-case>/docs/MIGRATION.md` §2.

### Update consumer connection strings

The legacy headless Service `clickhouse.storage` was replaced by the
Altinity operator's load-balanced convenience Service
`clickhouse-platform.storage.svc.cluster.local` (backed by cluster
`main`, pods `chi-platform-main-{0..1}-{0..1}`). Prefer the Service
DNS over pod-specific DNS, which is fragile to topology changes.

Platform-side files to update:

- `platform/components/data-processing/dbt/deployment.yaml`

Use-case-side files (analyzer, validator, feature-engine source modules
plus DAG callables) are flipped per `<use-case>/docs/MIGRATION.md` §2.

### Decommission

```bash
kubectl -n storage delete sts clickhouse
kubectl -n storage delete pvc -l app=clickhouse
```

---

## 3. Kafka (legacy StatefulSet -> Strimzi cluster)

**Status (2026-04-21):** tree-side cutover already applied — every file in
"Switch consumers + producers" below already points at
`platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092`.
Cluster-side MM2 drain + legacy `Kafka` STS deletion are still pending and
are the only remaining steps in this section. Use-case-side historical
plan snapshots that intentionally retain the legacy broker string (kept
as historical records) are listed in `<use-case>/docs/MIGRATION.md` §3.

**Legacy pod:** `data-ingestion/kafka-0` (single broker, Zookeeper-based).
**Target:** `Kafka/platform-kafka` + `KafkaNodePool/broker` (KRaft mode).

Cannot do an in-place upgrade from Zookeeper-mode to KRaft-mode in a
single broker; go via MirrorMaker2.

### Deploy MirrorMaker2 connector

```bash
kubectl apply -f - <<'YAML'
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaMirrorMaker2
metadata:
  name: platform-mm2
  namespace: data-ingestion
spec:
  version: 4.2.0
  replicas: 1
  connectCluster: target
  clusters:
    - alias: source
      bootstrapServers: kafka.data-ingestion.svc.cluster.local:9092
    - alias: target
      bootstrapServers: platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092
      config:
        config.storage.replication.factor: 1
        offset.storage.replication.factor: 1
        status.storage.replication.factor: 1
  mirrors:
    - sourceCluster: source
      targetCluster: target
      sourceConnector:
        config:
          replication.factor: 1
          offset-syncs.topic.replication.factor: 1
          sync.topic.acls.enabled: "false"
      heartbeatConnector:
        config:
          heartbeats.topic.replication.factor: 1
      checkpointConnector:
        config:
          checkpoints.topic.replication.factor: 1
      topicsPattern: ".*"
      groupsPattern: ".*"
YAML
```

Strimzi will spin up a MM2 Connect cluster that continuously mirrors
topics from source to target.

### Switch consumers + producers

Change every `bootstrap.servers` reference from
`kafka.data-ingestion.svc.cluster.local:9092` to
`platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092`.

Files (all already flipped on-tree as of 2026-04-21 — audit step only):

Platform-side:
- `platform/components/data-ingestion/kafka-connect/deployment.yaml`
- `platform/components/data-ingestion/kafka-exporter/deployment.yaml`
- `platform/components/data-ingestion/kafka-ui/deployment.yaml`
- `platform/components/data-ingestion/karapace/deployment.yaml`
- `platform/services/base/configmaps/pipeline-infrastructure.yaml:57`

Use-case-side (DAGs, configmaps, KEDA ScaledObject triggers, DataHub
ingestion config, ClickHouse Kafka-engine `kafka_broker_list` entries):
see `<use-case>/docs/MIGRATION.md` §3 for the per-file audit list.

### Cut over

Once MM2 reports `lag = 0` for all topics (`kubectl -n data-ingestion
get kafkatopic` + `kafka-consumer-groups.sh --describe`), stop the old
brokers:

```bash
kubectl -n data-ingestion delete sts kafka
kubectl -n data-ingestion delete svc kafka
kubectl -n data-ingestion delete kafkamirrormaker2 platform-mm2
```

---

## 4. Post-migration validation

```bash
# Kafka topics land on new brokers
kubectl -n data-ingestion exec -it platform-kafka-broker-0 -- \
  /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# CNPG primary responds
kubectl -n storage exec -it postgresql-1 -- \
  psql -U postgres -c '\l'

# CHI accepts writes and replicates
kubectl -n storage exec -it chi-platform-default-0-0 -- \
  clickhouse-client -q 'SELECT count() FROM features.price_ticks'

# Velero retains a pre-cutover backup
kubectl -n velero get backup
```

Sign off in the #platform-ops channel with a one-liner per store listing
the row/offset counts on both source and target.

---

## 5. Rolling back

Every step above has a rollback route:

- **Postgres** - re-target services at the legacy `postgresql` Service, re-run
  the old Deployment from `git checkout <pre-audit-sha> -- platform/components/storage/postgresql/`.
- **ClickHouse** - keep the legacy StatefulSet running until step 4 signs
  off. Rollback is literally changing client URLs back.
- **Kafka** - MM2 is bidirectional-capable. Re-enable the source-side
  connector if the target develops an issue within the first hour.

Do **not** delete the pre-migration Velero backup until 14 days after
sign-off.

---

## 6. Vault seal migration (Shamir → Transit)

**Source:** Vault StatefulSet (1 replica on single-node k3s) with Shamir
unseal, keys in Secret `security/vault-unseal`.
**Target:** same StatefulSet, but sealed with a Transit key living in a
separate, dedicated `unseal-vault` (single-replica Shamir Vault whose
keys live in an offline-printed recovery envelope).

Why: see REMEDIATION_RUNBOOK.md §10.14. The Shamir unseal keys today
live in the same namespace as the data they protect; Transit breaks
that co-location by moving the master key out to a trust anchor that
does NOT also hold the application ciphertext.

Risk category: **data loss if the Transit key is lost after migration**.
Print and physically store the Shamir key shares for unseal-vault
before starting.  Rehearse on a throwaway cluster first.

### 6.1 Pre-flight

```bash
# Everything green
kubectl -n security get pod -l app=vault -o wide
kubectl -n security exec vault-0 -c vault -- vault status

# Make a Velero backup restricted to the security namespace.  This is
# the last-known-good snapshot if the migration wedges.
kubectl -n velero create backup vault-pre-seal-migration \
  --include-namespaces security \
  --default-volumes-to-fs-backup=true
kubectl -n velero wait --for=condition=Complete backup/vault-pre-seal-migration \
  --timeout=10m

# Copy the current Shamir key bundle off-cluster. Store the JSON in a
# password-protected file (gpg, age, 1Password, …). DO NOT commit it.
kubectl -n security get secret vault-unseal -o jsonpath='{.data.init\.json}' \
  | base64 -d > vault-shamir-keys.pre-migration.json
gpg -c vault-shamir-keys.pre-migration.json   # prompts for passphrase
shred -u vault-shamir-keys.pre-migration.json
```

### 6.2 Bring up the unseal-vault

Apply `platform/components/security/vault/unseal-vault.yaml` (see
§6.5 for the manifest shape — it is NOT in the default kustomization
resource list, so `kubectl apply -f` directly):

```bash
kubectl apply -f platform/components/security/vault/unseal-vault.yaml
kubectl -n security wait --for=condition=Ready pod/unseal-vault-0 --timeout=300s

# Initialise the unseal-vault (once). Its own Shamir keys are printed
# to stdout — print them, photograph them, put them in the safe.
kubectl -n security exec unseal-vault-0 -- \
  vault operator init -key-shares=3 -key-threshold=2 -format=json \
  > unseal-vault-init.json
# Store these separately from the primary Vault keys; compromising BOTH
# sets is required to read the primary's data.

# Unseal it (every time it restarts — consider automating with a
# readinessProbe init-container in production).
THRESHOLD_KEYS=$(jq -r '.unseal_keys_b64[0:2][]' unseal-vault-init.json)
for k in $THRESHOLD_KEYS; do
  kubectl -n security exec unseal-vault-0 -- vault operator unseal "$k"
done

# Root token + create the transit key + policy.
ROOT=$(jq -r .root_token unseal-vault-init.json)
kubectl -n security exec unseal-vault-0 -- \
  env VAULT_TOKEN="$ROOT" vault secrets enable transit
kubectl -n security exec unseal-vault-0 -- \
  env VAULT_TOKEN="$ROOT" vault write -f transit/keys/autounseal \
    type=aes256-gcm96 allow_plaintext_backup=false deletion_allowed=false
kubectl -n security exec unseal-vault-0 -- \
  env VAULT_TOKEN="$ROOT" vault policy write primary-autounseal - <<'POLICY'
path "transit/encrypt/autounseal" { capabilities = ["update"] }
path "transit/decrypt/autounseal" { capabilities = ["update"] }
POLICY
# Mint a token scoped to the autounseal policy. period=24h => self-renewing
# while the primary uses it; explicit renewal reset on first seal-migrate.
PRIMARY_TOKEN=$(kubectl -n security exec unseal-vault-0 -- \
  env VAULT_TOKEN="$ROOT" vault token create \
    -policy=primary-autounseal -period=24h -format=json \
  | jq -r .auth.client_token)

# Shell it into the primary Vault as a K8s Secret consumed by the
# seal "transit" stanza.
kubectl -n security create secret generic primary-vault-unseal-token \
  --from-literal=VAULT_TOKEN="$PRIMARY_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
unset PRIMARY_TOKEN ROOT
```

### 6.3 Migrate the primary Vault seal

Add the `seal "transit"` stanza to `vault-config` ConfigMap
(`platform/components/security/vault/statefulset.yaml`), then restart
with `-migrate`:

```hcl
seal "transit" {
  address         = "http://unseal-vault.security.svc.cluster.local:8200"
  disable_renewal = "false"
  key_name        = "autounseal"
  mount_path      = "transit/"
  tls_skip_verify = "true"  # mesh-internal; mTLS handled by Istio
}
```

Apply the ConfigMap + mount the token Secret as env:

```bash
kubectl apply -f platform/components/security/vault/statefulset.yaml

# Rolling restart, one pod at a time, with the -migrate flag.
# Vault requires `vault operator unseal -migrate <shamir-key>` during
# the transition window — the Shamir keys are temporarily reused to
# authorise the seal swap.
for i in 0 1 2; do
  kubectl -n security delete pod vault-$i
  kubectl -n security wait --for=condition=Ready pod/vault-$i --timeout=300s

  # The pod comes up sealed with the NEW seal type active, but needs
  # the OLD Shamir keys one last time to migrate.
  for k in $(jq -r '.unseal_keys_b64[0:3][]' vault-shamir-keys.pre-migration.json); do
    kubectl -n security exec vault-$i -c vault -- \
      vault operator unseal -migrate "$k"
  done

  kubectl -n security exec vault-$i -c vault -- vault status | grep Sealed
done
```

### 6.4 Verify + decommission the Shamir Secret

```bash
# Every pod unsealed, seal type is Transit, Raft replication healthy.
for i in 0 1 2; do
  kubectl -n security exec vault-$i -c vault -- vault status \
    | grep -E '(Sealed|Seal Type|HA Mode)'
done
# Expected on every pod:
#   Sealed       false
#   Seal Type    transit
#   HA Mode      active  (one pod) / standby (two pods)

# The `vault-unseal` Secret is no longer load-bearing. Keep it for 14
# days as a rollback safety net, then shred:
kubectl -n security annotate secret vault-unseal \
  migration.platform.io/decommission-date="$(date -u -d '+14 days' +%Y-%m-%dT%H:%M:%SZ)"
# After the grace period:
kubectl -n security delete secret vault-unseal
shred -u vault-shamir-keys.pre-migration.json.gpg
```

### 6.5 The unseal-vault.yaml manifest

The manifest is intentionally NOT committed into the default
kustomization so that a naive `kubectl apply -k security/vault/` on a
fresh cluster cannot accidentally create a second Vault.  It lives at
`platform/components/security/vault/unseal-vault.yaml` and is applied
only as part of this migration procedure (§6.2).  Its shape:

- Namespace `security` (same as primary — trust boundary is pod-level
  via PSA + Istio AuthorizationPolicy, not namespace).
- StatefulSet `unseal-vault` with ONE replica.  HA is unnecessary — a
  restart window of minutes during the primary's re-seal attempt is
  tolerable; real HA for the unseal-vault belongs in a cloud KMS in
  production.
- `vault.hcl` enables only `transit/` — no KV, no PKI, no auth methods
  except the root token used once by §6.2.
- `storageClassName: longhorn-replicated` (3-way replicated even on
  single-node) — loss of this PVC is catastrophic.
- Shamir unseal with 3-of-5 keys; keys are NEVER committed or put in a
  K8s Secret.  Operator prints and stores physically.

### 6.6 Rollback

Within the 14-day grace period:

```bash
# 1. Restore the pre-migration Velero backup to a sandbox namespace to
#    extract the Shamir-sealed PVC.
kubectl -n velero create restore vault-rollback-$(date +%s) \
  --from-backup=vault-pre-seal-migration \
  --namespace-mapping=security:security-rollback

# 2. git revert the seal "transit" stanza + token Secret commit
git revert <sha-of-6.3-commit>

# 3. Delete the primary pods so they come up with the reverted
#    (Shamir-only) ConfigMap.
kubectl -n security delete pod -l app=vault
# Unseal with the original Shamir keys (still in the vault-unseal Secret
# if kept, otherwise decrypt the gpg-protected file you made in §6.1).
```

After 14 days the rollback path closes — the Shamir key bundle is
shredded and the Transit key in unseal-vault is the only way to read
the data.  This is the tradeoff you accept by running this migration.
