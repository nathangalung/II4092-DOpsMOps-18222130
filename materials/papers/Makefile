# IEEE paper build
# Engine is pdflatex, not xelatex. See paper.tex header for why.

DOC = paper
SECTIONS = $(wildcard sections/*.tex)
TABLES = $(wildcard tables/*.tex)
FIGURES = $(wildcard figures/*)
DEPS = $(DOC).tex $(SECTIONS) $(TABLES) $(FIGURES) references.bib IEEEtran.cls IEEEtran.bst

all: $(DOC).pdf

# bibtex needs the aux from a first pass
$(DOC).pdf: $(DEPS)
	pdflatex -interaction=nonstopmode $(DOC).tex
	bibtex $(DOC)
	pdflatex -interaction=nonstopmode $(DOC).tex
	pdflatex -interaction=nonstopmode $(DOC).tex

# All counts must be 0, pages exactly 6
check: $(DOC).pdf
	@echo "errors:    $$(grep -c '^!' $(DOC).log || true)   (expect 0)"
	@echo "Overfull:  $$(grep -c 'Overfull' $(DOC).log || true)   (expect 0)"
	@echo "Underfull: $$(grep -c 'Underfull' $(DOC).log || true)   (expect 0)"
	@echo "warnings:  $$(grep -cE 'LaTeX Warning|Font Warning|Package [a-z0-9]+ Warning|pdfTeX warning' $(DOC).log || true)   (expect 0)"
	@echo "undef ref: $$(grep -c 'LaTeX Warning: Reference' $(DOC).log || true)   (expect 0)"
	@echo "undef cit: $$(grep -c 'LaTeX Warning: Citation' $(DOC).log || true)   (expect 0)"
	@echo "pages:     $$(pdfinfo $(DOC).pdf | awk '/^Pages/{print $$2}')   (expect 6)"

clean:
	rm -f $(DOC).aux $(DOC).log $(DOC).out $(DOC).bbl $(DOC).blg $(DOC).spl

distclean: clean
	rm -f $(DOC).pdf

.PHONY: all check clean distclean
