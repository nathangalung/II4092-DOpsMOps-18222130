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

All diagram-as-code sources live in `diagrams/` (one `.eraser` file per figure, same basename as the rendered PNG in `figures/`; see `diagrams/README.md`): `diagrams/Integrate_General_Arch.eraser` is the source of truth for `figures/Integrate_General_Arch.png` (Gambar IV.1). The folder is chapter-agnostic — any chapter's architecture figure may keep its source there, mirroring how `tables/` holds every chapter's tables. The source groups nodes by the seven Bab IV layers plus the four user roles and the GitOps chain, and every node must name a tool that actually exists in `platform/components/`. Re-render manually: paste the file into https://app.eraser.io (diagram-as-code), export PNG, overwrite the figure file, rebuild the PDF. Never edit the PNG without updating the `.eraser` source first; stale Raystack/Kong/Redis-Stack/Jaeger nodes from the proposal era are exactly the drift this rule prevents. Beyond the master Gambar IV.1, four per-group detail sources (`Layer_Infra_Control`, `Layer_Data`, `Layer_Model`, `Layer_Govern_Obs`) split the same seven layers across the four §IV.2 subsections so each layer group can be read at full size; every chapter figure uses the self-healing `\IfFileExists{figures/X.png}{\includegraphics...}{placeholder box}` pattern so the build stays green until the PNG is rendered, and the placeholder auto-disappears once the figure exists.

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

Each architectural layer that has more than one credible open-source candidate carries a small comparison table in Bab II, immediately after the prose introducing the layer. The pattern is fixed so reviewers can scan across layers:

- 4 candidates per table (the chosen tool plus 3 credible alternatives).
- 4 criteria per table on a 0–2 scale. Criteria are layer-specific, not generic — pick the dimensions that drive the decision for that layer (e.g. *Latensi Rendah* for vector index, *K8s-Native* for orchestration, *Transaksi ACID* for table format).
- Total column sums to /8. The chosen tool holds the unique highest Total in its table and justifies it with a textual paragraph; it must not be hand-waved.
- The scoring rubric is stated once in prose immediately before the first scored table in Bab II (currently `k8s_distribution_comparison`, §2.2.1): 0 = criterion not met or feature absent, 1 = partial support that still needs extra components or carries a meaningful limitation, 2 = fully met by built-in capability. Scores derive from official documentation and project maintenance status. The narrow 3-level scale is deliberate: each level has an explicit justification, avoiding the false precision of a 5-point scale.
- The rubric also anchors the open-source claim: the license criterion follows OSI-approved license status, and stewardship under a neutral foundation (Apache Software Foundation, CNCF, Linux Foundation) counts as supporting evidence of open governance feeding the maturity and community criteria. Only state a foundation affiliation in prose when it is certain (e.g. Kafka under ASF, Valkey under Linux Foundation, OpenBao under Linux Foundation).
- Every scored table carries a textual **Lisensi (Yayasan)** column between the last criterion and Total: the official license plus the steward foundation in parentheses, e.g. `Apache 2.0 (CNCF)`, `MPL 2.0 (LF)`, `BUSL 1.1 (mandiri)`. `mandiri` marks vendor- or community-run projects without a neutral foundation; `komunitas` is reserved for pgvector under the PostgreSQL community. The column is informational only and never changes the Total; the legend paragraph in Bab II says so explicitly. Verified facts to keep: Featureform = MPL 2.0; OpenMetadata = Apache 2.0 under Linux Foundation (March 2026, via Collate); DataHub, Amundsen, Feast, Feathr, Milvus, KServe = LF AI & Data; MLflow, Valkey, OpenBao = LF; SOPS = CNCF; TorchServe = PyTorch Foundation (LF).
- Standard scored-table layout so all 24 tables render identically inside the 14 cm text width: `[!htb]`, `\footnotesize`, `\setlength{\tabcolsep}{3pt}`, columns `m{2.6cm}` (name, left-aligned, header centered via `\multicolumn`), four criteria `m{1.5cm}` centered, `m{2.3cm}` Lisensi (Yayasan), `m{0.9cm}` Total. Long criterion headers break with `\-` or `\allowbreak` instead of widening the column.
- Highest Total = the platform primary pick for the evaluated function. A lower-scoring row may still be deployed in a complementary role (e.g. Flink for streaming beside Spark for batch); the prose around the table must say so explicitly.
- `mlops_maturity_comparison.tex` and `architecture_comparison.tex` are non-scored (color matrix and longtable respectively) and sit outside the rubric.
- Caption above, label `tab:<topic>_comparison`, file `tables/<topic>_comparison.tex`.
- Placement spec is `\begin{table}[!htb]`, never `[H]`. `[H]` blocks text reflow: when the table does not fit the rest of the page it drags a large white gap with it. `[!htb]` lets body text fill the page and moves the table to the top of the next page, which is the agreed layout rule (text fills, table follows; a short last page of a section or chapter is fine). The three MLOps level figures follow the same `[!htb]` rule and sit directly after the first paragraph of the Tingkat Kematangan subsection, in level order 0, 1, 2.

Layers currently covered:

- `k8s_distribution_comparison.tex` — §2.2.1 (Kubernetes distribution: k3s vs k0s vs MicroK8s vs kind)
- `feature_store_comparison.tex` — §2.4
- `offline_storage_comparison.tex`, `online_storage_comparison.tex` — §2.4.2
- `vector_index_comparison.tex` — §2.4.3
- `orchestration_comparison.tex` — §2.5.2
- `tracking_comparison.tex` — §2.5.1
- `serving_comparison.tex` — §2.5.3
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

If there is only one objective, use that objective as the chapter title. Section IV.1 still gives the gambaran umum so the reader sees the whole picture before the detailed sections.

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
- IV.1 contains a system-overview figure and a short description.
- Each Bab V section refers back to the matching Bab IV section.
- Each kesimpulan point answers exactly one tujuan.
- Daftar Singkatan lists only acronyms that actually appear in Bab 1 to Bab 5, alphabetically, each with the chapter of first use; re-run the first-use grep after moving content between chapters (license and foundation acronyms ASF, CNCF, LF, MPL, BSL, BUSL, AGPL, BSD entered via the Lisensi (Yayasan) column and live in Bab II).

### 3.7 Per-Bab template comments (central store)

Chapter files under `chapters/` carry only a minimal pointer comment at the top (max 5 words per line, e.g. `% Bab I Pendahuluan`, `% Template: TEMPLATE_BAB.md`, `% Gaya: WRITING_GUIDE.md`). The full subbab layout, RM/T chain links, and standing notes per bab live ONLY here, so the template survives even if a chapter file is rewritten end-to-end. This section is the single source of truth. Bab I, II, and III headers already follow this convention; trim the remaining Bab IV to VII long headers when each chapter gets its revision pass.

**Bab I — Pendahuluan**

```
- I.1 Latar Belakang         : motivasi domain-agnostic platform DataOps + MLOps
- I.2 Rumusan Masalah        : RM-1..RM-4 (akar isu, bukan turunan tools)
- I.3 Tujuan                 : T-1..T-4, satu lawan satu dengan RM-N
- I.4 Batasan Masalah        : B-1..B-5 (ruang lingkup yang dijaga)
- I.5 Metodologi             : DSRM Peffers et al. (6 fase)
- I.6 Sistematika Penulisan  : peta bab II..VII
Catatan: kripto hanya use-case verifikasi; tidak masuk latar belakang.
```

**Bab II — Studi Literatur**

```
- II.1 DataOps dan MLOps            : definisi, kematangan, integrasi
- II.2 Kubernetes dan Cloud-Native  : orkestrasi, scaling (HPA/VPA/KEDA), operator, runtime
- II.3 Manajemen Data               : Lambda/Kappa, Kafka+Karapace, Flink, Spark+dbt,
                                      lakehouse (Iceberg/Trino), MinIO/lakeFS, PG/MySQL/OpenSearch
- II.4 Layanan Fitur                : Feast, ClickHouse, Valkey, Qdrant, HNSW, point-in-time
- II.5 Siklus Hidup Model           : MLflow, KFP+Argo Workflows, Notebooks/Katib/Trainer, KServe
- II.6 Tata Kelola Data             : DataHub, Great Expectations, OpenLineage
- II.7 Deteksi Drift                : PSI, Kolmogorov-Smirnov, retraining loop
- II.8 Observabilitas               : Prometheus/Loki/Tempo/Grafana/OTel, Sloth, Evidently,
                                      Pyroscope, Pushgateway, OpenCost, Superset
- II.9 GitOps                       : Argo CD, Gitea, Tekton, Argo Rollouts
- II.10 Keamanan Platform           : Dex+oauth2-proxy, SpiceDB, OpenBao+ESO+KES, Istio,
                                      APISIX, Kyverno/OPA, Falco, Trivy, Velero, Chaos Mesh
- II.11 Penelitian Terkait          : posisi platform terhadap pekerjaan terdahulu
Tabel perbandingan: tiap subbab dengan alternatif diakhiri \input{tables/<file>_comparison.tex}
(daftar lengkap pada §2.1 dokumen ini).
Penjelasan tool: setiap tool pada platform/components diberi definisi dan citasi resmi.
```

**Bab III — Analisis Masalah**

```
- III.1 Analisis Kondisi Saat Ini             : tiga sumber tekanan, diurutkan sesuai pemicu pada Bab I
  - III.1.1 Beban Konfigurasi Platform dari Nol     : configure-from-0
  - III.1.2 Biaya Berlangganan Layanan Terkelola    : cloud subscription + trade-off waktu lawan anggaran
  - III.1.3 Efek Domino Fragmentasi Lintas Peran    : pandangan umum fragmentasi DataOps + MLOps (per peran ke Lampiran C)
- III.2 Analisis Kebutuhan                    : identifikasi + KF + KNF (satu lawan satu sub-sistem)
- III.3 Analisis Pemilihan Solusi             : alternatif + penentuan solusi
Catatan:
  - Urutan sub-sub-section di III.1 mengikuti urutan pemicu pada Bab I Latar Belakang.
  - KF berorientasi kemampuan (apa yang dilakukan platform).
  - KNF berorientasi sifat sistem (latensi, ketersediaan, observabilitas, keamanan).
  - Setiap KNF wajib menyebut metrik dan ambang batas yang terukur.
  - Tabel KF (kolom: ID, Kebutuhan, Deskripsi, Tujuan) dan KNF (kolom: ID, Kebutuhan, Deskripsi, Target Metrik, Tujuan) sama-sama memuat kolom Tujuan yang menautkan tiap kebutuhan ke salah satu dari empat tujuan (T-1..T-4), mengikuti pengelompokan uji penerimaan pada Bab VI; untuk KNF kolom ini menunjuk tujuan utama karena KNF bersifat lintas-bidang.
  - Urutan baris (sort subject) yang wajib dijaga: KF diurut menurut lapisan arsitektur (KF-01..04 lapisan fitur, KF-05..10 siklus hidup model dan tata kelola, KF-11..14 lapisan operasional); KNF diurut menurut taksonomi atribut kualitas (kinerja, skalabilitas, keandalan, konsistensi, observability, keamanan, ekstensibilitas, lalu atribut operasional jangka panjang). Urutan ID sengaja tidak mengikuti Tujuan karena keterunutan ke T sudah ditampung kolom Tujuan secara terpisah.
  - ID KF-NN/KNF-NN terkunci satu lawan satu pada SK-F-NN/SK-N-NN di Bab VI dan dirujuk lintas bab; nomor tidak boleh diubah, perubahan urutan dilakukan lewat narasi pengelompokan bukan penomoran ulang.
  - Fragmentasi per peran (busus/dateng/datsci/mleng) dirinci pada Lampiran C agar Bab III tetap ramping.
```

**Bab IV — Perancangan Arsitektur Platform DataOps dan MLOps**

```
- IV.1 Gambaran Umum Sistem        : sintesis arsitektur tujuh lapis + diagram
- IV.2 Perancangan Sub-sistem A    : menjawab T-1 (arsitektur terintegrasi)
- IV.3 Perancangan Sub-sistem B    : menjawab T-2 (tata kelola data)
- IV.4 Perancangan Sub-sistem C    : menjawab T-3 (deteksi drift + PIT)
- IV.5 Perancangan Sub-sistem D    : menjawab T-4 (feature store dual-store)
- IV.6 Alur Kerja End-to-End       : rangkaian sub-sistem ke siklus produksi
Rantai keterhubungan: T-N ↔ IV.N+1 ↔ V.N+1 ↔ Kesimpulan ke-N
Catatan domain-agnostic: arsitektur murni platform; verifikasi kripto ditunda ke Bab V.
```

**Bab V — Implementasi Arsitektur Platform DataOps dan MLOps**

```
- V.1 Gambaran Umum Implementasi    : tumpukan teknologi + topologi cluster
- V.2 Implementasi Sub-sistem A     : memetakan IV.2 ke manifest + konfigurasi
- V.3 Implementasi Sub-sistem B     : memetakan IV.3 (governance + lineage)
- V.4 Implementasi Sub-sistem C     : memetakan IV.4 (drift + PIT)
- V.5 Implementasi Sub-sistem D     : memetakan IV.5 (feature store)
- V.6 Verifikasi Implementasi       : use-case kripto sebagai instans pengujian
Rantai keterhubungan: IV.N ↔ V.N ↔ Kesimpulan ke-N
Catatan use-case: kripto hanya untuk verifikasi jalur, tidak mengubah sifat domain-agnostic.
```

**Bab VI — Evaluasi**

```
- VI.1 Metode Evaluasi              : prosedur uji per tujuan T-1..T-4
- VI.2 Hasil Evaluasi               : metrik kuantitatif (DORA, kualitas, drift, latensi)
- VI.3 Pembahasan Hasil Evaluasi    : interpretasi, keterbatasan, tindak lanjut
Rantai keterhubungan: T-N ↔ VI.1.N ↔ VI.2.N ↔ VI.3.N ↔ Kesimpulan ke-N
Catatan pengisian: bab ini diisi setelah seluruh komponen platform berjalan
stabil pada cluster verifikasi dan data pengamatan kuantitatif tersedia.
```

**Bab VII — Penutup**

```
- VII.1 Kesimpulan : empat poin K1..K4, satu lawan satu dengan T-1..T-4
- VII.2 Saran      : tindak lanjut + arah pengembangan platform berikutnya
Rantai keterhubungan: T-N ↔ K-N ; tidak menambah klaim baru di luar bab sebelumnya
Catatan pengisian: bab ini diisi setelah hasil evaluasi pada Bab VI terkonsolidasi.
```

### 3.8 Chapter lead-in paragraphs

Every chapter opens with one short unnumbered lead-in (1 paragraph, maximum 2) placed directly after the \chapter heading and before the first \section. The lead-in states what the chapter covers and how it connects to the surrounding chapters; it is not a numbered subbab and must not duplicate the Sistematika Penulisan list in Bab I. Bab I through Bab VII all follow this rule (Bab II formerly used a numbered Cakupan section; converted 2026-06).

### 3.9 Section depth and section lead-ins in Bab II

Split a \section into \subsection blocks only when it carries four or more narrative paragraphs covering more than one distinct topic; each resulting subsection must still hold at least two paragraphs. Sections with two or three paragraphs on a single topic stay flat: currently §2.6 Tata Kelola, §2.7 Deteksi Drift, §2.8 Observabilitas, §2.9 GitOps, and §2.11 Penelitian Terkait. Six sections carry subsections: §2.1 DataOps dan MLOps, §2.2 Kubernetes, §2.3 Manajemen Data, §2.4 Layanan Fitur, §2.5 Siklus Hidup Model, and §2.10 Keamanan. Depth stops at \subsection; no \subsubsection is used anywhere in Bab II, so the heading tree is uniformly two levels deep.

Every section that has subsections opens with one short lead-in paragraph (four sentences) placed between the \section heading and the first \subsection. The lead-in names the subsection topics and their reading order, mirroring the chapter lead-in pattern (§3.8) and the proposal's Bab 2 layout; it is navigational only and introduces no factual claim that is not made with a citation inside a subsection. Revision 2026-06: formerly only §2.10 carried such a lead-in; the other five were added, and §2.3 was retitled from "Ingestasi, Streaming, dan Batch" to "Manajemen Data: Ingestasi, Pemrosesan, dan Penyimpanan" so the title covers its three storage subsections. Comparison tables are \input in the subsection whose prose cites them via Tabel~\ref (e.g. tab:feature_store_comparison sits in §2.4.2 where Feast is selected, not in the point-in-time subsection).

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
