# TA Final Report

LaTeX source for ITB STI final-year thesis (Tugas Akhir / TA).

## Build

```bash
make          # full build (xelatex + biber + xelatex x2)
make quick    # fast single-pass rebuild
make clean    # drop aux artifacts
make view     # open report.pdf
```

Requires XeLaTeX + Biber + `biblatex-chicago` + `fontspec`.

## Directory layout

```
reports/
├── report.tex             # main entry point
├── daftar-pustaka.bib     # bibliography (BibLaTeX)
├── report.pdf             # built output
├── Makefile               # build recipes
├── frontmatter/           # title page, abstract, ToC, etc.
│   ├── 01_Halaman_Judul.tex
│   ├── 02_Lembar_Pengesahan.tex
│   ├── 03_Pernyataan_Orisinalitas.tex
│   ├── 04_Pernyataan_Penggunaan_AI.tex
│   ├── 05_Abstrak.tex
│   ├── 06_Kata_Pengantar.tex
│   ├── 07_Daftar_Isi.tex
│   ├── 07a_Daftar_Lampiran.tex
│   ├── 08_Daftar_Gambar.tex
│   ├── 09_Daftar_Tabel.tex
│   ├── 10_Daftar_Persamaan.tex
│   ├── 11_Daftar_Algoritma.tex
│   ├── 12_Daftar_Listing.tex
│   ├── 13_Daftar_Simbol.tex
│   └── 14_Daftar_Singkatan.tex
├── chapters/              # main body Bab I-VII
│   ├── Bab_1.tex          # Pendahuluan
│   ├── Bab_2.tex          # Studi Pustaka
│   ├── Bab_3.tex          # Analisis
│   ├── Bab_4.tex          # Perancangan
│   ├── Bab_5.tex          # Implementasi
│   ├── Bab_6.tex          # Evaluasi
│   └── Bab_7.tex          # Penutup
├── appendices/            # lampiran
│   ├── Lampiran_A.tex
│   └── Lampiran_B.tex
├── tables/                # \input-able .tex tables
├── figures/               # images (.png/.jpg)
├── listings/              # code listings
└── algorithms/            # algorithm pseudocode

# `build/` is created on demand by `make` (xelatex aux output).

```

## Naming convention

- ASCII only, no spaces, underscores between words.
- Front matter: `NN_Title_Case.tex` (zero-padded numeric prefix).
- Chapters: `Bab_N.tex` (matches `proposals/`).
- Appendices: `Lampiran_X.tex`.

Mirror convention with `proposals/` so both projects feel uniform.

## Writing guide

Before drafting a chapter, read `WRITING_GUIDE.md` in this directory. It covers:

- Designing figures (key message, audience, graph choice, colour, cognitive load).
- When a table beats a figure, and how to lay tables out.
- Keeping rumusan masalah, tujuan, Bab IV, Bab V, and Kesimpulan synchronised.
- A drafting order that prevents late-stage structural rewrites.

The guide adapts Fujii (2026, *Nature Human Behaviour*) for figures and the ITB STI TA conventions for chapter structure.
