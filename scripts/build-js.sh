#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Building canopy JavaScript artifacts..."
# graphviz is now a workspace member — its JS artifacts land in the
# workspace _build/, not in graphviz/_build/.
moon build --target js --release
echo "Building canvas JavaScript artifacts..."
(cd "$PROJECT_ROOT/examples/canvas" && moon build --target js --release --target-dir "$PROJECT_ROOT/_build")

EXPECTED_ARTIFACTS=(
    "_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js"
    "_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/lambda/moonbit.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/json/json.js"
    "_build/js/release/build/dowdiness/canopy/ffi/json/json.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/json/moonbit.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js"
    "_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/markdown/moonbit.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js"
    "_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.d.ts"
    "_build/js/release/build/dowdiness/canopy/ffi/jsx/moonbit.d.ts"
    "_build/js/release/build/dowdiness/graphviz/browser/browser.js"
    "_build/js/release/build/dowdiness/graphviz/browser/browser.d.ts"
    "_build/js/release/build/dowdiness/canopy-canvas/main/main.js"
    "_build/js/release/build/dowdiness/canopy-canvas/main/main.d.ts"
    "_build/js/release/build/dowdiness/canopy-canvas/main/moonbit.d.ts"
)

for artifact in "${EXPECTED_ARTIFACTS[@]}"; do
    if [ ! -f "$artifact" ]; then
        echo "Missing expected artifact: $artifact" >&2
        exit 1
    fi
done

echo "JavaScript artifacts are up to date."
