# MLOps Pipeline — Crypto Use Case

A modular, configurable ML pipeline for cryptocurrency data. Extends generic service templates with crypto-specific configuration.

## Quick Start

```bash
# 1. Build images (Minikube)
make build-images

# 2. Deploy
make deploy
```

## How to Enable/Disable Services

### Method 1: Edit config/services.yaml

```yaml
services:
  ingestion:
    rest_collector:
      enabled: true # Set to false to disable
  quality:
    validator:
      enabled: false # Disabled
```

### Method 2: Edit manifests/base/kustomization.yaml (Kubernetes Deploy)

```yaml
resources:
  # Comment out to disable service
  - deployments/rest-collector.yaml
  # - deployments/validator.yaml  # <-- Disabled
```

## Directory Structure

```
use-case-crypto/
├── config/                  # Project metadata + service toggles
│   ├── project.yaml         # Project name, namespace (used by Makefile)
│   └── services.yaml        # Which services to enable/disable
├── services/                # Crypto-specific service code
│   ├── ingestion/           # REST + WebSocket collectors
│   ├── processing/          # Batch, stream, vector, feature-store
│   ├── training/            # Trainer extensions
│   └── dashboard/           # Backend, frontend, ML bridge
├── manifests/               # Kubernetes manifests
│   ├── base/                # K8s templates + domain configmap patches
│   │   ├── deployments/     # 16 Deployment manifests
│   │   ├── cronjobs/        # 9 CronJob manifests
│   │   ├── configmaps/      # 6 patches (identity, topics, sources, features, models, quality)
│   │   ├── patches/         # 5 service patches
│   │   ├── rbac/            # Roles and bindings
│   │   └── hpa/             # Autoscaling
│   └── overlays/            # Environment overlays (local/cloud)
├── database/                # ClickHouse init scripts
└── scripts/                 # Helper scripts
```

## Common Tasks

### Add New Data Source

1. Update `manifests/base/configmaps/sources.yaml` with the new env vars.
2. See `services/ingestion/README.md` for custom collector code if needed.

### Add New Model

1. Update `manifests/base/configmaps/models.yaml` with the new env vars (MODEL_TYPE, TASK_TYPE, etc.).
2. See `services/training/README.md` for custom model code if needed.

### Add New Features

1. Update `manifests/base/configmaps/features.yaml` (FEATURES_COLUMNS, FEAST_LATEST_FEATURES, Flink config).
2. See `services/processing/README.md` for custom feature code.

### Disable a Service Completely

In `manifests/base/kustomization.yaml`:

```yaml
# Comment out the service
# - deployments/validator.yaml
# - cronjobs/drift-multi-scale.yaml
```

## Service Documentation

Each service has a README with:

- How to use/configure the service
- How to add new components
- Code examples for customization

| Service    | README                                                         |
| ---------- | -------------------------------------------------------------- |
| Ingestion  | [services/ingestion/README.md](services/ingestion/README.md)   |
| Processing | [services/processing/README.md](services/processing/README.md) |
| Training   | [services/training/README.md](services/training/README.md)     |
| Dashboard  | [services/dashboard/README.md](services/dashboard/README.md)   |

## Example Configurations

### Minimal (Serving Only)

```yaml
# In manifests/base/kustomization.yaml, comment out everything except:
resources:
  - namespace.yaml
  - secrets.yaml
  - pipeline-infrastructure.yaml
  - deployments/gateway.yaml
  - inferenceservice-kserve.yaml
```

### Full Pipeline

Keep all resources enabled (default).

## CI/CD Integration

The pipeline is designed for GitOps:

- Domain config lives in `manifests/base/configmaps/` (Kustomize patches)
- Enable/disable services by commenting in `kustomization.yaml`
- ArgoCD application in `argocd/application.yaml`
