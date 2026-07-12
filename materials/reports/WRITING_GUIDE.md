# Writing Guide

Practical rules for figures, tables, and chapter structure in this final report. The figure and table guidance is adapted from Fujii, R. (2026) "How to design effective scientific figures" in *Nature Human Behaviour*. The chapter-structure guidance follows ITB STI TA conventions.

Read this once before drafting a chapter, then keep it open while you revise.

## 1. Figures

### 1.1 Decide the message first

A figure is not a dump of statistical output. Before you draw anything, write the one sentence the reader should walk away with. If you cannot state it in a sentence, the figure is not ready.

Then design the figure so that sentence is the part the reader notices first. Everything else (axes, legend, secondary series) supports that sentence. If a chart element does not serve the sentence, cut it.

The message also depends on who reads the figure. A figure aimed at thesis examiners can carry more methodological detail than a figure aimed at a viva audience. State both the message and the reader before choosing graph type or layout.

### 1.2 Match the figure to time and interaction

Different reading contexts give the reader different amounts of time and different chances to ask questions. Adjust complexity accordingly.

- **Thesis chapter (research article style).** Reader has unlimited time and can flip back to the caption or main text. Figures can carry more detail and small multiples, as long as the layout stays readable.
- **Slide in a viva or seminar.** Reader has seconds, no chance to interrupt. Strip the figure to a single comparison. Annotate key values directly on the plot so the reader does not have to map a legend to a line.
- **Poster.** Reader walks past and may stop to ask questions. The figure can be moderately detailed because you stand next to it and explain.
- **Lab discussion with supervisor or peers.** Reader shares context with you. Raw plots, residuals, and intermediate diagnostics are acceptable because the conversation fills in the gaps.

When the reader has little time or no chance to ask, simplify. When the reader can sit with the figure, you can layer more information.

### 1.3 Pick the graph type that fits the data

Many TA reports default to bar charts and line charts even when the data does not fit. Choose by data structure, not habit.

- **Distributions.** Use dot plots, jitter plots, box-and-dot plots, or violins. Bars hide spread and sample size.
- **Point estimates with uncertainty.** Use a point with a confidence interval. Bars exaggerate magnitude and hide the interval.
- **Groups or clusters.** Use categorical colour. PCA, t-SNE, and UMAP scatters are the standard examples.
- **Continuous magnitudes.** Use a sequential colour scale (single-hue gradient).
- **Deviation from a reference.** Use a diverging colour scale anchored at the reference.
- **Trends over time.** Line charts are fine, but annotate the inflection points the reader should notice.
- **Comparisons of many systems on shared metrics.** Small multiples or parallel coordinates often work better than overloaded grouped bars.

### 1.4 Use colour on purpose

Colour is a communication channel, not decoration. A colour should encode a group, a magnitude, or a deviation. If a colour means nothing, drop it or turn it grey.

Keep the palette small. Three to five categorical colours is usually enough. If you need more, the figure is probably trying to say too many things at once. Split it.

Pick a palette that survives colour-blind viewing. Combine colour with shape or line style when groups matter. Tools like ColorBrewer or scientific palettes (viridis, cividis) are safer defaults than ad-hoc choices.

Be careful with generative tools. They tend to map data to a default chart without thinking about message, audience, or colour-blind access. Treat AI output as a draft, not a final.

### 1.5 Reduce cognitive load

Every extra element costs the reader attention. Audit the figure and remove anything that is not earning its place.

- Drop gridlines unless the reader needs to read off exact values.
- Drop chart borders, drop shadows, and decorative backgrounds.
- Drop redundant labels. If the axis title says "Latency (ms)", the data points do not need "ms" suffixes.
- Pull legends close to the data they describe, or label series directly on the plot.
- Limit the number of panels. If a figure has eight panels and a paragraph of caption, the reader will skim and miss the point.

Send detailed numbers that do not fit cleanly into a chart to a supplementary table or an appendix instead of stuffing them into the figure.

Before the figure ships, show it to someone outside your immediate work. They will spot the labels that confused them and the panel order that surprised them. You are too close to your own data to see those problems.

### 1.6 Ask whether the figure is needed

A figure is the right tool when the reader needs to see a pattern, a trend, a distribution, or a relationship. If the goal is to report a small set of precise numbers, a table is usually clearer and more honest.

Common cases where a table beats a figure:
- Baseline characteristics or descriptive statistics.
- A short list of model performance numbers across runs.
- Side-by-side comparison of tool features (capability matrices).
- Exact thresholds, hyperparameters, or version pins that the reader may need to reference.

Tables and figures are not rivals. A dashboard that shows a chart and the underlying table together gives the reader both pattern recognition and precise lookup. Use that pairing where it makes sense.

### 1.7 Architecture diagrams as code

All diagram-as-code sources live in `diagrams/` (one `.eraser` file per figure, same basename as the rendered PNG in `figures/`; see `diagrams/README.md`). Every diagram must render wide (horizontal) and is included WITHOUT `\rotatebox`; content too large for one wide frame is split across several diagrams rather than rotated 90°, using the uniform `\includegraphics[width=\textwidth,height=0.42\textheight,keepaspectratio]{...}` pattern. The sources are organised in three narrative sections under ONE nine-layer taxonomy (Round 11): Section 1 (kondisi saat ini, Subbab III.1.3) `Fragment_DataOps_Flow` (Gambar III.1) and `Fragment_MLOps_Flow` (Gambar III.2), services only and deliberately disconnected; Section 2 (sasaran layanan, Subbab IV.1, before the IV.2 selection) `DataOps_MLOps_Flow` (Gambar IV.1, the nine layers from `tab:layanan_industri` on one Kubernetes control plane, tool-free); Section 3 (arsitektur dengan alat terpilih, Subbab IV.3, nine one-per-layer subsections) the TEN `Layer_*` sources naming the concrete tools, one per layer in table-row order with layer 5 (Model Lifecycle, which includes the model serving components per its table row) split across two figures. The folder is chapter-agnostic — any chapter's architecture figure may keep its source there, mirroring how `tables/` holds every chapter's tables. Every node in the Section 3 (`Layer_*`) diagrams must name a tool that actually exists in `platform/components/`, while the Section 1 and Section 2 diagrams are deliberately tool-free and name only generic services. Re-render manually: paste the file into https://app.eraser.io (diagram-as-code), export PNG, overwrite the figure file, rebuild the PDF. Never edit the PNG without updating the `.eraser` source first; stale Raystack/Kong/Redis-Stack/Jaeger nodes from the proposal era are exactly the drift this rule prevents. The ten Section 3 sources (`Layer_Orchestration_Infra`, `Layer_Ingestion_Processing`, `Layer_Data_Storage`, `Layer_Feature_Service`, `Layer_Model_Lifecycle`, `Layer_Model_Serving`, `Layer_Data_Governance`, `Layer_Observability`, `Layer_GitOps_CD`, `Layer_Security`) map 1:1 to the nine §IV.3 subsections (labels fig:layer-orkestrasi-infra, -ingestion-processing, -storage, -feature, -lifecycle, -serving, -governance, -observability, -gitops, -security), and they keep the self-healing `\IfFileExists{figures/X.png}{\includegraphics...}{placeholder box}` pattern so the build stays green until the PNG is rendered, and the placeholder auto-disappears once the figure exists. Every node carries an `icon:` from the verified docs.eraser.io/docs/icons list — brand logos in Section 3 where the list has them (`postgres` not `postgresql`; `flame` is not a valid name; forks keep generic icons: Valkey is not `redis`, OpenBao is not `vault`), generic icons only in Sections 1-2 — and every edge uses `>`/`<`/`<>` per the factual direction in the papers, the tool documentation, or `platform/components/`, with `--` (eraser renders it dotted) reserved for non-flow associations; the eraser cloud-architecture syntax has no `title` line, so each render happens on a fresh canvas named after the file. Full rules: `diagrams/README.md` 9-11.

Maturity grounding (2026-07): the before/after pair is anchored to published maturity frames, mirroring `subsec:maturity` (now folded into the MLOps subsection II.1.2 since the 2026-07-12 DataOps-first restructure; DataOps maturity lives in II.1.1). Section 1 renders the before state as two separate service flows: `Fragment_DataOps_Flow` carries a `Ciri Kematangan Kondisi Saat Ini` marker for the early DataOps evolution stages (data silos, manual pipeline monitoring, munappy2020adhoc) and `Fragment_MLOps_Flow` carries a `Ciri Kematangan Kondisi Saat Ini` marker for MLOps level 0 (manual script-driven process, one-way model handoff, no CI/CD, no active performance monitoring, googlecloud2024mlops), and the two files share no edge. Section 2 `DataOps_MLOps_Flow` renders a `Pemetaan Kematangan Target` mapping group for MLOps level 2 (googlecloud2024mlops) plus the DataOps stage (munappy2020adhoc), tool-free, since the mapping of the seven required components to concrete tools (Gitea, Tekton, Argo CD, MLflow, Feast, MLflow+MLMD, Kubeflow Pipelines) lives at the end of the IV.3 derivation paragraph (after selection, per the tool-free-before-IV.2 rule) and in the ten Layer_* diagrams. The five-stage DataOps evolution model (ad hoc, semi-automated, agile data science, continuous testing and monitoring, DataOps) is introduced in the closing paragraphs of Subbab II.1.1; the captions of Gambar III.1/III.2/IV.1 cite the relevant sources. Keep the three views — eraser source, figure captions, and the II.1.3/III.1.3/IV.1 prose — in sync whenever any of them changes.

Layer-derivation labels (2026-07, nine-layer single taxonomy): every layer group in the ten `Layer_*` sources carries its source-category annotation in the group label, mirroring the §IV.3 per-layer annotation (Najafabadi's six categories + Kreuzberger's components + Munappy's DataOps demands): Orchestration and Infrastructure (infrastructure and supporting services), Data Ingestion and Processing (data curation: collector + preprocessor), Data Storage (storage and versioning), Feature Service (feature store on storage and versioning), Model Lifecycle (ML training + model registry + ML metadata + inference on its model-serving part), Data Governance (data quality + data testing + data governance), Observability (monitoring), GitOps and Continuous Delivery (kategori CI/CD), Platform Security (security side of supporting services + controlled access). The `fig:integrate-service` caption (Subbab IV.1) ties each layer back to its sources through Tabel `layanan_industri`. Changing the derivation prose requires updating these labels, and vice versa; see diagrams/README.md rule 8 for the canonical list.

## 2. Tables

The figure guidance above already covers when to pick a table over a figure. A few additional rules for tables themselves:

- One idea per table. If the table answers two questions, split it.
- Order rows and columns by the comparison the reader cares about, not alphabetically.
- Right-align numbers, left-align text. Decimal points should line up.
- Keep precision honest. Reporting accuracy as 0.84327 hides that the standard error is 0.05.
- Use consistent units within a column. Mark the unit in the header, not on every cell.
- Bold or shade the row or column that carries the main result.
- Caption above the table (LaTeX convention for thesis reports), one sentence stating the comparison.

For long tables of raw numbers (per-symbol metrics, full hyperparameter sweeps), move them to an appendix and keep a summary table in the main chapter.

### 2.1 Tool comparison tables (per-layer)

Each architectural layer that has more than one credible open-source candidate carries a small comparison table in Bab IV §IV.2 (Analisis Pemilihan Open Source Tools; moved from Bab III per the 2026-07 revision because component selection is DSRM design work), grouped by service group and referring back to the concept subsection in Bab II. Bab II introduces the concept and names the candidates as examples; Bab IV §IV.1 (`sec:layanan-industri`) establishes the evidence-based nine service groups; Bab IV §IV.2 carries the scored comparison and the selection verdict. The pattern is fixed so reviewers can scan across layers:

- 4 candidates per table (the chosen tool plus 3 credible alternatives).
- 4 criteria per table on a 0–2 scale. Criteria are layer-specific, not generic — pick the dimensions that drive the decision for that layer (e.g. *Latensi Rendah* for vector index, *K8s-Native* for orchestration, *Transaksi ACID* for table format).
- Total column sums to /8. The chosen tool holds the unique highest Total in its table and justifies it with a textual paragraph; it must not be hand-waved.
- The scoring rubric is stated once in prose in the §IV.2 introduction (Bab IV), before the first scored table (`k8s_distribution_comparison`): 0 = criterion not met or feature absent, 1 = partial support that still needs extra components or carries a meaningful limitation, 2 = fully met by built-in capability. Scores derive from official documentation and project maintenance status. The narrow 3-level scale is deliberate: each level has an explicit justification, avoiding the false precision of a 5-point scale. Per-criterion 0/1/2 parameters live in Lampiran A (`appx:rubrik`, `appendices/Lampiran_A.tex`; the A/B order was swapped 2026-07 so the selection rubric precedes the verification catalog, matching document sequence): cross-table criteria (Kematangan, Komunitas, Ekstensibilitas, the license family, the K8s-integration family) are defined once, layer-specific criteria once per layer, and criterion names there must match the table column headers verbatim. The 24 tool tables use the `\skorlegendtools` legend macro that points to that Lampiran; `evaluasi_kf`/`evaluasi_knf` keep the generic `\skorlegend` (their scores mean requirement fulfilment, not the tool rubric), and `mlops_maturity_comparison` carries its own inline maturity-semantics legend.
- The rubric also anchors the open-source claim: the license criterion follows OSI-approved license status, and stewardship under a neutral foundation (Apache Software Foundation, CNCF, Linux Foundation) counts as supporting evidence of open governance feeding the maturity and community criteria. Only state a foundation affiliation in prose when it is certain (e.g. Kafka under ASF, Valkey under Linux Foundation, OpenBao under Linux Foundation).
- Every scored table carries a textual **Lisensi (Yayasan)** column between the last criterion and Total: the official license plus the steward foundation in parentheses, e.g. `Apache 2.0 (CNCF)`, `MPL 2.0 (LF)`, `BUSL 1.1 (mandiri)`. `mandiri` marks vendor- or community-run projects without a neutral foundation; `komunitas` is reserved for pgvector under the PostgreSQL community. The column is informational only and never changes the Total; the §IV.2 introduction (Bab IV) says so explicitly. Verified facts to keep: Featureform = MPL 2.0; OpenMetadata = Apache 2.0 under Linux Foundation (March 2026, via Collate); DataHub, Amundsen, Feast, Feathr, Milvus, KServe = LF AI & Data; MLflow, Valkey, OpenBao = LF; SOPS = CNCF; TorchServe = PyTorch Foundation (LF).
- Standard scored-table layout so all 24 tables render identically inside the 14 cm text width: `[H]`, `\footnotesize`, `\setlength{\tabcolsep}{3pt}`, columns `m{2.9cm}` (name, left-aligned, header centered via `\multicolumn`), four criteria `m{1.5cm}` centered, `m{2.5cm}` Lisensi (Yayasan), `m{0.9cm}` Total. Long criterion headers break with `\-` or `\allowbreak` instead of widening the column.
- Highest Total = the platform primary pick for the evaluated function. A lower-scoring row may still be deployed in a complementary role (e.g. Flink for streaming beside Spark for batch); the prose around the table must say so explicitly.
- `mlops_maturity_comparison.tex`, `dataops_maturity_comparison.tex`, and `architecture_comparison.tex` are non-scored (capability matrix, descriptive longtable, and longtable respectively) and sit outside the rubric.
- Caption above, label `tab:<topic>_comparison`, file `tables/<topic>_comparison.tex`.
- Placement spec is `\begin{table}[H]` (user directive 2026-07-12: every table attaches directly under its referencing paragraph, no drifting to a lonely page). `[H]` is provided by the `floatrow` package already in the preamble; do NOT add `\usepackage{float}` — floatrow errors on it and skips itself, breaking `\floatsetup`. When a table is too tall for the remaining page, `[H]` overfills vertically; the single known case is `perbandingan_biaya.tex` (Tabel VI.3), which therefore keeps `[!htb]` as the sole exception. The mid-section `\clearpage` after each Bab IV scored table was removed for the same reason (it sealed tables onto otherwise-empty pages). FIGURES stay on `[!htb]`/`[!htbp]`: they are large (up to 0.42\textheight) and `[H]` would leave big gaps; the three MLOps level figures keep `[!htb]` directly after the first paragraph of the Tingkat Kematangan subsection, in level order 0, 1, 2.

Layers currently covered (all 24 scored tables now live in Bab IV §IV.2 `sec:pemilihan-tools`, grouped into 9 service-group subsections; the §2.x anchor beside each names the Bab II concept subsection that its §IV.2 entry refers back to):

- `k8s_distribution_comparison.tex` — §2.2.1 (Kubernetes distribution: k3s vs k0s vs MicroK8s vs kind)
- `feature_store_comparison.tex` — §2.4
- `offline_storage_comparison.tex`, `online_storage_comparison.tex` — §2.4.2
- `vector_index_comparison.tex` — §2.4.3
- `orchestration_comparison.tex` — §2.5.2
- `tracking_comparison.tex` — §2.5.1
- `serving_comparison.tex` — §2.5.4
- `message_broker_comparison.tex` — §2.3.2 (Message broker: Kafka vs Redpanda vs Pulsar vs NATS JetStream)
- `schema_registry_comparison.tex` — §2.3.2
- `data_processing_comparison.tex` — §2.3
- `lakehouse_format_comparison.tex` — §2.3.5
- `object_storage_comparison.tex` — §2.3.6 (Object storage: MinIO vs Ceph RGW vs SeaweedFS vs Garage)
- `data_versioning_comparison.tex` — §2.3.6 (Data versioning: lakeFS vs DVC vs Nessie vs Pachyderm)
- `metadata_comparison.tex` — §2.6
- `monitoring_comparison.tex` — §2.8
- `dashboarding_comparison.tex` — §2.8
- `gitops_comparison.tex` — §2.9
- `identity_comparison.tex` — §2.10.1 (Identity Provider: Dex vs Keycloak vs Authelia vs Authentik)
- `secrets_comparison.tex` — §2.10.1 (Secrets manager: OpenBao vs Vault vs Sealed Secrets vs SOPS)
- `service_mesh_comparison.tex` — §2.10.2 (Service mesh: Istio vs Linkerd vs Cilium vs Consul Connect)
- `api_gateway_comparison.tex` — §2.10.2
- `policy_comparison.tex` — §2.10.2 (Policy engine: Kyverno vs OPA Gatekeeper vs jsPolicy vs Kubewarden)
- `runtime_security_comparison.tex` — §2.10.2
- `mlops_maturity_comparison.tex` — §2.1.3 (color-coded maturity matrix, non-scored, carries its own legend)
- `dataops_maturity_comparison.tex` — §2.1.3 (descriptive comparison of three DataOps maturity models: Munappy / DataKitchen / HighByte; deliberately NOT capability-scored because the three models measure different objects — see the §2.1.3 paragraph that introduces it)
- `architecture_comparison.tex` — §2.11 (longtable; *Aspek × Saat Ini × Diusulkan × Keuntungan × Referensi*, the only table allowed to use a different shape because it summarises across the whole architecture).

When adding a new comparison table, follow the same shape and place an `\input{tables/<file>}` directive immediately after the introductory paragraph that names the alternatives.

### 2.2 Every table is an extracted file (no inline tables)

The `tables/` rule is not limited to comparison tables. **Every** `\begin{table}` in the report lives in its own `tables/<snake_case>.tex` file and is pulled into the chapter with a single `\input{tables/<file>}` line; a chapter file must never carry an inline `\begin{table}...\end{table}` block. This keeps `grep \begin{table} chapters/` empty and mirrors how `diagrams/` holds every figure source. Non-comparison tables that follow the rule: `kebutuhan_fungsional`, `kebutuhan_nonfungsional`, `evaluasi_kf`, `evaluasi_knf`, `evaluasi_total`, `evaluasi_target`, `uji_penerimaan` (requirements and Bab VI evaluation), `peran_akses` (Tabel IV role-to-interface mapping), and `struktur_direktori` (Tabel V project-folder map). When a new table is needed, write the file first, then `\input` it directly after the paragraph that references it by `\ref`.

## 3. Chapter structure

The TA structure must stay synchronised end to end. The chain is:

Rumusan Masalah → Tujuan → Bab IV → Bab V → Kesimpulan.

If there are three problems, there should be three objectives, three chapter sections that build the artefact, three sets of evaluation results, and three conclusions.

### 3.1 Objectives describe the artefact, not the evaluation

The objective of a TA is the artefact you build. Evaluation is part of the methodology you run to verify the artefact; it is not the objective itself. Avoid writing "to evaluate" or "to test" as an objective. Evaluation will happen regardless; it does not need a slot in the objective list.

Correct framing:
- Designing the architecture of system X.
- Implementing system X.
- Deploying system X.

Incorrect framing (do not write these as objectives):
- Evaluating system X.
- Testing the performance of system X.

### 3.2 Bab IV mirrors the objectives

If there are three objectives, Bab IV has at least three sections, each corresponding to one objective. The chapter title is not the bland word "Perancangan". It names the artefact.

Example title: **Bab IV Sistem Pendeteksi Rasa Makanan.**

Section layout under that title:
- IV.1 Gambaran Umum Sistem (the system at a glance, with the overall diagram and a short description of how the parts fit).
- IV.2 Desain Arsitektur Sistem (the architecture objective).
- IV.3 Implementasi Sistem (the implementation objective).
- IV.4 Deployment Sistem (the deployment objective).

If there is only one objective, use that objective as the chapter title. Since the 2026-07-12 revision this report carries NO "Gambaran Umum" section in Bab IV: the whole-picture view is given by the chapter lead-in paragraph plus the tool-free integrated-service figure (Gambar IV.1) inside §IV.1 klasifikasi, because a separate overview section duplicated both the classification and the §IV.3 design intro. Do not reintroduce one.

### 3.3 Bab V mirrors Bab IV

Each evaluation section maps to one Bab IV section. Three architecture decisions, three evaluations. The reader should be able to read Bab IV §IV.2 and then jump to Bab V §V.2 and find the matching evaluation. Use parallel section titles where it helps the reader.

### 3.4 Kesimpulan answers the objectives one by one

If the objectives are numbered 1, 2, 3, the conclusion section has three points that each answer one objective. Each point states what was built and what the evaluation showed. Do not add a new claim in the conclusion that did not appear earlier.

### 3.5 Paragraph density rule

Narrative paragraphs (those under `\section` or `\subsection`) must contain at least four full sentences, and every `\subsection` must contain at least two such paragraphs. Each additional sentence should add a concrete fact — a citation, a tool name, a CRD, a metric — rather than restating a previous one.

This rule is exempt for items inside `\begin{enumerate}` and `\begin{itemize}`. Numbered or bulleted items follow the proposal format: bold title on the first line (no trailing period), then one to three short sentences of explanation on the following line, separated by `\vspace{0.5em}` between items. Do not force enumerate items into multi-paragraph form.

### 3.6 Quick checklist before submission

Run through this list when the draft is close to done.

- Number of rumusan masalah equals number of tujuan equals number of Bab IV section pairs equals number of Bab V section pairs equals number of kesimpulan points.
- No objective contains the verbs "evaluate", "test", or "measure".
- Bab IV title names the artefact, not a generic word.
- The chapter carries one system-overview figure (Gambar IV.1, `fig:integrate-service`, tool-free) inside §IV.1 klasifikasi with a short description; there is no separate Gambaran Umum section (removed 2026-07-12).
- Each Bab V section refers back to the matching Bab IV section.
- Each kesimpulan point answers exactly one tujuan.
- Daftar Singkatan lists only acronyms that actually appear in Bab 1 to Bab 7, alphabetically, each with the chapter of first use; re-run the first-use grep after moving content between chapters (license and foundation acronyms AGPL, ASF, BSD, BSL, BUSL, LF, MPL entered via the Lisensi (Yayasan) column of the 24 scored tables and live in Bab IV §IV.2; CNCF first appears earlier, in Bab II prose).

### 3.7 Per-Bab template comments (central store)

Chapter files under `chapters/` carry only a minimal pointer comment at the top (max 5 words per line, e.g. `% Bab I Pendahuluan`, `% Template: TEMPLATE_BAB.md`, `% Gaya: WRITING_GUIDE.md`). The full subbab layout, RM/T chain links, and standing notes per bab live ONLY here, so the template survives even if a chapter file is rewritten end-to-end. This section is the single source of truth. Bab I through V follow this convention with the minimal three-line header; Bab VI and VII retain a short template-block header summarizing their subbab layout and chain links. All seven chapters have completed their revision pass: Bab VI and VII report acceptance on functional and structural verification at single-node scope, with quantitative multi-node load characterization framed as future direction (no deferred wording).

**Bab I — Pendahuluan**

```
- I.1 Latar Belakang         : motivasi domain-agnostic platform DataOps + MLOps
- I.2 Rumusan Masalah        : RM-1..RM-4 (akar isu, bukan turunan tools)
- I.3 Tujuan                 : T-1..T-4, satu lawan satu dengan RM-N
- I.4 Batasan Masalah        : BP-1..BP-3 saja (batasan penelitian, enumerate polos
                               bergaya RM/T tanpa judul tebal; batasan implementasi
                               BI-1..BI-2 dipindah ke V.1.1 karena kontribusi utama
                               adalah arsitektur lintas use case, bukan perwujudan
                               satu lingkungan)
- I.5 Metodologi             : DSRM Peffers et al. (6 fase)
- I.6 Sistematika Penulisan  : peta bab II..VII
Catatan: kripto hanya use-case verifikasi; tidak masuk latar belakang.
```

**Bab II — Studi Literatur**

```
- II.1 DataOps dan MLOps            : definisi, kematangan, integrasi
- II.2 Kubernetes dan Cloud-Native  : orkestrasi, scaling (HPA/VPA/KEDA), operator, runtime
- II.3 Manajemen Data               : Lambda/Kappa, message broker + data ingestion,
                                      stream processing, batch processing + SQL,
                                      lakehouse, objek + versi data, relasional + pencarian
                                      (alat contoh: Kafka+Karapace, Flink, Spark+dbt,
                                      Iceberg/Trino, MinIO/lakeFS, PG/MySQL/OpenSearch)
- II.4 Layanan Fitur                : Feast, ClickHouse, Valkey, Qdrant, HNSW, point-in-time
- II.5 *Model Lifecycle*            : MLflow, KFP+Argo Workflows, Notebooks/Katib/Trainer, KServe
- II.6 Tata Kelola Data             : DataHub, Great Expectations, OpenLineage
- II.7 Deteksi Drift                : PSI, Kolmogorov-Smirnov, retraining loop
- II.8 Observabilitas               : Prometheus/Loki/Tempo/Grafana/OTel, Sloth, Evidently,
                                      Pyroscope, Pushgateway, OpenCost, Superset
- II.9 GitOps                       : Argo CD, Gitea, Tekton, Argo Rollouts
- II.10 Keamanan Platform           : Dex+oauth2-proxy, SpiceDB, OpenBao+ESO+KES, Istio,
                                      APISIX, Kyverno/OPA, Falco, Trivy, Velero, Chaos Mesh
- II.11 Penelitian Terkait          : posisi platform terhadap pekerjaan terdahulu
Tabel perbandingan berskor: sejak revisi 2026-07 di-\input pada Bab IV §IV.2, bukan pada Bab II;
Bab II hanya menyebut kandidat alat sebagai contoh (daftar lengkap tabel pada §2.1 dokumen ini).
Penjelasan tool: setiap tool pada platform/components diberi definisi dan citasi resmi.
```

**Bab III — Analisis Masalah**

```
- III.1 Analisis Kondisi Saat Ini             : tiga sumber tekanan, diurutkan sesuai pemicu pada Bab I
  - III.1.1 Beban Konfigurasi Platform dari Nol     : configure-from-0
  - III.1.2 Biaya Berlangganan Layanan Terkelola    : cloud subscription + trade-off waktu lawan anggaran
  - III.1.3 Efek Domino Fragmentasi Lintas Peran    : dua alur layanan terfragmentasi DataOps dan MLOps (Gambar III.1 dan III.2, sengaja tidak tersambung, tanpa rincian per peran)
- III.2 Analisis Kebutuhan                    : identifikasi + KF + KNF (satu lawan satu sub-sistem)
- III.3 Analisis Pemilihan Solusi             : alternatif + penentuan solusi (menutup bab)
Catatan:
  - Analisis Pemilihan Open Source Tools dipindah ke Bab IV §IV.2 (revisi 2026-07): pemilihan komponen adalah aktivitas perancangan DSRM, bukan analisis masalah.
  - Urutan sub-sub-section di III.1 mengikuti urutan pemicu pada Bab I Latar Belakang.
  - KF berorientasi kemampuan (apa yang dilakukan platform).
  - KNF berorientasi sifat sistem (latensi, ketersediaan, observabilitas, keamanan).
  - Setiap KNF wajib menyebut metrik dan ambang batas yang terukur.
  - Tabel KF (kolom: ID, Kebutuhan, Deskripsi, Tujuan) dan KNF (kolom: ID, Kebutuhan, Deskripsi, Target Metrik, Tujuan) sama-sama memuat kolom Tujuan yang menautkan tiap kebutuhan ke salah satu dari empat tujuan (T-1..T-4), mengikuti pengelompokan uji penerimaan pada Bab VI; untuk KNF kolom ini menunjuk tujuan utama karena KNF bersifat lintas-bidang.
  - Urutan baris (sort subject) yang wajib dijaga: KF diurut menurut layer arsitektur (KF-01..04 layanan fitur, KF-05..10 model lifecycle dan tata kelola, KF-11..14 operasional); KNF diurut menurut taksonomi atribut kualitas (kinerja, skalabilitas, keandalan, konsistensi, observability, keamanan, ekstensibilitas, lalu atribut operasional jangka panjang). Urutan ID sengaja tidak mengikuti Tujuan karena keterunutan ke T sudah ditampung kolom Tujuan secara terpisah.
  - ID KF-NN/KNF-NN terkunci satu lawan satu pada SK-F-NN/SK-N-NN di Bab VI dan dirujuk lintas bab; nomor tidak boleh diubah, perubahan urutan dilakukan lewat narasi pengelompokan bukan penomoran ulang.
  - Fragmentasi ditampilkan sebagai dua alur layanan terfragmentasi yang sengaja tidak tersambung pada Gambar III.1 (DataOps) dan Gambar III.2 (MLOps); rincian per peran tidak ditulis karena tesis bersifat layer-centric (lihat TEMPLATE_BAB.md §5). Lampiran C dan keempat diagram fragmentasi per peran sudah dihapus.
```

**Bab IV — Perancangan Arsitektur Platform DataOps dan MLOps**

```
(paragraf pengantar bab tanpa nomor; TIDAK ada subbab Gambaran Umum sejak 2026-07-12)
- IV.1 Analisis Layanan DataOps dan MLOps pada Praktik Industri : bukti layanan berulang
        (kreuzberger 9 komponen, amershi 9 tahap Microsoft, najafabadi 35 komponen dengan
        frekuensi kemunculan, gcp 7 komponen level 2, munappy/rella/jain sisi data) +
        klasifikasi 9 layer platform (tabel layanan_industri) + Gambar IV.1 bebas alat +
        tabel peran_akses sebagai penutup; tanpa klaim mayoritas mutlak, argumen
        konvergensi lintas sumber
- IV.2 Analisis Pemilihan Open Source Tools         : 9 subbab layer, 24 tabel berskor
        0-2, legenda skorlegendtools + rubrik Lampiran A (dipindah dari Bab III 2026-07)
- IV.3 Perancangan Arsitektur Terintegrasi          : menjawab T-1; pembuka memuat kontras
        fragmentasi (tiga penyatuan) + derivasi kategori per layer; 9 subbab layer berjudul
        identik dengan IV.2, satu diagram beralat per layer (Model Lifecycle dua gambar)
- IV.4 Perancangan Sub-sistem Tata Kelola Data      : menjawab T-2 (tata kelola data)
- IV.5 Perancangan Sub-sistem Deteksi Drift dan Continuous Training : menjawab T-3 (deteksi drift + PIT)
- IV.6 Perancangan Sub-sistem Layanan Fitur Dual-Store : menjawab T-4 (feature store dual-store)
- IV.7 Alur Kerja End-to-End                        : rangkaian sub-sistem ke siklus produksi
Rantai keterhubungan: T-N ↔ IV.N+2 ↔ V.N+1 ↔ Kesimpulan ke-N (IV.1 dan IV.2 subbab
pendukung di luar rantai; alur bab = layanan → alat → arsitektur → sub-sistem)
Catatan domain-agnostic: arsitektur murni platform; verifikasi kripto ditunda ke Bab V,
dengan justifikasi cakupan use case menunjuk sembilan layer IV.1 pada Bab V
(sec:verifikasi) dan Bab VI (subsec:instans-verifikasi).
Catatan sembilan layer (taksonomi tunggal 2026-07-11): tiap layer = baris bersumber
tabel layanan_industri, urutan = subbab konsep Bab II; anotasi kategori najafabadi +
kreuzberger + munappy pada paragraf derivasi pembuka IV.3; bukan taksonomi baru.
Catatan anti-duplikasi: subbab layer IV.3 yang topiknya diperdalam sub-sistem
(Governance→IV.4, drift→IV.5, Feature→IV.6) hanya ringkasan + penunjuk maju.
```

**Bab V — Implementasi Arsitektur Platform DataOps dan MLOps**

```
- V.1 Lingkungan Implementasi                       : tumpukan teknologi + topologi cluster;
                                                      V.1.1 Batasan Implementasi (BI-1..BI-2,
                                                      enumerate polos bergaya RM/T)
- V.2 Implementasi Arsitektur Terintegrasi          : memetakan IV.3 ke manifest + konfigurasi
- V.3 Implementasi Sub-sistem Tata Kelola Data      : memetakan IV.4 (governance + lineage)
- V.4 Implementasi Sub-sistem Deteksi Drift dan Continuous Training : memetakan IV.5 (drift + PIT)
- V.5 Implementasi Sub-sistem Layanan Fitur Dual-Store : memetakan IV.6 (feature store)
- V.6 Verifikasi Implementasi                       : use-case kripto sebagai instans pengujian
Rantai keterhubungan: IV.(N+2) ↔ V.(N+1) ↔ Kesimpulan ke-N (IV.3↔V.2, IV.4↔V.3, IV.5↔V.4, IV.6↔V.5)
Catatan use-case: kripto hanya untuk verifikasi jalur, tidak mengubah sifat domain-agnostic.
```

**Bab VI — Evaluasi**

```
- VI.1 Metode Evaluasi              : prosedur uji per tujuan T-1..T-4
- VI.2 Hasil Evaluasi               : status pemenuhan per kebutuhan (struktural, fungsional, terinstrumentasi)
- VI.3 Pembahasan Hasil Evaluasi    : interpretasi, keterbatasan, tindak lanjut
Rantai keterhubungan: T-N ↔ VI.1.N ↔ VI.2.N ↔ VI.3.N ↔ Kesimpulan ke-N
Catatan status: setiap klaim sepadan dengan bukti pada lingkungan node tunggal (BI-1);
karakterisasi beban kuantitatif multi-node menjadi arah pengembangan pada Bab VII.
```

**Bab VII — Penutup**

```
- VII.1 Kesimpulan : empat poin K1..K4, satu lawan satu dengan T-1..T-4
- VII.2 Saran      : tindak lanjut + arah pengembangan platform berikutnya
Rantai keterhubungan: T-N ↔ K-N ; tidak menambah klaim baru di luar bab sebelumnya
Catatan: Saran-1 memperluas karakterisasi beban kuantitatif; Saran-2 arah pengembangan platform.
```

### 3.8 Chapter lead-in paragraphs

Every chapter opens with one short unnumbered lead-in (1 paragraph, maximum 2) placed directly after the \chapter heading and before the first \section. The lead-in states what the chapter covers and how it connects to the surrounding chapters; it is not a numbered subbab and must not duplicate the Sistematika Penulisan list in Bab I. Bab I through Bab VII all follow this rule (Bab II formerly used a numbered Cakupan section; converted 2026-06).

### 3.9 Section depth and section lead-ins in Bab II

Per the 2026-07 directive, every Bab II section carries at least two topic-titled subsections EXCEPT §2.11 Penelitian Terkait, which stays flat; each subsection must hold at least two paragraphs, and the old "short sections stay flat" exemption no longer applies to Bab II. Ten sections carry subsections: §2.1 DataOps dan MLOps, §2.2 Kubernetes, §2.3 Manajemen Data, §2.4 Layanan Fitur, §2.5 *Model Lifecycle*, §2.6 Tata Kelola, §2.7 Deteksi *Drift*, §2.8 Observabilitas, §2.9 GitOps, and §2.10 Keamanan. Depth stops at \subsection; no \subsubsection is used anywhere in Bab II, so the heading tree is uniformly two levels deep.

Concept-first rule (2026-07): every Bab II subsection and sub-subsection opens with concept paragraphs grounded in literature and names open-source tools only in its closing example paragraph(s), typically with the phrase "Contoh perwujudan \textit{open source} ...", because tool selection happens in Bab IV §IV.2. Never open a unit with a tool name or a decision sentence ("Pada platform ini, X dipakai"); implementation-operational detail (auth modes, topic topology, bucket layout, PodDisruptionBudget and the like) lives in Bab V. Tool-named subsection titles were renamed to concept titles while keeping their labels: subsec:kafka = "\textit{Message Broker} dan \textit{Data Ingestion}", subsec:flink = "\textit{Stream Processing}", subsec:spark = "\textit{Batch Processing} dan Transformasi SQL". The report must read forward, never reverse-engineered: Bab I overview, Bab II concepts per service, Bab III problem decomposition, Bab IV service classification (§IV.1) then per-layer tool comparison and selection (§IV.2) before the architecture design (§IV.3).

Every section that has subsections opens with one short lead-in paragraph (four sentences) placed between the \section heading and the first \subsection. The lead-in names the subsection topics and their reading order, mirroring the chapter lead-in pattern (§3.8) and the proposal's Bab 2 layout; it is navigational only and introduces no factual claim that is not made with a citation inside a subsection. Revision 2026-06: formerly only §2.10 carried such a lead-in; the others were added, and §2.3 was retitled from "Ingestasi, Streaming, dan Batch" to "Manajemen Data: \textit{Ingestion}, \textit{Processing}, dan \textit{Storage}" (current round-8 form) so the title covers its three storage subsections; since the 2026-07 pass all ten sub-sectioned sections carry one. Non-comparison tables are \input in the subsection whose prose cites them via Tabel~\ref; the scored comparison tables live in Bab IV §IV.2 since the 2026-07 move (e.g. tab:feature_store_comparison sits in the Feature Service Layer subsection there, not in Bab II).

## 4. Working order while drafting

A drafting order that catches structural problems early:

1. Write the rumusan masalah and the tujuan first. Stop and read them aloud. If a tujuan starts with "to evaluate", rewrite it.
2. Sketch the Bab IV section titles directly from the tujuan. Do this on paper before opening the LaTeX file.
3. Draft the system overview figure that goes into IV.1. The figure forces you to commit to scope.
4. Write Bab IV section by section, putting figures and tables in as you go. Apply the figure rules from Section 1.
5. Draft Bab V in parallel section order. Apply the figure and table rules.
6. Write Kesimpulan last, point by point, answering one tujuan per point.
7. Run the submission checklist in Section 3.5.

Doing it in this order means the chapters stay in sync without late rewrites.

## References

1. Fujii, R. (2026). How to design effective scientific figures. *Nature Human Behaviour*. https://doi.org/10.1038/s41562-026-02466-9
2. Tufte, E. R. (2001). *The Visual Display of Quantitative Information* (2nd ed.). Graphics Press.
3. Wilke, C. O. (2019). *Fundamentals of Data Visualization*. O'Reilly Media.
4. Weissgerber, T. L., Milic, N. M., Winham, S. J., & Garovic, V. D. (2015). Beyond bar and line graphs. *PLoS Biology*, 13(4), e1002128.
5. Crameri, F., Shephard, G. E., & Heron, P. J. (2020). The misuse of colour in science communication. *Nature Communications*, 11, 5444.
6. Midway, S. R. (2020). Principles of effective data visualization. *Patterns*, 1(9), 100141.

### 4.x Term register: English kept vs Indonesian accepted

English engineering terms whose Indonesian force-translation shifts meaning or
is not the accepted register stay in English (italic in prose, plain inside
code listings). Never reintroduce the calque on the left:

- penyebaran / penggelaran / penerapan (for deploy) -> `\textit{deployment}`
- citra (for container image) -> `\textit{image}`
- kanari -> `\textit{canary}`
- topik (for Kafka topic) -> `\textit{topic}` (discourse "topik" is fine)
- perkakas -> `\textit{tool}`
- pembelajaran mesin -> `\textit{machine learning}`
- peladen -> `\textit{server}`; simpul (for cluster node) -> `\textit{node}`
- penyematan (for embedding) -> `\textit{embedding}`; muatan (for payload) -> `\textit{payload}`
- danau data / gudang data -> `\textit{data lake}` / `\textit{warehouse}`
- titik pemeriksaan -> `\textit{checkpoint}`; ruang nama -> `\textit{namespace}`

Indonesian terms that ARE the accepted register and stay Indonesian:
klaster (not kluster), berkas, antarmuka, penskalaan,
pencadangan, alur kerja (workflow as concept; Argo Workflows the product
stays English), gerbang kualitas (quality gate), sumber kebenaran tunggal,
beban kerja (workload). Round 8 removed bidang kendali and ingestasi from
this list; they are now `\textit{control plane}` and
`\textit{ingestion}`/`\textit{data ingestion}`.

"penerapan" remains valid Indonesian when it means applying a technique
(e.g. "penerapan deteksi drift pada lingkungan serverless"), never as the
translation of deploying software.

Round-3 refinements:

- "menutup/ditutup" is VALID for concluding (menutup bab, bab ini ditutup
  dengan, menutup siklus, menutup kesenjangan, menutup jalur = blocking) and
  BANNED only in the covers/spans sense (menutup rentang/risiko/dimensi ->
  mencakup/menjawab; menutup rantai-of-coverage -> melengkapi).
- graf for every graph data structure (metadata graph, lineage graph, kueri
  graf); grafik only for charts. Recheck after each big edit.
- Bare English tokens must be italicized (server -> `\textit{server}`).
- Dual registers sanctioned as-is (do not churn): klaster and
  `\textit{cluster}`; pelacakan and `\textit{tracking}`; registri and
  `\textit{registry}`. Unified to Indonesian: pencadangan (not italic
  backup), pemantauan, rahasia, penemuan, materialisasi,
  alur kerja (generic workflow).
- Transitive verbs need their -kan: menyebarkan peraturan, not menyebar.

KBBI round (round 4) doctrine and verdicts:

- Symmetric-metaphor principle: a loan stays Indonesian when its KBBI sense
  differs from the technical sense in the SAME way the English word's
  dictionary sense differs from its own technical sense (the metaphor is
  inherited, so English gains no fidelity). Verified keeps under this rule:
  orkestrasi, latensi, artefak, konektor, kontainer, kredensial, metrik,
  materialisasi, rotasi, jendela (statistical window), kontrak (data
  contract), pendaratan data (landing).
- KBBI-confirmed same-sense keeps: kompatibilitas (KBBI's own computing
  example), retensi (archival example), replika, telemetri, agregasi,
  agregat, konsistensi, purwarupa, anotasi, katalog, klaster (dasbor was
  reversed to `\textit{dashboard}` by round 8).
- Standard informatics loans absent from KBBI, kept by academic usage:
  observabilitas, skalabilitas, ekstensibilitas,
  reproduksibilitas, granularitas, kueri, portabilitas, modularitas,
  registri, granular, idempoten, deklaratif, rekonsiliasi.
- Fixed this round: Maturitas -> Kematangan (headers; prose already used the
  baku form), peraturan (Kyverno rules) -> kebijakan, instans (non-word) ->
  kasus, penjamin (person-surety) -> "yang menjamin", terversion (hybrid) ->
  berversi, preambel -> preambul (KBBI spelling), keterpicuan -> terpicunya,
  Keutuhan lineage -> Keterhubungan lineage, bare English tokens italicized
  (notebook, listing, medallion, serving/reproducible/retrain cells to
  their locked forms).

Opus 4.8 sign-off round (round 5) verdicts:

- Spelling to KBBI baku: otentikasi -> autentikasi (all forms); konsumer ->
  konsumen; Preambel -> Preambul (capitalized caption escapee).
- False friend fixed: "terjaga secara konstruktif" (by construction) ->
  "terjaga secara struktural" (KBBI konstruktif = bersifat membangun).
- Calques out: "panggilan ulang" (ANN recall) -> `\textit{recall}`;
  "menempel pada pipeline" -> "dijalankan pada pipeline";
  "\textit{exactly-once} semantik" -> "semantik \textit{exactly-once}"
  (head noun first); "pengamatan ... dipantau" doubled subject -> drop
  "pengamatan".
- Register unifications: manifes everywhere (no bare/italic manifest);
  materialisasi (never `\textit{materialize}`); artefak for the
  measurement-artifact sense (`\textit{artifact}` only inside
  `\textit{artifact store}`); tabel `\textit{medallion}` (never "medali");
  Pencadangan sentence-initial (capital `\textit{Backup}` escapee).
- Bare English italicized: `\textit{node}` tunggal and multi-`\textit{node}`
  everywhere (Bab 6/7, KNF, Abstrak, evaluasi_target aligned to the
  guide-locked form); `\textit{wire-protocol}`, `\textit{suite}`,
  `\textit{hook}`, `\textit{sidecar}`, `\textit{emitter}`,
  `\textit{probe}`, `\textit{idle}`, sisi `\textit{server}` (Daftar
  Singkatan + lampiran rubrik, kini Lampiran A), `\textit{ambient}/\textit{sidecar}`.
- "tuning resource" -> "penyetelan \textit{resource}" (register match with
  "penyetelan sumber daya").
Round 15 (2026-07-12, PNG delivery + rename): user exported 12 PNGs and
  renamed the Section-2 diagram Integrate_Service_Arch -> DataOps_MLOps_Flow
  (.eraser renamed by user; PNG, Bab_4 include, README, TEMPLATE_BAB, and the
  normative sections here all updated; label fig:integrate-service and the
  sec labels unchanged). Layer_Orchestration_infra.png case-fixed to _Infra.
  Fragment_MLOps_Flow.png was NOT exported: its Bab_3 figure now uses the
  same IfFileExists placeholder pattern until the user exports that canvas.
Round 12 (user directive 2026-07-12, remove Gambaran Umum + de-dup sub-systems):
- User: "WHY STILL HAS THE GAMBARAN UMUM PLATFORM IN THE 4.1, JUST REMOVE IT
  BECAUSE IT WILL REDUNDANT, JUST STRAIGHT TO THE ANALISIS". Section IV.1
  Gambaran Umum Platform (sec:gambaran-umum-platform) DELETED. Bab IV now:
  intro paragraph -> IV.1 analisis layanan (sec:layanan-industri) -> IV.2
  pemilihan tools (sec:pemilihan-tools) -> IV.3 arsitektur (T-1) -> IV.4
  tata kelola (T-2) -> IV.5 drift (T-3) -> IV.6 dual-store (T-4) -> IV.7 e2e.
  Chain shift: T-N <-> IV.(N+2) <-> V.(N+1) <-> K-N.
- Salvage map (content that had to survive): tabel peran_akses + its lead
  paragraph moved to the tail of IV.1.2 klasifikasi (after Gambar IV.1,
  tool-free wording kept, closing sentence now says roles bind to tools only
  after IV.2); the three-unification fragmentation contrast (control plane,
  Git source of truth, observability interface + efek-domino sentence) moved
  into the IV.3 opening paragraph (design answers the before-state there);
  the MLOps-level-2 seven-component promise back-ref retargeted from the
  deleted section to subsec:layanan-praktik, which already lists the seven
  components with the googlecloud2024mlops citation. Everything else in old
  IV.1 (three-step pointer, L2/DataOps-stage chain restatement, enumerate of
  the three differences) was pure duplication and died with the section.
- Sub-system audit (user: "CHECK Tata Kelola, Deteksi Drift, Dual Store, IF
  REDUNDANT OR NOT USED, JUST REMOVE"): all three KEPT — each answers one
  Tujuan (T-2/T-3/T-4), each is implemented by a Bab V twin (V.3/V.4/V.5)
  and closed by a Kesimpulan point; removal would break the locked chain.
  What WAS removed is the layer-vs-subsystem duplication: the IV.3 Data
  Governance Layer subsection no longer repeats the DataHub metadata-source
  list (Kafka/ClickHouse/MinIO+Iceberg/Feast/dbt) that IV.4.1 owns — it now
  summarises and forward-points, matching how the Feature Service Layer
  subsection already forward-points to IV.6. New anti-duplication rule in
  TEMPLATE_BAB.md: layer subsections deepened by a sub-system carry summary +
  pointer only; detailed lists live once, in the sub-system.
- Renumbering swept: TEMPLATE_BAB locked chain + rules, WRITING_GUIDE
  normative sections (historical Round blocks below keep their era numbering),
  diagrams/README three-section map, all 13 .eraser Acuan comments
  (Subbab IV.2->IV.1, IV.3->IV.2, IV.4->IV.3), Bab_1 sistematika Bab IV
  sentence ("gambaran umum" phrase dropped). LaTeX \ref auto-renumbers.
- Also fixed while sweeping: WRITING_GUIDE §3.7 Bab IV block still said
  "sintesis arsitektur tujuh layer" and "Governance and Observability
  Layer" (Round 11 leftover) — rewritten to the nine-layer form.
Round 11 (user directive 2026-07-11, single nine-layer taxonomy):
- User: "just choose 1, layer or service so it not redundant". Decision: the
  NINE literature-derived layers are the single taxonomy end-to-end; the
  seven-layer consolidation and the nine tool-free `Service_*` detail
  diagrams from Round 10 are deleted as the redundancy. `tab:layanan_industri`
  rows ARE the nine layers (caption and header column now say Layer); IV.2.2
  retitled "Klasifikasi Sembilan Layer Platform"; IV.2.3 removed; IV.3
  subsection titles unchanged (they already were the nine layer names); IV.4
  restructured from four subsections to NINE, 1:1 with the table rows in
  table-row order (Model Lifecycle Layer includes model serving per row 5 and
  carries two figures), the derivation paragraph rewritten as per-layer
  source-category annotation (najafabadi + kreuzberger + munappy) with the
  L2 component-to-tool mapping kept at its end. "kelompok layanan"
  terminology replaced by "layer" across Bab 1/4/5/6 and both tables; the
  abstract now lists the nine layer names; Bab 5 V.2 merged the
  ingestion+processing subsections into "Data Ingestion and Processing
  Layer", retitled "Data Storage Layer" and "Model Lifecycle Layer", and its
  lead maps the remaining layers to V.1 (orchestration, security, GitOps),
  V.3 (governance), and V.5 (feature service). Bab 6 already used the nine
  layer names; only "kelompok" wording swept. New IV.4 subsection labels:
  subsec:lapisan-{infra,data,storage,feature,model,tata-kelola,observabilitas,
  gitops,keamanan}.
- Diagram set now 13 files: 2 Fragment + Integrate_Service_Arch + 10 Layer_*
  (one per layer; layer 5 split into lifecycle + serving figures). New or
  renamed: Layer_Orchestration_Infra + Layer_GitOps_CD (split of
  Layer_Infra_Control), Layer_Ingestion_Processing (merge of
  Layer_Data_Ingestion + Layer_Processing), Layer_Data_Storage +
  Layer_Feature_Service (split of Layer_Storage_Feature), Layer_Security
  (rename of Layer_Infra_Security), Layer_Data_Governance (rename of
  Layer_Governance). The six old Layer_* files, the nine Service_* files, and
  their orphan or stale placeholder PNGs are deleted; export list is 13 PNGs
  (diagrams/README.md). Figure labels: fig:layer-orkestrasi-infra,
  -ingestion-processing, -storage, -feature, -lifecycle, -serving,
  -governance, -observability, -gitops, -security.

Round 10 (user directive 2026-07-11, diagram logos + Section-2 per-group split; the Service_* set it introduced was removed again in Round 11):
- Every node in every `.eraser` now carries an `icon:` — bare nodes render
  logo-less boxes, the exact symptom the user reported on
  `Integrate_Service_Arch` inner nodes. Icon names verified against the
  official list at docs.eraser.io/docs/icons (3842 names extracted
  2026-07-11). Brand logos now used in Section 3: kafka, airflow, spark,
  flink, dbt, trino, clickhouse, postgres, mysql, opensearch, minio, qdrant,
  mlflow, argo, istio, trivy, tempo, grafana, prometheus, superset,
  kubernetes, git, docker. `postgresql` and `flame` are NOT on the list (both
  were silently logo-less; fixed to `postgres` and `gauge`). Forks keep
  generic icons (Valkey is not `redis`, OpenBao is not `vault`); Sections 1-2
  stay generic-icon only (tool-free rule).
- Connector audit per user request ("maybe it is not need has connection"):
  every edge now uses `>`/`<` per the factual direction in the papers
  (Sections 1-2) or the tool docs and `platform/components/` (Section 3);
  `<>` only for factually two-way pairs (Istio mTLS, inference
  request/response, Kubernetes-Kyverno AdmissionReview, Trivy scan+report
  CRs, Trino federated query, OpenCost-Prometheus, KFP-Katib HPO loop); `--`
  (eraser dotted line) only for non-flow associations (control-plane
  umbrella). Artificial sibling chains (storage `dataset repository -- data
  storage -- data versioning`, the orchestration four-node chain, the
  security chain, reversed `monitoring -- model/data`) were replaced by
  source-grounded directed edges, and `Integrate_Service_Arch` gained
  group-level edges (Orchestration schedules the data and ML pipelines,
  GitOps releases to Model Lifecycle, ingestion feeds Data Governance, a new
  `Pengguna Platform` actor enters via Platform Security) so no group floats
  unconnected. Karapace now stores schemas on Kafka's internal topic and
  Kafka Connect checks compatibility (Karapace docs); Knative scales KServe
  revisions; storage/metadata edges follow write direction.
- Section 2 split per user request: nine new tool-free `Service_*` sources
  (`Service_Orchestration_Infra`, `Service_Ingestion_Processing`,
  `Service_Storage`, `Service_Feature`, `Service_Model_Lifecycle`,
  `Service_Data_Governance`, `Service_Observability`, `Service_GitOps_CD`,
  `Service_Security`) detail one group each with components verbatim from
  `tab:layanan_industri` and gray boundary nodes for neighbour groups, wired
  as new Subbab IV.2.3 (`subsec:rincian-kelompok`): a 5-sentence lead
  paragraph plus nine one-sentence figure lead-ins and `\IfFileExists`
  figures (fig:service-orkestrasi-infra .. fig:service-security) in
  table-row order, `\clearpage` before IV.3; the IV.2 intro now announces
  three parts. Export list is now 21 PNGs (diagrams/README.md).
- Eraser cloud-architecture syntax has NO `title` line
  (docs.eraser.io/docs/syntax), so canvas name is the title; every `.eraser`
  header now instructs rendering on a fresh canvas named after the file
  (stale canvas names like "DataOps_MLOps_Flow" were leaking into exports).
- The five retired PNGs (`Fragment_General_Arch`, `Integrate_General_Arch`,
  `Layer_Data`, `Layer_Model`, `Layer_Govern_Obs`) are now DELETED from
  `figures/` (Round 9 had left them on disk); `figures/` holds only
  referenced files.
- Tool-free rule before §IV.3 (user directive 2026-07-11): Bab 4 names NO open
  source tool before `sec:pemilihan-tools` (Kubernetes excepted as the thesis
  title premise; Bab 2 closing-paragraph examples stay allowed). IV.1
  rewritten to service level: the seven L2 components are listed generically
  with an explicit three-step pointer (services IV.2, selection IV.3, mapping
  IV.4); Argo CD / Grafana+Prometheus+Loki+Tempo / DataHub mentions became
  "layanan rekonsiliasi GitOps" / "satu antarmuka dashboard dengan penyimpan
  khusus tiap pilar" / "satu katalog metadata ber-lineage"; `tab:peran-akses`
  now maps roles to generic interfaces + service groups (tool column removed).
  The explicit seven-component-to-tool mapping sentence lives at the end of
  the IV.4 derivation paragraph, after selection.
- Bab 2 to nine-group traceability made explicit (IV.2.2): group order follows
  the Bab 2 concept-section order (`sec:kubernetes`; `sec:manajemen-data`
  covering both the ingestion+processing and storage groups;
  `sec:feature-store`; `sec:siklus-model`; `sec:tata-kelola-teori`;
  `sec:observability`; `sec:gitops`; `sec:keamanan-platform`), with
  `sec:drift` stated as cross-cutting and realised as the IV.6 sub-system
  (`sec:drift-ct`); the IV.4 opening adds the layers-to-groups-to-Bab-2 chain
  sentence so all three taxonomies trace to the same literature sections.

Round 9 (user directive 2026-07-10, structural reflow):
- Section move: Analisis Pemilihan Open Source Tools (`sec:pemilihan-tools`,
  9 group subsections, 24 scored tables) moved verbatim from Bab III to Bab IV
  §IV.3. Rationale: component selection is DSRM Design and Development work
  and per-group assessment presupposes the service classification. Bab III now
  ends at III.3; cross-refs are label-based and renumber automatically; the
  lead-ins of Bab II/III/IV and the moved section's first and last paragraphs
  were rewritten for the new direction (no self-references, evidence
  de-duplicated into IV.2).
- New IV.2 Analisis Layanan DataOps dan MLOps pada Praktik Industri
  (`sec:layanan-industri`; subsecs `subsec:layanan-praktik` +
  `subsec:klasifikasi-layanan`; `tables/layanan_industri.tex`): evidence-based
  service baseline from kreuzberger2023mlops (9 components), amershi2019software
  (9 Microsoft workflow stages), najafabadi2024analysis (35 components across
  43 studies WITH occurrence counts: model repository 21, ML metadata
  repository 15, ML experiment pipeline 14, training pipeline/runtime monitor
  12, data collector/dataset repository/inference service 10, feature store 8),
  googlecloud2024mlops (7 level-2 components), plus the DataOps side
  (munappy2020adhoc, rella2022mlops, jain2025integrating). NO absolute-majority
  claim: the argument is convergence across independent sources, and the
  evidence-weight difference per group is stated openly (Platform Security
  lightest). Bab V (`sec:verifikasi`) and Bab VI (`subsec:instans-verifikasi`)
  justify the crypto test case by its coverage of all nine groups.
- Lampiran swap: the scoring rubric (`appx:rubrik`) is now Lampiran A and the
  verification command catalog (`appx:verifikasi`) is now Lampiran B, so the
  selection rubric precedes the evaluation catalog in document order. File
  contents swapped so filenames still match letters; Pernyataan AI row 6
  ("Bab 5 dan Lampiran B") and the Bab I struktur-dokumen sentence updated.
- Maturity detail legends in Bab II: `tables/mlops_level_legend.tex`
  (per-level process characteristics + required components, verbatim from
  googlecloud2024mlops) and `tables/dataops_stage_legend.tex` (five Munappy
  evolution stages + per-stage requirements, verbatim from munappy2020adhoc
  §4.3), each introduced by a 4-sentence paragraph inside the maturity
  subsection. DataOps source verdict (revised 2026-07 after user supplied the
  whitepaper): Munappy stays the anchor (peer-reviewed, pipeline-capability
  focus); DataKitchen (datakitchen2020maturity, five levels struggle..optimized
  across six org dimensions) and HighByte (harrington2021highbyte, four
  industrial stages) are cited as vendor context in
  `tables/dataops_maturity_comparison.tex` — descriptive only, no cross-model
  capability scores, because the three models measure different objects.
  Munappy Fig. 2 and Fig. 3 are reproduced as `figures/DataOps_Maturity.png`
  (fig:dataops-maturity, §2.1.3) and
  `figures/Big_Data_Analytics_Pipeline_Ericson.png` (fig:pipeline-ericsson,
  §2.1.1) with \autocite{munappy2020adhoc} in the captions.
  salama2021practitioners (GCP Practitioners Guide, May 2021) corroborates the
  IV.2.1 service evidence with its core-MLOps-capability list.
- Daftar Singkatan first-use repoints: AGPL, ASF, BSD, BSL, BUSL, ESO, LF,
  MPL, OLAP moved Bab III → Bab IV (they live in the moved tables); HPA, VPA,
  KEDA moved Bab I → Bab II (stale since the BP/BI split relocated batasan
  implementasi to V.1.1).
- Bab II structure rule replaced: every Bab II section carries at least two
  topic-titled subsections EXCEPT Penelitian Terkait (user directive). The
  old "short sections stay flat" exemption no longer applies to Bab II, and
  subsection naming is unified to straight-to-topic titles (no bare "Konsep X"
  headings). The final Bab II outline lives in the §3 outline block.
- Diagram set reorganised into three narrative sections, all rendered wide
  (horizontal) and included WITHOUT `\rotatebox` (large content split across
  diagrams, not rotated). Section 1 (kondisi saat ini) splits the retired
  `fig:fragment-general`/`Fragment_General_Arch` into two service-only,
  deliberately disconnected flows `fig:fragment-dataops`/`Fragment_DataOps_Flow`
  (Gambar III.1) and `fig:fragment-mlops`/`Fragment_MLOps_Flow` (Gambar III.2).
  Section 2 adds a new tool-free service architecture
  `fig:integrate-service`/`Integrate_Service_Arch` (Gambar IV.1, Subbab IV.2,
  nine groups from `tab:layanan_industri`) placed before the IV.3 selection.
  Section 3 keeps the four `Layer_*` sources (Subbab IV.4, tooled,
  source-category annotations) but un-rotated. The old overview
  `fig:integrate-general`/`Integrate_General_Arch` is retired (its `.eraser`
  deleted, PNG left on disk at the time; deleted in Round 10), as is
  `Fragment_General_Arch`. Seven PNGs
  re-export; the three new PNG filenames temporarily hold placeholder copies of
  the old exports.

Round 8 (user override 2026-07, final English-term scheme):
- ORDER RULE: multiword English technical NPs are written in proper English
  order inside one `\textit{...}` (lowercase in prose, Title Case in
  headings/diagram labels). English words in Indonesian order are banned:
  "\textit{layer} pemrosesan" and "Data Ingestion Manual" are wrong;
  "\textit{processing layer}" and "Manual Data Ingestion" are right. A
  single English borrow with an Indonesian modifier stays legal ("antar
  \textit{layer}", "\textit{dashboard} operasional", "jalur \textit{ingestion}").
- lapis/lapisan (architecture, stratum, medallion, defense senses) ->
  `\textit{layer}`; named layers use the canonical set below; medallion ->
  "\textit{bronze layer}" / "\textit{silver layer}" / "\textit{gold layer}";
  LaTeX labels (subsec:lapisan-*) stay unchanged; the Abstrak triad now reads
  "melengkapi observabilitas metrik, log, dan \textit{trace}" (the "tiga
  pilar:" lead was dropped in the 2026-07 abstract compression for one-page
  fit).
- ingestasi -> `\textit{ingestion}` / `\textit{data ingestion}`; bidang
  kendali -> `\textit{control plane}` (KEEP bidang orkestrasi, bidang
  serverless, bidang identitas, bidang data, and jalur kendali).
- penyajian model -> `\textit{model serving}`; penyajian fitur ->
  `\textit{feature serving}`; serving-sense penyajian -> `\textit{serving}`;
  siklus hidup model -> `\textit{model lifecycle}`; pelatihan model ->
  `\textit{model training}`; pelatihan ulang -> `\textit{retraining}`
  (reverses the round-2 lock); data/pipeline/job/run pelatihan ->
  `\textit{training data}` / `\textit{training pipeline}` /
  `\textit{training job}` / `\textit{training run}`; verbs melatih/dilatih
  stay Indonesian.
- fitur \textit{online}/\textit{offline}/vektor/tabular -> `\textit{online
  feature}` / `\textit{offline feature}` / `\textit{vector feature}` /
  `\textit{tabular feature}` (KEEP layanan fitur, definisi fitur, and bare
  fitur inside Indonesian syntax); dasbor -> `\textit{dashboard}` (reverses
  the round-3 unification).
- Adjudicated KEEP (do not churn): jalur (the alur = flow vs jalur = path
  split is deliberate), penskalaan, peristiwa, antrean, ketertelusuran,
  orkestrasi, observabilitas (prose), tata kelola (prose), granularitas,
  nonstasioner, sambungan, perakitan/dirakit, jendela waktu, pemutaran
  ulang, kanal, tulang punggung, efek domino, layanan fitur.
- Round-8 consistency fixes: bus pesan -> `\textit{message broker}`;
  perekayasaan/merekayasa/rekayasa fitur -> `\textit{feature engineering}`;
  silang-rujuk / saling-rujuk -> dirujuk silang / saling dirujuk;
  Reprodusibilitas -> Reproduksibilitas; "keterikatan vendor" -> keterikatan
  (redundant beside penyedia); kosa kata -> kosakata; terstandarisasi ->
  terstandardisasi.
Canonical seven-layer name set (Bab I/IV, Abstrak, titles, diagram labels):
\textit{Infrastructure Layer}; \textit{Data Ingestion Layer};
\textit{Processing Layer}; \textit{Storage and Feature Store Layer};
\textit{Model Lifecycle Layer}; \textit{Model Serving Layer};
\textit{Governance and Observability Layer}. Bab V storage-only subsection:
\textit{Storage Layer}. Compact prose list: "yaitu \textit{infrastructure},
\textit{data ingestion}, \textit{processing}, \textit{storage and feature
store}, \textit{model lifecycle}, \textit{model serving}, serta
\textit{governance and observability}". Diagram labels use the same names in
plain text (no \textit).

Round 7 (user override of round-6 keeps): every remaining rare or
literary-technical word converted to common Indonesian or the italicized
English term. Replaced: pendaratan data -> `\textit{landing}` data,
mendaratkan -> memuat; yayasan penaung -> yayasan yang menaungi; lekukan
pada kurva -> bentuk kurva; terusir -> tergusur (Pod eviction); luaran ->
keluaran; tataran -> tingkatan; serempak -> bersamaan; fitur volatil ->
fitur fluktuatif; reproduksibel -> yang dapat direproduksi; lazim -> umum;
merembet -> menjalar; multimoda -> multimodal; dikawal -> dikendalikan;
dipancarkan -> dikirim; pemutus (tie-breaker) -> penentu; merutekan ->
meneruskan. Still kept (everyday words): menyasar, berpijak, pada
hakikatnya, pemutus rantai (idiom), keluaran, dirunut.

Commonness rule (round 6, after the tunak ban): baku-but-rare words an
Indonesian engineer would not write unprompted are replaced with common
Indonesian or the italicized English term. Replaced: teremit -> terkirim;
uji jalan -> uji coba; keterbentukan -> terbentuknya; preambul -> langkah
persiapan; pembongkaran beban -> penurunan beban; menjenuhkan kuota ->
memenuhi kuota; berbutir halus -> granular; keterpantauan -> pemantauan;
percabangan tanpa salin -> percabangan `\textit{zero-copy}`; konformansi ->
lolos uji `\textit{conformance}`; konsolidatif -> terpadu; keluwesan ->
fleksibilitas; kebergantungan -> ketergantungan; peleburan -> penggabungan;
regu keamanan -> tim keamanan; dirambatkan -> diteruskan; runtutan -> deret.
Checked and KEPT as common: dirunut (8 uses, standard academic) and
menjembatani; the rest of this round-6 keep list was superseded by the
round-7 replacements above.
- tunak (steady state) avoided as uncommon: use plain phrasing (sesudah tahun pertama, alokasi tetap) or `\textit{steady-state}` for the technical latency sense.
- Deliberately kept: bare "log" (naturalized document-wide; italicizing one
  triad line would create inconsistency), skalabel,
  `\textit{sub-sistem}`, `\textit{image container}` word order.




Additional locked pairs (register-audit round 2):

- pasca-fakta (after-the-fact calque) -> "pekerjaan susulan"
- pelanggan (for Kafka consumer) -> konsumen
- grafik (for graph data structure) -> graf ("grafik" only for charts)
- pengembalian (for rollback) -> `\textit{rollback}`
- inferensi -> `\textit{inference}` (majority register)
- (reversed by round 8) the old round-2 lock "control plane -> bidang
  kendali" no longer applies; write `\textit{control plane}`
- `\textit{promotion}` -> promosi; `\textit{materialization}` -> materialisasi;
  (reversed by round 8) `\textit{retraining}` and `\textit{ingestion}` are
  now the locked forms; the old pelatihan-ulang / ingestasi directions no
  longer apply
- menutup/ditutup for "covers/rounds out" -> melengkapi/tercakup;
  menjatuhkan for "taking down a pipeline" -> menghentikan;
  ditempelkan for "bolted onto" -> digabungkan langsung
- "menggantikan X oleh Y" -> "menggantikan X dengan Y"; bare "otomatis" before a
  passive verb -> "secara otomatis" after it

Also accepted (do NOT convert to English): alat (tool; `\textit{tool}` where
already present is fine), pelacakan (tracking), penemuan (discovery), registri,
promosi, materialisasi, indikator, beban uji. Requirement
titles in kebutuhan_fungsional.tex stay Indonesian by design even when their
descriptions use the italic English term.

