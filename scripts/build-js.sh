#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Building canopy JavaScript artifacts..."
moon build --target js --release

echo "Building graphviz JavaScript artifacts..."
(
    cd graphviz
    moon build --target js --release
)

EXPECTED_ARTIFACTS=(
    "_build/js/release/build/canopy.js"
    "_build/js/release/build/canopy.d.ts"
    "_build/js/release/build/moonbit.d.ts"
    "graphviz/_build/js/release/build/browser/browser.js"
    "graphviz/_build/js/release/build/browser/browser.d.ts"
)

for artifact in "${EXPECTED_ARTIFACTS[@]}"; do
    if [ ! -f "$artifact" ]; then
        echo "Missing expected artifact: $artifact" >&2
        exit 1
    fi
done

echo "JavaScript artifacts are up to date."
