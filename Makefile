.PHONY: test build lint check mod-check package-check package-curl-smoke source-smoke android-check help install-deps clean codd codd-install codd-scan codd-validate codd-gunkan

# Default target
help:
	@echo "Multi-CLI Shogun - Development Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  make test          - Run bats unit tests"
	@echo "  make test-int      - Run bats integration tests"
	@echo "  make build         - Run build_instructions.sh"
	@echo "  make lint          - Run shellcheck on lib/ and scripts/"
	@echo "  make check         - Run build + diff check (CI equivalent)"
	@echo "  make mod-check     - Run package checks + cURL smoke + source smoke + Android check"
	@echo "  make package-check - Run package prepublish checks"
	@echo "  make package-curl-smoke - Install release package through cURL in a temp HOME"
	@echo "  make source-smoke  - Run detached source checkout runtime smoke"
	@echo "  make android-check - Run Android unit tests + debug build"
	@echo "  make codd          - Run CoDD validate"
	@echo "  make codd-gunkan   - Run Gunkan CoDD audit wrapper"
	@echo "  make install-deps  - Install test dependencies (bats, helpers)"
	@echo "  make clean         - Clean test artifacts"
	@echo ""

# Run unit tests
test:
	@echo "Running unit tests..."
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "ERROR: bats not installed. Run 'make install-deps' first."; \
		exit 1; \
	fi
	@if ls tests/*.bats 1>/dev/null 2>&1; then \
		echo "--- Root-level tests ---"; \
		bats tests/*.bats --timing; \
	fi
	@if [ -d tests/unit ] && ls tests/unit/*.bats 1>/dev/null 2>&1; then \
		echo "--- Unit tests ---"; \
		bats tests/unit/ --timing; \
	fi

# Run integration tests
test-int:
	@echo "Running integration tests (Claude only)..."
	@if [ ! -d tests/integration ]; then \
		echo "ERROR: tests/integration directory not found"; \
		exit 1; \
	fi
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "ERROR: bats not installed. Run 'make install-deps' first."; \
		exit 1; \
	fi
	bats tests/integration/ --filter-tags '!copilot,!codex' --timing

# Run all tests
test-all: test test-int

# Build instructions (Phase 2 feature)
build:
	@echo "Building instruction files..."
	@if [ -f scripts/build_instructions.sh ]; then \
		bash scripts/build_instructions.sh; \
	else \
		echo "WARNING: scripts/build_instructions.sh not found"; \
		echo "This will be available in Phase 2 (template generation)"; \
	fi

# Run shellcheck linter
lint:
	@echo "Running shellcheck..."
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not installed"; \
		echo "Install: sudo apt-get install shellcheck (Linux) or brew install shellcheck (Mac)"; \
		exit 1; \
	fi
	@echo "Checking lib/..."
	@if [ -d lib ]; then \
		find lib -name '*.sh' -type f -exec shellcheck {} \; ; \
	fi
	@echo "Checking scripts/..."
	@if [ -d scripts ]; then \
		find scripts -name '*.sh' -type f -exec shellcheck {} \; ; \
	fi
	@echo "✓ Shellcheck passed"

# Build + diff check (CI equivalent)
check: build
	@echo "Checking for uncommitted instruction changes..."
	@if [ -f scripts/build_instructions.sh ] && [ -d instructions/generated ] && [ -d .opencode/agents ]; then \
		if git diff --exit-code instructions/generated/ .opencode/agents/; then \
			echo "✓ Generated instructions and OpenCode agents are in sync"; \
		else \
			echo "ERROR: Generated instructions or OpenCode agents are out of sync!"; \
			echo "Run 'make build' and commit the changes."; \
			exit 1; \
		fi; \
	else \
		echo "WARNING: build_instructions.sh, instructions/generated, or .opencode/agents not found"; \
		echo "Skipping diff check (Phase 2 feature)"; \
	fi

mod-check: package-check package-curl-smoke source-smoke android-check

package-curl-smoke:
	bash -euo pipefail -c '\
		root="$$(pwd -P)"; \
		run_id="$${SHOGUNATE_PACKAGE_CURL_SMOKE_RUN_ID:-package-curl-smoke-$$(date +%Y%m%d%H%M%S)}"; \
		work="$$root/runtime_sandboxes/$$run_id"; \
		home="$$work/home"; \
		prefix="$$home/.shogunate/shogunate"; \
		bin="$$home/.local/bin"; \
		project="$$work/project"; \
		tmp="$$work/tmp"; \
		package="$${SHOGUNATE_PACKAGE_CURL_SMOKE_PACKAGE:-$$work/multi-agent-shognate-package.tar.gz}"; \
		mkdir -p "$$home" "$$bin" "$$project" "$$tmp"; \
		trap '\''rm -rf "$$work"'\'' EXIT; \
		if [ -z "$${SHOGUNATE_PACKAGE_CURL_SMOKE_PACKAGE:-}" ]; then \
			git archive --worktree-attributes --format=tar.gz --prefix=multi-agent-shognate/ HEAD -o "$$package"; \
		else \
			test -f "$$package"; \
		fi; \
		SHOGUNATE_PACKAGE_URL="file://$$package" HOME="$$home" TMPDIR="$$tmp" \
			curl -fsSL "file://$$root/shogunate_mod/package/bootstrap.sh" \
			| SHOGUNATE_PACKAGE_URL="file://$$package" HOME="$$home" TMPDIR="$$tmp" \
				bash -s -- --prefix "$$prefix" --bin-dir "$$bin" --no-setup; \
		test -x "$$bin/shogunate"; \
		test -f "$$prefix/shogunate_mod/manifest.yaml"; \
		PATH="$$bin:$$PATH" HOME="$$home" "$$bin/shogunate" help >/dev/null; \
		PATH="$$bin:$$PATH" HOME="$$home" "$$bin/shogunate" --project "$$project" where > "$$work/where.txt"; \
		grep -F "Project:  $$(cd "$$project" && pwd -P)" "$$work/where.txt" >/dev/null; \
		test -f "$$home/.shogunate/workspaces/"*/queue/runtime/target_project; \
		PATH="$$bin:$$PATH" HOME="$$home" "$$bin/shogunate" --project "$$project" pair --help >/dev/null; \
		echo "[PASS] package cURL smoke passed"; \
	'

source-smoke:
	bash shogunate_mod/runtime/source_smoke.sh

android-check:
	cd android && ./gradlew --no-daemon -Dkotlin.compiler.execution.strategy=in-process -Pkotlin.compiler.execution.strategy=in-process testDebugUnitTest assembleDebug

package-check:
	bash shogunate_mod/package/prepublish_check.sh

codd:
	bash scripts/codd_check.sh validate

codd-install:
	bash scripts/codd_check.sh install

codd-scan:
	bash scripts/codd_check.sh scan

codd-validate:
	bash scripts/codd_check.sh validate

codd-gunkan:
	bash scripts/codd_check.sh gunkan

# Install test dependencies
install-deps:
	@echo "Installing test dependencies..."
	@echo "1. Installing bats-core..."
	@if command -v npm >/dev/null 2>&1; then \
		npm install -g bats; \
	else \
		echo "ERROR: npm not found. Install Node.js first."; \
		echo "Alternatively: brew install bats-core (Mac) or apt-get install bats (Linux)"; \
		exit 1; \
	fi
	@echo "2. Setting up bats helpers..."
	@mkdir -p tests/test_helper
	@if [ ! -d tests/test_helper/bats-support ]; then \
		git clone --depth 1 https://github.com/bats-core/bats-support tests/test_helper/bats-support; \
	fi
	@if [ ! -d tests/test_helper/bats-assert ]; then \
		git clone --depth 1 https://github.com/bats-core/bats-assert tests/test_helper/bats-assert; \
	fi
	@echo "3. Checking venv + PyYAML..."
	@if [ ! -f .venv/bin/python3 ]; then \
		echo "WARNING: .venv not found. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"; \
	elif ! .venv/bin/python3 -c "import yaml" 2>/dev/null; then \
		echo "WARNING: PyYAML not in venv. Run: .venv/bin/pip install -r requirements.txt"; \
	fi
	@echo "✓ Dependencies installed"

# Clean test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@find tests -name '*.tap' -type f -delete 2>/dev/null || true
	@echo "✓ Cleaned"

# Quick development workflow
dev: lint test
	@echo "✓ Development checks passed"
