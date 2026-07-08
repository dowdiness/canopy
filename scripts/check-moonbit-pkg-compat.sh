#!/usr/bin/env bash

# Pre-build compatibility check: verify the pinned MoonBit toolchain can
# parse all moon.pkg files in the workspace, including vendored submodules.
#
# The problem this solves:
#   `moon check` does NOT deeply parse moon.pkg `options(...)` fields.
#   Bundling (wasm-gc / native) DOES parse them. If a submodule's moon.pkg
#   uses a key the pinned toolchain doesn't support (e.g. `formatter`),
#   `moon build` and `moon test` fail with [4070] / "Failed to bundle
#   core" / "Unexpected key 'XXX' found in moon.pkg".
#
# This script catches such mismatches before any test steps run, with
# a clear error message instead of an opaque bundling failure.
#
# Usage: check-moonbit-pkg-compat.sh
#
# Designed to run right after `moon check` and before `moon test`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# --- Phase 1: Extract the pinned MoonBit version ---
PIN_FILE=".github/actions/setup-moonbit/action.yml"
if [ ! -f "$PIN_FILE" ]; then
    echo "check-moonbit-pkg-compat: pin file not found at $PIN_FILE" >&2
    exit 1
fi

PINNED_VERSION="$(sed -n 's/^ *version: *\(.*\)/\1/p' "$PIN_FILE" | head -1)"
if [ -z "$PINNED_VERSION" ]; then
    echo "check-moonbit-pkg-compat: could not extract version from $PIN_FILE" >&2
    exit 1
fi
echo "Pinned MoonBit version: $PINNED_VERSION"

# --- Phase 2: Build check that triggers moon.pkg parsing ---
# We run `moon build --release` which forces workspace-level moon.pkg
# parsing for the default (native) target. This catches moon.pkg parse
# errors that `moon check` doesn't surface.
echo ""
echo "--- Running build compatibility check ---"

set +e
build_output="$(moon build --release 2>&1)"
build_status=$?
set -e

# Check for known moon.pkg parse errors in the output
moonpkg_errors=0
while IFS= read -r line; do
    if echo "$line" | grep -qE "Unexpected key.*found in moon\.pkg"; then
        echo "[MOON.PKG COMPAT] $line" >&2
        moonpkg_errors=$(( moonpkg_errors + 1 ))
    fi
    if echo "$line" | grep -qE "Unable to read.*moon\.pkg"; then
        echo "[MOON.PKG COMPAT] $line" >&2
        moonpkg_errors=$(( moonpkg_errors + 1 ))
    fi
    if echo "$line" | grep -qE "\[4070\]"; then
        # Only flag [4070] if it's related to moon.pkg parsing (not other
        # bundling issues like v128/SIMD which are target-specific).
        if echo "$line" | grep -qi "moon\.pkg\|bundle"; then
            echo "[MOON.PKG COMPAT] $line" >&2
            moonpkg_errors=$(( moonpkg_errors + 1 ))
        fi
    fi
done <<EOF
$build_output
EOF

if [ "$moonpkg_errors" -gt 0 ]; then
    echo ""
    echo "FAIL: $moonpkg_errors moon.pkg compatibility error(s) detected." >&2
    echo "The pinned MoonBit version ($PINNED_VERSION) doesn't support" >&2
    echo "features used in one or more moon.pkg files." >&2
    echo "" >&2
    echo "Fix options:" >&2
    echo "  1. Update the MoonBit version pin in $PIN_FILE" >&2
    echo "     to a version that supports the feature." >&2
    echo "  2. Or update the submodule moon.pkg to remove the" >&2
    echo "     incompatible options." >&2
    echo "" >&2
    echo "Full build output:" >&2
    echo "$build_output" >&2
    exit 1
fi

echo "✅ moon.pkg compatibility check passed."
echo ""
