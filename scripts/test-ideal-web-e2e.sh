#!/usr/bin/env bash

# Build the Ideal editor MoonBit JS output and run the non-performance
# Playwright E2E specs. The editor-response perf spec is gated separately by
# .github/workflows/benchmark.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

(
    cd examples/ideal
    # Retry-wrapped: transient mooncakes CDN 403 (issue #467) auto-recovers.
    "$SCRIPT_DIR/moon-update.sh"
)

echo "Running Ideal editor Playwright E2E..."
cd examples/ideal/web

if [ ! -d node_modules ]; then
    echo "Installing Ideal editor web dependencies..."
    npm ci
fi

# Disable workspace mode for the JS build that vite-plugin-moonbit kicks off.
# When examples/ideal is a moon.work member, `moon build --target js` only
# emits wasm-gc artifacts (moon picks the workspace target over ideal's
# `preferred-target: js`), so vite can't find the JS output it imports.
# Tracked as #335; remove once moon honors per-member preferred-target.
export MOON_WORK=off

DEFAULT_SPECS=()
while IFS= read -r spec; do
    DEFAULT_SPECS+=("$spec")
done < <(find e2e -maxdepth 1 -name '*.spec.ts' ! -name 'editor-response.perf.spec.ts' | sort)

if [ "$#" -eq 0 ]; then
    set -- "${DEFAULT_SPECS[@]}"
fi

CI="${CI:-1}" npx playwright test "$@"
