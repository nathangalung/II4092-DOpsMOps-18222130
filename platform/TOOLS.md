# Open Source Tool Catalog

This document lists every open source tool used in the platform and explains
what each one does and which parts of the pipeline depend on it. The platform
itself is domain agnostic. The crypto use case at the end shows how these same
tools are wired for one concrete domain.

The tools are grouped by the layer they belong to, following the seven layer
DataOps and MLOps architecture: infrastructure, ingestion, processing, feature
storage, model lifecycle, model serving, and governance with observability.
Security and GitOps run across all layers.

The source of truth for which components are enabled is
`platform/config/components.yaml`. Every entry below matches a real directory
under `platform/components/`.

## How to read this

Each table has three columns:

- Tool: the open source project.
- Role in this project: what it actually does here, not a generic description.
- Depended on by: the services or other tools that need it. "Platform wide"
  means many components rely on it.

## Layer 1: Infrastructure and common

The base that everything else runs on: the cluster, the mesh, autoscaling, job
admission, identity, and the local image registry.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| Kubernetes (k3s) | Single node cluster that hosts every workload. Lightweight distribution suited to one machine. | Platform wide |
| containerd | Container runtime under k3s that pulls and runs images. | Platform wide |
| Helm and Kustomize | Render and overlay the component manifests. Argo CD uses them to produce the applied YAML. | Argo CD, every component |
| cert-manager | Issues and rotates TLS certificates. Backs Istio mTLS and APISIX TLS. | Istio, APISIX |
| Istio | Service mesh. Provides mutual TLS between services, traffic routing, and the ingress gateway. | Knative, gateway, meshed services |
| Dex and oauth2-proxy | OIDC identity provider and auth proxy. Single sign on across the web UIs. | Grafana, DataHub, other UIs |
| KEDA | Event driven autoscaler. Scales workloads on Kafka lag and scales idle UIs down to zero. | Kafka consumers, Superset, DataHub frontend |
| Kueue | Kubernetes native job queue. Admits batch and training jobs by priority and quota. | Spark batch, training jobs |
| metrics-server | Serves pod and node resource metrics. Feeds the Horizontal Pod Autoscalers. | HPAs across the platform |
| Knative Serving | Serverless runtime installed as an available capability. Not on the serving path here, since KServe runs in RawDeployment mode. | None on the serving path |
| Docker Registry | In cluster image registry at localhost:5000. Holds locally built service images so pulls work without external registries. | Every custom service image |
| Kubeflow core | Shared Kubeflow components (central dashboard, profiles, RBAC) that the pipelines, tuning, training, and notebooks build on. | Kubeflow Pipelines, Katib, Trainer, Notebooks |

## Layer 2: Storage

Databases, object storage, the vector store, and the open lakehouse. This is
where raw data, features, metadata, artifacts, and the cold archive live.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| ClickHouse | Columnar warehouse. Holds the bronze, silver, and gold medallion tables and serves as the Feast offline store. | analyzer, batch, trainer, drift, dashboard backend, dbt, Trino |
| Altinity ClickHouse Operator | Manages the ClickHouse StatefulSet and its keeper. | ClickHouse |
| PostgreSQL (CloudNativePG) | Metadata database and the change data capture source. | MLflow, Airflow, DataHub, Superset, LakeFS |
| CloudNativePG | Operator that runs PostgreSQL with backups and failover. | PostgreSQL |
| MySQL | Metadata database for the Kubeflow control plane. | Kubeflow Pipelines, Katib |
| Valkey | In memory key value store, a Redis fork. The online feature store and cache. | feature cache, Flink job, materialization, Feast online |
| MinIO | S3 compatible object storage. Backs MLflow artifacts, the data lake, Iceberg files, and the Loki and Tempo stores. | MLflow, LakeFS, Iceberg, Loki, Tempo, inference |
| Qdrant | Vector database. Stores news and sentiment embeddings for similarity search. | vector service |
| lakeFS | Git like version control over the MinIO data lake, with branch, commit, and merge on data. | lakehouse workflow |
| Lakekeeper | Rust Iceberg REST catalog. The table catalog for the open lakehouse. | Spark archive, Trino |
| Apache Iceberg | Open table format. The cold, engine neutral archive written by Spark and read by Trino. | Spark archive, Trino |
| SpiceDB | Fine grained authorization based on the Google Zanzibar model. Backs APISIX authorization. | APISIX |

## Layer 3: Data ingestion

The streaming backbone plus schema enforcement and the tools to inspect it.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| Apache Kafka (KRaft) | Event streaming backbone. Every collector and processor publishes or consumes here. | rest collector, websocket collector, validator, batch, Flink job, drift |
| Strimzi | Kafka operator. Manages the cluster, topics, users, and the kafka-exporter. | Kafka |
| Kafka Connect and Debezium | Change data capture from PostgreSQL and sink connectors. | CDC pipelines |
| Karapace | Confluent compatible schema registry. Collectors and validators enforce message schemas. | validator, rest collector, Kafka Connect |
| Kafbat UI | Web UI to inspect Kafka topics, consumer groups, and lag. | operators, debugging |

## Layer 4: Data processing

Batch and stream engines, orchestration, validation, SQL transformation, query
federation, and business dashboards.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| Apache Flink | Stream processing. The speed layer computing real time features from Kafka into Valkey. | Flink job |
| Apache Spark | Batch processing. Archives raw trades from ClickHouse into Iceberg on a schedule. | lakehouse archive |
| Apache Airflow | Workflow orchestration. Runs the scheduled DAGs for features, the quality gate, the lakehouse, materialization, and retraining. | materialization, retraining, scheduled gold |
| Great Expectations | Data validation framework. Asserts expectations on the training data before it is used. | analyzer, quality gate |
| dbt | SQL transformation on ClickHouse. Builds the silver and gold marts inside the warehouse. | gold table build |
| Apache Superset | Business intelligence dashboards over ClickHouse and Trino. | analysts |
| Trino | Federated SQL engine. Joins ClickHouse gold tables against the Iceberg archive in a single query. | Superset, cross store queries |

## Layer 5: Model lifecycle

Experiment tracking, the feature store, pipeline orchestration, distributed
training, tuning, and interactive development.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| MLflow | Experiment tracking and model registry. The trainer logs runs and registers models here. | trainer, dashboard backend, ml bridge |
| Feast | Feature store. Serves online features from Valkey and offline features from ClickHouse. | batch, feature cache, materialization, ml bridge |
| Kubeflow Pipelines | ML pipeline orchestration. Runs the retraining pipeline of train, evaluate, and deploy. | trainer, retraining |
| Kubeflow Trainer | Distributed training operator. Available as a capability. On a single node it runs one worker. | training jobs |
| Katib | Hyperparameter tuning and AutoML. Available as a capability. The production path uses FLAML inside the trainer. | tuning experiments |
| Kubeflow Notebooks | Interactive Jupyter development for exploration. | data science work |

## Layer 6: Model serving

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| KServe | Model serving. Runs the predictor as an InferenceService in RawDeployment mode using the v2 protocol. | ml bridge, dashboard |

## Layer 7: Data governance

Metadata catalog, lineage, and the search index behind them.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| DataHub | Metadata catalog and lineage graph. Ingests from ClickHouse, dbt, Airflow, and MLflow. | governance, discovery |
| OpenSearch | Search index behind DataHub. | DataHub |
| OpenLineage | Lineage event standard. Airflow and Spark emit lineage events that land in DataHub. | DataHub lineage |

## Observability

Metrics, logs, traces, profiling, cost, drift, and autoscaling signals. Metrics
and logs and traces share MinIO as their store where possible.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| Prometheus (kube-prometheus-stack) | Metrics collection and alerting rules. Scrapes services, exporters, and the Pushgateway. Ships node-exporter and kube-state-metrics. | drift, dashboards, alerts |
| Grafana | Dashboards and visualization over Prometheus, Loki, and Tempo. | operators, monitoring |
| Loki | Log aggregation, backed by MinIO. | log search |
| Tempo | Distributed tracing, OpenTelemetry native, backed by MinIO. | trace search |
| OpenTelemetry Operator and Collector | Telemetry pipeline that collects traces and metrics from the services. | Tempo, service tracing |
| Pushgateway | Relay for short lived batch job metrics. CronJobs and Airflow DAGs push job success, duration, and exit code here. | trainer, batch, CronJobs |
| Pyroscope | Continuous profiling of the heavy Python services. | performance analysis |
| Sloth | Generates Prometheus SLO recording and alerting rules from SLO specifications. | SLO alerts |
| OpenCost | Kubernetes cost monitoring, allocating spend per namespace and workload. | cost reporting |
| Evidently | ML monitoring and data drift reporting. | drift analysis |
| Vertical Pod Autoscaler | Recommends and right sizes pod resource requests. | resource tuning |

## Security

Secrets, the API gateway, admission policy, runtime detection, scanning, backup,
and chaos testing. Authorization and encryption keys are also here.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| OpenBao | Secret management, a Vault API compatible fork. The source of truth for secrets. | External Secrets, platform wide |
| External Secrets Operator | Syncs secrets from OpenBao into Kubernetes Secrets. | every service reading secrets |
| APISIX | API gateway. TLS termination, routing, and authentication for external access. | gateway, external clients |
| KES | MinIO Key Encryption Server. Holds the server side encryption keys for MinIO. | MinIO encryption |
| Kyverno | Policy engine. Admission policies for resource limits, pod security, and image rules. | Platform wide |
| Falco | Runtime security. Detects suspicious syscalls and container behavior. | threat detection |
| Trivy Operator | Continuous vulnerability and misconfiguration scanning of images and workloads. | security posture |
| Velero | Backup and restore of cluster resources and persistent volumes. | disaster recovery |
| Chaos Mesh | Chaos engineering. Fault injection for resilience testing. | resilience tests |

## GitOps and CI/CD

The delivery loop. Source lives in Gitea, Argo CD reconciles it, Tekton builds,
Argo Rollouts and Argo Workflows handle progressive delivery and automation.

| Tool | Role in this project | Depended on by |
| --- | --- | --- |
| Argo CD | GitOps continuous delivery. The app of apps reconciles every component from Gitea. | Platform wide |
| Argo Rollouts | Progressive delivery. Canary and blue green for the serving path. | serving deployments |
| Argo Workflows | Workflow engine. Runs the retrain on drift CronWorkflow. | automated retraining |
| Gitea | Self hosted Git. The source of truth that Argo CD pulls from. | Argo CD |
| Tekton | CI pipeline engine. Builds and tests, for example the dbt project pipeline. | build pipelines |

## Use case: crypto

The platform above is domain agnostic. The crypto use case under
`use-case-crypto/` instantiates it for one domain without changing any platform
tool. It only adds domain specific code and configuration.

Data sources feeding the pipeline:

- Coinbase for OHLCV bars and trades, per second, starting 1 January 2026 up to
  real time. This is the primary tabular data.
- Supplementary sentiment and news, so the pipeline is not tabular only. Sources
  include CoinGecko, the Fear and Greed index, and CryptoPanic. Text is embedded
  and stored in Qdrant.

The crypto services are the project's own code, not open source tools. They
consume the tools above. The main ones:

- Collectors and validator in Rust, publishing to Kafka.
- A batch service in Python for feature engineering.
- A dashboard with a Go backend, a React frontend, and an ml bridge that reads
  predictions and online features.

Open source libraries used inside the crypto code:

- FLAML for automated model selection.
- LightGBM as the selected model.
- Evidently for drift reports.
- sentence-transformers for text embeddings.

## Notes on scope

- Every tool listed is enabled in `platform/config/components.yaml` and present
  under `platform/components/`.
- A few tools are installed as capabilities but are deliberately not on the
  production path on a single node: Knative Serving (KServe uses RawDeployment),
  Kubeflow Trainer and Katib (the trainer uses FLAML directly). They are kept so
  the architecture stays complete and can scale out on a multi node cluster.
- node-exporter and kube-state-metrics are not separate components. They ship
  inside the kube-prometheus-stack and provide node and object metrics.
