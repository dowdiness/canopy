#!/usr/bin/env bash
# Run tests for all modules in the monorepo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

FAILED=()

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running tests for all modules                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Function to run tests in a directory
run_test() {
    local dir=$1
    local name=$2

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -d "$dir" ]; then
        if "$SCRIPT_DIR/run-moon-module.sh" test "$dir"; then
            echo "✅ $name: PASSED"
        else
            echo "❌ $name: FAILED"
            FAILED+=("$name")
        fi
    else
        echo "⚠️  $name: Directory not found, skipping"
    fi
    echo ""
}

# Test main module
run_test "modules/canopy" "Main Module (canopy)"

# Test submodules
run_test "deps/event-graph-walker" "event-graph-walker"
run_test "deps/loom/loom" "loom"
run_test "deps/svg-dsl" "svg-dsl"
run_test "deps/graphviz" "graphviz"

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Summary                                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ ${#FAILED[@]} -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Failed modules:"
    for module in "${FAILED[@]}"; do
        echo "  - $module"
    done
    exit 1
fi
