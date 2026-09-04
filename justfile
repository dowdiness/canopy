set shell := ["nu", "-c"]

moon_update := justfile_directory() + "/scripts/moon-update.sh"

# Show this help message
help:
    @just --list

# Verify CLAUDE.md is a symlink to AGENTS.md
check-agent-doc-links:
    @bash ./scripts/check-agent-doc-links.sh

# Run tests for main module
test:
    @./scripts/run-moon-module.sh test modules/canopy

# Run tests for the root MoonBit workspace
test-all:
    @moon test

# Verify the repository-level contract used by every pre-commit route
hook-repository-contract *sentinel:
    @bash ./scripts/check-agent-doc-links.sh

# Format staged MoonBit sources and regenerate interfaces before commit.
hook-moonbit-prepare:
    @nu ./scripts/local-validation.nu prepare-commit

# Check and test changed MoonBit packages before push.
hook-moonbit-validate *sentinel:
    @nu ./scripts/local-validation.nu validate-push

# Validate active documentation contracts selected by Lefthook.
hook-documentation-contract:
    @bash ./scripts/check-agent-doc-links.sh
    @./scripts/check-documentation-lifecycle.sh

# Run existing lightweight contracts for the Waku application.
hook-web-contract:
    @npm --prefix apps/web run typecheck
    @npm --prefix apps/web run check:boundaries
    @npm --prefix apps/web run test:boundaries

# Run the main module's MoonBit check from Lefthook
hook-moonbit-check:
    @./scripts/run-moon-module.sh check modules/canopy

# Run the main module's MoonBit format check from Lefthook
hook-moonbit-format-check:
    @./scripts/run-moon-module.sh fmt-check modules/canopy

# Validate configured-origin reachability for the checkout or a pushed gitlink tree
hook-submodule-reachability commit="":
    @nu scripts/check-submodule-reachability.nu --commit "{{ commit }}"

# Validate tooling files selected by Lefthook
hook-tooling-contract:
    @just --unstable --fmt --check
    @just --dry-run pre-commit
    @just --dry-run hook-submodule-reachability
    @node -e 'JSON.parse(require("fs").readFileSync(".claude/settings.json", "utf8"))'
    @bash -n .cursor/install.sh .githooks/pre-commit .githooks/pre-push scripts/install-hooks.sh scripts/test-install-hooks.sh scripts/test-lefthook-pre-commit-routing.sh scripts/test-lefthook-pre-push-routing.sh scripts/test-local-validation.sh scripts/test-submodule-reachability.sh scripts/run-submodule-reachability.sh scripts/validate-ci-yaml.sh
    @nu --ide-check 100 scripts/check-moon-registry-bootstrap.nu
    @nu --ide-check 100 scripts/check-moon-interfaces.nu
    @nu scripts/check-moon-registry-bootstrap.nu
    @nu --ide-check 100 scripts/check-submodule-reachability.nu
    @nu --ide-check 100 scripts/install-hooks.nu
    @nu --ide-check 100 scripts/local-validation.nu
    @lefthook validate

# Run moon check for main module
check: hook-repository-contract hook-moonbit-check

# Run strict checks and formatting for the root MoonBit workspace
check-all:
    @bash ./scripts/check-agent-doc-links.sh
    @./scripts/check-strict.sh
    @env NEW_MOON_MOD=0 moon fmt --check

# Format code with moon fmt
fmt:
    cd modules/canopy; moon fmt
    cd modules/canopy; moon info

# Check formatting for the main module without keeping changes
fmt-check: hook-repository-contract hook-moonbit-format-check

# Build main module (default target)
build:
    @moon build --release

# Build JavaScript artifacts for canopy + graphviz
build-js:
    @./scripts/build-js.sh

# Build web application (MoonBit + Waku)
build-web:
    @./scripts/build-web.sh

# Run Waku web Playwright E2E tests
test-web-e2e:
    @./scripts/test-web-e2e.sh

# Run canvas Playwright E2E tests
test-canvas-e2e:
    @./scripts/test-canvas-e2e.sh

# Run demo-react Playwright E2E tests
test-demo-react-e2e:
    @./scripts/test-demo-react-e2e.sh

# Run realistic ideal editor response benchmarks
benchmark-ideal-editor-response:
    @cd apps/ideal/web; npm run test:perf

# Build tree-sitter-moonbit for ast-grep custom-language support
setup-ast-grep:
    @./scripts/setup-ast-grep-moonbit.sh

# Build JS artifacts and start the Waku web dev server
web-dev: build-js
    @cd apps/web; npm run dev

# Clean build artifacts
clean:
    @moon clean
    @rm -rf target _build
    @rm -rf apps/web/dist release

# Run the path-aware local pre-commit gate through Lefthook
pre-commit:
    @lefthook run pre-commit

# Install git pre-commit hooks through Lefthook
install-hooks:
    @nu scripts/install-hooks.nu

# Run all CI checks locally
ci: check-all test-all

# Refresh MoonBit registry dependencies explicitly for local development
registry-refresh:
    @bash "{{ moon_update }}"

# Run the throwaway Loomark Document-lead cache lifecycle prototype
prototype-loomark-document-lead-cache viewport="narrow":
    @node apps/loomark/prototypes/document-lead-cache/cli.mjs --{{ viewport }}

# Run the throwaway Loomark Document-lead graph against the Rabbita browser runtime
prototype-loomark-document-lead-rabbita:
    @apps/loomark/prototypes/document-lead-rabbita/run.sh

# Run benchmarks
bench:
    @moon bench --release
    @cd deps/event-graph-walker; moon bench --release

# Package release artifacts (version is positional)
release-artifacts version:
    @test -n "{{ version }}"
    @./scripts/package-release.sh "{{ version }}"
