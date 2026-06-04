# DataHub lineage walk — SK-F-08 (KF-08; the read side / evidence for #495)

`lineage-walk.sh` is the read side of governance lineage. OpenLineage **emission**
is already wired in the platform (Airflow `AIRFLOW__OPENLINEAGE__TRANSPORT` →
DataHub GMS; the `lakehouse` DAG + dbt emit RunEvents; #488 fixed the mesh reset),
so this script only **queries** the DataHub GMS GraphQL API to confirm datasets
were ingested and to walk lineage up/downstream. Read-only.

Deliberately thin `curl`s over inline GraphQL — if the deployed DataHub version
wants a slightly different query shape, edit the heredoc and re-run.

```bash
set -a; . experiments/config.crypto.env; set +a
kubectl -n data-governance port-forward svc/datahub-gms 8080:8080 &
export DATAHUB_GMS_URL=http://localhost:8080
export DATAHUB_TOKEN=...        # Bearer PAT (GMS has METADATA_SERVICE_AUTH_ENABLED=true)
./experiments/lineage/lineage-walk.sh discover           # list ingested datasets + URNs
./experiments/lineage/lineage-walk.sh walk '<urn>' UPSTREAM
```

`DATAHUB_TOKEN`: reuse the `gms_token` Airflow emits with (in the `airflow-secrets`
Secret) or mint one in the DataHub UI (Settings → Access Tokens).

> **The graph is keyed by OpenLineage namespace.** The Airflow *provider*
> transport emits jobs under `default` (`$OPENLINEAGE_NAMESPACE_PROVIDER`); the
> `lakehouse` DAG's manual emit and the dbt provider emit under
> `<use-case>-pipeline` (`$OPENLINEAGE_NAMESPACE_PIPELINE`). Job nodes therefore
> split across two namespaces — search **both** before concluding lineage is
> broken. Dataset nodes (the `clickhouse://`, `postgres://`, `lakefs://`, `s3://`
> URNs) dedupe across namespaces, so the dataset graph itself stays connected.

| Env var | Purpose | Default |
|---------|---------|---------|
| `DATAHUB_GMS_URL` | GMS base URL (GraphQL at `/api/graphql`) | `http://datahub-gms.data-governance.svc.cluster.local:8080` |
| `DATAHUB_TOKEN` | Bearer personal-access-token | (required) |
| `OPENLINEAGE_NAMESPACE_PROVIDER` | Airflow provider transport namespace | `default` |
| `OPENLINEAGE_NAMESPACE_PIPELINE` | manual-emit / dbt namespace | `crypto-pipeline` |
