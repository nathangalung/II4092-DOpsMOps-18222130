# DataOps / MLOps Platform

K8s-native data + ML platform composed from open-source components, applied via a
single root `Makefile` with composable phases.

## Repository layout

```
.
├── Makefile               # Root entry — composable phases, atoms, ops, use-case dispatch
├── scripts/               # Shell + python helpers invoked from the Makefile
│   ├── apply-component.sh        # Generic kubectl apply -k <component-dir>
│   ├── apply-namespaces.sh       # Create all platform namespaces
│   ├── create-buckets.sh         # Seed MinIO buckets
│   ├── list-components.sh        # Print every installable component
│   ├── nuke.sh                   # Tear down everything (DESTRUCTIVE)
│   ├── nuke-vps.sh               # Reset VPS to fresh state (DESTRUCTIVE)
│   ├── preflight.sh              # Verify kubectl/helm/kustomize toolchain
│   ├── render-scalability.sh     # Render HPA/VPA/KEDA from templates
│   ├── retry.sh                  # Retry harness used by apply-component
│   ├── scale-zero-all.sh         # Scale all Deploy + STS to zero
│   ├── scale.sh                  # Scale a single Deployment / StatefulSet
│   ├── seed-gitea.sh             # Bootstrap Gitea repo + main branch
│   ├── seed-openbao-from-env.sh  # Bootstrap OpenBao KV from .env
│   ├── set-replicas-zero.py      # Baseline replicas=0 in components (uv-runnable)
│   ├── setup-databases.sh        # Initial schemas / users
│   ├── setup-toolchain.sh        # Install kubectl/helm/kustomize on the host
│   ├── wait-component.sh         # Wait for pods labelled app=<name> Ready
│   └── wipe-data.sh              # Delete PVCs in storage namespaces (DESTRUCTIVE)
├── platform/              # Use-case-agnostic platform manifests (single-node k3s)
│   ├── components/        # Per-namespace kustomize trees (~70 components)
│   │   ├── common/                 # cert-manager, istio, knative, keda, kueue
│   │   ├── security/               # openbao, ESO, kyverno, falco, trivy, opa
│   │   ├── storage/                # postgres, minio, valkey, mysql, qdrant, lakefs
│   │   ├── data-ingestion/         # kafka stack, meltano, debezium
│   │   ├── data-processing/        # flink, spark, airflow, dbt, trino, superset, GE
│   │   ├── data-governance/        # datahub, opensearch, openlineage
│   │   ├── model-lifecycle/        # mlflow, feast, kubeflow, katib
│   │   ├── model-serving/          # kserve
│   │   ├── observability/          # prom, grafana, loki, tempo, alloy, opencost
│   │   └── gitops/                 # argocd, gitea, tekton, argo-rollouts
│   ├── scalability/       # HPA + VPA + KEDA ScaledObject templates
│   ├── services/          # Generic service manifests (use-case-agnostic)
│   ├── config/            # Cluster-wide config maps + values
│   └── config.yaml
├── use-case-crypto/       # Crypto microservices, DAGs, dbt models, manifests
└── use-case-stock/        # Stock use-case stub (not wired yet)
```

## Quickstart

```sh
make preflight              # Verify kubectl + helm + kustomize on the host
make phase-base             # Mesh + secrets + Postgres + MinIO + ArgoCD
make phase-observability    # + LGTM stack
make phase-stream-e2e       # Full streaming → feast → train → serve pipeline
```

## Composable phases

Phases compose **atoms** (`atom-<group>`). Pick the smallest phase that satisfies
your goal. Three categories:

**Layer-only** — single concern, no downstream:

| Phase | Bundles |
|---|---|
| `phase-base` | namespaces + cert/istio + KEDA/kueue + ESO/Vault + Kyverno + ArgoCD + Postgres + MinIO |
| `phase-observability` | base + LGTM (Prom, Grafana, Loki, Tempo, Alloy) |
| `phase-ingest-stream` | base + Kafka only (Strimzi, Karapace, Connect, UI) |
| `phase-ingest-batch` | base + Meltano only (Singer ELT) |
| `phase-stream` | Kafka + Flink (no Feast) |
| `phase-batch` | Meltano + Spark/Airflow/dbt/Trino/Superset + GE (no Feast) |
| `phase-feast` | Redis + Feast standalone (BYO upstream) |
| `phase-mlflow` | MySQL + MLflow standalone |
| `phase-kubeflow` | MySQL + Kubeflow Pipelines/Trainer/Katib/Notebooks |
| `phase-serve` | Knative + KServe only (BYO model) |
| `phase-governance` | DataHub + OpenSearch + OpenLineage |
| `phase-gitops` | ArgoCD + Tekton + Gitea + Argo Rollouts |

**Cross-layer** — compose two stages:

| Phase | Bundles |
|---|---|
| `phase-stream-to-feast` | Stream → Flink → Feast |
| `phase-batch-to-feast` | Batch → Spark/Airflow/dbt/GE → Feast |
| `phase-feast-to-mlflow` | Feast → MLflow only |
| `phase-feast-to-kubeflow` | Feast → Kubeflow only |
| `phase-feast-to-training` | Feast → MLflow + Kubeflow |
| `phase-feast-to-serving` | Feast online store → KServe |
| `phase-mlflow-to-serving` | MLflow → KServe (no Feast, no Kubeflow) |
| `phase-kubeflow-to-serving` | Kubeflow → KServe (no Feast, no MLflow) |
| `phase-train-to-serving` | MLflow + Kubeflow → KServe |

**End-to-end** — full pipeline:

| Phase | Bundles |
|---|---|
| `phase-stream-e2e` | Stream → Feast → Train → Serve |
| `phase-batch-e2e` | Batch → Feast → Train → Serve |
| `phase-full` | Everything |

## Per-component install

```sh
make install-<component>          # e.g. install-kafka, install-feast
make uninstall-<component>
make install-ns-<namespace>       # apply every component in a namespace
make list-components              # see all available names
```

`install-%` dispatches to `scripts/apply-component.sh`, which finds the component
under `platform/components/<ns>/<name>` and runs `kubectl apply -k` (kustomize).

## Scalability primitives

Three templates under `platform/scalability/`:

| Tool | Use when |
|---|---|
| HPA v2 | Stateless web/API, CPU/mem-bound (min 1+) |
| VPA (Off mode) | Stateful DBs — advisory rightsize |
| KEDA ScaledObject | Event-driven, scale-to-zero (Kafka lag, queues, cron) |

```sh
make install-hpa COMPONENT=feast NS=model-lifecycle MIN=1 MAX=5 \
    CPU_TARGET=70 MEM_TARGET=80 KIND=Deployment

make install-vpa COMPONENT=mlflow NS=model-lifecycle KIND=Deployment \
    MODE=Off CPU_MIN=100m CPU_MAX=2 MEM_MIN=128Mi MEM_MAX=4Gi

make install-keda-scaledobject COMPONENT=consumer NS=data-processing \
    KIND=Deployment MIN=0 MAX=10 TRIGGER=kafka \
    TRIGGER_META='bootstrapServers: ... topic: ... lagThreshold: "100"'
```

See `platform/scalability/README.md` for per-component recommendations.

## Operations

```sh
make scale-zero-all               # Scale all Deploys + STS to 0 (operators preserved)
make scale-up COMPONENT=feast REPLICAS=2
make scale-down COMPONENT=feast
make wipe-data                    # Drop PVCs in storage namespaces (DESTRUCTIVE)
make nuke                         # Tear down namespaces + CRDs (full reset)
make status                       # Pod state per namespace
make events                       # Last 50 cluster events
```

## Use-case dispatch

```sh
make usecase-crypto-up            # Deploy crypto microservices
make usecase-crypto-down
make usecase-crypto-status
make usecase-crypto-build         # Build images
make usecase-crypto-test          # Run tests
```

All use-case targets live in the root `Makefile` prefixed with `usecase-<name>-`
(e.g. `usecase-crypto-up`, `usecase-crypto-build`); paths inside those targets
resolve relative to the use-case directory (e.g. `use-case-crypto/`).

## Conventions

- ArgoCD `selfHeal=false` — components do not auto-revert. Manual sync only.
- Namespaces created upfront via `scripts/apply-namespaces.sh`.
- All scripts are POSIX `bash`, idempotent, and never use `until` polling loops.
- Component manifests labelled `app.kubernetes.io/managed-by: platform-makefile`.
