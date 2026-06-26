#!/usr/bin/env bash

# Shared vendored-submodule error suppression for moon check.
#
# Vendored submodules are workspace members that Canopy does not own.
# Their pre-existing errors/warnings are suppressed so they don't fail CI.
#
# Usage:
#   source vendored-check-common.sh
#   VENDORED_DIRS="rabbita/rabbita ..."
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
VENDORED_DIRS="${VENDORED_DIRS:-rabbita/rabbita event-graph-walker loom order-tree graphviz svg-dsl}"

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

    # Build a grep -v pipeline that excludes each vendored directory.
    local grep_exclude=""
    local sep=""
    for dir in $VENDORED_DIRS; do
        # Skip the keep_dir so its errors are NOT suppressed.
        if [ -n "$keep_dir" ] && [ "$dir" = "$keep_dir" ]; then
            continue
        fi
        grep_exclude="${grep_exclude}${sep}-e /$dir/"
        sep=" "
    done

    local non_vendored=0
    local total_paths=0
    while IFS= read -r line; do
        local path
        path=$(echo "$line" | sed -n 's|.*\[ \(/.*\.mbt\):.*|\1|p')
        if [ -n "$path" ]; then
            total_paths=$(( total_paths + 1 ))
            if echo "$path" | grep -q $grep_exclude; then
                : # vendored — suppress
            else
                non_vendored=$(( non_vendored + 1 ))
            fi
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
