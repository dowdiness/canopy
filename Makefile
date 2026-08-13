.PHONY: help test test-all check check-all fmt fmt-check check-agent-doc-links build build-js build-web test-web-e2e test-canvas-e2e test-demo-react-e2e benchmark-ideal-editor-response setup-ast-grep web-dev clean pre-commit install-hooks ci update bench release-artifacts

.DEFAULT_GOAL := help

# Keep GNU Make as a compatibility entry point; recipe logic lives in justfile.
test test-all check check-all fmt fmt-check check-agent-doc-links \
build build-js build-web test-web-e2e test-canvas-e2e test-demo-react-e2e \
benchmark-ideal-editor-response setup-ast-grep web-dev clean pre-commit \
install-hooks ci update bench:
	@just $@

help:
	@just help

release-artifacts:
	@test -n "$(VERSION)" || { echo "VERSION is required (example: make release-artifacts VERSION=v0.2.0)" >&2; exit 1; }
	@just release-artifacts "$(VERSION)"
