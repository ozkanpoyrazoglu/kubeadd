PREFIX ?= $(HOME)/.local

.PHONY: help install uninstall test

help:
	@echo "make install     install kubeadd into $(PREFIX)/bin (override with PREFIX=...)"
	@echo "make uninstall   remove it again"
	@echo "make test        run the test suite"

install:
	PREFIX="$(PREFIX)" sh ./install.sh

uninstall:
	PREFIX="$(PREFIX)" sh ./install.sh --uninstall

test:
	python3 -m unittest discover -s tests -v
