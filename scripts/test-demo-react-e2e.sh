#!/usr/bin/env bash
#
# Run demo-react Playwright E2E tests. Skips the MoonBit JS build step when
# CANOPY_SKIP_MOON_BUILD=1 (CI uses pre-built artifacts from build-js).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [[ "${CANOPY_SKIP_MOON_BUILD:-0}" != "1" ]]; then
    "$SCRIPT_DIR/build-js.sh"
fi

echo "Running demo-react Playwright E2E..."
cd examples/demo-react

if [ ! -d node_modules ]; then
    echo "Installing demo-react dependencies..."
    npm ci
fi

CI="${CI:-1}" npx playwright test "$@"
