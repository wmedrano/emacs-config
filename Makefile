EMACS ?= emacs
ELPA_DIRS := $(filter-out elpa/archives/,$(wildcard elpa/*/))
LOAD_PATH := $(addprefix -L ,$(ELPA_DIRS)) -L user-lisp

.PHONY: jj-test jj-byte-compile jj-checkdoc cargo-byte-compile disasm-byte-compile monorepo-byte-compile byte-compile clean test

jj-test:
	$(EMACS) --batch $(LOAD_PATH) -l ert -l jj -l jj-diff -l jj-describe -l user-lisp/jj-tests.el -f ert-run-tests-batch-and-exit

jj-byte-compile:
	$(EMACS) --batch $(LOAD_PATH) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile user-lisp/jj.el user-lisp/jj-diff.el user-lisp/jj-describe.el
	rm -f user-lisp/jj.elc user-lisp/jj-diff.elc user-lisp/jj-describe.elc

jj-checkdoc:
	$(EMACS) --batch $(LOAD_PATH) -l checkdoc --eval "(dolist (f '(\"user-lisp/jj.el\" \"user-lisp/jj-diff.el\" \"user-lisp/jj-describe.el\")) (checkdoc-file f))"

cargo-byte-compile:
	$(EMACS) --batch $(LOAD_PATH) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile user-lisp/cargo.el
	rm -f user-lisp/cargo.elc

disasm-byte-compile:
	$(EMACS) --batch $(LOAD_PATH) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile user-lisp/disasm.el
	rm -f user-lisp/disasm.elc

monorepo-byte-compile:
	$(EMACS) --batch $(LOAD_PATH) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile user-lisp/monorepo.el
	rm -f user-lisp/monorepo.elc

byte-compile: jj-byte-compile cargo-byte-compile disasm-byte-compile monorepo-byte-compile

clean:
	rm -f user-lisp/*.elc

test: jj-test
