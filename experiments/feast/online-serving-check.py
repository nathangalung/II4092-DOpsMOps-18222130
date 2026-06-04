#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx>=0.27"]
# ///
"""SK-F-02 online feature-serving correctness check (validates KF-02; gathers the
runtime evidence #492 needs — running this green against the live cluster is what
closes #492, not the file existing).

The k6 latency benchmark (experiments/load/feast-online-latency.js) proves the
Feast feature server answers `/get-online-features` with HTTP 200 fast enough,
but a 200 with all-null values still "passes" latency while serving nothing.
This check is the value assertion the load test deliberately omits: for every
sampled entity it asserts the online store returns a NON-NULL, PRESENT value
for at least one feature — i.e. the batch -> Feast materialize -> online read
path (wired in #491) actually populated Valkey.

Scope: this covers the *serving-availability* leg of SK-F-02 — the necessary
precondition that the online store answers with real values. The full SK-F-02
acceptance ("nilai online dan offline konsisten") additionally compares those
online values against the offline store for the same entity + reference time;
that value-equality leg uses the Feast SDK (`get_online_features` vs
`get_historical_features`) and is documented in this directory's README.

Read-only: a single POST per entity to the same REST contract the k6 script and
the platform ml-bridge reader use (feature_service + entities). It mutates
nothing and is safe to run against the live cluster.

Run (after loading the config — see experiments/README.md):
    set -a; . experiments/config.crypto.env; set +a
    # reach the in-cluster feature server from your shell, e.g.:
    kubectl -n model-lifecycle port-forward svc/feast 6566:6566 &
    FEAST_URL=http://localhost:6566 uv run experiments/feast/online-serving-check.py

Exit code 0 = every sampled entity served >=1 non-null feature; 1 = at least one
entity came back empty/null (materialization gap — #492 NOT satisfied); 2 = the
server errored or returned an unrecognised shape (cannot judge — fix first).
"""

from __future__ import annotations

import json
import os
import sys

import httpx

FEAST_URL = os.environ.get("FEAST_URL", "http://feast.model-lifecycle.svc:6566").rstrip(
    "/"
)
FEATURE_SERVICE = os.environ.get("FEATURE_SERVICE", "crypto_inference_features")
ENTITY_KEY = os.environ.get("ENTITY_KEY", "symbol")
SYMBOLS = [
    s.strip()
    for s in os.environ.get("SYMBOLS", "BTC-USD,ETH-USD,SOL-USD").split(",")
    if s.strip()
]


def _query(client: httpx.Client, entity: str) -> dict:
    """POST one entity to the Feast feature server. Same contract as the k6
    script: {feature_service, entities: {<key>: [<value>]}}."""
    resp = client.post(
        f"{FEAST_URL}/get-online-features",
        json={"feature_service": FEATURE_SERVICE, "entities": {ENTITY_KEY: [entity]}},
        headers={"Content-Type": "application/json"},
        timeout=10.0,
    )
    resp.raise_for_status()
    return resp.json()


def _non_null_features(payload: dict) -> dict[str, object]:
    """Extract {feature_name: value} for the single requested entity row,
    keeping only features that are PRESENT with a non-null value.

    Feast feature-server response shape:
        metadata.feature_names: [name, ...]   # entity key is one of these
        results: [{values: [...], statuses: [...]}, ...]  # aligned to names
    We sent one entity row, so index [0] of each result is what we read.
    Raises ValueError if the shape is not recognisable (fail loud, never
    silently report "0 features" as if the server said so)."""
    try:
        names = payload["metadata"]["feature_names"]
        results = payload["results"]
    except (KeyError, TypeError) as e:
        raise ValueError(
            f"unrecognised feature-server response: {json.dumps(payload)[:400]}"
        ) from e
    if len(names) != len(results):
        raise ValueError(f"feature_names ({len(names)}) != results ({len(results)})")

    present: dict[str, object] = {}
    for name, result in zip(names, results):
        if name == ENTITY_KEY:
            continue
        values = result.get("values") or []
        statuses = result.get("statuses") or []
        if not values:
            continue
        value = values[0]
        status = statuses[0] if statuses else "PRESENT"
        if value is not None and status == "PRESENT":
            present[name] = value
    return present


def main() -> int:
    print(
        f"feast online-serving check -> {FEAST_URL}  service={FEATURE_SERVICE}  key={ENTITY_KEY}"
    )
    empty: list[str] = []
    with httpx.Client() as client:
        for entity in SYMBOLS:
            try:
                payload = _query(client, entity)
                present = _non_null_features(payload)
            except httpx.HTTPError as e:
                print(
                    f"  ERROR  {entity}: feature server request failed: {e}",
                    file=sys.stderr,
                )
                return 2
            except ValueError as e:
                print(f"  ERROR  {entity}: {e}", file=sys.stderr)
                return 2
            if present:
                sample = ", ".join(f"{k}={v}" for k, v in list(present.items())[:3])
                print(
                    f"  OK     {entity}: {len(present)} non-null feature(s) [{sample}]"
                )
            else:
                print(
                    f"  EMPTY  {entity}: 0 non-null features (online store not materialised)"
                )
                empty.append(entity)

    if empty:
        print(
            f"\nFAIL: {len(empty)}/{len(SYMBOLS)} entit(ies) served no features: {', '.join(empty)}"
        )
        print(
            "KF-02 / #492 NOT satisfied — check the materialization CronJob and the offline gold mart "
            "(experiments/etl/data-landed-check.sh)."
        )
        return 1
    print(
        f"\nPASS: all {len(SYMBOLS)} entit(ies) served non-null features. KF-02 online serving verified."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
