#!/usr/bin/env bash
# test-focus.sh — run tests only for the package containing the edited file
# Used as a PostToolUse hook for Edit|Write on .mbt files
#
# Reads hook JSON from stdin: {"tool_input":{"file_path":"/abs/path/to/file.mbt"}}
# Exits 0 on success, 1 on test failure

set -euo pipefail

# Extract file path from hook stdin
FILE=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
if [ -z "$FILE" ]; then
  exit 0
fi

# Only run for .mbt files
case "$FILE" in
  *.mbt) ;;
  *) exit 0 ;;
esac

# Skip test files themselves (avoid infinite loops if hook triggers on test output)
case "$FILE" in
  *_test.mbt|*_wbtest.mbt|*_benchmark.mbt) exit 0 ;;
esac

# Find the repo root (nearest directory with moon.mod.json)
DIR=$(dirname "$FILE")
ROOT="$DIR"
while [ "$ROOT" != "/" ]; do
  if [ -f "$ROOT/moon.mod.json" ]; then
    break
  fi
  ROOT=$(dirname "$ROOT")
done

if [ ! -f "$ROOT/moon.mod.json" ]; then
  exit 0  # Not in a moon project
fi

# Get module name from moon.mod.json
MOD_NAME=$(jq -r '.name' "$ROOT/moon.mod.json")

# Get relative path from root to the file's directory
REL_DIR=$(realpath --relative-to="$ROOT" "$DIR")

# Build package name: module_name/relative_path
# Handle root package (file directly in module root)
if [ "$REL_DIR" = "." ]; then
  PKG="$MOD_NAME"
else
  PKG="$MOD_NAME/$REL_DIR"
fi

# Run focused test
cd "$ROOT"
OUTPUT=$(moon test -p "$PKG" 2>&1) || {
  EC=$?
  # Count pass/fail from output
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"test-focus: FAIL in $PKG\\n$(echo "$OUTPUT" | tail -5)\"}}"
  exit 0  # Don't block — just report
}

# Extract test count from output
TESTS=$(echo "$OUTPUT" | grep -oP 'Total tests: \K\d+' || echo "?")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"test-focus: $TESTS tests passed in $PKG\"}}"
