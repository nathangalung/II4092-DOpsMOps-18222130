# Open Source Tool Catalog

This document lists every open source tool used in the platform, what each one
does here, which parts of the pipeline depend on it, and whether it is actually
running. The platform is domain agnostic. An example use case at the end shows
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
| Knative Serving | Serverless runtime, installed and healthy but with no contribution to the running pipeline: KServe serves in RawDeployment mode, so no request ever passes through Knative. Kept only as a scale out option. | Nothing | Running, no contribution |
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
| Kafka Connect and Debezium | Change data capture capability. Currently contributes nothing: no connectors are registered and the runtime pod has an image pull failure. The Iceberg sink it once carried was superseded by the Spark archive job. | Nothing currently | Deployed, no contribution |
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
| Kubeflow Trainer and JobSet | Distributed training operators. No contribution to the production path: the trainer runs as a plain Kubernetes Job with FLAML inside, not through these operators. Kept for multi node scale out. | Nothing on the production path | Running, no contribution |
| Katib | Hyperparameter tuning and AutoML operator. No contribution to the production path: model selection happens with FLAML inside the trainer, and no Katib experiment runs in the pipeline. | Nothing on the production path | Running, no contribution |
| Kubeflow Notebooks | Jupyter notebook controller and web app. Used for one SDK walkthrough notebook during development; no contribution to the running pipeline. | development only | Running, no pipeline contribution |

## Layer 6: Model serving

| Tool | Role in this project | Depended on by | Status |
| --- | --- | --- | --- |
| KServe | Model serving in RawDeployment mode with the v2 inference protocol. Two InferenceServices exist and report Ready: a platform health check and the example use-case predictor. The predictor deployment was at zero replicas at the snapshot. | ml bridge, dashboard | Running controller, predictor scaled down |
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

## Why each tool was chosen

Every category below was compared in the thesis (Bab 3) with a zero to two
score on maturity, performance, footprint, community, and license. This
section summarizes the deciding reasons in plain words: the main strength of
the winner and the concrete reason each alternative lost. License facts are
as of April 2026. Two constraints shaped almost every decision: the whole
platform runs on one node with limited disk IO, and every tool must be truly
open source under a neutral license, not source available.

### Data and ML layer

Offline store: ClickHouse, over Druid, Pinot, and Kudu. ClickHouse is a
single binary with top query performance, native Kafka ingestion, and a dbt
adapter. Druid and Pinot score similarly on speed but each needs four or more
coordinator, broker, and server components plus ZooKeeper, which is too much
machinery for one node. Kudu depends on an external SQL engine like Impala and
has the weakest community of the four.

Online store: Valkey, over Redis, Cassandra, and DragonflyDB. Redis dropped
its permissive BSD license in March 2024 for SSPL and RSAL, and only added the
copyleft AGPLv3 back in 2025; Valkey is the BSD-3 fork under the Linux
Foundation, permissively licensed and vendor neutral from the start, and stays
protocol compatible so the Feast online store and every Redis client work
unchanged. Cassandra is a JVM cluster database, heavy for simple key value
lookups. DragonflyDB sits under the Business Source License, which fails the
open source requirement.

Feature store: Feast, over Hopsworks, Featureform, and Feathr. Feast is a
light library plus registry with pluggable stores, which lets ClickHouse serve
offline and Valkey serve online without new infrastructure. Hopsworks is a
full platform with its own stack, far too heavy here. Feathr has stayed at LF
AI sandbox stage with a small adoption footprint, and Featureform has a much
smaller community.

Vector index: Qdrant, over Milvus, pgvector, and Weaviate. Qdrant is one Rust
binary with low memory use, payload filtering, and a simple API, measured here
at single digit millisecond latency. Milvus needs etcd plus object storage and
more components. pgvector would couple vector search load to the PostgreSQL
metadata database. Weaviate is a heavier server with a module system this
project does not need.

Experiment tracking and registry: MLflow, over TensorBoard, Neptune, and DVC.
MLflow combines tracking, a model registry, and artifact storage, and KServe
can serve straight from its registry. TensorBoard only visualizes; it has no
registry. Neptune is a proprietary hosted service. DVC versions data and
models in git but offers no serving integrated registry.

ML orchestration: Kubeflow Pipelines, over Airflow, Argo Workflows, and
Prefect. Kubeflow Pipelines is ML specific: pipeline components carry
artifacts, metadata, and caching, which generic DAG engines lack. Airflow is
still used in this platform, but for data pipelines; the comparison here is
about the ML training path. Argo Workflows has no ML metadata layer (it runs
the drift trigger instead), and Prefect's control plane is oriented toward its
hosted cloud.

Model serving: KServe, over Seldon Core, BentoML, and TorchServe. KServe is a
Kubernetes native InferenceService CRD with the open v2 inference protocol,
multi framework runtimes, and canary support, and it runs in RawDeployment
mode on a single node. Seldon Core moved to the Business Source License in
January 2024, with production use requiring a paid subscription. BentoML is a
packaging framework that needs its own serving platform around it. TorchServe
serves PyTorch only, is no longer maintained, and its repository was archived
in 2025.

Catalog and governance: DataHub, over Apache Atlas, OpenMetadata, and
Amundsen. DataHub has ingestion connectors for exactly this stack (ClickHouse,
dbt, Airflow, MLflow, Feast, Kafka, MinIO, PostgreSQL) and an OpenLineage
endpoint, so lineage arrives from the orchestrators without custom glue. Atlas
carries Hadoop era dependencies like HBase and Solr. Amundsen development has
largely stalled. OpenMetadata is the closest competitor but scored lower on
lineage maturity and connector fit for this exact toolset.

BI and dashboards: Superset, over Metabase, Redash, and Lightdash. Superset
is an Apache project with first class ClickHouse and Trino drivers and a REST
API that lets dashboards be bootstrapped as code, which the use case does.
Metabase splits features between AGPL core and a paid edition. Redash went
dormant for years after its acquisition and only recently restarted as a
community led project, so its pace and ecosystem trail Superset. Lightdash
only models dbt projects, a narrower scope than the platform needs.

Monitoring: Prometheus and Grafana together, over Jaeger, ELK, and InfluxDB.
Prometheus is the Kubernetes native pull model with operator CRDs
(ServiceMonitor, PodMonitor) and alert rules; Grafana visualizes it plus Loki
and Tempo in one place. Jaeger only does tracing, and this platform covers
that need with Tempo. The ELK stack is JVM heavy for a single node, and its
2021 license change fractured the ecosystem into the OpenSearch fork;
Elasticsearch only returned to an OSI approved license, AGPLv3, in late 2024.
InfluxDB is a time series database without Kubernetes native service
discovery and with disruptive version churn.

### Platform layer

Kubernetes distribution: k3s, over k0s, MicroK8s, and kind. k3s is a CNCF
certified single binary with a built in datastore, storage provisioner, and
helm controller, which fits one VPS with the smallest footprint. k0s is
similar but with a smaller ecosystem. MicroK8s is tied to snap packaging and
Canonical tooling. kind exists for CI and testing, not production.

Service mesh: Istio, over Linkerd, Cilium, and Consul Connect. Istio gives
the fine grained policy this platform leans on, mutual TLS with per workload
PeerAuthentication modes and AuthorizationPolicy, and it is the mesh KServe
and Knative integrate with first. Linkerd is simpler but its stable release
artifacts moved behind a vendor in 2024. Cilium mesh couples to eBPF and
kernel versions, risky on a generic VPS. Consul is under the Business Source
License.

GitOps: Argo CD, over Flux CD, Rancher Fleet, and Jenkins X. Argo CD's app of
apps and ApplicationSet patterns drive this whole platform from Gitea, and its
UI makes reconciliation visible, which matters for operating and for the
defense demo. Flux is solid but ships no UI. Fleet is Rancher centric. Jenkins
X is CI first and effectively dormant.

Identity provider: dex, over Keycloak, Authelia, and Authentik. dex is a
small stateless OIDC federator, a good fit when the need is single sign on in
front of UIs rather than a full identity suite. Keycloak is a JVM identity
platform with its own database, hundreds of megabytes for a need this small.
Authelia and Authentik focus on portal style authentication and bring larger
runtimes.

Secret management: OpenBao, over Vault, Sealed Secrets, and SOPS. Vault moved
to the Business Source License in 2023; OpenBao is the Linux Foundation fork
under MPL-2.0 and keeps the Vault API, so External Secrets Operator works
unchanged. Sealed Secrets only encrypts manifests in git, with no dynamic
secrets or rotation. SOPS is a file encryption tool, not a secret service.

Policy engine: Kyverno, over OPA Gatekeeper, Kubewarden, and jsPolicy.
Kyverno policies are plain Kubernetes YAML and cover validation, mutation, and
generation in one engine. Gatekeeper requires learning Rego and is validation
centric. Kubewarden's WebAssembly policy toolchain is more moving parts than
the need justifies. jsPolicy is a small vendor driven niche.

Message broker: Kafka, over Redpanda, Pulsar, and NATS JetStream. The
deciding factor is ecosystem gravity: Strimzi operates it, ClickHouse ingests
from it natively, and Flink, Spark, and Debezium all treat it as their first
class source. KRaft mode removed the ZooKeeper dependency. Redpanda is under
the Business Source License. Pulsar needs brokers plus BookKeeper, a
multi tier system too heavy here. NATS JetStream is light but has a much
thinner analytics connector ecosystem.

Schema registry: Karapace, over Apicurio, Confluent, and Cloudera. Karapace
is Apache-2.0 and speaks the Confluent Schema Registry API, so standard
clients and Kafka Connect converters work unchanged. Confluent's own registry
is under the Confluent Community License, source available but not open
source. Apicurio is open but a heavier JVM service with a broader API this
project does not need. Cloudera's registry ties to a commercial platform.

Processing frameworks: Spark and Flink together, over Kafka Streams and Beam.
This is a deliberate two engine split: Flink owns the streaming speed layer
into the online store, Spark owns scheduled batch work like the Iceberg
archive. Kafka Streams is a JVM library embedded in your own application, with
no cluster management or operator. Beam is an abstraction that still needs a
runner underneath, adding a layer without removing an engine.

Lakehouse format: Iceberg, over Delta Lake, Hudi, and Parquet. Iceberg is
governed neutrally at Apache, defines the REST catalog standard that
Lakekeeper implements, and is readable by Spark, Trino, and ClickHouse alike.
Delta Lake's direction is steered by one vendor, and for years parts of its
feature set lived only in that vendor's runtime, a criticism its competitors
documented publicly. Hudi is the most operationally demanding of the three
table formats because correct operation depends on tuning its table services
for compaction, clustering, and cleaning. Parquet is only a file format;
without a table layer it has no schema evolution, snapshots, or ACID commits.

Object storage: MinIO, over Ceph RGW, SeaweedFS, and Garage. MinIO is a
single binary with faithful S3 semantics, a console, and server side
encryption through KES, which is the right size for one node. Its AGPL
license is the one copyleft exception in the stack, accepted because it runs
as an unmodified service. Ceph is a full distributed storage system, far
oversized here. SeaweedFS covers only part of the S3 API. Garage is young
with a small ecosystem.

## Example use case

The platform above is domain agnostic. A complete worked example that
instantiates it end to end, without changing any platform tool, lives in
`use-case-crypto/`. It adds domain code and configuration only. The data
sources, the project services that consume these tools, and the model
libraries are documented there in `use-case-crypto/README.md` and
`use-case-crypto/docs/RUNBOOK.md`.

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

## Tools installed without a current contribution

Stated plainly so the catalog does not inflate the tool count. These are
installed and mostly healthy, but nothing in the running pipeline depends on
them today:

- Knative Serving: no request passes through it, KServe serves in
  RawDeployment mode. Kept as the serverless option for multi node scale out.
- Kubeflow Trainer and JobSet: the trainer runs as a plain Job with FLAML
  inside. Kept for distributed training on more nodes.
- Katib: no experiment on the production path, FLAML covers model selection.
  Kept as the AutoML option at scale.
- Kubeflow Notebooks: one development walkthrough notebook, nothing at
  runtime.
- Kafka Connect and Debezium: no connectors registered, pod failing image
  pull. Candidate for removal or repair; its former Iceberg sink duty moved to
  the Spark archive job.
- Trivy Operator: scaled to zero at the snapshot, so scanning is paused.

Everything else in the catalog has a live, verified consumer.

## Notes on scope

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
