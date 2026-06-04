# Medallion data-landed check — SK-F-11 (KF-11; supports KNF-05)

`data-landed-check.sh` is the data engineer's read-only "is the ETL flowing?"
probe: for each medallion layer it reports row count, and on the landing table
event-time freshness, so an empty silver/gold immediately localises the broken
hop. It is the manual form of the diagnoses behind #463 (bronze empty) and #470
(gold empty). It SELECTs only MergeTree target tables via `clickhouse-client`
inside the CHI pod (`kubectl exec`); it never mutates pipeline state.

> **Never query a `*_kafka` table.** `bronze.crypto_ohlcv_kafka`,
> `*_sentiment_kafka`, `*_features_kafka`, `*_tickers_kafka`, `*_trades_kafka`,
> `gold.cdc_predictions_kafka` are `ENGINE = Kafka()`. A plain `SELECT` on them
> **consumes the topic offset** — the rows you read are dropped from the live
> stream and never reach the MergeTree target, silently corrupting the running
> pipeline. Always query the MergeTree table the matching `*_consumer`
> materialized view writes into (the value of `$BRONZE_LANDING_TABLE`). The
> script refuses to run if any configured table name ends in `_kafka`.

```bash
set -a; . experiments/config.crypto.env; set +a
# optional admin creds if the in-pod default user is password-protected:
export CLICKHOUSE_USER=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
  -o jsonpath='{.data.username}' | base64 -d)
export CLICKHOUSE_PASSWORD=$(kubectl -n "$CLICKHOUSE_NAMESPACE" get secret clickhouse-admin \
  -o jsonpath='{.data.password}' | base64 -d)
./experiments/etl/data-landed-check.sh
```

| Env var | Purpose | Default |
|---------|---------|---------|
| `CLICKHOUSE_NAMESPACE` | ns of the platform CHI | `storage` |
| `CLICKHOUSE_CHI` | CHI name → pod label `clickhouse.altinity.com/chi` | `platform` |
| `BRONZE_LANDING_TABLE` | raw landing (MergeTree, not `_kafka`) | `bronze.crypto_ohlcv` |
| `SILVER_STAGING_TABLE` | dbt staging model | `silver.stg_ohlcv` |
| `GOLD_FEATURES_TABLE` | dbt features mart | `gold.fct_ohlcv_features` |
| `GOLD_TRAINING_TABLE` | dbt point-in-time training mart | `gold.fct_training_data` |
| `EVENT_TIME_COLUMN` | freshness column on the landing table | `timestamp` |
| `CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD` | clickhouse-client auth | (none → in-pod default user) |

Exit `0` = every layer has rows (KF-11 batch+stream landing verified); `1` = a
layer is empty (broken hop upstream); `2` = setup error / `_kafka` guard tripped.
