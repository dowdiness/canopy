#!/usr/bin/env bash
# Run moon check and moon fmt for all modules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

FAILED=()

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Checking code quality for all modules                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Function to check a directory
check_module() {
    local dir=$1
    local name=$2

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Checking: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -d "$dir" ]; then
        # Run moon check
        echo "Running moon check..."
        if "$SCRIPT_DIR/run-moon-module.sh" check "$dir"; then
            echo "  ✅ moon check passed"
        else
            echo "  ❌ moon check failed"
            FAILED+=("$name (check)")
        fi

        # Run moon fmt check
        echo "Running moon fmt check..."
        if "$SCRIPT_DIR/run-moon-module.sh" fmt-check "$dir"; then
            echo "  ✅ Code is formatted"
        else
            echo "  ❌ Code is not formatted (changes detected)"
            FAILED+=("$name (format)")
        fi
    else
        echo "⚠️  $name: Directory not found, skipping"
    fi
    echo ""
}

# Check main module
check_module "." "Main Module (canopy)"

# Check submodules
check_module "event-graph-walker" "event-graph-walker"
check_module "loom/loom" "loom"
check_module "svg-dsl" "svg-dsl"
check_module "graphviz" "graphviz"

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Check Summary                                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ ${#FAILED[@]} -eq 0 ]; then
    echo "✅ All checks passed!"
    exit 0
else
    echo "❌ Failed checks:"
    for check in "${FAILED[@]}"; do
        echo "  - $check"
    done
    exit 1
fi
