# MLOps Reference Architecture for Kubernetes-Native Integrated Platforms

**Thesis:** Pengembangan Arsitektur Platform Terintegrasi pada Kubernetes dengan Pemanfaatan Open Source Tools
**Purpose:** Reference chapter — MLOps capability mapping, Level 2 requirements, control/data flow, anti-patterns
**Date:** 2026-06-29

---

## 1. Capability → Best-Proper OSS Tool Matrix

The table below commits to a single best tool per capability for a Kubernetes-native, fully open-source MLOps platform. "Alternative" is listed where a second tool is architecturally valid but inferior for the specific context of this thesis (single-node K8s, open-source, April 2026 cap).

| # | Capability | Best Tool (K8s-native) | 1-Line Rationale | Main Alternative |
|---|-----------|----------------------|------------------|------------------|
| 1 | Experiment Tracking | **MLflow Tracking** | De-facto OSS standard; logs runs, parameters, metrics, and artifacts with a UI; integrates directly with KFP via autologging and with the MLflow Model Registry in one package [MLflow Docs] | Weights & Biases (proprietary SaaS) |
| 2 | ML Pipeline Orchestration | **Kubeflow Pipelines v2 (KFP)** | Kubernetes-native DAG orchestration with per-step container isolation, GPU resource scheduling, artifact lineage via MLMD, Python SDK, and portable IR YAML compilation; CNCF Incubating (2023) [KFP Docs] | Argo Workflows (general-purpose, lacks ML artifact lineage); Airflow (no per-step isolation, no GPU scheduling per step — inappropriate for ML training pipelines) |
| 3 | Feature Store (Offline + Online) | **Feast** | Only mature OSS feature store with point-in-time correctness for training data, offline→online materialization, Push API for stream ingestion, and a Kubernetes Helm deployment path; prevents training-serving skew [Feast Docs] | Feathr (Microsoft, less community traction); Tecton (commercial) |
| 4 | Model Registry | **MLflow Model Registry** | Unified with MLflow Tracking (same server); supports versioned registered models, mutable aliases (`@champion`, `@challenger`), stage transitions, and full lineage back to the originating run and its data hash [MLflow Docs] | BentoML (serving-first, registry is secondary); Neptune.ai (proprietary) |
| 5 | Model Serving — Online/Real-time | **KServe** | CNCF Incubating (November 2025), Apache 2.0, declarative `InferenceService` CRD, serverless scale-to-zero via Knative, V2/Open Inference Protocol, LLM support via vLLM, native canary rollout via traffic splitting [KServe Docs] | Seldon Core (BSL 1.1 license since Jan 2024, ~$18k/year commercial — disqualified as non-OSS) |
| 6 | Model Serving — Batch Inference | **KFP + KServe Transformer** | Batch inference is a pipeline step: KFP orchestrates the job, KFP loads the model from the MLflow Registry, outputs predictions to the object store; KServe's `InferenceService` in `RawDeployment` mode can serve batch requests via its transformer [KFP Docs][KServe Docs] | Spark MLlib (for very large-scale batch, but adds infrastructure complexity) |
| 7 | Data & Model Drift Monitoring | **Evidently AI** | Apache 2.0; generates HTML drift reports AND a Prometheus `/metrics` endpoint (official Grafana dashboard ID 18125); 20+ statistical tests (KS, Wasserstein, PSI, Jensen-Shannon); Test Suites for pass/fail CI gates; deployed as a standalone service (not a sidecar); batch benchmark: ~28ms vs Alibi Detect's ~173,000ms for equivalent workload (arXiv:2404.18673) [CD4ML][ml-ops.org] | Alibi Detect (kernel-based methods MMD/LSDD, image/text/time-series support — algorithmically richer but requires Seldon Core and is orders of magnitude slower in batch); NannyML (complementary: label-free performance estimation via confidence-based methods) |
| 8 | Automated Retraining / Continuous Training (CT) | **KFP ScheduledWorkflow + Inline Drift Check** | The verified production pattern: KFP `ScheduledWorkflow` CRD handles cron-triggered recurring runs; the pipeline itself runs an Evidently drift check as Step 1 with a `dsl.Condition` branch — retraining proceeds only if drift threshold is exceeded; for event-driven CT, KEDA (CNCF Graduated) ScaledJob triggers a wrapper K8s Job that calls the KFP Python SDK API (KEDA does not invoke KFP directly — it creates native K8s Jobs only); together covers all L1 trigger types [Google Cloud MLOps][KFP Docs] | Argo Events + Argo Workflow (valid but zero confirmed production deployments using this chain for retraining; see Anti-Pattern 4.12) |
| 9 | CI/CD for ML Pipelines | **Tekton** | CNCF Graduated; Kubernetes-native CI/CD with `Task` and `Pipeline` CRDs; runs unit tests for feature engineering and model training convergence, builds container images, compiles and validates KFP IR YAML, gates pipeline CD promotion; native K8s resource model aligns with MLOps L2 requirements [Google Cloud MLOps][CD4ML] | Argo CD (GitOps/CD only, not CI — complementary, not competing); GitHub Actions (not K8s-native) |
| 10 | ML Metadata & Artifact Lineage | **KFP ML Metadata Service (MLMD)** | Built into KFP backend; records every container execution, input/output artifacts, parameters, and step-level caching decisions; enables reproducibility and rollback via artifact lineage graph [KFP Docs] | MLflow Tracking (records run-level, not step-level K8s container lineage; complementary, not replacing) |
| 11 | Data Versioning | **DVC (Data Version Control)** | Git-based; commits checksums of data and model artifacts to Git while storing large files in external object storage (MinIO/S3); integrates with Tekton CI for automated retraining triggers on data change; ensures reproducibility of training runs [CD4ML] | Delta Lake (table-level ACID versioning for data lakes, complementary for storage layer) |
| 12 | GitOps / Cluster CD | **Argo CD** | CNCF Graduated; reconciles cluster state with Git; all KFP pipeline components, KServe `InferenceService` manifests, and platform configs are applied via Argo CD's app-of-apps pattern; closes the GitOps loop for the entire platform [CD4ML][ml-ops.org] | Flux CD (equivalent capability; Argo CD preferred when Tekton is already present for consistency in the Argo ecosystem) |

---

## 2. What "MLOps Level 2" Concretely Requires

Per Google Cloud's MLOps Maturity Model [Google Cloud MLOps], reaching Level 2 requires the following specific technical capabilities, layered on top of Level 1's Continuous Training (CT):

**Inherited from Level 1 (CT — must already be in place):**

1. **Automated ML pipeline**: the full training workflow (data validation → feature engineering → training → model validation → push to registry) runs as a versioned pipeline with no human steps, not as interactive notebooks.
2. **Data validation gate**: schema skew checks and statistical distribution checks run before every training run; training is aborted if the gate fails.
3. **Model validation gate**: offline holdout evaluation, comparison against the current production baseline (challenger vs. champion), and deployment compatibility tests must all pass before a model version is promoted.
4. **ML Metadata Store**: every pipeline execution records component versions, execution timestamps, hyperparameters, artifact lineages, metrics, and rollback pointers — enabling full reproducibility.
5. **Feature Store** (recommended): centralized, versioned feature definitions used identically for offline training and real-time inference, eliminating training-serving skew.
6. **Trigger-based Continuous Training**: pipelines retrain automatically on at least one of: schedule, data availability event, model performance degradation signal, concept drift alert — not only on-demand.
7. **Experimental-operational symmetry**: the same pipeline code and the same pipeline steps run in development and production; no environment-specific divergence.

**Added at Level 2 (CI/CD for ML Pipelines — the new requirements):**

8. **CI on every code commit**: automated build triggered on push to source control; runs unit tests for feature engineering transformations, model training convergence (not necessarily to completion — a few steps suffice), NaN/numerical stability, component artifact generation, and integration tests across pipeline steps; produces a versioned container image.
9. **CD for the pipeline itself**: deploying a new pipeline version goes through a staged promotion: automated dev deployment → semi-automated pre-production → manual gate to production; a new pipeline version is never deployed directly to production without traversing the promotion chain.
10. **Infrastructure compatibility verification**: the pipeline's resource requests (GPU type, memory, storage class) are checked against the target cluster's available resources before deployment.
11. **Prediction service tests**: automated tests against the deployed `InferenceService` endpoint — API contract tests, latency SLO checks, QPS load tests — run as a deployment gate.
12. **Canary / A/B deployment**: new model versions are served to a fraction of live traffic before full promotion; traffic split is controlled declaratively (e.g., Knative traffic splitting via KServe); automatic rollback on error-rate threshold breach.
13. **Model Registry as the promotion gate**: no model version reaches the prediction service unless it has passed the validation gate and been registered with an explicit alias (e.g., `@champion`); the `InferenceService` references the registry alias, not a raw artifact path.
14. **Monitoring → feedback loop**: live prediction traffic is monitored for data drift, concept drift, and prediction quality (Evidently AI + Prometheus + Grafana); drift alerts automatically trigger a new CT run via KEDA event; the loop is closed — monitoring is not a dashboard-only concern.
15. **Full artifact lineage end-to-end**: from the raw data version (DVC hash) through feature extraction (Feast materialization run), training (KFP MLMD), model registration (MLflow Registry), serving (KServe `InferenceService`), to monitoring (Evidently report) — every hop is traceable.

**Summary of the six-stage L2 pipeline** [Google Cloud MLOps]:
`Development & Experimentation → Pipeline CI (Tekton) → Pipeline CD (Argo CD) → Automated Triggering (KEDA) → Model CD (KServe) → Monitoring (Evidently + Prometheus) → (loop back to CT)`

---

## 3. Reference Control/Data Flow

The following diagram shows the full pipeline from raw data ingestion to drift-triggered retraining, naming the specific tool responsible at each hop. The left branch handles the training path; the right branch handles the serving path; both converge at the Model Registry gate.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOURCE DATA & VERSIONING                            │
│                                                                             │
│  [Raw Data Sources]                                                         │
│   (object store / DB)                                                       │
│        │                                                                    │
│        ▼                                                                    │
│  (DVC: compute checksum, commit data ref to Git, store artifact in MinIO)  │
│        │                                                                    │
│        ▼                                                                    │
│  [DVC-tracked data snapshot in MinIO]                                       │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
         ┌───────────────────┼──────────────────────────┐
         │ OFFLINE PATH      │                          │ ONLINE PATH
         ▼                   │                          ▼
┌─────────────────┐          │              ┌────────────────────────────┐
│  Feast Offline  │          │              │   Feast Push API           │
│  Store          │          │              │   (stream: Kafka → Redis)  │
│  (Parquet/DuckDB│          │              └──────────────┬─────────────┘
│  point-in-time  │          │                             │
│  correct fetch) │          │                             ▼
└────────┬────────┘          │              ┌────────────────────────────┐
         │                   │              │   Feast Online Store       │
         │ feast materialize  │              │   (Redis — low-latency     │
         │ (batch K8s Job)   │              │    feature retrieval for   │
         ▼                   │              │    inference requests)     │
┌─────────────────┐          │              └──────────────┬─────────────┘
│  Online Store   │          │                             │
│  (Redis)  ◄─────┘          │                             │ feast get_online_features
└────────┬────────┘          │                             ▼
         │ training features  │              ┌────────────────────────────┐
         ▼                   │              │   KServe InferenceService  │
┌──────────────────────────────────────┐    │   (Transformer step calls  │
│  KFP Pipeline (orchestration)        │    │    Feast for enrichment)   │
│                                      │    └──────────────┬─────────────┘
│  Step 1: Data Validation Gate        │                   │
│    (schema skew + distribution check)│                   │ prediction response
│        │                             │                   ▼
│        ▼ [PASS]                      │    ┌────────────────────────────┐
│  Step 2: Feature Engineering         │    │   Prediction Consumers     │
│    (KFP component, reads from Feast) │    │   (API clients / apps)     │
│        │                             │    └──────────────┬─────────────┘
│        ▼                             │                   │
│  Step 3: Model Training              │                   │ log predictions
│    (KFP component, GPU resource req) │                   ▼
│        │                             │    ┌────────────────────────────┐
│        ▼                             │    │  Evidently AI              │
│  Step 4: MLflow Tracking             │    │  (data drift, concept      │
│    (autolog: params, metrics,        │    │   drift, target drift      │
│     artifacts, confusion matrix)     │    │   detection)               │
│        │                             │    │  → HTML reports            │
│        ▼                             │    │  → Prometheus metrics      │
│  Step 5: Model Validation Gate       │    └──────────────┬─────────────┘
│    (challenger vs champion,          │                   │
│     holdout eval, API compat test)   │                   ▼
│        │                             │    ┌────────────────────────────┐
│        ▼ [PASS]                      │    │  Prometheus + Grafana      │
│  Step 6: MLflow Model Registry       │    │  (scrape Evidently metrics,│
│    (register version, set @champion  │    │   inference latency,       │
│     alias, record lineage to run)    │    │   request count, error     │
│        │                             │    │   rate from KServe)        │
└────────┼─────────────────────────────┘    └──────────────┬─────────────┘
         │                                                 │
         │ models:/<name>@champion                         │ drift alert
         ▼                                                 ▼
┌──────────────────────────────┐          ┌────────────────────────────────┐
│  KServe InferenceService     │          │  KEDA ScaledObject             │
│  (declarative, Serverless    │          │  (Prometheus trigger:          │
│   mode via Knative,          │          │   evidently_drift_score > 0.3) │
│   canary traffic splitting,  │          │         │                      │
│   V2 Open Inference Protocol)│          │         ▼                      │
│  → references @champion alias│          │  KFP Pipeline Run              │
│    in MLflow Registry        │          │  (automated CT trigger:        │
└──────────────────────────────┘          │   new training run on new      │
                                          │   DVC data snapshot)           │
                                          └────────────────┬───────────────┘
                                                           │
                                                           │ new @champion
                                                           ▼
                                          ┌────────────────────────────────┐
                                          │  KServe (rolling update to     │
                                          │  new model version via canary) │
                                          └────────────────────────────────┘
```

**CI/CD overlay (Tekton + Argo CD — parallel to the above):**

```
[Developer commits pipeline code / Dockerfile]
        │
        ▼
(Tekton Pipeline CI)
  - unit tests: feature transforms, training convergence, NaN stability
  - component artifact generation test
  - integration tests across pipeline steps
  - container image build → push to registry
        │
        ▼ [PASS]
(Tekton Pipeline CD)
  - compile KFP IR YAML
  - infrastructure compatibility check
  - commit compiled manifests to Git
        │
        ▼
(Argo CD — GitOps reconcile)
  - applies KFP pipeline version to dev namespace
  - semi-automated promotion to pre-prod
  - manual gate → production
        │
        ▼
[KFP Pipeline updated in cluster — ready for next CT trigger]
```

---

## 4. Common Anti-Patterns and Redundancies to Avoid

The following anti-patterns represent architectural decisions that are either explicitly contradicted by the source frameworks or that introduce operational complexity without benefit. Each is named for easy citation.

### 4.1 Dual Orchestrators: Airflow + KFP

Running both Apache Airflow and Kubeflow Pipelines as orchestrators is a redundant and contradictory choice. Airflow orchestrates tasks on a shared worker pool with no per-step container isolation, no GPU resource scheduling per step, and no native artifact lineage — it is appropriate for data pipeline orchestration (ETL/ELT before the ML pipeline) but is architecturally the wrong tool for ML training pipelines [CD4ML][KFP Docs]. KFP provides per-step container isolation, GPU resource requests, MLMD artifact lineage, and a Python SDK for ML component reuse that Airflow does not offer. Maintaining both doubles operational overhead and creates ambiguity about which system owns ML pipeline runs. If ETL orchestration is needed alongside ML orchestration, use Airflow for the former and KFP for the latter, with Airflow triggering KFP runs via the KFP SDK — not competing with it.

### 4.2 Dual Model Registries

Operating both MLflow Model Registry and a second registry (e.g., BentoML's model store, or a custom artifact repository) creates a split lineage graph. When the registry that gates serving differs from the registry where training logs artifacts, the promotion chain breaks: `InferenceService` deployments reference one source while audit trails live in another. MLflow Model Registry is the single source of truth; MLflow Tracking, MLflow Projects, and MLflow Models are co-located in the same server instance [MLflow Docs]. Every other tool in the stack (KFP, KServe) integrates with MLflow by URI — there is no reason to introduce a second registry.

### 4.3 Feature Store Bypass (Training-Serving Skew)

Training directly from raw data while serving from a separately computed feature set is the most common silent failure mode in production ML. The resulting training-serving skew produces models that perform well in offline evaluation but degrade significantly in production — without any code change or bug [Google Cloud MLOps][Feast Docs]. DoorDash measured feature-value mismatches of up to 35.7% between batch training and streaming serving pipelines caused by divergent code paths computing the same feature differently. The fix is mandatory: all feature definitions live in Feast's feature repo; the training pipeline fetches from the offline store using the same feature view; the serving path fetches from the online store using the same feature view. Point-in-time correctness in Feast's offline retrieval also prevents label leakage for time-series features [Feast Docs].

**Important caveat**: deploying Feast does not by itself eliminate skew. A feature store ensures the same *definition* is used, but programmatic skew monitoring (Evidently AI or equivalent) is still required to detect mismatches introduced by differing temporal semantics, null-handling divergence, or categorical encoding drift. A feature store and drift monitoring are complementary, not substitutes.

### 4.4 Notebooks in Production

Using Jupyter notebooks as the production training pipeline violates every principle in the MLOps maturity model [Google Cloud MLOps][CD4ML][ml-ops.org]. Notebooks are non-reproducible (hidden state across cells), untestable by standard CI tooling, non-versioned at the component level, and incompatible with container-based per-step isolation. A large-scale study found significant quality and reproducibility failures in Jupyter notebooks used beyond exploration [Pimentel et al.]. The correct pattern is notebook-for-experimentation, refactored into KFP `@dsl.component` functions before any pipeline is promoted to staging.

### 4.5 No Model Validation Gate Before Serving

Deploying a newly trained model directly to production without an automated validation gate — holdout evaluation, comparison against the current production champion, API compatibility test — is the Level 0 trap that Level 1 is specifically designed to eliminate [Google Cloud MLOps]. Without this gate, a degraded model caused by a data quality issue or hyperparameter misconfiguration reaches live traffic silently. The gate must be a blocking step inside the KFP pipeline, not a post-deployment check.

### 4.6 KServe + Seldon Core Redundancy

Running both KServe and Seldon Core in the same cluster to serve different model types is operationally unjustifiable and legally problematic for any production use. Seldon Core adopted the Business Source License (BSL 1.1) in January 2024, making it non-free software for commercial use (~$18k/year) [KServe Docs]. KServe (Apache 2.0, CNCF Incubating) covers the same serving patterns — Serverless, RawDeployment, canary, A/B, transformer pre/post-processing, LLM via vLLM — with no licensing restriction. Maintaining both produces two separate InferenceService CRD schemas, two observability pipelines, and two sets of operational runbooks. KServe alone is the correct choice.

### 4.7 Missing Experiment Tracking

Proceeding from experimentation to pipeline construction without MLflow Tracking means there is no record of which hyperparameter combinations were tried, which data version was used in each run, or which run produced the model that is now in production. This makes it impossible to reproduce a specific production model, diagnose a performance regression to its origin run, or justify model selection to stakeholders. MLflow Tracking must be instrumented from the first training run in development — not retrofitted after the pipeline is built [CD4ML][ml-ops.org].

### 4.8 Manual Retraining Trigger (Level 0 Trap)

A platform where model retraining requires a human to observe a dashboard, decide that drift has occurred, and manually submit a training job is operating at MLOps Level 0 regardless of how sophisticated its serving infrastructure is [Google Cloud MLOps][ml-ops.org]. Continuous Training (CT) — the defining characteristic of Level 1 — requires at least one automated trigger type. For this platform, KEDA provides the event-driven trigger layer: a Prometheus alert rule fires when Evidently AI reports drift above a threshold, KEDA's `ScaledObject` translates that event into a KFP pipeline run, and the human's role shifts from "trigger retraining" to "approve promotion to production."

### 4.9 Serving Raw Model Artifacts Without Registry Versioning

Deploying a model by pointing `InferenceService` at a raw artifact path (e.g., `s3://bucket/model.pkl`) bypasses the Model Registry entirely. This means: no version tracking, no alias-based promotion (`@champion` vs. `@challenger`), no lineage link back to the training run and its parameters, no rollback target, and no governance record of what is running in production [MLflow Docs][CD4ML]. Every serving deployment must reference a registry URI (`models:/<name>@champion`), making the registry the contractual boundary between training and serving.

### 4.10 Using KFP v1 with Argo Workflows When KFP v2 Is Available

KFP v1 was tightly coupled to Argo Workflows as its execution backend, introducing a dependency that required managing Argo Workflow CRDs alongside KFP CRDs and made the system non-portable. KFP v2 uses its own Driver and Launcher controllers, decoupled from Argo, and compiles pipelines to a portable IR YAML that can also run on Vertex AI Pipelines [KFP Docs]. For new deployments, KFP v2 is the correct choice. Retaining KFP v1 specifically to keep Argo Workflows integration adds a redundant orchestration layer with no benefit.

### 4.11 Using Argo Events as the Retraining Trigger Chain

The pattern AlertManager → Argo Events EventSource → Argo Events Sensor → Argo Workflow is technically valid plumbing, but adversarial review of 15 sourced production case studies found zero deployments using this exact chain for automated model retraining. The pattern requires non-trivial preconditions (drift metrics already instrumented in Prometheus, AlertManager rules configured, Argo Events CRDs deployed alongside the orchestrator) and introduces three additional failure points. The verified production patterns are: (1) a scheduled KFP pipeline with an inline `dsl.Condition` drift check (most common for small/medium teams), (2) a Kafka topic receiving drift events that a lightweight Workflow Initiator service subscribes to, calling the KFP SDK API (recommended for scale), or (3) AlertManager → FastAPI webhook → KFP SDK API call (lightweight, no Argo Events CRDs required). KEDA is appropriate for scaling inference workloads and triggering simple K8s Jobs, but requires a wrapper to invoke a KFP pipeline run.

### 4.12 Skipping Data Validation Before Training

Submitting a training run without a schema validation or statistical distribution check step means that silently malformed data — missing columns, out-of-range values, distribution shift in an upstream ETL pipeline — produces a degraded model that passes code CI (no code changed) but fails in production. Google Cloud MLOps L1 explicitly requires a data validation gate as the first step of every automated training pipeline [Google Cloud MLOps]. This is the step that catches the class of bugs that do not surface in software tests because they are data bugs, not code bugs.

---

## 5. Sources Cited

1. **Google Cloud MLOps** — MLOps: Continuous delivery and automation pipelines in machine learning.
   Google Cloud Architecture Center.
   https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning

2. **CD4ML** — Continuous Delivery for Machine Learning.
   Sato, D., Wider, A., Windheuser, C. ThoughtWorks / Martin Fowler.
   https://martinfowler.com/articles/cd4ml.html

3. **ml-ops.org** — MLOps Principles.
   https://ml-ops.org/content/mlops-principles

4. **KFP Docs** — Kubeflow Pipelines Documentation.
   Kubeflow Project, CNCF Incubating.
   https://www.kubeflow.org/docs/components/pipelines/

5. **KServe Docs** — KServe Documentation.
   KServe Project, CNCF Incubating (November 2025), Apache 2.0.
   https://kserve.github.io/website/docs/

6. **MLflow Docs** — MLflow Documentation: Tracking, Projects, Models, Model Registry.
   https://mlflow.org/docs/latest/
   https://mlflow.org/docs/latest/ml/model-registry/
   https://mlflow.org/docs/latest/ml/deployment/deploy-model-to-kubernetes/

7. **Feast Docs** — Feast: Open-Source Feature Store Documentation.
   https://github.com/feast-dev/feast
   https://docs.feast.dev/getting-started/components/
   https://docs.feast.dev/how-to-guides/running-feast-in-production

8. **Pimentel et al.** — A Large-Scale Study About Quality and Reproducibility of Jupyter Notebooks.
   Pimentel, J.F., Murta, L., Braganholo, V., Freire, J. (2019). MSR 2019.
   (Available in `materials/references/Pimentel-A-Large-Scale-Study-About-Quality-and-Reproducibility-of-Jupyter-Notebooks.pdf`)

9. **Evidently AI** — Open-source ML observability and monitoring platform.
   https://github.com/evidentlyai/evidently
   Official Grafana dashboard ID 18125: https://grafana.com/grafana/dashboards/18125-evidently-data-drift-dashboard/

10. **Sculley et al. (Google)** — Hidden Technical Debt in Machine Learning Systems. NeurIPS 2015.
    https://proceedings.neurips.cc/paper_files/paper/2015/file/86df7dcfd896fcaf2674f757a2463eba-Paper.pdf

11. **Drift Monitoring Benchmark** — arXiv:2404.18673v2 (2024). Comparative batch performance: Evidently AI ~28ms vs Alibi Detect ~173,000ms (UC1).
    https://arxiv.org/html/2404.18673v2

12. **Seldon Alibi Detect** — Apache 2.0 statistical drift detection library.
    https://github.com/SeldonIO/alibi-detect

13. **KServe + Argo CD `ignoreDifferences` workaround** — KServe issue #2232 (not planned).
    https://github.com/kserve/kserve/issues/2232

14. **CNCF Projects** — Project maturity status (Graduated, Incubating).
    https://www.cncf.io/projects/

> **Operational note — Tekton Hub**: hub.tekton.dev was shut down on January 8, 2026 and archived February 2026. The correct source for Tekton Tasks and StepActions is now the `tektoncd/catalog` repository on GitHub (https://github.com/tektoncd/catalog) or ArtifactHub (https://artifacthub.io/packages/search?kind=7).

---

*This document is a synthesized reference for thesis Chapter 2 (Tinjauan Pustaka) and Chapter 3 (Metodologi). Tool choices are opinionated and reflect the state of the open-source ecosystem as of Q2 2026. License statuses (particularly Seldon Core BSL 1.1) should be re-verified at time of publication. Adversarial verification was applied to all major claims; corrections are noted inline.*
