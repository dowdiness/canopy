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

DENY_WARN_FLAGS=(--deny-warn)

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
        # Retry-wrapped: transient mooncakes CDN 403 (issue #467) auto-recovers.
        "$SCRIPT_DIR/moon-update.sh"
        moon check "${DENY_WARN_FLAGS[@]}"
        moon test --release
        ;;
    bench)
        "$SCRIPT_DIR/moon-update.sh"
        moon bench --release
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
