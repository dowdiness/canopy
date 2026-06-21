#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <check|check-lenient|test|fmt-check|ci|ci-lenient|bench> <module-dir>" >&2
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

# Keep mixed-manifest modules buildable while Canopy still has legacy
# moon.mod.json path-dependency exceptions. This mode accepts both moon.mod and
# moon.mod.json without requiring every local path dependency to become a
# moon.work member.
export NEW_MOON_MOD="${NEW_MOON_MOD:-0}"

DENY_WARN_FLAGS=(--deny-warn)

# Vendored submodules built standalone (event-graph-walker, loom) still use the
# deprecated `try?` ([0020], MoonBit 0.10.0); canopy does not own their source
# and cannot migrate it, so the `ci-lenient` mode exempts only that one warning
# via --warn-list=-20. All other warnings stay denied, and canopy's own modules
# (migrated off try?) run fully strict. Drop this once the ecosystem migrates
# (tracked in #573).
LENIENT_WARN_FLAGS=(--deny-warn --warn-list=-20)

case "$ACTION" in
    check)
        moon check "${DENY_WARN_FLAGS[@]}"
        ;;
    check-lenient)
        # Same --deny-warn but exempts only the try? [0020] deprecation
        # from vendored submodules canopy cannot migrate (tracked in #573).
        moon check "${LENIENT_WARN_FLAGS[@]}"
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
    ci-lenient)
        # Same as `ci`, but exempts the try? [0020] deprecation for vendored
        # submodules canopy cannot migrate (see LENIENT_WARN_FLAGS above).
        "$SCRIPT_DIR/moon-update.sh"
        moon check "${LENIENT_WARN_FLAGS[@]}"
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
