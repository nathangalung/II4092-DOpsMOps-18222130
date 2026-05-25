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
- 4 criteria per table on a 1–5 scale. Criteria are layer-specific, not generic — pick the dimensions that drive the decision for that layer (e.g. *Latensi Rendah* for vector index, *K8s-Native* for orchestration, *Transaksi ACID* for table format).
- Total column sums to /20. The chosen tool should justify its 20 with a textual paragraph; it must not be hand-waved.
- Caption above, label `tab:<topic>_comparison`, file `tables/<topic>_comparison.tex`.

Layers currently covered:

- `feature_store_comparison.tex` — §2.5
- `offline_storage_comparison.tex`, `online_storage_comparison.tex` — §2.5.2
- `vector_index_comparison.tex` — §2.5.3
- `orchestration_comparison.tex` — §2.6.2
- `tracking_comparison.tex` — §2.6.1
- `serving_comparison.tex` — §2.6.3
- `data_processing_comparison.tex` — §2.4
- `lakehouse_format_comparison.tex` — §2.4.5
- `metadata_comparison.tex` — §2.7
- `monitoring_comparison.tex` — §2.9
- `gitops_comparison.tex` — §2.10
- `identity_comparison.tex` — §2.11 (Identity Provider: Dex vs Keycloak vs Authelia vs Authentik)
- `secrets_comparison.tex` — §2.11 (Secrets manager: OpenBao vs Vault vs Sealed Secrets vs SOPS)
- `service_mesh_comparison.tex` — §2.11 (Service mesh: Istio vs Linkerd vs Cilium vs Consul Connect)
- `policy_comparison.tex` — §2.11 (Policy engine: Kyverno vs OPA Gatekeeper vs jsPolicy vs Kubewarden)
- `mlops_maturity_comparison.tex` — §2.2.3
- `architecture_comparison.tex` — §2.12 (longtable; *Aspek × Saat Ini × Diusulkan × Keuntungan × Referensi*, the only table allowed to use a different shape because it summarises across the whole architecture).

When adding a new comparison table, follow the same shape and place an `\input{tables/<file>}` directive immediately after the introductory paragraph that names the alternatives.

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

### 3.5 Quick checklist before submission

Run through this list when the draft is close to done.

- Number of rumusan masalah equals number of tujuan equals number of Bab IV section pairs equals number of Bab V section pairs equals number of kesimpulan points.
- No objective contains the verbs "evaluate", "test", or "measure".
- Bab IV title names the artefact, not a generic word.
- IV.1 contains a system-overview figure and a short description.
- Each Bab V section refers back to the matching Bab IV section.
- Each kesimpulan point answers exactly one tujuan.

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
