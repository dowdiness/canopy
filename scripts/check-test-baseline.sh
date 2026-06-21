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

# Run the command, capturing combined stdout+stderr and the exit code
output="$("$@" 2>&1)"
status=$?

# Sum all "failed: N" fields from "Total tests: ..., failed: N. [target]" lines
failures=$(echo "$output" | grep -oP 'failed:\s*\K\d+' | paste -sd+ - | bc 2>/dev/null || echo 0)

echo "Test baseline check: $failures failures (baseline: $BASELINE)"

if [ "$failures" -gt "$BASELINE" ]; then
    echo "Too many test failures: $failures exceeds baseline of $BASELINE" >&2
    echo "$output" >&2
    # Exit non-zero even if the wrapped command succeeded (e.g., test count
    # parser worked but the baseline was exceeded).
    if [ "$status" -ne 0 ]; then
        exit "$status"
    fi
    exit 1
fi

if [ "$status" -ne 0 ] && [ "$failures" -le "$BASELINE" ]; then
    echo "Non-zero exit ($status) with acceptable failure count ($failures ≤ $BASELINE) — suppressing exit code."
fi

exit 0
