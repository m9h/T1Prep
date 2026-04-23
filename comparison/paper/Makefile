# Build main.pdf from main.pnw via Pweave.
#
# main.pnw → (pweave) → main.tex → (pdflatex) → main.pdf
#
# Figures and tables are generated from the current feature parquets.
# Edit main.pnw, then `make` to re-weave + re-render.

PWEAVE ?= pweave
PDFLATEX ?= pdflatex
BIBTEX ?= bibtex

main.pdf: main.tex refs.bib
	$(PDFLATEX) -interaction=nonstopmode main.tex >/dev/null
	$(BIBTEX) main
	$(PDFLATEX) -interaction=nonstopmode main.tex >/dev/null
	$(PDFLATEX) -interaction=nonstopmode main.tex >/dev/null

main.tex: main.pnw
	$(PWEAVE) -f tex main.pnw

clean:
	rm -f main.tex main.aux main.bbl main.blg main.log main.out main.toc \
	      main.fls main.fdb_latexmk main.synctex.gz \
	      figures/*.pdf figures/*.png

.PHONY: clean
