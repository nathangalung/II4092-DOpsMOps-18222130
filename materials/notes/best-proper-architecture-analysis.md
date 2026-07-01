# Best-Proper Architecture Analysis
## Integrated DataOps + MLOps Platform on Kubernetes with Open-Source Tools

*Research-grounded design analysis for the thesis "Pengembangan Arsitektur Platform Terintegrasi pada Kubernetes dengan Pemanfaatan Open Source Tools".*
*Date: 2026-06-29. Status: analysis / design-rationale — NOT a change order. No cluster changes or tool removals are implied as performed.*

---

## 0. Purpose and method

This document compares the **as-built** platform against the **best-proper** reference architecture for an integrated DataOps + MLOps platform on Kubernetes built from open-source tools, and states where the platform is already best-proper, where *genuine* redundancy exists, where capabilities are *deliberately offered but not yet activated* by the example use case, and where real gaps remain.

**Method.** Five parallel research agents drew from authoritative sources — project/vendor documentation via the context7 MCP (Apache Iceberg, Flink, Kafka/Strimzi, dbt, Trino, ClickHouse, lakeFS, Debezium, DataHub, Argo CD, Kyverno, OpenTelemetry, KServe, MLflow, Feast, KEDA, External Secrets, Istio, Polaris) and published reference architectures / comparison studies (CNCF Landscape + CNCF Platforms White Paper, OpenGitOps, Google "MLOps: Continuous delivery and automation pipelines", ml-ops.org, Databricks/Dremio/Onehouse lakehouse papers, Ververica Streamhouse) — plus a full read of the repository. The companion file `materials/notes/mlops-reference-architecture.md` holds the long-form MLOps reference report.

**Two caveats that govern how to use this document:**

1. **Analysis, not execution.** What to *act on* (keep / consolidate / fill) is a separate user decision. Nothing here has been removed from the cluster.
2. **`[verify]` = do not cite until checked.** Several findings rest on fast-moving specifics (version numbers, release dates, new features, license dates). Research synthesis can carry plausible-but-wrong specifics. Any `[verify]`-tagged claim must be confirmed against its primary source before it enters the thesis (Bab 2) as a citation.

---

## 1. The framing that makes the analysis correct: **capability vs activation**

The single most important lens. Agent-confirmed (CNCF Platforms White Paper), and matching the repository structure: this is a **domain-agnostic platform base** (`platform/components/*`) plus a **per-use-case overlay** (`use-case-crypto/`). The two layers have different jobs:

- **Platform layer — *offers* capabilities.** It is deliberately broad so it can serve diverse future use cases (crypto today; healthcare, e-commerce, IoT tomorrow). A platform tool is justified by the *class of use case* it enables, not by whether one example wires it.
- **Use-case layer — *activates* a subset.** The crypto overlay wires only what this domain needs.

**Consequence for "redundancy":**

| Situation | Verdict |
|---|---|
| Two tools doing the **same job** in the **same flow** | **Genuine redundancy** → candidate to consolidate |
| One platform tool **offered**, this use case **doesn't wire it** | **Under-activation** → deliberate capability, *not* redundancy |

Conflating "unexercised by the crypto use case" with "redundant" would wrongly read as "the platform is over-built." For a thesis titled *Arsitektur Platform Terintegrasi*, the correct and stronger story is: **the platform provides capability X; this use case activates the appropriate subset; here is the rationale.** §3 keeps the two lists strictly separate.

---

## 2. Best-proper reference architecture (the target)

The headline result up front: **the platform's tool selections match the best-proper reference architecture in the large majority of capabilities.** The matrix below merges the three reference-architecture agents (DataOps, MLOps, Foundation). "As-built" marks what the platform already runs.

### 2.1 Foundation / platform-engineering layer — *validated as best-proper*

| Capability | Best-proper OSS | As-built | Aligned? |
|---|---|---|---|
| GitOps / CD | Argo CD + app-of-apps (+ ApplicationSet for multi-env) | Argo CD + app-of-apps | ✅ |
| Packaging | Helm (upstream charts) + Kustomize (overlays) — hybrid | Helm + Kustomize | ✅ |
| Policy-as-code | Kyverno (YAML/CEL, PSS `podSecurity` subrule) | Kyverno | ✅ |
| Secrets | External Secrets Operator + OpenBao backend | ESO + OpenBao | ✅ |
| Service mesh | Istio (ambient mode) — warranted for multi-ns mTLS | Istio | ✅ |
| Metrics / Logs / Traces / Profiles | Prometheus / Loki / Tempo / Pyroscope, via OTel Collector | same | ✅ |
| Autoscaling | KEDA (event) + HPA (CPU) + VPA (right-size) | KEDA + HPA + VPA | ✅ |
| Certs / Gateway / Registry | cert-manager / APISIX + Gateway API / Harbor-or-Zot | cert-manager / APISIX / in-cluster registry | ✅ |
| Platform↔use-case split | base + Kustomize overlays (CNCF "platform as a product") | exactly this pattern | ✅ |

**Finding:** the foundation layer needs no architectural change. It is the CNCF-canonical stack.

### 2.2 Data plane (DataOps)

| Capability | Best-proper OSS | As-built | Note |
|---|---|---|---|
| Streaming bus | Kafka (Strimzi, KRaft) | Kafka (Strimzi) | ✅ |
| API/market-data ingest | **Direct Kafka producer** (no DB intermediary) | rest-collector + websocket-collector (Rust/Go) → Kafka | ✅ correct pattern |
| CDC (OLTP→lake) | Debezium (Kafka Connect) | Debezium (offered; see §3.3) | capability, not crypto-wired |
| Stream processing | Flink (Kubernetes Operator) | Flink | ✅ |
| Batch processing | Spark — for large-scale; else compute-in-warehouse | Spark (offered) + first-party Python + dbt | see §3.3 |
| Object store | MinIO (S3) | MinIO | ✅ |
| Table format (lake) | **Apache Iceberg** | Iceberg (format) | ✅ keep the format |
| Lake versioning + catalog | lakeFS (git-over-object-store) **+ its built-in Iceberg REST catalog `[verify]`** | lakeFS + Lakekeeper (separate catalog) | see §3.2 |
| Warehouse / OLAP serving | ClickHouse (gold, sub-second) | ClickHouse | ✅ |
| Federated query | Trino — when cross-source JOINs are needed | Trino (wired to one quality check, see §3.4) | not idle |
| Transformation (ELT) | dbt Core | dbt | ✅ |
| Orchestration (data) | Airflow 3.x (KubernetesExecutor) | Airflow | ✅ |
| Data quality | Great Expectations / Soda + dbt tests | GE + first-party validator + dbt/Trino checks | ✅ |
| Catalog + lineage + governance | **DataHub** (Kafka-native) | DataHub + OpenSearch | ✅ |
| BI | Superset | Superset + first-party dashboard | ✅ |

**Medallion / lakehouse (best-proper):** Bronze (raw, append-only) and Silver (cleaned/conformed) live as **Iceberg tables on MinIO**; Gold (business/feature) lives both as Iceberg (multi-engine/ad-hoc) and materialized into **ClickHouse** (sub-second serving). Iceberg (lake) and ClickHouse (warehouse) are **different layers, not competitors** — the correct hot/cold split.

### 2.3 ML plane (MLOps — target maturity Level 2)

| Capability | Best-proper OSS | As-built | Note |
|---|---|---|---|
| Experiment tracking | MLflow Tracking | MLflow | ✅ |
| Model registry | MLflow Registry (`@champion`/`@challenger` aliases) | MLflow | ✅ (gate is a gap, §3.5) |
| Pipeline orchestration | Kubeflow Pipelines v2 | KFP v2 | ✅ |
| Feature store | Feast (offline + online, point-in-time) | Feast (CH offline, Valkey online) | ✅ (offline API bypassed, §3.5) |
| Online serving | **KServe** (Seldon disqualified by BSL license `[verify]`) | KServe + Knative | ✅ |
| Drift monitoring | Evidently (canonical) **+** custom logic where spec'd | first-party multi-scale PSI/KS **+** Evidently | ✅ complementary (§3.5) |
| Continuous training | scheduled KFP + inline drift condition (KEDA→Job wrapper for event-driven) | Argo CronWorkflow → KFP retrain | ✅ (close variant) |
| HPO | Katib (K8s-native Bayesian) and/or AutoML | Katib (baseline) + FLAML (per-run) | both legitimate |
| Distributed training | Kubeflow Trainer — for deep/large models | Kubeflow Trainer (offered) | §3.3 |
| CI / CD for ML | Tekton (CI) + Argo CD (CD) | Tekton + Argo CD | ✅ |
| ML metadata / lineage | KFP MLMD + DataHub | KFP MLMD + DataHub (OpenLineage) | ✅ |

**MLOps-L2 control loop (best-proper):** data (versioned) → Feast offline (point-in-time) → KFP pipeline with **data-validation gate** and **model-validation gate** → MLflow Tracking → MLflow Registry `@champion` alias (promotion gated) → KServe (canary) → Evidently/Prometheus monitoring → drift trigger → KFP retrain (loop). The platform implements most hops; the **promotion gate** is the main missing piece (§3.5).

### 2.4 Governance (cross-cutting)

- **One catalog is enough — DataHub.** It is Kafka-native (reuses Strimzi), giving real-time metadata + column-level lineage. OpenMetadata would duplicate every core function and would *still* need Kafka to consume lineage events. **Do not add OpenMetadata.**
- **OpenLineage is a protocol, not a product.** Tools emit OpenLineage events; DataHub consumes them. DataHub's *native* Airflow/Spark plugins are preferred over a generic OpenLineage proxy. The repository's deleted `openlineage/deployment.yaml` is therefore a **correct removal**, not a gap.

---

## 3. As-built vs best-proper — the assessment (dual lens)

### 3.1 What is already best-proper (the large majority)

Foundation: all of §2.1. Data: Kafka, direct producers, Flink, MinIO, Iceberg-format, lakeFS, ClickHouse, dbt, Airflow, GE, DataHub, Superset. ML: MLflow (tracking+registry), KFP, Feast, KServe, Tekton+Argo, MLMD. **The platform is a faithful instantiation of the best-proper integrated DataOps+MLOps reference architecture.** The items below are refinements, not a rebuild.

### 3.2 Genuine redundancies (same job, two tools) — the real, short target list

| # | Redundancy | Disposition | Confidence |
|---|---|---|---|
| R1 | **inference-engine (first-party C++)** ↔ **KServe** | Dead code — already excluded from overlays; the source tree still carries it. Remove the codebase. | High (no external claim) |
| R2 | **Lakekeeper (standalone Iceberg REST catalog)** ↔ **lakeFS built-in Iceberg REST catalog `[verify]`** | *If* lakeFS ships a spec-compliant Iceberg REST catalog (`/iceberg/api`), a separate Lakekeeper is exact duplication — point engines at lakeFS. | **Conditional — verify the lakeFS-catalog claim before acting or citing.** This is load-bearing. |

That is the entire genuine-redundancy list. Everything else commonly mistaken for redundancy is addressed below as either *under-activation* (§3.3) or a *write-path quality* point (§3.4).

### 3.3 Offered-but-not-activated platform capabilities (deliberate — NOT redundancy)

These are platform capabilities the **crypto** use case correctly does not wire. They remain the right tools for the *class* of use case they target. For an "integrated platform" thesis this is a design **strength** (capability demonstrated; activation matched to need), not waste.

| Capability | Why crypto doesn't activate it | When it *is* the right tool |
|---|---|---|
| **Debezium CDC** | CDC taps a database transaction log (Postgres WAL / MySQL binlog). The Coinbase source is a WebSocket/REST API with no log to tap. Routing API→Postgres→CDC-out would be a two-hop anti-pattern. | Any future use case with an **operational OLTP database** to mirror into the lake (orders, positions, accounts) with before/after + delete semantics. |
| **Spark** | Crypto's gold path is small/tabular — first-party Python + dbt + ClickHouse suffice. | Large-scale distributed batch transforms / historical backfills. |
| **Kubeflow Trainer** | Crypto trains a small tabular model (FLAML) that runs as a plain Job. | Distributed deep-learning training (PyTorchJob/TFJob), multi-GPU. |
| **Katib** | FLAML's in-trainer AutoML already does per-run model selection; a baseline Katib Experiment is provided. | Periodic, K8s-native Bayesian HPO as a first-class search (legitimate alongside FLAML — different roles). |

**Framing for Bab 2:** "The platform base provides ingestion-via-CDC, distributed batch (Spark), distributed training (Kubeflow Trainer), and K8s-native HPO (Katib) as **capabilities**; the crypto use case activates the subset appropriate to per-second market data and a small tabular model. This is deliberate platform/use-case separation, not over-provisioning."

### 3.4 Lakehouse write-path refinement (architecture-quality, independent of activation)

This is the substance behind the earlier "Iceberg/kafka-connect" question, stated precisely:

- **If** an Iceberg lake is to be populated, the best-proper writer is **Flink** (exactly-once via checkpointing, stateful transforms, seconds-latency, reuses the already-deployed Flink cluster). The **Kafka Connect Iceberg sink** is the inferior path here (stateless, ~5-minute commit interval `[verify]`, needs a separate Connect cluster). Flink `DynamicIcebergSink` `[verify: Flink 1.20+ / Iceberg 1.10, release date]` closes the sink's one advantage (multi-table fan-out).
- **CDC (Debezium) is not the lake-ingest path for API-sourced data** (§3.3).
- **Streaming Iceberg requires a compaction job** (~tens of thousands of small Parquet files/day `[verify the file-count figure]`); Flink's `TableMaintenance` `[verify]` can embed it.
- **Trino is *not* idle.** It backs the lakehouse federated `trino_quality_check` (`use-case-crypto/dags/lakehouse.py`, task #511). Its federation (JOIN across MinIO-Iceberg + ClickHouse + relational in one query) is its non-overlapping value. It *could* be rewired to ClickHouse if no federation is required, but that is a scope decision, not a redundancy.

**Clean target lake-write path (best-proper):**
`Kafka producer → Flink (window/normalize/OHLCV) → Bronze Iceberg on MinIO [via lakeFS catalog] → Spark/dbt → Silver/Gold → ClickHouse → Feast/KServe & MLflow/KFP`. The platform's `Kafka-Connect + Debezium + Iceberg-sink` variant is, for this use case, both not-needed (API data) and write-path-suboptimal (Flink writes Iceberg better) — so it is the natural thing for the crypto overlay to leave unwired, and the natural place to prefer Flink if/when the lake is populated.

### 3.5 Gaps vs best-proper MLOps Level 2 (real — worth filling)

| Gap | Best-proper expectation | Fill |
|---|---|---|
| **Champion-challenger promotion gate** | A new model is gated by accuracy/drift before promotion (MLflow `@champion`/`@challenger` aliases + KServe canary). | Add an evaluation step that compares challenger vs champion on a holdout and only promotes (alias swap / canary) on improvement. Current promotes immediately post-train. |
| **Model explainability** | SHAP/feature-attribution for governance + debugging. | Add SHAP to the trainer/serving path; surface per-prediction attributions. |
| **Data contracts** | Schema-compatibility tests across producer/consumer and the CH/PG/dbt boundary (beyond Kafka schemas in Karapace). | Add GE data contracts / dbt contracts at layer boundaries. |
| **Feast offline API usage** | Training reads features through Feast's **point-in-time-correct** offline retrieval. | Route training feature reads through Feast offline (today it queries `gold.fct_training_data` directly). |

**NOT a gap — keep both:** the **first-party multi-scale PSI/KS drift service** implements the *spec'd requirement* "drift check with comparable timelines (month-to-month, day-to-day)", which Evidently does not provide out of the box. First-party = the **gating metric** wired to the retrain trigger; Evidently = the **reporting/visual** layer. Complementary by design.

---

## 4. Headline decisions (dual-lens, with verify-flags)

| Item | Best-proper view | Recommendation | Flag |
|---|---|---|---|
| Foundation stack | CNCF-canonical | **Keep as-is** | — |
| Iceberg (table format) | Correct lake layer, distinct from ClickHouse warehouse | **Keep** | — |
| lakeFS | Repository versioning + (likely) Iceberg catalog | **Keep**; use its Iceberg catalog | lakeFS-catalog `[verify]` |
| Lakekeeper | Duplicates lakeFS catalog *if* the above holds | **Consolidate** into lakeFS (conditional) | `[verify]` |
| Kafka Connect Iceberg sink | Flink is the better Iceberg writer | **Prefer Flink** for any lake write; leave the sink unwired for crypto | sink-commit-interval `[verify]` |
| Debezium CDC | For OLTP→lake; N/A to API data | **Keep as offered capability**; not wired by crypto | — |
| Trino | Federation; backs one quality check | **Keep** (it is wired); rewire to ClickHouse only if federation drops out of scope | — |
| Spark / Kubeflow-Trainer | Big-data / big-model capabilities | **Keep as offered capabilities**; document the activation rationale | — |
| Katib | K8s-native HPO | **Keep** alongside FLAML (different roles) | — |
| inference-engine (C++) | Superseded by KServe | **Remove** dead source | — |
| DataHub | Sufficient single catalog | **Keep**; do **not** add OpenMetadata | — |
| OpenLineage standalone | A protocol, not a product | Already correctly removed | — |
| first-party drift + Evidently | Complementary (gate vs report) | **Keep both** | — |
| Champion-challenger / SHAP / data-contracts / Feast-offline | MLOps-L2 expectations | **Fill** (4 gaps) | — |

---

## 5. Implications for the thesis (Bab 2) — *pending citation verification*

1. **Headline the platform can defend:** its tool selection is a faithful, reference-architecture-grounded instantiation of the best-proper integrated DataOps+MLOps stack on Kubernetes — across foundation, data plane, ML plane, and governance. (§2.1–§2.4)
2. **The strongest narrative is capability-vs-activation** (platform offers; use case wires the appropriate subset) — it directly substantiates the word *Terintegrasi* in the title and reframes "unexercised" tools as deliberate design. (§1, §3.3)
3. **Acknowledge the genuine redundancies honestly:** inference-engine (dead) and Lakekeeper-vs-lakeFS-catalog (conditional). (§3.2)
4. **Claims that MUST be verified against the primary source before citing** (research-synthesis may be wrong on specifics):
   - lakeFS ships a built-in spec-compliant **Iceberg REST catalog** — *load-bearing for the Lakekeeper verdict.*
   - ClickHouse Iceberg DML roadmap (versions 25.7 / 25.8 / 25.9).
   - Flink `DynamicIcebergSink` feature + release date ("Nov 2025").
   - Kafka Connect Iceberg sink default commit interval (5 min) + streaming small-file counts.
   - Seldon Core BSL-1.1 license change (date / cost).
   - Evidently-vs-Alibi-Detect latency figures; Tekton Hub shutdown date.
5. **Decide the deliverable's purpose** (open question for the user): is this a **pure design-rationale artifact** (an ADR/architecture chapter input) or **direct input to Bab 2 edits**? The latter requires completing the `[verify]` checks first.

---

## 6. Sources

Consolidated from the five research agents; full per-claim source lists are in each agent's report and in `materials/notes/mlops-reference-architecture.md`. Primary families: context7 project docs (Iceberg, Flink, Strimzi, dbt, Trino, ClickHouse, lakeFS, Debezium, DataHub, Polaris, Argo CD, Kyverno, OpenTelemetry, KServe, MLflow, Feast, KEDA, External Secrets, Istio); CNCF Landscape + Platforms White Paper; OpenGitOps; Google MLOps maturity model + ml-ops.org; Databricks/Dremio/Onehouse/Ververica lakehouse papers; lakeFS / Debezium / Apache Flink engineering blogs; comparison studies (Atlan, OvalEdge, Onehouse, rmoff.net, BigData Boutique). **All recency-sensitive specifics are `[verify]`-flagged above.**
