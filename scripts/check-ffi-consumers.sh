#!/usr/bin/env bash

# CI gate for the TypeScript consumers of the Canopy FFI artifacts.
# When the FFI, shared adapter, or any direct TypeScript consumer changes,
# run the same install + check/build fan-out as the web-build CI jobs so drift
# in the generated JS/TS surfaces is caught before merge.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

base_ref="${1:-origin/main}"

cd "$PROJECT_ROOT"

if git diff --quiet "$base_ref...HEAD" -- \
  modules/canopy/ffi \
  apps/canvas/main \
  adapters/editor \
  apps/web \
  apps/ideal/web \
  apps/canvas/web \
  apps/block-editor/web \
  apps/relay-server \
  examples/demo-react \
  examples/prosemirror
then
  echo "check-ffi-consumers: no changes under $base_ref...HEAD in FFI consumers; skipping"
  exit 0
fi

run_consumer() {
  local label="$1"
  local prefix="$2"
  local script="$3"

  echo "==> [$label] npm --prefix $prefix ci"
  npm --prefix "$prefix" ci
  echo "==> [$label] npm --prefix $prefix run $script"
  npm --prefix "$prefix" run "$script"
}

run_consumer "adapter" "adapters/editor" "test:unit"
echo "==> [adapter] npm --prefix adapters/editor run typecheck:cm6"
npm --prefix adapters/editor run typecheck:cm6
run_consumer "web" "apps/web" "typecheck"
echo "==> [web] npm --prefix apps/web run build"
npm --prefix apps/web run build
run_consumer "demo-react" "examples/demo-react" "build"
# `tsc -b` rewrites this tracked cache across local TypeScript versions; it is
# not review evidence and must not dirty the exact candidate HEAD.
git checkout -- examples/demo-react/tsconfig.tsbuildinfo
run_consumer "prosemirror" "examples/prosemirror" "build"
run_consumer "ideal-web" "apps/ideal/web" "build"
run_consumer "canvas-web" "apps/canvas/web" "build"
run_consumer "block-editor-web" "apps/block-editor/web" "build"
run_consumer "relay-server" "apps/relay-server" "typecheck"

echo "check-ffi-consumers: all FFI consumers passed."
