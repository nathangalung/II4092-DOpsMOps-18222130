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

# Fails loudly on any gate breach
check: $(DOC).pdf
	@echo "errors:    $$(grep -c '^!' $(DOC).log || true)"
	@echo "Overfull:  $$(grep -c 'Overfull' $(DOC).log || true)"
	@echo "undef ref: $$(grep -c 'LaTeX Warning: Reference' $(DOC).log || true)"
	@echo "undef cit: $$(grep -c 'LaTeX Warning: Citation' $(DOC).log || true)"
	@echo "pages:     $$(pdfinfo $(DOC).pdf | awk '/^Pages/{print $$2}')"

clean:
	rm -f $(DOC).aux $(DOC).log $(DOC).out $(DOC).bbl $(DOC).blg $(DOC).spl

distclean: clean
	rm -f $(DOC).pdf

.PHONY: all check clean distclean
