#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["confluent-kafka>=2.6"]
# ///
"""SK-F-07 synthetic drift injector (validates KF-07; supports SK-N-05).

Consumes recent records from the validated market topic, shifts the price
distribution by a configurable sigma, and republishes them so the platform
``drift-detector`` (PSI / K-S) observes a genuine distribution shift and the
``retrain-on-drift`` Argo Workflow is triggered. Payload distortion is out of
scope for chaos-mesh, so it is done here as a deliberate producer.

Run:
    KAFKA_BOOTSTRAP=platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9093 \\
    KAFKA_USER=... KAFKA_PASSWORD=... KAFKA_CA=/etc/kafka/ca.crt \\
    uv run experiments/drift/inject_drift.py --sigma 2.0 --duration 3600
"""

from __future__ import annotations

import argparse
import json
import os
import time

from confluent_kafka import Consumer, Producer

TOPIC = os.environ.get("DRIFT_TOPIC", "crypto.validated")
# Numeric fields the injector shifts. Override per use case via PRICE_FIELDS
# (comma-separated); defaults mirror the crypto OHLCV schema.
PRICE_FIELDS = tuple(
    f.strip()
    for f in os.environ.get("PRICE_FIELDS", "open,high,low,close,vwap").split(",")
    if f.strip()
)


def _kafka_conf() -> dict:
    conf = {
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP"],
        "security.protocol": os.environ.get("KAFKA_SECURITY_PROTOCOL", "SASL_SSL"),
        "sasl.mechanism": os.environ.get("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512"),
        "sasl.username": os.environ["KAFKA_USER"],
        "sasl.password": os.environ["KAFKA_PASSWORD"],
    }
    ca = os.environ.get("KAFKA_CA")
    if ca:
        conf["ssl.ca.location"] = ca
    return conf


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", type=float, default=2.0, help="price shift, in sigma")
    parser.add_argument("--duration", type=int, default=3600, help="run time, seconds")
    args = parser.parse_args()

    consumer = Consumer(
        {**_kafka_conf(), "group.id": "drift-injector", "auto.offset.reset": "latest"}
    )
    producer = Producer(_kafka_conf())
    consumer.subscribe([TOPIC])

    # Multiplicative shift: price * (1 + 0.01 * sigma) per record.
    factor = 1.0 + 0.01 * args.sigma
    deadline = time.monotonic() + args.duration
    injected = 0

    try:
        while time.monotonic() < deadline:
            msg = consumer.poll(1.0)
            if msg is None or msg.error():
                continue
            try:
                record = json.loads(msg.value())
            except (ValueError, TypeError):
                continue
            for field in PRICE_FIELDS:
                if isinstance(record.get(field), (int, float)):
                    record[field] = record[field] * factor
            record["_synthetic_drift"] = True
            producer.produce(TOPIC, key=msg.key(), value=json.dumps(record).encode())
            injected += 1
            if injected % 1000 == 0:
                producer.flush()
                print(f"injected={injected}", flush=True)
    finally:
        producer.flush()
        consumer.close()
        print(f"done injected={injected}", flush=True)


if __name__ == "__main__":
    main()
