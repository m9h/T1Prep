# Build main.pdf from main.pnw via Pweave + tectonic.
#
# main.pnw → (pweave) → main.tex → (tectonic) → main.pdf
#
# Tectonic bundles TeX Live and handles bibtex + multi-pass builds
# automatically. Single-binary install (no apt texlive).

PWEAVE   ?= pweave
TECTONIC ?= $(shell command -v tectonic || echo ~/.local/bin/tectonic)

main.pdf: main.tex refs.bib
	$(TECTONIC) main.tex

main.tex: main.pnw paper_helpers.py
	$(PWEAVE) -f tex main.pnw

clean:
	rm -f main.tex main.aux main.bbl main.blg main.log main.out main.toc \
	      main.fls main.fdb_latexmk main.synctex.gz main.pdf \
	      figures/*.pdf figures/*.png

watch:
	while inotifywait -e modify main.pnw paper_helpers.py refs.bib 2>/dev/null; do \
	    $(MAKE) main.pdf; \
	done

.PHONY: clean watch
