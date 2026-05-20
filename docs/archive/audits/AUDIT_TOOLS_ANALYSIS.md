# Per-Tool Deep Analysis — ADD / REMOVE / KEEP

**Companion to** `AUDIT_REPORT.md` (2026-04-20)
**Goal**: justify every tool decision against (a) actual cluster state, (b) documented use case for the thesis, (c) whether a working replacement already exists.

> **Important semantic note**: "remove clickhouse-0" ≠ "remove ClickHouse". "remove kafka-0" ≠ "remove Kafka". The legacy pods are hand-rolled StatefulSets that duplicate what the new operator-managed clusters (CHI, Strimzi) are supposed to run. ClickHouse and Kafka themselves STAY — they are the core offline store + event backbone, and `components.yaml` lists them as required.

---

## PART A — Deep dive per tool (ordered by criticality)

### 1. ClickHouse — **KEEP the software, FINISH the migration (legacy → CHI)**

- **Role in project**: offline feature/metrics store; hosts medallion `bronze.*`, `silver.*`, `gold.*`, `features.*` databases. Source of truth for 631 K sentiment rows, 74 K OHLCV, 1,814 training rows.
- **Current cluster state**:
  - `storage/clickhouse-0` (StatefulSet `clickhouse`, 13d old) — **legacy hand-rolled, serving live traffic**
  - `clickhouse-system/clickhouse-operator-altinity` — Altinity operator running (46h)
  - `ClickHouseInstallation/platform` CR **applied** with full spec (1 shard, 1 replica, zookeeper nodes, podTemplate, PVC 20Gi, resources 500m–4 CPU / 2–8 Gi) but NOT reconciling data (operator-managed pod not yet the one holding rows)
- **Replacement**: none needed — Altinity CHI *is* ClickHouse, just operator-managed. Gives you rolling updates, backups, ZooKeeper/ClickHouse-Keeper, replication, and a declarative `ClickHouseInstallation` CR.
- **Thesis angle**: CHI = K8s-native operator pattern, matches the thesis architecture diagram ("operator-managed data stores"). Hand-rolled StatefulSets don't.
- **Verdict**: **KEEP ClickHouse · MIGRATE data · DELETE legacy StatefulSet** once row-count parity confirmed via `clickhouse-backup` restore into the CHI-managed pod.

### 2. Kafka — **KEEP the software, COMPLETE the Strimzi cutover**

- **Role**: event backbone. Topics `crypto.rest.raw`, `crypto.ws.raw`, `crypto.validated`, `crypto.features.v1`, `crypto.predictions.v1`, `crypto.supplementary` + DataHub's `MetadataChangeEvent`, `MetadataAuditEvent`.
- **Current cluster state**:
  - legacy `data-ingestion/kafka-0` (StatefulSet `kafka`, 13d) — DataHub still talking to it
  - Strimzi `data-ingestion/platform-kafka-broker-0` (KRaft mode, 46h) — crypto pipeline topics live here
  - Split-brain ⇒ every new service must pick a broker; config divergence likely.
- **Replacement**: none. Strimzi *is* Kafka managed by an operator. Adds declarative `Kafka`, `KafkaTopic`, `KafkaUser`, `KafkaConnect`, `KafkaMirrorMaker2` CRDs.
- **Thesis angle**: KRaft (no ZooKeeper) = state-of-2026 Kafka. Operator-managed topics = auditable via Git.
- **Verdict**: **KEEP Kafka · FINISH MirrorMaker2 migration per `MIGRATION.md` §3 · DELETE legacy StatefulSet** after DataHub is re-pointed.

### 3. Jaeger vs Tempo — **KEEP Jaeger (do NOT add Tempo)** — *revising earlier recommendation*

- **Current cluster state**:
  - `observability/jaeger-549c95c6fc-hq2w6` Running 7d16h with OTLP ports 4317/4318 + UI 16686
  - OpenTelemetry Operator 2/2 Running (2d9h) → auto-instrumenting services to send OTLP
  - **No Tempo pod/service exists** — I had mis-characterised this earlier
- **Comparison on THIS project's needs**:
  | Criterion | Jaeger | Tempo |
  |---|---|---|
  | OTLP native | ✅ | ✅ |
  | UI for trace browsing | ✅ (16686) | ❌ (must use Grafana Explore) |
  | Storage backend | Badger/ES/Cassandra | **object storage (MinIO)** ✅ cheap |
  | Grafana integration | via datasource | **native, first-class** |
  | Already deployed | ✅ | ❌ |
  | CNCF maturity | Graduated | Incubating |
  | Migration cost | 0 | moderate (reconfigure OTel collector, Grafana ds) |
- **Verdict**: **KEEP Jaeger**. Revisit only if storage cost becomes a pain (Tempo on MinIO is cheaper at > 1 TB traces). Remove "Jaeger → Tempo" from the migration list.
- **Components.yaml impact**: mark Tempo as `enabled: false` if it's listed; Jaeger stays `enabled: true`.

### 4. metacontroller — **KEEP** — *revising earlier recommendation*

- **Evidence that it IS used**:
  ```
  $ kubectl get decoratorcontroller -A
  NAME                                  AGE
  kubeflow-pipelines-profile-controller 13d
  ```
  Kubeflow Pipelines Multi-User profile controller is implemented as a metacontroller DecoratorController. Removing metacontroller = breaking Kubeflow Pipelines profiles.
- **Why I thought it was dead**: `Deployment/metacontroller` showed 0/0 — but the actual StatefulSet `metacontroller-0` may be the running instance; the 0/0 deployment is a stale helm leftover.
- **Action**: verify `kubectl get sts -n metacontroller` shows the operator Running; delete the redundant Deployment/metacontroller (0/0) but keep the CRDs + running StatefulSet.
- **Verdict**: **KEEP metacontroller software · DELETE the 0/0 Deployment artifact** (cosmetic cleanup).

### 5. kuberay / Ray — **DECIDE: use in ≤ 2 weeks or REMOVE**

- **Current cluster state**: `kuberay-operator` Running but **restarted 75 times** in 6d2h (≈12 restarts/day → crashlooping on a schedule). `ray-head` Service exists; **no RayCluster / RayJob / RayService CR exists.**
- **Documented use case** (per `components.yaml` line 215–218): "Ray distributed ML operator".
- **Real usage**: zero. FLAML AutoML + Kubeflow Trainer cover current workload. Dataset (1,814 training rows) does **not** justify distributed training.
- **Thesis angle**: mentioning Ray in the architecture and not using it weakens the paper ("why is this here?"). Either demonstrate a RayTune hyperparameter sweep (good thesis evidence) or remove.
- **Verdict**: **REMOVE kuberay unless you ship a RayTune run for the defense**. 75 restarts = active resource drain for zero value. If removed, update `components.yaml` line 215 → `enabled: false` and remove `ADR-005` ambiguity.

### 6. label-studio — **REMOVE**

- **Components.yaml** line 219: `enabled: true`, description "Data annotation and labeling tool"
- **ADR-005**: explicitly listed as **removed**
- **Cluster state**: **no pod named label-studio runs** — it's a config-only orphan
- **Use case in crypto project**: zero. The thesis deals with *unsupervised* financial time-series + sentiment scoring; no human labels required.
- **Verdict**: **REMOVE from components.yaml** (flip `enabled: false` OR delete the block). Reconciles config with ADR-005.

### 7. neo4j — **CONFIRMED REMOVED, clean up references**

- **Components.yaml** line 246: `enabled: false` ✅
- **Cluster state**: no pod — confirmed absent
- **Replacement**: DataHub GMS switched to Elasticsearch graph impl (see description field)
- **Verdict**: **already done** — just grep-and-remove any dangling `neo4j` env vars in manifests/docs.

### 8. KEDA — **ADD**

- **Current cluster state**: `kubectl get scaledobjects` → `resource type not found`. CRDs not installed.
- **Use case in project**:
  - `rest-collector`, `websocket-collector`, `validator`, `feature-engine` are **I/O-bound**; CPU HPA is wrong signal
  - Correct signal = **Kafka consumer lag** on `crypto.*` topics
  - KEDA's `kafka` scaler reads lag via `ScaledObject` → scales deployment 0..N
- **Thesis angle**: 12-Factor IX "disposability" + demonstrates event-driven scaling, which DORA identifies as elite-performer pattern
- **Alternative**: Prometheus Adapter + custom HPA metric — possible but 3× the YAML and fragile
- **Verdict**: **ADD KEDA** (CNCF Graduated, ~80 MB footprint, reversible). Ship 1 `ScaledObject` for `validator` as evidence chapter.

### 9. Flagger — **ADD**

- **Current state**: not installed.
- **Use case**: `use-case-crypto/manifests/base/inferenceservices/crypto-inference.yaml` defines a canary on KServe. Canary traffic % is **static** (hand-set in YAML). With Flagger:
  - Promote canary automatically when error rate < threshold + latency < SLO
  - Rollback automatically on regression — **directly lifts DORA MTTR + CFR**
- **Alternative**: Argo Rollouts. Comparable; Flagger has tighter Istio+KServe integration (matches our stack), Rollouts has richer UI. Either works — I recommend Flagger for fit.
- **Verdict**: **ADD Flagger** (one Helm chart, ~50 MB). Chapter 4 "Progressive Delivery" becomes defensible.

### 10. Harbor (or zot) — **ADD**

- **Current state**: no private registry; every pull hits `docker.io`; already caused CronJob failures (`rancher/mirrored-pause:3.6` timeout → P0-7).
- **Use case**:
  1. Cluster-local image mirror (fixes P0-7)
  2. Cosign signing + policy at admission (fixes OWASP A03 Supply Chain — direct thesis security requirement)
  3. Trivy scan results on push (OWASP A06)
  4. SBOM generation (thesis chapter on security compliance)
- **Which to pick**:
  - **Harbor**: full-featured, replication, RBAC, projects; ~700 MB footprint. Right choice for "production-grade" thesis framing.
  - **zot**: single binary, OCI-compliant, minimal; ~80 MB. Right for "lab mode" single-node k3s.
- **Verdict**: **ADD zot for this single-node k3s**; mention "Harbor for multi-node production variant" in the thesis Future Work section.

### 11. Spegel — **ADD (only if multi-node planned)**

- **Current state**: not installed.
- **What it does**: peer-to-peer image mirror across nodes — a node that has pulled an image serves it to peers, eliminating upstream pull on second node.
- **Use case on single-node k3s**: **near-zero** — no peers to share with.
- **Verdict**: **DEFER**. Worth adding only when you move to 3-node k3s HA (ADR-013's "production variant"). Document in Future Work.

### 12. Backstage — **ADD (high value for thesis)**

- **Current state**: no portal; 144 services across 15 namespaces → tribal knowledge.
- **Use case**:
  - Software Catalog `catalog-info.yaml` in every repo → single pane showing ownership, runbooks, dashboards, and ArgoCD sync state per service.
  - TechDocs (MkDocs rendered from each repo) → acts as a live, queryable appendix for the thesis.
  - Plugins: ArgoCD, Kubernetes, Prometheus, Grafana, Kafka — visually glues the whole stack together.
- **Verdict**: **ADD Backstage** · spin up with the `backstage/backstage` Helm chart · ship a short demo video in the defense. CNCF Incubating, strong open-source story for the paper.

### 13. fourkeys / DORA exporter — **ADD**

- **Current state**: no DORA metrics dashboard.
- **Use case**: thesis rubric asks for DORA numbers (deploy frequency, lead time, CFR, MTTR). Without `dora-team/fourkeys` (Google's open-source exporter) or Cloud Native Foundation alternatives (e.g. `DevLake`), you'd have to compute manually and defend the methodology.
- **Alternative**: Apache **DevLake** (richer, more setup) — consider for production
- **Verdict**: **ADD fourkeys for thesis-scope minimum viable proof**. One Grafana dashboard → one thesis figure.

### 14. Policy Reporter for Kyverno — **ADD (tiny)**

- **Current state**: Kyverno CRDs installed, **0 policies applied** (P0-8). No Policy Reporter.
- **Use case**: when policies land, Policy Reporter gives a Grafana dashboard of pass/fail per namespace → SRE Golden Signal for policy.
- **Verdict**: **ADD after** P0-8 is done. Low effort (Helm one-liner).

### 15. Ingress / Gateway — **CLARIFY the APISIX path**

- **Current state**: 1 Ingress only (Traefik default). APISIX installed but no `ApisixRoute` CR exists.
- **Use case**: APISIX + SpiceDB authorization was chosen per ADR-002 to replace Kong. Without migration, SpiceDB is decorative.
- **Verdict**: **Keep APISIX · convert the single Ingress + per-service routes to `ApisixRoute`** · wire SpiceDB check-plugin for `/api/**`. This is a P1 but the highest-leverage security win.

### 16. NetworkPolicies — **KEEP (expand)**

- **Current state**: 4 NetPols in-cluster — **none are default-deny**.
- **Use case**: Zero Trust. Any pod can currently reach any pod, including MinIO root, Vault, Postgres admin.
- **Verdict**: **ADD `default-deny-all` in every namespace** + explicit allow per service-to-service edge. This is P1-1 from the main report, repeated here for completeness.

### 17. Feast offline store — **CLARIFY, then ACTIVATE**

- **Current state**: feast-server Deploy up, Feast not applied against `gold.fct_training_data`.
- **Use case**: offline store = ClickHouse (confirmed by `components.yaml` offline-store description). Online store = Redis.
- **Verdict**: run `feast apply` against the crypto feature repo; the trainer should pull from Feast, not raw CSV. Until this lands, the "Feature Store" stage in the thesis diagram is aspirational.

---

## PART B — Net change summary

| Tool | Earlier rec | **Corrected rec** | Reason |
|---|---|---|---|
| ClickHouse | (ambiguous wording) | **KEEP · migrate legacy→CHI** | ClickHouse is the offline store; only legacy StatefulSet is surplus |
| Kafka | "remove legacy" | **KEEP · migrate legacy→Strimzi** | same pattern as ClickHouse |
| Tempo | ADD | **DO NOT ADD** | Jaeger already fine; no Tempo pod exists today |
| Jaeger | REMOVE | **KEEP** | corollary of above |
| metacontroller | REMOVE | **KEEP** | Kubeflow Pipelines profile controller uses it |
| kuberay / Ray | "maybe remove" | **REMOVE unless RayTune sweep ships in 2 weeks** | 75 restarts, zero users |
| label-studio | REMOVE | **REMOVE (confirmed)** | contradicts ADR-005, no pod running |
| neo4j | already off | **already off · clean references** | confirmed |
| Harbor | ADD | **ADD zot** | lighter, fits single-node k3s |
| Spegel | ADD | **DEFER** | single-node → no peer benefit |
| Flagger | ADD | **ADD (confirmed)** | KServe canary automation |
| Backstage | ADD | **ADD (confirmed)** | discoverability + TechDocs |
| KEDA | ADD | **ADD (confirmed)** | Kafka-lag autoscaling |
| fourkeys | ADD | **ADD (confirmed)** | DORA dashboard for thesis |
| Policy Reporter | ADD | **ADD after Kyverno policies land** | order matters |

### Bottom line
- **Keep installed** (no removal): ClickHouse, Kafka, Jaeger, metacontroller, + all the "KEEP" tools from `AUDIT_REPORT.md` §4.3
- **Delete artifacts only** (not software): legacy `clickhouse-0` StatefulSet, legacy `kafka-0` StatefulSet, 0/0 metacontroller Deployment, components.yaml `label-studio` block
- **Decide within 2 weeks**: kuberay — ship a RayTune sweep or remove
- **Add now** (confirmed high value): Flagger, KEDA, zot, Backstage, fourkeys
- **Add later**: Spegel (after multi-node), Policy Reporter (after Kyverno policies)

This leaves `components.yaml` with ~28 core tools, each with a demonstrable use case on the crypto pipeline and a clear mapping to a thesis requirement (DORA / OWASP / 9-Principles / 12-Factor / CRISP-DM).
