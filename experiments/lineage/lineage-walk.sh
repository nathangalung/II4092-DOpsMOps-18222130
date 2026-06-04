#!/usr/bin/env bash
# =============================================================================
# experiments/lineage/lineage-walk.sh
# SK-F-08 — DataHub lineage walk (validates KF-08; the read side / evidence for
# #495 — running this against the live graph is what closes #495, not the file).
# =============================================================================
# The governance / data-engineer answer to "can I trace a dataset end to end?".
# OpenLineage emission is already wired (platform airflow AIRFLOW__OPENLINEAGE__
# TRANSPORT -> DataHub GMS; the lakehouse DAG + dbt emit RunEvents; #488 fixed
# the mesh reset). This script is the READ side: it queries the DataHub GMS
# GraphQL API to (a) confirm datasets were ingested and (b) walk the lineage
# graph up/downstream from one of them. Read-only.
#
# ┌─ CAVEAT — the lineage graph is keyed by OpenLineage namespace ─────────────┐
# │ The Airflow provider transport emits under namespace "default"             │
# │ ($OPENLINEAGE_NAMESPACE_PROVIDER); the lakehouse DAG's manual emit and the  │
# │ dbt provider emit under "<use-case>-pipeline"                               │
# │ ($OPENLINEAGE_NAMESPACE_PIPELINE). Jobs land under different namespaces, so │
# │ if the graph looks fragmented (a dataset's producer/consumer "missing"),    │
# │ search BOTH namespaces before concluding lineage is broken — that split is  │
# │ expected, not a bug. Datasets (the clickhouse://, postgres://, lakefs://,   │
# │ s3:// nodes) dedupe across namespaces by URN, so the dataset graph itself   │
# │ stays connected; only the job nodes split.                                  │
# └────────────────────────────────────────────────────────────────────────────┘
#
# Auth: GMS runs with METADATA_SERVICE_AUTH_ENABLED=true, so every call needs a
# Bearer personal-access-token. The same token Airflow uses for OL emission is
# in the airflow-secrets Secret (the rendered gms_token); or mint one in the
# DataHub UI (Settings -> Access Tokens). Export it as DATAHUB_TOKEN.
#
# Run (after loading the config — see experiments/README.md):
#   set -a; . experiments/config.crypto.env; set +a
#   kubectl -n data-governance port-forward svc/datahub-gms 8080:8080 &
#   export DATAHUB_GMS_URL=http://localhost:8080
#   export DATAHUB_TOKEN=...   # Bearer PAT (see above)
#   ./experiments/lineage/lineage-walk.sh discover           # list ingested datasets + URNs
#   ./experiments/lineage/lineage-walk.sh walk '<urn>' UPSTREAM
#
# These are deliberately thin curls over inline GraphQL: if the deployed DataHub
# version wants a slightly different query shape, edit the heredoc and re-run.
# =============================================================================
set -euo pipefail

DATAHUB_GMS_URL="${DATAHUB_GMS_URL:-http://datahub-gms.data-governance.svc.cluster.local:8080}"
ACTION="${1:-discover}"

if [[ -z "${DATAHUB_TOKEN:-}" ]]; then
  echo "ERROR: set DATAHUB_TOKEN (Bearer PAT). See the header of this script." >&2
  exit 2
fi

gql() {
  # POST an inline GraphQL query to the GMS GraphQL endpoint. jq -n builds the
  # {"query": "..."} envelope with correct escaping (no python — UV mandate).
  local payload
  payload="$(jq -n --arg q "$1" '{query: $q}')"
  curl -fsS -X POST "${DATAHUB_GMS_URL}/api/graphql" \
    -H "Authorization: Bearer ${DATAHUB_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data-binary "$payload"
}

case "$ACTION" in
  discover)
    echo "datasets known to DataHub GMS (${DATAHUB_GMS_URL}):"
    gql 'query { search(input: {type: DATASET, query: "*", start: 0, count: 25}) {
      total
      searchResults { entity { urn ... on Dataset { name platform { name } } } }
    } }'
    echo
    echo "Pick a URN above, then: $0 walk '<urn>' [UPSTREAM|DOWNSTREAM]"
    ;;
  walk)
    URN="${2:?usage: $0 walk '<dataset-urn>' [UPSTREAM|DOWNSTREAM]}"
    DIRECTION="${3:-UPSTREAM}"
    echo "lineage ${DIRECTION} from ${URN}:"
    gql "query { searchAcrossLineage(input: {
        urn: \"${URN}\", direction: ${DIRECTION},
        types: [], query: \"*\", start: 0, count: 50
      }) {
        total
        searchResults { degree entity { urn type } }
      } }"
    ;;
  *)
    echo "usage: $0 [discover | walk '<urn>' [UPSTREAM|DOWNSTREAM]]" >&2
    exit 2
    ;;
esac
