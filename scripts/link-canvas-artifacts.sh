#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SOURCE="$PROJECT_ROOT/_build"
DEST="$PROJECT_ROOT/apps/canvas/_build"
ARTIFACT="$SOURCE/js/release/build/dowdiness/canopy-canvas/main/main.js"

[ -f "$ARTIFACT" ] || {
  echo "Missing Canvas artifact: $ARTIFACT" >&2
  exit 1
}

ln -sfn "$SOURCE" "$DEST"
[ -f "$DEST/js/release/build/dowdiness/canopy-canvas/main/main.js" ]
echo "ok: Canvas artifacts linked at $DEST"
