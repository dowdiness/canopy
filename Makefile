.PHONY: help test test-all check check-all fmt fmt-check check-agent-doc-links build build-js build-web test-web-e2e test-demo-react-e2e clean install-hooks release-artifacts

help: ## Show this help message
	@echo "Canopy - Development Tasks"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

check-agent-doc-links: ## Verify CLAUDE.md is a symlink to AGENTS.md
	@bash ./scripts/check-agent-doc-links.sh

test: ## Run tests for main module
	@./scripts/run-moon-module.sh test .

test-all: ## Run tests for all modules (including submodules)
	@./scripts/test-all.sh

check: ## Run moon check for main module
	@bash ./scripts/check-agent-doc-links.sh
	@./scripts/run-moon-module.sh check .

check-all: ## Run moon check and fmt for all modules
	@bash ./scripts/check-agent-doc-links.sh
	@./scripts/check-all.sh

fmt: ## Format code with moon fmt
	moon fmt
	moon info

fmt-check: ## Check formatting for the main module without keeping changes
	@bash ./scripts/check-agent-doc-links.sh
	@./scripts/run-moon-module.sh fmt-check .

build: ## Build main module (default target)
	moon build --release

build-js: ## Build JavaScript artifacts for canopy + graphviz
	@./scripts/build-js.sh

build-web: ## Build web application (MoonBit + Vite)
	@./scripts/build-web.sh

test-web-e2e: ## Run web Playwright E2E tests
	@./scripts/test-web-e2e.sh

test-demo-react-e2e: ## Run demo-react Playwright E2E tests
	@./scripts/test-demo-react-e2e.sh

web-dev: build-js ## Build JS artifacts and start the web dev server
	@cd examples/web && npm run dev

clean: ## Clean build artifacts
	moon clean
	rm -rf target _build
	rm -rf examples/web/dist release

install-hooks: ## Install git pre-commit hooks
	@./scripts/install-hooks.sh

ci: check-all test-all ## Run all CI checks locally

update: ## Update MoonBit dependencies
	moon update
	cd event-graph-walker && moon update
	cd loom/loom && moon update
	cd svg-dsl && moon update
	cd graphviz && moon update

bench: ## Run benchmarks
	moon bench --release
	cd event-graph-walker && moon bench --release

release-artifacts: ## Package release artifacts (set VERSION=x.y.z)
	@test -n "$(VERSION)" || (echo "VERSION is required" && exit 1)
	@./scripts/package-release.sh "$(VERSION)"

.DEFAULT_GOAL := help
