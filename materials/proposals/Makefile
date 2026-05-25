# Makefile for LaTeX document compilation
# Usage: make, make clean, make build, make view

# Document name (without extension)
DOC = Proposal
BUILD_DIR = build

# Source directories
CHAPTERS_DIR = chapters
TABLES_DIR = tables
FIGURES_DIR = figures
REFERENCES_DIR = references

# Dependencies
MAIN_TEX = $(DOC).tex
CHAPTER_FILES = $(wildcard $(CHAPTERS_DIR)/*.tex)
TABLE_FILES = $(wildcard $(TABLES_DIR)/*.tex)
BIB_FILES = $(wildcard *.bib) $(wildcard $(REFERENCES_DIR)/*.bib)
FIGURE_FILES = $(wildcard $(FIGURES_DIR)/*)

# All dependencies
DEPS = $(MAIN_TEX) $(CHAPTER_FILES) $(TABLE_FILES) $(BIB_FILES) $(FIGURE_FILES)

# Default target
all: $(DOC).pdf

# Build PDF using XeLaTeX and Biber
$(DOC).pdf: $(DEPS)
	@echo "Building $(DOC).pdf..."
	@echo "Dependencies: chapters, tables, figures, and bibliography files"
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

# Show project structure
structure:
	@echo "Project structure:"
	@echo "├── $(DOC).tex (main document)"
	@echo "├── DafPus.bib (bibliography)"
	@echo "├── $(CHAPTERS_DIR)/ (chapter files)"
	@find $(CHAPTERS_DIR) -name "*.tex" -exec echo "│   ├── {}" \; 2>/dev/null || echo "│   └── (no chapter files)"
	@echo "├── $(TABLES_DIR)/ (table files)"
	@find $(TABLES_DIR) -name "*.tex" -exec echo "│   ├── {}" \; 2>/dev/null | head -5 || echo "│   └── (no table files)"
	@find $(TABLES_DIR) -name "*.tex" | wc -l | xargs -I {} echo "│   └── (and {} total table files)"
	@echo "├── $(FIGURES_DIR)/ (figures)"
	@find $(FIGURES_DIR) -name "*" -type f -exec echo "│   ├── {}" \; 2>/dev/null | head -3 || echo "│   └── (no figures)"
	@echo "└── $(BUILD_DIR)/ (build output)"

# Quick build without verbose output
quick:
	@mkdir -p $(BUILD_DIR)
	@xelatex -output-directory=$(BUILD_DIR) -interaction=nonstopmode $(DOC).tex > /dev/null
	@biber $(BUILD_DIR)/$(DOC) > /dev/null 2>&1
	@xelatex -output-directory=$(BUILD_DIR) -interaction=nonstopmode $(DOC).tex > /dev/null
	@cp $(BUILD_DIR)/$(DOC).pdf .
	@echo "Quick build complete: $(DOC).pdf"

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
	@echo ""
	@echo "Project uses:"
	@echo "  - XeLaTeX for compilation"
	@echo "  - Biber for bibliography processing"
	@echo "  - Modular structure with chapters/, tables/, figures/"

.PHONY: all build clean distclean view help structure quick