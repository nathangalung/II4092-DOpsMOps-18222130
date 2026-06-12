# Batch ↔ Stream Parity (KF-11 / SK-F-11)

Read-only oracle asserting that the two halves of the lambda architecture
compute the same feature from the same events:

| side   | path                                                                 | column          |
|--------|----------------------------------------------------------------------|-----------------|
| stream | Flink `FeatureFunction` → `crypto.features.v1` → CH Kafka engine → MV | `secondary_avg` |
| batch  | Airflow lakehouse DAG → dbt `fct_ohlcv_features`                      | `volume_sma_20` |

Both are a **trailing 20-event volume mean per symbol in event-time order**
(stream period from `FLINK_SECONDARY_AVG_PERIOD` in
`use-case-crypto/manifests/base/configmaps/features.yaml`; batch window
`ROWS BETWEEN 19 PRECEDING AND CURRENT ROW` in
`use-case-crypto/dbt/models/marts/fct_ohlcv_features.sql`).

## Run

```sh
set -a; . "${EXPERIMENTS_CONFIG:-experiments/config.crypto.env}"; set +a
./experiments/parity/parity-check.sh
```

Exit 0 = match rate ≥ `PARITY_MIN_MATCH_RATE`; 1 = parity broken / no overlap;
2 = setup error. All knobs (tables, columns, lookback, tolerances, threshold)
come from the config env — point them at any other use case's tables without
touching the script.

## Why a match RATE, not strict equality

* **Stream warm-up** — after a Flink restart without state restore the
  trailing window refills from empty; the first <20 events per symbol average
  fewer rows than the batch side.
* **Dedup ordering** — batch reads deduplicated silver; the stream averages
  events in arrival order, so a duplicate-heavy second can shift the window
  by one event.
* **Float round-trip** — Java `double` → JSON → ClickHouse `Float64`; absorbed
  by the relative tolerance.

A healthy steady-state pipeline sits at match rate ≈ 1.0 with p99 relative
error at float-noise level; sustained drops point at a real semantic split
between the Flink job and the dbt model (e.g. a period knob changed on one
side only).

## Prerequisites

Both paths must have landed rows in the lookback window — verify with
`experiments/etl/data-landed-check.sh` first. The batch column ships with the
`crypto-dbt-project` image, so after editing the dbt model rebuild it
(`make usecase-crypto-build-dbt`) and let the next lakehouse DAG run publish.
