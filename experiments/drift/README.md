# Synthetic drift injector — SK-F-07

`inject_drift.py` republishes records from `crypto.validated` with a shifted
price distribution so the platform drift detector (`platform/services/quality/drift`,
PSI / K-S) flags a shift in `gold.drift_multi_scale`, which the `retrain-on-drift`
Argo CronWorkflow then acts on.

Self-contained via PEP 723 inline metadata (`confluent-kafka`) — run with `uv run`
(script mode), no virtualenv setup:

```bash
KAFKA_BOOTSTRAP=platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9093 \
KAFKA_USER=... KAFKA_PASSWORD=... KAFKA_CA=/etc/kafka/ca.crt \
uv run experiments/drift/inject_drift.py --sigma 2.0 --duration 3600
```

These variables match `experiments/config.crypto.env`; source it
(`set -a; . experiments/config.crypto.env; set +a`) to set them all at once,
then add the runtime `KAFKA_USER` / `KAFKA_PASSWORD` secrets (kept out of the
committed config).

| Env var | Purpose | Default |
|---------|---------|---------|
| `KAFKA_BOOTSTRAP` | Strimzi bootstrap `host:9093` | (required) |
| `KAFKA_USER` / `KAFKA_PASSWORD` | SCRAM credentials | (required) |
| `KAFKA_CA` | cluster CA cert path | (none → system trust) |
| `KAFKA_SASL_MECHANISM` | SASL mechanism | `SCRAM-SHA-512` |
| `DRIFT_TOPIC` | topic to perturb | `crypto.validated` |
| `PRICE_FIELDS` | numeric fields to shift (comma-sep) | `open,high,low,close,vwap` |

`--sigma` sets the multiplicative price shift; `--duration` the run time in seconds.
