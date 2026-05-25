# Use-Case Services (Extensions)

This directory contains **domain-specific code** that extends or overrides
the generic services. Only services that need crypto-specific logic live here.

## Architecture

```
services-src/                       <- Generic service source code
  processing/batch/
    transformers/technical.py       <- Rolling stats, z-score (numpy/pandas only)
  dashboard/frontend/
    src/config/domain.ts            <- Generic labels (POSITIVE/NEGATIVE/NEUTRAL)
  dashboard/ml-bridge/
    services/prediction.py          <- Generic fields (predicted_value, class_label)
  trainer/
    src/*.py                        <- NUM_CLASSES from env var (default 3)

services/                           <- Domain-specific extensions
  processing/
    batch/
      transformers/technical.py     <- Adds MACD, Bollinger, ATR, OBV, MFI, VWAP (ta lib)
      requirements-extra.txt        <- Extra Python deps (ta>=0.11.0)
    feature-store/
      feature_store.yaml            <- Feast config (ClickHouse offline + Redis online)
      definitions.py                <- Feast feature views (OHLCV, momentum, sentiment)
  dashboard/
    frontend/
      src/config/domain.ts          <- Crypto labels (BUY/SELL/HOLD), price mock data
      src/types/index.ts            <- Extended Prediction type with predicted_price/signal
    ml-bridge/
      services/prediction.py        <- Crypto fields (predicted_price, signal)
```

## How the Overlay Works

During `make build-<category>`, the Makefile:

1. Copies generic service code from `SERVICES_SRC` into a temp directory
2. Copies `services/<path>/` on top (overlaying files)
3. Builds the Docker image from the merged directory

This means crypto override files **replace** the generic ones,
adding domain-specific behavior while keeping the same interfaces.

The `requirements-extra.txt` file is picked up by the Dockerfile to install
extra dependencies.

## What Lives Where

| Component               | Location                                  | Why                      |
| ----------------------- | ----------------------------------------- | ------------------------ |
| Generic services (18)   | `SERVICES_SRC` (configurable)             | Shared service code      |
| K8s manifests           | `manifests/base/` + `manifests/overlays/` | Kustomize deployment     |
| Pipeline config         | `manifests/base/configmaps/*.yaml`        | Domain-specific settings |
| Batch transformers      | `services/processing/batch/transformers/` | Crypto TA indicators     |
| Feature store           | `services/processing/feature-store/`      | Feast definitions        |
| Dashboard domain config | `services/dashboard/frontend/src/config/` | BUY/SELL/HOLD labels     |
| ML-Bridge prediction    | `services/dashboard/ml-bridge/services/`  | Crypto prediction fields |
| Database init           | `database/init_clickhouse.sql`            | Crypto-specific tables   |

## Adding a New Extension

To add domain-specific code for another service:

1. Create the directory: `services/<category>/<service>/`
2. Add only the files that differ from the generic version
3. Keep the same function signatures so the overlay is drop-in compatible
4. Add `requirements-extra.txt` if you need extra Python dependencies
5. Update the Makefile `build-<category>` target with the overlay pattern

## Env Var Configuration

Services are configurable via env vars in `manifests/base/configmaps/`:

| Env Var                    | Service         | Description                                   |
| -------------------------- | --------------- | --------------------------------------------- |
| `NUM_CLASSES`              | trainer models  | Number of classification classes (default: 3) |
| `TARGET_COLUMN`            | trainer         | Column to predict (crypto: "close")           |
| `CLASSIFICATION_THRESHOLD` | trainer         | Threshold for class assignment                |
| `ACTIVE_HOURS_START/END`   | batch processor | Active hours range (crypto: 0-23, 24/7)       |
| `RESPONSE_FIELD_MAPPING`   | rest-collector  | API response field mapping                    |
