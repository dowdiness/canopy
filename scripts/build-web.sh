#!/usr/bin/env bash

# Build the apps/web app against the current MoonBit JS outputs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

"$SCRIPT_DIR/build-js.sh"

echo "Building apps/web..."
cd apps/web

if [ ! -d node_modules ]; then
    echo "Installing web dependencies..."
    npm ci
fi

npm run build
