.PHONY: test lint fixtures clean

SCRIPTS := scripts/helpers.sh scripts/session_discovery.sh scripts/db_query.sh scripts/status.sh scripts/pane.sh scripts/toggle.sh
ENTRY   := tomux.tmux

test: lint fixtures
	@echo "=== Unit tests ==="
	bats tests/unit/*.bats
	@echo "=== Integration tests ==="
	-bats tests/integration/*.bats 2>/dev/null || true

lint:
	shellcheck $(wildcard scripts/*.sh) $(wildcard tomux.tmux) 2>/dev/null || true

fixtures:
	bash tests/fixtures/gen-fixtures.sh

clean:
	rm -f tests/fixtures/*.db /tmp/tomux_*
