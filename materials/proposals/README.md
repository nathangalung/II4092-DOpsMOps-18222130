# TA Proposal

LaTeX source for ITB STI final-year thesis proposal.

## Build

```bash
make          # full build (xelatex + biber + xelatex x2)
make quick    # fast single-pass rebuild
make clean    # drop aux artifacts
make view     # open Proposal.pdf
```

Requires XeLaTeX + Biber + `biblatex-chicago` + `fontspec`.

## Directory layout

```
proposals/
├── Proposal.tex           # main entry point
├── DafPus.bib             # bibliography (BibLaTeX)
├── Proposal.pdf           # built output
├── Makefile               # build recipes
├── LICENSE
├── chapters/              # Bab 1-5
│   └── Bab_N.tex
├── tables/                # \input-able .tex tables
├── figures/               # images (.png/.jpg)
├── references/            # literature PDFs (citations)
└── build/                 # aux build artifacts (gitignored)
```

## Naming convention

- ASCII only, no spaces, underscores between words.
- Chapters: `Bab_N.tex`.
- Tables: snake_case `.tex` files, `\input{tables/name}` from chapter.
- Figures: descriptive `Snake_Case.png`.
