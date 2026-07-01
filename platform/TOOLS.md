# Open Source Tool Catalog

This document lists every open source tool used in the platform, what each one
does here, which parts of the pipeline depend on it, and whether it is actually
running. The platform is domain agnostic. The crypto use case at the end shows
how the same tools are wired for one concrete domain.

The tools are grouped by the layer they belong to, following the seven layer
DataOps and MLOps architecture: infrastructure, ingestion, processing, feature
storage, model lifecycle, model serving, and governance with observability.
Security and GitOps run across all layers.

The source of truth for enabled components is `platform/config/components.yaml`.
Every entry below matches a real directory under `platform/components/` or a
chart it installs. The Status column was verified against the live cluster on
1 July 2026 (see the verification note at the end).

## How to read this

Each table has four columns:

- Tool: the open source project.
- Role in this project: what it actually does here, not a generic description.
- Depended on by: the services or tools that need it. "Platform wide" means
  many components rely on it.
- Status: live state at verification time. "Running" means pods verified
  Running. "At zero replicas" means deployed but scaled down at the snapshot.
  "Capability" means installed and healthy but deliberately not on the
  production path on this single node.

## Layer 1: Infrastructure and common

The base everything runs on: the cluster, mesh, identity, autoscaling, job
admission, and the local image registry.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| Kubernetes (k3s) | Single node cluster hosting every workload. Ships the local-path-provisioner that backs all PersistentVolumes. | Platform wide | Running |
| containerd | Container runtime under k3s. | Platform wide | Running |
| Helm and Kustomize | Render and overlay the component manifests. Argo CD uses them to produce the applied YAML. | Argo CD, every component | In use |
| cert-manager | Issues and rotates TLS certificates for Istio and APISIX. | Istio, APISIX | Running |
| Istio | Service mesh. Mutual TLS between services, traffic routing, ingress gateway. | Meshed services, gateway | Running |
| Dex | OIDC identity provider. Single sign on for the web UIs; the Grafana OIDC client is wired in source. | Grafana, other UIs | Running |
| oauth2-proxy | Auth proxy in front of UIs that cannot speak OIDC themselves. | UI access | Running |
| KEDA | Event driven autoscaler. Kafka lag scalers for the validator and analyzer, an rps scaler for the gateway, cron schedules for the Superset and DataHub frontends. | Kafka consumers, UI scaling | Running |
| Kueue | Kubernetes native job queue. Admits batch and training jobs by queue labels. | Spark batch, training jobs | Running |
| metrics-server | Pod and node resource metrics for the Horizontal Pod Autoscalers. | HPAs platform wide | Running |
| Knative Serving | Serverless runtime installed as a capability. KServe runs in RawDeployment mode, so Knative is not on the serving path here. | None on the serving path | Running, capability |
| Docker Registry | In cluster registry at localhost:5000 holding the locally built service images. | Every custom service image | Running |
| Kubeflow core | Shared plumbing for the Kubeflow components: gateway, RBAC roles, and network policies. Not the central dashboard. | Kubeflow Pipelines, Katib, Trainer, Notebooks | Applied |

## Layer 2: Storage

Databases, object storage, the vector store, and the open lakehouse. Raw data,
features, metadata, artifacts, and the cold archive live here.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| ClickHouse | Columnar warehouse. Holds the bronze, silver, and gold medallion tables and serves as the Feast offline store. | analyzer, batch, trainer, drift, dashboard backend, dbt, Trino | Running |
| Altinity ClickHouse Operator | Manages the ClickHouse installation and its keeper. | ClickHouse | Running |
| PostgreSQL (CloudNativePG) | Metadata database and the change data capture source. | MLflow, Airflow, DataHub, Superset, LakeFS | Running |
| CloudNativePG | Operator running PostgreSQL, with the barman-cloud plugin for backups. | PostgreSQL | Running |
| MySQL | Metadata database for the Kubeflow control plane. | Kubeflow Pipelines, Katib | Running |
| Valkey | In memory key value store, a Redis fork. The online feature store and cache. | Flink job, materialization, Feast online | Running |
| MinIO | S3 compatible object storage. Backs MLflow artifacts, the data lake, Iceberg files, and the Loki and Tempo stores. | MLflow, LakeFS, Iceberg, Loki, Tempo | Running |
| Qdrant | Vector database. Stores news and sentiment embeddings for similarity search. | vector embedding job | Running |
| lakeFS | Git like version control over the MinIO data lake. The lakehouse DAG branches, commits, and merges data changes. | lakehouse workflow | Running |
| Lakekeeper | Rust Iceberg REST catalog for the open lakehouse. The warehouse bootstrap job is staged in source, pending the next GitOps push. | Spark archive, Trino | Running |
| Apache Iceberg | Open table format. The cold, engine neutral archive written by Spark and read by Trino. | Spark archive, Trino | Format, staged |
| SpiceDB | Fine grained authorization based on the Google Zanzibar model. | APISIX | Running |

## Layer 3: Data ingestion

The streaming backbone plus schema enforcement and inspection.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| Apache Kafka (KRaft) | Event streaming backbone. Every collector and processor publishes or consumes here. | collectors, validator, Flink, ClickHouse Kafka engine | Running |
| Strimzi | Kafka operator. Manages the broker, topics, users, and the kafka-exporter. | Kafka | Running |
| kafka-exporter (Strimzi) | Exposes consumer group lag as Prometheus metrics. | lag monitoring, KEDA | Running |
| Kafka Connect and Debezium | Change data capture capability. Deployed, but no connectors are registered at the moment and the runtime pod has an image pull failure. The Iceberg sink it once carried was superseded by the Spark archive job. | none currently | Deployed, failing image pull |
| Karapace | Confluent compatible schema registry. Collectors and the validator enforce message schemas. | validator, collectors | Running |
| Kafbat UI | Web UI to inspect Kafka topics, consumer groups, and lag. | operators, debugging | Running |

## Layer 4: Data processing

Batch and stream engines, orchestration, validation, SQL transformation, query
federation, and business dashboards.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| Apache Flink | Stream processing. The speed layer computing real time features from Kafka into Valkey. | online features | Running |
| Flink Kubernetes Operator | Manages the FlinkDeployment resources (session cluster and the stream processor). | Flink | Running |
| Apache Spark | Batch engine for the lakehouse archive: raw trades from ClickHouse into Iceberg on a six hour schedule. The ScheduledSparkApplication is staged in source, not yet applied to the cluster. | lakehouse archive | Operator running, job staged |
| Spark Operator | Runs SparkApplication resources natively on Kubernetes. | Spark jobs | Running |
| Apache Airflow | Workflow orchestration. Runs the scheduled DAGs: data pipeline, hourly features, quality gate, and the lakehouse build. Executes dbt and Feast materialization as pod tasks. | scheduled gold path, materialization | Running |
| Great Expectations | Data validation. Runs inside the quality gate DAG and a scheduled checkpoint CronJob against the training data. Latest checkpoint runs failed and need a look. | quality gate | Scheduled, recent runs failed |
| dbt | SQL transformation on ClickHouse. Builds the silver and gold marts, invoked by the lakehouse DAG under a lakeFS branch and merge. | gold table build | In use via Airflow |
| Apache Superset | Business intelligence dashboards over ClickHouse and Trino. | analysts | Deployed, stuck initializing at snapshot |
| Trino | Federated SQL engine. Joins ClickHouse gold tables against the Iceberg archive in one query. | Superset, cross store queries | Running |

## Layer 5: Model lifecycle

Experiment tracking, the feature store, pipelines, training, tuning, and
interactive development.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| MLflow | Experiment tracking and model registry. The trainer logs runs and registers the model KServe serves. | trainer, ml bridge, dashboard backend | Running |
| Feast | Feature store. Online features from Valkey, offline from ClickHouse. Materialization runs as an Airflow task. | ml bridge, materialization | Running |
| Kubeflow Pipelines | ML pipeline orchestration. Holds the retraining pipeline of train, evaluate, and deploy steps. | retraining | Running |
| Kubeflow Trainer and JobSet | Distributed training operators. Installed capability; on one node the trainer runs as a single worker Job. | training jobs | Running, capability |
| Katib | Hyperparameter tuning and AutoML capability. The production path selects models with FLAML inside the trainer instead. | tuning experiments | Running, capability |
| Kubeflow Notebooks | Jupyter notebook controller and web app for interactive work. | data science work | Running |

## Layer 6: Model serving

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| KServe | Model serving in RawDeployment mode with the v2 inference protocol. Two InferenceServices exist and report Ready: a platform health check and the crypto predictor. The predictor deployment was at zero replicas at the snapshot. | ml bridge, dashboard | Running controller, predictor scaled down |
| Argo Rollouts | Progressive delivery. The ml bridge ships as a Rollout, giving canary style rollouts on the serving path. | ml bridge | Running |

## Layer 7: Data governance

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| DataHub | Metadata catalog and lineage graph. Ingest CronJobs pull from ClickHouse, dbt, Feast, Kafka, MinIO, MLflow, and PostgreSQL. Verified populated: about 255 ClickHouse datasets, 21 Airflow entities, 16 dbt models. | governance, discovery | Running (frontend pod was Pending at snapshot) |
| OpenSearch | Search index behind DataHub. | DataHub | Running |
| OpenLineage | Lineage event standard. Airflow DAGs emit run events to the DataHub endpoint; the staged Spark job carries the same listener. | DataHub lineage | In use |

## Observability

Metrics, logs, traces, profiles, cost, drift, SLOs, and autoscaling signals.

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| Prometheus (kube-prometheus-stack) | Metrics collection and alert rules. Scrapes ServiceMonitors and PodMonitors cluster wide. Ships node-exporter and kube-state-metrics. | dashboards, alerts, KEDA | Running |
| Alertmanager | Routes and groups the alerts Prometheus fires. | alerting | Running |
| Grafana | Dashboards over Prometheus, Loki, and Tempo. Three platform dashboards (DataOps, MLOps, storage) are provisioned from ConfigMaps. | operators | Running |
| Pushgateway | Relay for short lived batch job metrics. CronJobs and Airflow DAGs push job success, duration, and exit code here. The Prometheus scrape config for it is staged in source, pending the next GitOps push. | batch job monitoring | Running |
| Loki | Log aggregation backed by MinIO. | log search | Crash looping at snapshot |
| Grafana Alloy | Collector agent. Ships container logs to Loki and profiles to Pyroscope. | Loki, Pyroscope | Running |
| Tempo | Distributed tracing backend, OpenTelemetry native, backed by MinIO. | trace search | Running |
| OpenTelemetry Operator and Collectors | Telemetry pipeline. An agent collector and a gateway collector route traces from services to Tempo. | Tempo, service tracing | Running |
| Pyroscope | Continuous profiling backend, fed by Alloy. | performance analysis | Running |
| Sloth | Generates Prometheus SLO recording and alert rules from SLO specs. | SLO alerts | Running |
| OpenCost | Kubernetes cost allocation per namespace and workload. | cost reporting | Running |
| Evidently | ML monitoring workspace service. The drift reporter posts drift snapshots to it. | drift analysis | Running |
| Vertical Pod Autoscaler | Resource right sizing in recommendation mode: the recommender runs, no updater is installed, so it suggests rather than mutates. | resource tuning | Running, recommender only |

## Security

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| OpenBao | Secret management, a Vault API compatible fork. Source of truth for secrets, with an auto unsealer sidecar deployment. | External Secrets, platform wide | Running |
| External Secrets Operator | Syncs secrets from OpenBao into Kubernetes Secrets. | every service reading secrets | Running |
| APISIX | API gateway. TLS termination, routing, and authentication for external access. | external clients | Running |
| KES | MinIO Key Encryption Server. Server side encryption keys for MinIO. | MinIO encryption | Running |
| Kyverno | Policy engine. Admission policies for resource limits, pod security, and image rules. | Platform wide | Running |
| Falco and Falcosidekick | Runtime security. Detects suspicious syscalls; sidekick forwards events. | threat detection | Running |
| Trivy Operator | Vulnerability and misconfiguration scanning. Scaled to zero at the snapshot. | security posture | At zero replicas |
| Velero | Backup and restore of cluster resources and volumes, with node agents. | disaster recovery | Running |
| Chaos Mesh | Chaos engineering. Fault injection experiments used by the chaos evaluation scenarios. | resilience tests | Running |

## GitOps and CI/CD

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| Argo CD | GitOps delivery. The app of apps reconciles every component from Gitea. | Platform wide | Running |
| Gitea | Self hosted Git. The source of truth Argo CD pulls from; the working tree is pushed here by the seed script. | Argo CD | Running |
| Tekton | CI pipeline engine with dashboard and triggers. The use case ships a Tekton pipeline that builds the dbt project image. | build pipelines | Running |
| Argo Workflows | Workflow engine running the retrain on drift CronWorkflow. Its controller was at zero replicas at the snapshot, which stalls new retrain runs until scaled back. | automated retraining | At zero replicas |
| Argo Rollouts | Listed under model serving; also generally available for progressive delivery. | serving deployments | Running |

## Use case: crypto

The platform above is domain agnostic. The crypto use case under
`use-case-crypto/` instantiates it for one domain without changing any platform
tool. It adds domain code and configuration only.

Data sources feeding the pipeline:

- Coinbase for OHLCV bars and trades, from 1 January 2026 up to real time. This
  is the primary tabular data (verified in ClickHouse: about 744 thousand
  minute bars and 1.76 million trades at the last check).
- Supplementary sentiment and news, so the pipeline is not tabular only:
  CoinGecko, DefiLlama, the Fear and Greed index, and news text that is
  embedded and stored in Qdrant (about 63 thousand sentiment rows).

The crypto services are project code, not open source tools. They consume the
tools above:

- Rust websocket collector publishing trades to Kafka (running); the REST and
  supplementary collection runs as scheduled CronJobs.
- A Rust validator and gateway, deployed with KEDA scalers and scaled to zero
  while idle.
- A Python batch service for feature engineering, run by Airflow.
- A dashboard with a Go backend, a React frontend, and a Python ml bridge (an
  Argo Rollout) that reads predictions and online features.

Open source libraries inside the crypto code, verified in the dependency files:

- FLAML for automated model selection (flaml 2.3 in the trainer).
- LightGBM as the selected model family (lightgbm 4.5 in the trainer).
- Evidently for drift reports (drift reporter service).
- sentence-transformers for text embeddings, with the model baked into the
  vector job image.

## Known gaps at verification time

An honest list, so this document does not overclaim. State on 1 July 2026,
after an IO saturated period on the single disk node:

- kafka-connect pod in image pull failure; no connectors registered anyway.
- Loki crash looping; logs were flowing before the IO storm.
- Superset stuck initializing; DataHub frontend pod Pending (it served fine
  earlier the same day).
- Argo Workflows controller and Trivy operator at zero replicas.
- The Spark Iceberg archive and the Lakekeeper warehouse bootstrap are staged
  in source and validated, waiting on the next Gitea push and Argo sync.
- Latest runs of the lakehouse DAG, the Great Expectations checkpoint, and the
  retrain decide step failed and need investigation.

## Notes on scope

- Three tools are installed capabilities kept off the single node production
  path on purpose: Knative Serving (KServe uses RawDeployment), Kubeflow
  Trainer, and Katib (model selection happens in-trainer with FLAML). They keep
  the architecture complete for multi node scale out.
- node-exporter and kube-state-metrics are not separate components; they ship
  inside the kube-prometheus-stack.
- Storage is provisioned by the k3s built in local-path-provisioner; there is
  no separate CSI component.

## How this was verified

Status comes from a four command read only kubectl snapshot on 1 July 2026
(pods, deployments and statefulsets, cronjobs, and the Spark, KServe, Flink,
and KEDA custom resources across all namespaces), cross checked against the
manifests in this repository and `platform/config/components.yaml`. Row counts
and catalog numbers come from queries run against the live ClickHouse and
DataHub earlier the same day. Nothing in this document is inferred from tool
marketing descriptions.
