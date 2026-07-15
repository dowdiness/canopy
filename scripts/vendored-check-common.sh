#!/usr/bin/env bash

# Shared vendored-submodule error suppression for moon check.
#
# Vendored submodules are workspace members that Canopy does not own.
# Their pre-existing errors/warnings are suppressed so they don't fail CI.
#
# Usage:
#   source vendored-check-common.sh
#   VENDORED_DIRS="rabbita ..."
#   run_moon_check_with_vendored_filter [moon-check-args...]
#
# The function runs moon check, then filters errors from vendored paths.
# Returns the moon check exit code if non-vendored errors exist, 0 otherwise.

# Vendored submodule root directories at the repository level. Errors from
# these paths are known pre-existing issues (deprecation warnings, vendored
# test diffs) that Canopy cannot fix. Paths are matched against the repo
# checkout directory so they work regardless of the CI checkout path.
#
# When adding a new vendored submodule to moon.work, add its repo-root
# directory here if it has pre-existing --deny-warn errors.
#
# Entries are repository-root names rather than package paths so nested
# workspace members (for example loom/*) share one suppression boundary.
VENDORED_DIRS="${VENDORED_DIRS:-alga event-graph-walker graphviz loom order-tree rabbita svg-dsl}"

run_moon_check_with_vendored_filter() {
    # Parse --keep=<dir> to exclude a directory from vendored suppression.
    # Used when running check from within a vendored submodule directory
    # (Test Submodules CI) — errors in the module under test must surface.
    local keep_dir=""
    if [[ "${1:-}" == --keep=* ]]; then
        keep_dir="${1#--keep=}"
        shift
    fi

    set +e
    local output
    output="$(moon check "$@" 2>&1)"
    local status=$?
    set -e

    echo "$output"

    if [ "$status" -eq 0 ]; then
        return 0
    fi

    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    local non_vendored=0
    local total_paths=0
    while IFS= read -r line; do
        local path=""
        # Try .mbt source path first.
        path=$(echo "$line" | sed -n 's|.*\[ \(/[^:]*\):.*|\1|p')
        if [ -z "$path" ]; then
            # Try moon.pkg path: "at path '/some/dir'".
            path=$(echo "$line" | sed -n "s|.*at path '\([^']*\)'.*|\1|p")
        fi
        if [ -z "$path" ]; then
            continue
        fi

        total_paths=$(( total_paths + 1 ))
        local relative_path=""
        if [[ "$path" == "$repo_root/"* ]]; then
            relative_path="${path#"$repo_root"/}"
        fi
        local repo_dir="${relative_path%%/*}"
        local is_vendored=0
        if [ -n "$keep_dir" ] &&
           { [ "$relative_path" = "$keep_dir" ] ||
             [[ "$relative_path" == "$keep_dir/"* ]]; }; then
            # The module under test remains unsuppressed.
            is_vendored=0
        else
            for dir in $VENDORED_DIRS; do
                if [ -n "$repo_dir" ] && [ "$repo_dir" = "$dir" ]; then
                    is_vendored=1
                    break
                fi
            done
        fi
        if [ "$is_vendored" -eq 0 ]; then
            non_vendored=$(( non_vendored + 1 ))
        fi
    done <<EOF
$output
EOF

    if [ "$non_vendored" -gt 0 ]; then
        echo "vendored-check: $non_vendored error path(s) from non-vendored sources — failing." >&2
        return "$status"
    fi

    if [ "$total_paths" -eq 0 ]; then
        echo "vendored-check: moon check failed (exit $status) with no parseable source paths — failing." >&2
        return "$status"
    fi

    echo "vendored-check: $total_paths vendored-submodule error path(s) suppressed (exit $status)."
    return 0
}
