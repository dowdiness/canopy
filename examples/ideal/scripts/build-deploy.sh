#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IDEAL_ROOT="$REPO_ROOT/examples/ideal"
WEB_ROOT="$IDEAL_ROOT/web"

echo "=== Building Canopy Ideal Editor ==="

# 1. Init submodules
echo "→ Submodules..."
cd "$REPO_ROOT"
git submodule update --init --recursive

# 2. Moon update + build (release JS)
echo "→ MoonBit dependencies..."
cd "$IDEAL_ROOT"
moon update

echo "→ MoonBit build (release JS)..."
moon build --target js --release

# 3. Vite build
echo "→ Vite build..."
cd "$WEB_ROOT"
npm ci --ignore-scripts 2>/dev/null || npm install
npm run build

echo "=== Build complete: $WEB_ROOT/dist/ ==="

# 4. Deploy (if --deploy flag passed)
if [[ "${1:-}" == "--deploy" ]]; then
  echo "→ Deploying to Cloudflare Pages..."
  npx wrangler pages deploy dist --project-name canopy-editor
  echo "=== Deployed ==="
fi
