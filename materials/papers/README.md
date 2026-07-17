# IEEE Conference Paper

Six-page IEEE conference paper distilled from the thesis in `../reports/`.

Title: Development of an Integrated DataOps and MLOps Platform Architecture on Kubernetes Using Open Source Tools

## Build

```bash
cd materials/papers
make          # pdflatex, bibtex, pdflatex, pdflatex
make check    # prints the gates
make clean    # removes aux files, keeps the PDF
```

Or by hand:

```bash
pdflatex -interaction=nonstopmode paper.tex
bibtex paper
pdflatex -interaction=nonstopmode paper.tex
pdflatex -interaction=nonstopmode paper.tex
```

Two passes after bibtex are needed because the first resolves the citation labels and the second settles the page references.

## Why pdflatex and not xelatex

The thesis in `../reports/` builds with xelatex and biber. This paper deliberately does not.

`IEEEtran.cls` sets `\rmdefault` to `ptm` unconditionally, because IEEE requires Times. Under xelatex the default encoding is TU, in which `ptm` has no font shape, so NFSS falls back to Latin Modern and only emits a font warning:

```
LaTeX Font Warning: Font shape `TU/ptm/m/n' undefined
(Font)              using `TU/lmr/m/n' instead
```

The document still compiles with zero errors, so the failure is silent. The typeface is wrong and the metrics differ, which changes line breaking and therefore the page count against a six-page limit. Verified on this machine with `pdffonts`:

- pdflatex embeds `NimbusRomNo9L`, Type 1, which is Times and what IEEE asks for.
- xelatex embeds `LMRoman`, which is not.

IEEE also requires Type 1 vector fonts. pdflatex produces Type 1 directly. A xelatex plus fontspec workaround produces CID Type 0C instead, so pdflatex is the safer path.

## Why bibtex and not biber

IEEE distributes `IEEEtran.bst` and the IEEEtran HOWTO documents `\bibliographystyle{IEEEtran}` with bibtex. The HOWTO never mentions biblatex or biber. `cite.sty`, which IEEE ships in its own conference template, is a hard error alongside biblatex:

```
! Package biblatex Error: Incompatible package 'cite'.
```

`biblatex-ieee` exists and works, but it is a third-party reimplementation rather than an IEEE product, and some venues require the `.bbl` produced by `IEEEtran.bst`.

## Vendored class files

`IEEEtran.cls` v1.8b and `IEEEtran.bst` v1.14 are committed here, fetched from CTAN. Neither is installed on the build machine, and `texlive-publishers` would need a system package install. Vendoring keeps the paper self-contained and reproducible.

## Layout

```
paper.tex               root, preamble, author block
sections/               one file per section
  00_abstract.tex       abstract and index terms
  01_introduction.tex   problem, pressures, contribution
  02_related_work.tex   four prior works and the gap
  03_method.tex         DSRM phases, four objectives
  04_architecture.tex   layer derivation, selection, bridges, subsystems
  05_implementation.tex environment, GitOps pattern, use case
  06_evaluation.tex     tiers, results, cost, threats
  07_conclusion.tex     findings and next steps
tables/                 one file per table
figures/                DataOps_MLOps_Flow.png, from ../reports/figures/, flattened here
references.bib          only the 20 entries actually cited
```

## Figure

The architecture figure spans both columns as a `figure*` at `width=\textwidth`. A single column shrinks its node labels to about 3.2 pt, which is unreadable in print, so the two-column form is deliberate.

The PNG is 1588 by 816 pixels, about 222 ppi at text width. The eraser.io export carried an alpha channel with a transparent background; pdflatex embeds that as an image plus a soft mask, which IEEE PDF checkers flag. The copy here is flattened onto white, plain RGB, no mask, visually identical. For sharper print, re-export `../reports/diagrams/DataOps_MLOps_Flow.eraser` at twice the scale, replace the PNG, and reflatten.

## Page numbers

Pages carry a bottom center number through `\pagestyle{plain}`, which is the IEEE manuscript convention for drafts and review copies. IEEE camera-ready conference papers omit page numbers because the proceedings paginate. Before a camera-ready submission, delete the two pagestyle lines after `\maketitle` in `paper.tex`.

## Template compliance

Checked against the official IEEE conference template, version of June 2024. Author block follows the template shape: one italic department line, one italic organization line, city and country, email. Labels such as T-1 were removed from the body, objectives are named descriptively. Abbreviations are spelled out at first use, prefixes non and sub are joined, the figure caption ends with a period, table captions do not, index terms are alphabetical, every decimal carries a leading zero.

Deliberate deviations from the template: `booktabs` tables instead of fully ruled ones, `url` for reference line breaking, `array` for ragged right table cells, which is what removes underfull boxes inside narrow columns. `algorithmic` and `xcolor` are omitted because the template only uses them for algorithm listings and its own guidance text. `dblfloatfix` was tried and removed, both double-column floats sit at page tops, which needs no package.

## Bibliography scope

The thesis `.bib` holds 164 entries, 108 of them `@misc` and 78 of those tool documentation. This paper cites 20, extracted verbatim from `../reports/daftar-pustaka.bib` so nothing is retyped. Tool documentation is left out because IEEE convention names tools in prose rather than in numbered references, and keeping it would spend most of the reference budget on things that are not arguments. Two `@misc` entries are kept because each carries a claim rather than a product choice, namely the Kubernetes documentation and the Google Cloud MLOps maturity levels. Their Indonesian access notes were converted to IEEE form.

## What the paper claims

The contribution is the conjunction of four properties, matching the four objectives. No individual element is claimed as new.

The thesis states its novelty twice with two different triads, in Bab 2 and Bab 3. Each is a three-of-four selection from the same four objectives. The paper states all four, which is traceable to both and invents nothing.

## Evidence discipline

The thesis uses three tiers, namely structural, functional, and instrumented, so that no claim outruns its evidence. Of 26 requirements, 2 are functional, 5 are instrumented with the target unmeasured, and 19 are structural. The paper reports that distribution rather than rounding it up.

Bab 7 of the thesis uses "terbukti" (proven) where the Bab 6 status tables say "structural". Where the two disagree, this paper follows Bab 6, which is the more conservative reading and matches the thesis's own stated vocabulary.

Numbers carry their limits. The drift result comes from one controlled 2-sigma injection on one feature and shows the trigger chain fires, not detection accuracy. Vector latency was measured on an empty collection. The p99 of 157 ms reported in the thesis is a ramp-down artefact and is deliberately not printed here. Cost totals rest on an assumed labour allocation, which the paper says plainly.

The thesis uses Indonesian number formatting, where a comma is the decimal separator. Figures were converted, so PSI `18,107` is written 18.107 and `USD 39.543,16` is written USD 39,543.16.

## Two chapters, two lettering schemes

Bab 3 scores four architecture alternatives A to D and selects B, open source on Kubernetes. Bab 6 prices three provisioning options A to C, where C is that same open source design. Alternative B and Option C are the same thing. This paper names the options descriptively and never by letter.
