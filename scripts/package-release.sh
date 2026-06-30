#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

VERSION="$1"
RELEASE_DIR="$PROJECT_ROOT/release"

mkdir -p "$RELEASE_DIR"

tar -czf "$RELEASE_DIR/canopy-moonbit-${VERSION}.tar.gz" \
    -C "$PROJECT_ROOT" \
    _build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js \
    _build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.d.ts \
    _build/js/release/build/dowdiness/canopy/ffi/lambda/moonbit.d.ts \
    _build/js/release/build/dowdiness/canopy/ffi/json/json.js \
    _build/js/release/build/dowdiness/canopy/ffi/json/json.d.ts \
    _build/js/release/build/dowdiness/canopy/ffi/json/moonbit.d.ts \
    _build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js \
    _build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.d.ts \
    _build/js/release/build/dowdiness/canopy/ffi/markdown/moonbit.d.ts \
    moon.mod \
    moon.pkg \
    README.md \
    README.mbt.md \
    LICENSE

tar -czf "$RELEASE_DIR/canopy-web-${VERSION}.tar.gz" \
    -C "$PROJECT_ROOT/examples/web/dist" .

echo "Release artifacts created in $RELEASE_DIR"
