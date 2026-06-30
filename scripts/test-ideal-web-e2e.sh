#!/usr/bin/env bash
#
# Run Ideal editor Playwright E2E specs (non-performance). Skips the MoonBit
# dep update step when CANOPY_SKIP_MOON_BUILD=1 (CI uses pre-built artifacts
# from build-js). The editor-response perf spec is gated separately by
# .github/workflows/benchmark.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [[ "${CANOPY_SKIP_MOON_BUILD:-0}" != "1" ]]; then
    (
        cd examples/ideal
        # Retry-wrapped: transient mooncakes CDN 403 (issue #467) auto-recovers.
        "$SCRIPT_DIR/moon-update.sh"
    )
fi

echo "Running Ideal editor Playwright E2E..."
cd examples/ideal/web

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
