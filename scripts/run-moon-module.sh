#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Shared vendored-submodule error suppression for --deny-warn checks.
# Defines run_moon_check_with_vendored_filter().
source "$SCRIPT_DIR/vendored-check-common.sh"

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <check|check-lenient|test|fmt-check|ci|ci-lenient|bench> <module-dir>" >&2
    exit 1
fi

ACTION="$1"
MODULE_DIR="$2"

# Accept either manifest format: moon.mod (TOML) or moon.mod.json (legacy).
# moon reads both under NEW_MOON_MOD=0.
if [ ! -f "$PROJECT_ROOT/$MODULE_DIR/moon.mod.json" ] &&
   [ ! -f "$PROJECT_ROOT/$MODULE_DIR/moon.mod" ]; then
    echo "Module root not found: $MODULE_DIR (expected moon.mod.json or moon.mod at $PROJECT_ROOT/$MODULE_DIR)" >&2
    exit 1
fi

cd "$PROJECT_ROOT/$MODULE_DIR"

# Keep both manifest formats buildable. NEW_MOON_MOD=0 accepts both moon.mod and
# moon.mod.json so local path-deps in moon.mod.json still resolve.
export NEW_MOON_MOD="${NEW_MOON_MOD:-0}"

DENY_WARN_FLAGS=(--deny-warn)

# Vendored submodules built standalone (event-graph-walker, loom) still use
# deprecated `try?` ([0020]) and MoonBit 0.10.4's [0082]/[0083] diagnostics;
# canopy does not own their source and cannot migrate it. The `ci-lenient`
# mode exempts only these known warnings. All other warnings stay denied, and
# canopy's own modules (migrated off try?) run fully strict. Drop these
# exemptions once the ecosystem migrates (tracked in #573).
LENIENT_WARN_FLAGS=(--deny-warn --warn-list=-20-82-83)

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
        # When checking from within a vendored submodule, suppress only
        # *transitive* vendored errors (deps), not the module under test.
        # Keep the exact module subtree under test unsuppressed.
        keep_dir="$MODULE_DIR"
        run_moon_check_with_vendored_filter "--keep=$keep_dir" "${DENY_WARN_FLAGS[@]}" || exit $?
        moon test --release
        ;;
    ci-lenient)
        # Same as `ci`, but exempts the try? [0020] deprecation for vendored
        # submodules canopy cannot migrate (see LENIENT_WARN_FLAGS above).
        "$SCRIPT_DIR/moon-update.sh"
        keep_dir="$MODULE_DIR"
        run_moon_check_with_vendored_filter "--keep=$keep_dir" "${LENIENT_WARN_FLAGS[@]}" || exit $?
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
