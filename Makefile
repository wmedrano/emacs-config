EMACS ?= emacs
ELPA_DIRS := $(shell for d in elpa/*/; do if [ "$$d" = "elpa/archives/" ] || [ "$$d" = "elpa/gnupg/" ]; then continue; fi; b=$${d%/}; b=$${b##*/}; pkg=$$(echo "$$b" | sed -E 's/-[0-9].*//'); echo "$$pkg $$d"; done | sort -k1,1 -k2,2V | awk '{latest[$$1]=$$2} END {for (p in latest) printf "%s ", latest[p]}')
LOAD_PATH := $(addprefix -L ,$(ELPA_DIRS)) -L user-lisp

JJ_FILES := user-lisp/jj.el user-lisp/jj-diff.el user-lisp/jj-describe.el
CHECKDOC_FILES := $(JJ_FILES) user-lisp/eglot-extra.el user-lisp/cargo-extra.el user-lisp/disasm.el user-lisp/monorepo.el user-lisp/paths-extra.el
BYTE_COMPILE_FILES := $(CHECKDOC_FILES)

.PHONY: all jj-test checkdoc byte-compile test

all: jj-test checkdoc byte-compile

jj-test:
	$(EMACS) --batch $(LOAD_PATH) -l ert -l jj -l jj-diff -l jj-describe -l user-lisp/jj-tests.el -f ert-run-tests-batch-and-exit

checkdoc:
	$(EMACS) --batch $(LOAD_PATH) -l checkdoc --eval "(let ((checkdoc-diagnostic-buffer \"*checkdoc-diagnostics*\")) (with-current-buffer (get-buffer-create checkdoc-diagnostic-buffer) (erase-buffer)) (dolist (f '($(foreach f,$(CHECKDOC_FILES),\"$(f)\"))) (with-current-buffer (find-file-noselect f) (checkdoc-current-buffer t))) (with-current-buffer checkdoc-diagnostic-buffer (goto-char (point-min)) (when (re-search-forward \"\\.el:[0-9]+:\" nil t) (princ (buffer-string)) (kill-emacs 1))))"

byte-compile:
	tmpdir=$$(mktemp -d); $(EMACS) --batch $(LOAD_PATH) --eval "(setq byte-compile-error-on-warn t)" --eval "(setq byte-compile-dest-file-function (lambda (f) (expand-file-name (concat (file-name-nondirectory (file-name-sans-extension f)) \".elc\") \"$$tmpdir\")))" -f batch-byte-compile $(BYTE_COMPILE_FILES); st=$$?; rm -rf "$$tmpdir"; exit $$st

test: jj-test
