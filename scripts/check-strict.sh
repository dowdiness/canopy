#!/usr/bin/env bash

# Strict moon check — suppresses errors from vendored submodule sources
# (both .mbt paths and moon.pkg parse errors).
#
# Usage: check-strict.sh [moon-check-args...]
#
# Runs `moon check --deny-warn` from the workspace root. If any error
# originates from a path NOT under a vendored directory, the script fails.
# Errors from vendored directories (known pre-existing deprecation warnings,
# vendored test diffs, moon.pkg syntax mismatches) are suppressed.
#
# Replaces check-lenient (--warn-list=-20) which exempted try? [0020]
# for ALL workspace members. Now a try? reintroduction in Canopy-owned
# code fails CI.

set -euo pipefail

# Run moon check --deny-warn
set +e
output="$(moon check --deny-warn "$@" 2>&1)"
status=$?
set -e

echo "$output"

if [ "$status" -eq 0 ]; then
    exit 0
fi

# Vendored submodule root directories at the repository level. Errors from
# these paths are known pre-existing issues (deprecation warnings, vendored
# test diffs, moon.pkg syntax) that Canopy cannot fix. Paths are matched
# against the repo checkout directory so they work regardless of the CI
# checkout path.
#
# When adding a new vendored submodule to moon.work, add its repo-root
# directory here if it has pre-existing --deny-warn errors.
# Directories are repo-root relative. Matches paths containing "/dir/".
VENDORED_DIRS="loom/loom"

# Build a grep -v pipeline that excludes each vendored directory.
# For each dir, we match lines containing "/dir/" in the path.
grep_exclude=""
sep=""
for dir in $VENDORED_DIRS; do
    grep_exclude="${grep_exclude}${sep}-e /$dir/"
    sep=" "
done

# Path extraction handles two error formats:
#   .mbt source:  ╭─[ /path/to/file.mbt:line:col ]
#   moon.pkg:     at path '/home/.../rabbita/rabbita'
non_vendored=0
total_paths=0
while IFS= read -r line; do
    path=""
    # Try .mbt source path first
    candidate=$(echo "$line" | sed -n 's|.*\[ \(/[^:]*\):.*|\1|p')
    if [ -n "$candidate" ]; then
        path="$candidate"
    else
        # Try moon.pkg path: "at path '/some/dir'"
        candidate=$(echo "$line" | sed -n "s|.*at path '\([^']*\)'.*|\1|p")
        if [ -n "$candidate" ]; then
            path="$candidate"
        fi
    fi
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
    echo "check-strict: $non_vendored error path(s) from non-vendored sources — failing." >&2
    exit "$status"
fi

# If moon check failed but no .mbt or moon.pkg paths were found in the
# output (e.g., import-resolution failure without file attribution), this
# is a real error — propagate it rather than falling through to success.
if [ "$total_paths" -eq 0 ]; then
    echo "check-strict: moon check failed (exit $status) with no parseable source paths — failing." >&2
    exit "$status"
fi

echo "check-strict: $total_paths vendored-submodule error path(s) suppressed (exit $status)."
exit 0
