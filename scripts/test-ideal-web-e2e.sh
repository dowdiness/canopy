#!/usr/bin/env bash
#
# Run Ideal editor Playwright E2E specs (non-performance). CI uses pre-built
# artifacts from the build-js job. The editor-response perf spec is gated separately by
# .github/workflows/benchmark.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Running Ideal editor Playwright E2E..."
cd apps/ideal/web

if [ ! -d node_modules ]; then
    echo "Installing Ideal editor web dependencies..."
    npm ci
fi

DEFAULT_SPECS=()
while IFS= read -r spec; do
    DEFAULT_SPECS+=("$spec")
done < <(find e2e -maxdepth 1 -name '*.spec.ts' ! -name 'editor-response.perf.spec.ts' | sort)

if [ "$#" -eq 0 ]; then
    set -- "${DEFAULT_SPECS[@]}"
fi

CI="${CI:-1}" npx playwright test "$@"
