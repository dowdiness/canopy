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

# Accept either manifest format: moon.mod.json (legacy) or moon.mod (the
# experimental TOML format that event-graph-walker main adopted). moon reads
# both as dependencies and as a primary module under NEW_MOON_MOD=0.
if [ ! -f "$PROJECT_ROOT/$MODULE_DIR/moon.mod.json" ] &&
   [ ! -f "$PROJECT_ROOT/$MODULE_DIR/moon.mod" ]; then
    echo "Module root not found: $MODULE_DIR (expected moon.mod.json or moon.mod at $PROJECT_ROOT/$MODULE_DIR)" >&2
    exit 1
fi

cd "$PROJECT_ROOT/$MODULE_DIR"

# --warn-list=-20 exempts the `try?` deprecation ([0020], MoonBit 0.10.0) from
# --deny-warn. try? is still used ecosystem-wide (canopy, loom, event-graph-walker,
# moonbitlang/core) and its replacement idiom is not yet stabilized; all OTHER
# warnings remain denied. Remove the exemption once try? is migrated everywhere.
DENY_WARN_FLAGS=(--deny-warn --warn-list=-20)

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
