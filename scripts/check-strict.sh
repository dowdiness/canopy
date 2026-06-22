#!/usr/bin/env bash

# Strict moon check — only suppresses errors from vendored rabbita submodule.
#
# Usage: check-strict.sh [moon-check-args...]
#
# Runs `moon check --deny-warn` from the workspace root. If any error
# originates from a path NOT under rabbita/rabbita/, the script fails.
# Errors from rabbita/rabbita/ (known vendored-submodule try? warnings)
# are suppressed.
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
# test diffs) that Canopy cannot fix. Paths are matched against the repo
# checkout directory so they work regardless of the CI checkout path.
#
# When adding a new vendored submodule to moon.work, add its repo-root
# directory here if it has pre-existing --deny-warn errors.
VENDORED_DIRS="rabbita/rabbita alga"

# Build a grep -v pipeline that excludes each vendored directory.
# For each dir, we match lines containing "/dir/" in the path.
grep_exclude=""
sep=""
for dir in $VENDORED_DIRS; do
    grep_exclude="${grep_exclude}${sep}-e /$dir/"
    sep=" "
done

# Error path lines look like:  ╭─[ /path/to/file.mbt:line:col ]
# Extract all such paths and check whether any are NOT under a vendored dir.
non_vendored=0
total_paths=0
while IFS= read -r line; do
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
    echo "check-strict: $non_vendored error path(s) from non-vendored sources — failing." >&2
    exit "$status"
fi

# If moon check failed but no .mbt source paths were found in the output
# (e.g., moon.pkg/moon.mod load error, import-resolution failure), this
# is a real error — propagate it rather than falling through to success.
if [ "$total_paths" -eq 0 ]; then
    echo "check-strict: moon check failed (exit $status) with no parseable source paths — failing." >&2
    exit "$status"
fi

echo "check-strict: $total_paths vendored-submodule error path(s) suppressed (exit $status)."
exit 0
