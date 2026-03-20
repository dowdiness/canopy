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
    _build/js/release/build/canopy.js \
    _build/js/release/build/canopy.d.ts \
    _build/js/release/build/moonbit.d.ts \
    moon.mod.json \
    moon.pkg \
    README.md \
    README.mbt.md \
    LICENSE

tar -czf "$RELEASE_DIR/canopy-web-${VERSION}.tar.gz" \
    -C "$PROJECT_ROOT/examples/web/dist" .

echo "Release artifacts created in $RELEASE_DIR"
