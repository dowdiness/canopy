#!/usr/bin/env bash

# Run moon test commands and gate on the failure count not exceeding a
# known baseline of vendored-submodule test failures.
#
# Usage: check-test-baseline.sh <baseline> <command...>
#
#   baseline  - maximum acceptable number of failing tests (integer)
#   command   - the moon test command and its arguments
#
# Extracts "failed: N" counts from the command's stderr/stdout and sums
# them. If the total exceeds the baseline, exits with the command's exit
# code (or 1 if the command succeeded). Otherwise exits 0, absorbing the
# known vendored-submodule failures.
#
# Example:
#   check-test-baseline.sh 7 moon test --release

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <baseline> <command...>" >&2
    exit 1
fi

BASELINE="$1"
shift

# Must be a non-negative integer
if ! [[ "$BASELINE" =~ ^[0-9]+$ ]]; then
    echo "check-test-baseline: baseline must be a non-negative integer, got '$BASELINE'" >&2
    exit 1
fi

# Run the command, capturing combined stdout+stderr and the exit code.
# The || true prevents set -e from exiting on the command's own failure;
# we inspect $? afterwards via PIPESTATUS.
set +e
output="$("$@" 2>&1)"
status=$?
set -e

# Sum all "failed: N" fields from "Total tests: ..., failed: N. [target]" lines.
# Uses sed instead of grep -P for portability; sums with pure bash arithmetic.
failures=0
while IFS= read -r line; do
    n=$(echo "$line" | sed -n 's/.*failed: *\([0-9]\+\).*/\1/p')
    if [ -n "$n" ]; then
        failures=$(( failures + n ))
    fi
done <<EOF
$output
EOF

# Verify every failing test is from a vendored submodule.
# Failure lines look like:
#   [moonbit-community/rabbita] test dom/README.mbt.md:17 (#0) failed: ...
#   [dowdiness/canopy] test core/some_test.mbt:5 failed
#   [example/codemirror_demo] test ... failed
# Any test failure NOT explicitly from a vendored submodule is an error.
#
# Vendored modules with known pre-existing test failures:
#   moonbit-community/rabbita  (DOM tests, URL formatting diffs)
#   All submodule workspace members added in #740 — pre-existing
#   failures that Canopy cannot fix.  The path-prefix "/loom/" covers
#   every loom-owned submodule (loom/loom, seam, pretty, text-change,
#   moji, egglog, egraph, examples/*).
non_vendored_failures=0
while IFS= read -r line; do
    case "$line" in
        *" test "*" failed"* | *" test "*" failed:"*)
            case "$line" in
                *"[moonbit-community/rabbita]"* | *"rabbita/rabbita/"*) ;;
                *"/alga/"*) ;;
                *"/rle/"*) ;;
                *"/order-tree/"*) ;;
                *"/loom/"*) ;;
                *"/event-graph-walker/"*) ;;
                *"/graphviz/"*) ;;
                *"/svg-dsl/"*) ;;
                *) non_vendored_failures=$(( non_vendored_failures + 1 )) ;;
            esac
            ;;
    esac
done <<EOF
$output
EOF

echo "Test baseline check: $failures failures (baseline: $BASELINE), $non_vendored_failures non-vendored"

if [ "$non_vendored_failures" -gt 0 ]; then
    echo "FAIL: $non_vendored_failures failing test(s) from non-vendored sources." >&2
    echo "$output" >&2
    exit 1
fi

if [ "$failures" -gt "$BASELINE" ]; then
    echo "Too many test failures: $failures exceeds baseline of $BASELINE" >&2
    echo "$output" >&2
    if [ "$status" -ne 0 ]; then
        exit "$status"
    fi
    exit 1
fi

# If the command failed but no test-failure lines were found, this is not a
# test-failure issue — it's a real error from moon check, moon build, etc.
# Propagate the original exit code rather than absorbing it.
if [ "$status" -ne 0 ] && [ "$failures" -eq 0 ]; then
    echo "Command failed (exit $status) with no test-failure lines — propagating error." >&2
    echo "$output" >&2
    exit "$status"
fi

if [ "$status" -ne 0 ]; then
    echo "Non-zero exit ($status) with acceptable failure count ($failures ≤ $BASELINE) — suppressing exit code."
fi

exit 0
