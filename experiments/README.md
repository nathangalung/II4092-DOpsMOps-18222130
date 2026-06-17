# Experiments — Evaluation & Verification Harness

Scenario-as-code for the thesis evaluation (Bab VI — *Evaluasi*). Each functional
(KF) and nonfunctional (KNF) requirement is paired with at least one runnable
scenario that **probes the deployed system to gather evidence of compliance**.

This directory is a top-level sibling of `platform/` and `use-case-crypto/` on
purpose: it is the **verification layer**, kept separate from the system under
test so the deployed use-case stays strict and is never edited just to make a
check pass. Nothing here is part of `make phase-full` or Argo CD reconciliation —
every artifact is **run manually, read-only against a live cluster**, and never
mutates the deployed use-case.

Who runs what:
- **Data scientist** — online feature-serving non-null check (`feast/`, KF-02),
  drift injection + retrain trigger (`drift/`), MLflow replay / stage-transition
  audits (KF-07, KF-09, KF-10).
- **Data engineer** — medallion data-landed + freshness (`etl/`), batch↔stream
  feature parity (`parity/`, KF-11), DataHub lineage walk (`lineage/`, KF-08),
  point-in-time + leakage probes (KF-03, KNF-05), throughput + consumer-lag
  (KNF-02).
- **Business / platform owner** — cost + utilisation + SLO + security +
  single-sign-on access (KNF-07, KNF-09, KNF-10), reproducibility on a fresh
  node (KNF-11).

> Prerequisites: platform up (`make phase-full`), use-case deployed
> (`make usecase-crypto-build && make usecase-crypto-up`), all pods `Running`
> (`kubectl get pods -A`). Load generators run from the `platform-test`
> namespace — create it first:
>
> ```bash
> kubectl apply -f experiments/namespace.yaml
> ```
>
> Endpoints below are defaults; override via `config.crypto.env` (see
> [Configuration](#configuration)) to match the live cluster
> (`kubectl -n model-lifecycle get svc`, `kubectl -n use-case-crypto get svc`).

## Configuration

All scenarios read their domain inputs (entity symbols, Feast feature service,
Qdrant collection, Kafka topic, predictor name, medallion table names, ClickHouse
+ DataHub GMS endpoints, OpenLineage namespaces, load knobs) from one env file —
**`config.crypto.env`** — so the scripts stay domain-agnostic and a new use case
is a config swap, never a code edit. Load it before running
anything; the k6 scripts read the values as `__ENV.*`, the drift injector as
`os.environ`, and the chaos manifests are rendered from them with `envsubst`:

```bash
set -a; . "${EXPERIMENTS_CONFIG:-experiments/config.crypto.env}"; set +a
```

For a different use case, copy the file and edit only its DOMAIN block:

```bash
cp experiments/config.crypto.env experiments/config.fraud.env
$EDITOR experiments/config.fraud.env          # change DOMAIN values only
export EXPERIMENTS_CONFIG=experiments/config.fraud.env
```

The crypto values are the working defaults, so the thesis use case runs with no
edits. This file mirrors canonical declarations in `use-case-crypto/`;
`make usecase-configure` rebrands that tree only and does **not** rewrite this
sibling, so a prefix change there must be mirrored here by hand.

## Kebutuhan Fungsional (KF)

| KF | Skenario | Artefak / Cara jalan |
|----|----------|----------------------|
| KF-01 | SK-F-01 | Edit `use-case-crypto/scripts/libs/feature_store/definitions.py` → `git push` Gitea → Argo CD sync → `uv run feast feature-views list` |
| KF-02 | SK-F-02 | `uv run experiments/feast/online-serving-check.py` (online non-null) + `etl/data-landed-check.sh` (offline landed) + online↔offline value parity via Feast SDK `get_online_features`/`get_historical_features` (see `feast/README.md`) |
| KF-03 | SK-F-03 | `get_historical_features` point-in-time audit on `gold.fct_training_data` |
| KF-04 | SK-F-04 | `k6 run load/vector-search-latency.js` (Qdrant top-10 recall) |
| KF-05 | SK-F-05 | `uv run --with 'kfp[kubernetes]==2.16.0' use-case-crypto/pipelines/retraining_pipeline.py` (Kubeflow Pipelines) |
| KF-06 | SK-F-06 | Argo Rollouts canary + forced-bad-model rollback |
| KF-07 | SK-F-07 | `uv run experiments/drift/inject_drift.py --sigma 2.0` → `quality/drift` → `retrain-on-drift` CronWorkflow |
| KF-08 | SK-F-08 | `experiments/lineage/lineage-walk.sh discover` then `walk '<urn>'` — DataHub GMS lineage graph (`crypto.ws.raw` → prediction) |
| KF-09 | SK-F-09 | Two MLflow runs + replay from snapshot (≤1% metric delta) |
| KF-10 | SK-F-10 | MLflow stage transitions none→staging→production→archived + audit trail |
| KF-11 | SK-F-11 | `./experiments/parity/parity-check.sh` — batch (dbt `volume_sma_20`) ↔ stream (Flink `secondary_avg`) tolerance match-rate on the same trailing 20-event volume mean (the SK-F-11 acceptance). Substrate health first: `experiments/etl/data-landed-check.sh` (medallion rows + freshness — a data-engineer health probe, not the parity test itself) |
| KF-12 | SK-F-12 | YAML replica change in Gitea → Argo CD sync, no drift |
| KF-13 | SK-F-13 | One UV notebook: Feast + KServe + MLflow SDKs |
| KF-14 | SK-F-14 | Kueue `ClusterQueue` saturation (jobs beyond quota → `Pending`) |

## Kebutuhan Nonfungsional (KNF)

| KNF | Skenario | Artefak / Cara jalan |
|-----|----------|----------------------|
| KNF-01 | SK-N-01 | `k6 run load/feast-online-latency.js` (p50<5 / p95<8 / p99<10 ms) |
| KNF-02 | SK-N-02 | `k6 run load/feast-throughput.js` (>10k QPS/node); stream half via `kafka-producer-perf-test` → `crypto.validated` (1M msg/s), watch `kafka_consumergroup_lag` |
| KNF-03 | SK-N-03 | `k6 run load/hpa-keda-rampup.js` (external load) or `envsubst < chaos/stress-chaos.yaml \| kubectl apply -f -` (in-pod gateway CPU stress); watch `kubectl get hpa,scaledobject,pods` |
| KNF-04 | SK-N-04 | load config, then `envsubst < chaos/pod-chaos.yaml \| kubectl apply -f -` + `envsubst < chaos/network-chaos.yaml \| kubectl apply -f -`; full drill via `envsubst < chaos/game-day.yaml \| kubectl apply -f -` (RTO<5m, RPO<1m) |
| KNF-05 | SK-N-05 | Great Expectations checkpoint + synthetic future-timestamp leakage probe |
| KNF-06 | SK-N-06 | OpenTelemetry trace walk on Tempo (single trace ID end-to-end) |
| KNF-07 | SK-N-07 | `trivy` cluster scan + `testssl.sh` on public endpoints (TLS 1.3, AES-256) |
| KNF-08 | SK-N-08 | Swap serving runtime or online store via CRD/overlay (e.g. Seldon as alternative), isolated change |
| KNF-09 | SK-N-09 | Akses seluruh konsol lewat satu sesi identitas dex + oauth2-proxy (SSO, tanpa login ulang), dokumentasi tersedia |
| KNF-10 | SK-N-10 | OpenCost + ClickHouse compression ratio + CPU utilisation (>70%, >5:1) |
| KNF-11 | SK-N-11 | Re-apply GitOps manifests on a fresh K3s node |
| KNF-12 | SK-N-12 | `make usecase-crypto-test` coverage (>80%) + `make phase-full` clean-cluster timing |

## Layout

```
experiments/
├── README.md             # this index (KF/KNF → scenario map)
├── config.crypto.env     # single domain swap point (sourced before any run)
├── namespace.yaml        # platform-test namespace (load generators)
├── load/                 # k6 load scripts (client-side latency / throughput)
├── chaos/                # chaos-mesh fault injection — resilience (KNF-04) + autoscale (KNF-03)
├── drift/                # synthetic drift injector (UV / PEP 723)
├── feast/                # online feature-serving non-null check (UV / PEP 723)
├── etl/                  # medallion data-landed / freshness probe (clickhouse-client)
├── lineage/              # DataHub GMS lineage walk (GraphQL via curl)
└── parity/               # batch↔stream feature parity oracle (KF-11, clickhouse-client)
```
