# Makefile for LaTeX document compilation
# Usage: make, make clean, make build, make view

# Document name (without extension)
DOC = report
BUILD_DIR = build

# Source directories
FRONTMATTER_DIR = frontmatter
CHAPTERS_DIR = chapters
APPENDICES_DIR = appendices
TABLES_DIR = tables
FIGURES_DIR = figures
LISTINGS_DIR = listings
ALGORITHMS_DIR = algorithms

# Dependencies
MAIN_TEX = $(DOC).tex
FRONTMATTER_FILES = $(wildcard $(FRONTMATTER_DIR)/*.tex)
CHAPTER_FILES = $(wildcard $(CHAPTERS_DIR)/*.tex)
APPENDIX_FILES = $(wildcard $(APPENDICES_DIR)/*.tex)
TABLE_FILES = $(wildcard $(TABLES_DIR)/*.tex)
LISTING_FILES = $(wildcard $(LISTINGS_DIR)/*.tex)
ALGORITHM_FILES = $(wildcard $(ALGORITHMS_DIR)/*.tex)
BIB_FILES = $(wildcard *.bib)
FIGURE_FILES = $(wildcard $(FIGURES_DIR)/*)

# All dependencies
DEPS = $(MAIN_TEX) $(FRONTMATTER_FILES) $(CHAPTER_FILES) $(APPENDIX_FILES) \
       $(TABLE_FILES) $(LISTING_FILES) $(ALGORITHM_FILES) $(BIB_FILES) $(FIGURE_FILES)

# Default target
all: $(DOC).pdf

# Build PDF using XeLaTeX and Biber
$(DOC).pdf: $(DEPS)
	@echo "Building $(DOC).pdf..."
	@mkdir -p $(BUILD_DIR)
	@echo "Running XeLaTeX (1st pass)..."
	xelatex -output-directory=$(BUILD_DIR) $(DOC).tex
	@echo "Running Biber for bibliography..."
	biber $(BUILD_DIR)/$(DOC)
	@echo "Running XeLaTeX (2nd pass)..."
	xelatex -output-directory=$(BUILD_DIR) $(DOC).tex
	@echo "Running XeLaTeX (3rd pass)..."
	xelatex -output-directory=$(BUILD_DIR) $(DOC).tex
	@cp $(BUILD_DIR)/$(DOC).pdf .
	@echo "Build complete! Output: $(DOC).pdf"

# Alternative target name
build: $(DOC).pdf

# Clean auxiliary files
clean:
	@echo "Cleaning auxiliary files..."
	@rm -rf $(BUILD_DIR)
	@rm -f *.aux *.bbl *.bcf *.blg *.brf *.fdb_latexmk *.fls *.idx *.ilg *.ind *.lof *.log *.lol *.lot *.out *.run.xml *.synctex.gz *.toc *.xdv
	@echo "Clean complete!"

# Clean everything including PDF
distclean: clean
	@rm -f $(DOC).pdf

# View PDF (if available)
view: $(DOC).pdf
	@if command -v xdg-open >/dev/null 2>&1; then \
		xdg-open $(DOC).pdf; \
	elif command -v evince >/dev/null 2>&1; then \
		evince $(DOC).pdf; \
	else \
		echo "No PDF viewer found. Please open $(DOC).pdf manually."; \
	fi

# Quick build without verbose output
quick:
	@mkdir -p $(BUILD_DIR)
	@xelatex -output-directory=$(BUILD_DIR) -interaction=nonstopmode $(DOC).tex > /dev/null
	@biber $(BUILD_DIR)/$(DOC) > /dev/null 2>&1
	@xelatex -output-directory=$(BUILD_DIR) -interaction=nonstopmode $(DOC).tex > /dev/null
	@cp $(BUILD_DIR)/$(DOC).pdf .
	@echo "Quick build complete: $(DOC).pdf"

# Show project structure
structure:
	@echo "Project structure:"
	@echo "├── $(DOC).tex (main document)"
	@echo "├── daftar-pustaka.bib (bibliography)"
	@echo "├── $(FRONTMATTER_DIR)/ (front matter)"
	@echo "├── $(CHAPTERS_DIR)/ (chapter files)"
	@echo "├── $(APPENDICES_DIR)/ (appendices)"
	@echo "├── $(TABLES_DIR)/ (table files)"
	@echo "├── $(FIGURES_DIR)/ (figures)"
	@echo "├── $(LISTINGS_DIR)/ (code listings)"
	@echo "├── $(ALGORITHMS_DIR)/ (algorithm pseudocode)"
	@echo "└── $(BUILD_DIR)/ (build output)"

# Help
help:
	@echo "Available targets:"
	@echo "  all/build    - Build the PDF document (verbose)"
	@echo "  quick        - Quick build without verbose output"
	@echo "  clean        - Remove auxiliary files"
	@echo "  distclean    - Remove all generated files including PDF"
	@echo "  view         - Open the PDF in default viewer"
	@echo "  structure    - Show project file structure"
	@echo "  help         - Show this help message"

.PHONY: all build clean distclean view help structure quick
