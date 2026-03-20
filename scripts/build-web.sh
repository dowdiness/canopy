#!/usr/bin/env bash
# Build script for web deployment
# Automates: moon build --target js && cp _build/js/release/build/crdt.js examples/web/public/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔨 Building MoonBit for JavaScript target..."
moon build --target js --release

echo "📦 Copying JS build to examples/web/public/..."
mkdir -p examples/web/public
cp _build/js/release/build/crdt.js examples/web/public/

echo "✅ MoonBit build copied successfully!"
echo ""
echo "Next steps:"
echo "  cd examples/web"
echo "  npm run build    # Build for production"
echo "  npm run dev      # Start dev server"
