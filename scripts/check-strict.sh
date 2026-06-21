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

# Error path lines look like:  ╭─[ /path/to/file.mbt:line:col ]
# Extract all such paths and check whether any are NOT under rabbita/rabbita/.
non_rabbita=0
while IFS= read -r line; do
    # Match lines that start with whitespace + box-drawing char + [ /path
    # Extract the file path from error-path lines like:
    #   ╭─[ /path/to/file.mbt:line:col ]
    path=$(echo "$line" | sed -n 's|.*\[ \(/.*\.mbt\):.*|\1|p')
    if [ -n "$path" ]; then
        case "$path" in
            */rabbita/rabbita/*) ;;
            *) non_rabbita=$(( non_rabbita + 1 )) ;;
        esac
    fi
done <<EOF
$output
EOF

if [ "$non_rabbita" -gt 0 ]; then
    echo "check-strict: $non_rabbita error path(s) from non-rabbita sources — failing." >&2
    exit "$status"
fi

echo "check-strict: suppressing rabbita-only errors (exit $status)."
exit 0
