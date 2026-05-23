#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <check|test|fmt-check|ci|bench> <module-dir>" >&2
    exit 1
fi

ACTION="$1"
MODULE_DIR="$2"

if [ ! -f "$PROJECT_ROOT/$MODULE_DIR/moon.mod.json" ]; then
    echo "Module root not found: $MODULE_DIR (expected moon.mod.json at $PROJECT_ROOT/$MODULE_DIR)" >&2
    exit 1
fi

cd "$PROJECT_ROOT/$MODULE_DIR"

# Warning [20] = "Use Debug instead of Show for debugging purposes". The latest
# MoonBit compiler reports this on ~150 sites across canopy core (relay/,
# editor/, …) that pre-date the Show-on-container deprecation. Cleanup is
# tracked in #334; suppress here so CI stays green on the latest compiler
# under --deny-warn. Other warnings remain hard errors.
DENY_WARN_FLAGS=(--deny-warn --warn-list "-20")

case "$ACTION" in
    check)
        moon check "${DENY_WARN_FLAGS[@]}"
        ;;
    test)
        moon test --release
        ;;
    fmt-check)
        moon fmt --check
        ;;
    ci)
        moon update
        moon check "${DENY_WARN_FLAGS[@]}"
        moon test --release
        ;;
    bench)
        moon update
        moon bench --release
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
