# Use-case Crypto MIGRATION steps (cross-references to platform/MIGRATION.md)

Use-case-specific data-migration steps. The platform-side runbook
`platform/MIGRATION.md` covers generic store cutovers (Postgres → CNPG,
ClickHouse → Altinity CHI, Kafka → Strimzi). This file is the use-case
binding: the concrete file paths, schema files, and source-code references
that need to flip when the platform-side cutover happens.

## §2 (use-case implementation) — ClickHouse cutover

Maps to platform MIGRATION.md §2.

### Schema file

Replicated*MergeTree engines in `use-case-crypto/database/init_clickhouse.sql`
did not actually replicate before because there was no Keeper. After
migration they will, once Keeper is active.

The schema file uses the `{shard}` and `{replica}` macros which Altinity
auto-populates from the CHI pod labels. Re-running the file against the
CHI is a no-op for existing tables; new tables land correctly.

```bash
CHI_POD=$(kubectl -n storage get pod -l clickhouse.altinity.com/chi=platform \
  -o name | head -n1)
kubectl -n storage exec "$CHI_POD" -- \
  clickhouse-client --multiquery < use-case-crypto/database/init_clickhouse.sql
```

### Consumer connection-string updates

Update these files to use
`clickhouse-platform.storage.svc.cluster.local` (Altinity load-balanced
Service) instead of the legacy headless `clickhouse.storage`:

- `use-case-crypto/services/analyzer/main.py` — ClickHouse client URL
- `use-case-crypto/services/validator/main.py`
- `use-case-crypto/services/feature-engine/main.py`
- `use-case-crypto/dags/*.py` (DAGs live in `use-case-crypto/dags/` per the
  use-case/platform boundary move, ARCHITECTURE_REVIEW_2026-04-19 §266)

The platform-side dbt deployment (`platform/components/data-processing/dbt/deployment.yaml`)
is also flipped, but that is platform scope.

## §3 (use-case implementation) — Kafka bootstrap-server cutover

Maps to platform MIGRATION.md §3.

### Files flipped on-tree (audit trail)

All use-case-side Kafka bootstrap-server references already point at
`platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092` as of
2026-04-21 (cycle-5 cutover). Audit list:

- `use-case-crypto/dags/crypto_data_pipeline.py` — DAG location (originally
  the path under `platform/components/data-processing/airflow/dags/` was
  phantom; the DAG lives in `use-case-crypto/dags/` per the use-case
  boundary move, ARCHITECTURE_REVIEW_2026-04-19 §266)
- `use-case-crypto/manifests/base/configmaps/rest-collector-config.yaml:28`
  (services read bootstrap from configmap, not source code)
- `use-case-crypto/manifests/base/configmaps/topics.yaml:22`
  (`FEATURE_KAFKA__BROKERS` — consumed by validator + feature-engine)
- `use-case-crypto/manifests/base/patches/feature-engine.yaml:16`
- `use-case-crypto/manifests/base/scaling/scaledobjects.yaml` (4 KEDA
  triggers, lines 77 / 124 / 131 / 171)
- `use-case-crypto/scripts/libs/datahub/ingestion_config.py` (lines 22, 35)
- `use-case-crypto/database/init_clickhouse.sql` (6 `kafka_broker_list`
  entries at lines 63 / 101 / 194 / 240 / 283 / 377)

The platform-side flips (`kafka-connect`, `kafka-exporter`, `kafka-ui`,
`karapace`, `pipeline-infrastructure.yaml`) are platform scope and live
in `platform/MIGRATION.md` §3.

### Historical plan snapshot (intentionally untouched)

`use-case-crypto/docs/superpowers/plans/2026-03-19-phase1-medallion-dbt-oltp-cdc.md:404`
intentionally retains the legacy broker string as a historical record of
the pre-cutover plan; do not flip it.
