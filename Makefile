EMACS = emacs
ifdef emacs
	EMACS = $(emacs)
endif
EMACS_CMD := $(EMACS) -Q -batch -L .

.PHONY: clean
clean:
	find . -name "*.elc" -exec rm -f {} \;

.PHONY: parser
parser:
	$(EMACS_CMD) -L ~/.emacs.d/emacs-parser/ -l phps-mode-lexer.el -l admin/phps-mode-automation.el -eval "(progn (require 'parser-generator-lr-export)(setq debug-on-signal t)(setq debug-on-error t)(phps-mode-automation))"

.PHONY: compile
compile:
	find . -name "*.el" -exec $(EMACS_CMD) -f batch-byte-compile {} \;

.PHONY: tests
tests: test-integration test-lexer test-lex-analyzer test-parser test-syntax-table

.PHONY: test-integration
test-integration:
	$(EMACS_CMD) -l test/phps-mode-test-integration.el

.PHONY: test-lex-analyzer
test-lex-analyzer:
	$(EMACS_CMD) -l test/phps-mode-test-lex-analyzer.el

.PHONY: test-lexer
test-lexer:
	$(EMACS_CMD) -l test/phps-mode-test-lexer.el -f "phps-mode-test-lexer"

.PHONY: benchmark-lexer
benchmark-lexer:
	$(EMACS_CMD) -l test/phps-mode-test-lexer.el -f "phps-mode-test-lexer-benchmark"

.PHONY: test-parser
test-parser:
	$(EMACS_CMD) -l test/phps-mode-test-parser.el

.PHONY: test-syntax-table
test-syntax-table:
	$(EMACS_CMD) -l test/phps-mode-test-syntax-table.el
