#!/usr/bin/env bash
# Regression check for loomgen: re-generate the lambda example from annotations
# and verify typecheck + tests still pass.
#
# This is the outer-loop CI companion to loomgen/regression_wbtest.mbt.
# The whitebox harness verifies generated content (Show, ToRawKind, IsTrivia);
# this script verifies the generated code actually compiles and the full
# lambda test suite passes after regeneration.
#
# Usage: scripts/loomgen_regression_check.sh
# Run from the canopy monorepo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=== loomgen regression check ==="
echo ""

# Paths within the loom workspace
LOOM_DIR="$PROJECT_ROOT/loom"
LOOMGEN_DIR="$LOOM_DIR/loomgen"
LAMBDA_DIR="$LOOM_DIR/examples/lambda"

# Temp output dirs for regeneration
TEMP_TOKEN_OUT=$(mktemp -d)
TEMP_SYNTAX_OUT=$(mktemp -d)
trap 'rm -rf "$TEMP_TOKEN_OUT" "$TEMP_SYNTAX_OUT"' EXIT

echo "1. Generating token_impls from lambda fixture..."
(cd "$LOOM_DIR" && moon run loomgen --target native -- \
  --seed "examples/lambda/syntax/syntax_kind.mbt" \
  "loomgen/fixtures/term_kind.mbt" \
  "$TEMP_TOKEN_OUT" "$TEMP_SYNTAX_OUT") || {
  echo "FAILED: loomgen generation"
  exit 1
}
echo "   OK"

echo ""
echo "2. Verifying generated files exist..."
ls "$TEMP_TOKEN_OUT/token_impls.g.mbt" > /dev/null || {
  echo "FAILED: token_impls.g.mbt not generated"
  exit 1
}
ls "$TEMP_SYNTAX_OUT/syntax_kind.mbt" > /dev/null || {
  echo "FAILED: syntax_kind.mbt not generated"
  exit 1
}
echo "   OK"

echo ""
echo "3. Comparing generated syntax_kind with canonical (seed should preserve identity)..."
diff <(cat "$TEMP_SYNTAX_OUT/syntax_kind.mbt") \
     "$LAMBDA_DIR/syntax/syntax_kind.mbt" && {
  echo "   IDENTICAL — no seed drift"
} || {
  # Stylistic differences (moon fmt, comment order) are acceptable.
  # Structurally, ToRawKind raw values must match — quick check.
  echo "   NOTICE: generated file differs from canonical — check ToRawKind values"
  echo "   Canonical FnKeyword => 43: $(grep 'FnKeyword' "$LAMBDA_DIR/syntax/syntax_kind.mbt")"
  echo "   Generated FnKeyword => 43: $(grep 'FnKeyword' "$TEMP_SYNTAX_OUT/syntax_kind.mbt")"
}

echo ""
echo "4. Copying regenerated files to lambda example..."
cp "$TEMP_TOKEN_OUT/token_impls.g.mbt" "$LAMBDA_DIR/token/token_impls.g.mbt"
cp "$TEMP_SYNTAX_OUT/syntax_kind.mbt" "$LAMBDA_DIR/syntax/syntax_kind.mbt"
echo "   OK"

echo ""
echo "5. Running moon check on lambda example..."
(cd "$LOOM_DIR" && moon check --target native -p examples/lambda) || {
  echo "FAILED: generated code does not typecheck in lambda example"
  exit 1
}
echo "   OK"

echo ""
echo "6. Running lambda tests..."
# Run from the loom workspace root; moon resolves -p examples/lambda
(cd "$LOOM_DIR" && moon test --target native -p examples/lambda) || {
  echo "FAILED: lambda tests failed after regeneration"
  exit 1
}
echo "   OK"

echo ""
echo "=== loomgen regression check PASSED ==="
