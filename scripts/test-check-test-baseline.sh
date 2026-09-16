#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

expect_status() {
  local label="$1" expected="$2" baseline="$3" command_status="$4" output="$5"
  local actual=0 result
  result="$(bash "$root_dir/scripts/check-test-baseline.sh" "$baseline" \
    bash -c 'printf "%s\n" "$1"; exit "$2"' _ "$output" "$command_status" 2>&1)" || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    printf 'FAIL: %s: expected exit %s, got %s\n%s\n' "$label" "$expected" "$actual" "$result" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$label"
}

# Compiler diagnostics print source excerpts, not test-result records.
expect_status "warning source containing failed is not a failed test" 0 7 0 \
  'Warning: [0071]
 585 │ test "bench: delimiter resolver failed opener search R=512" (b : @bench.T) {
Total tests: 3, passed: 3, failed: 0. [js]'

expect_status "diagnostic text cannot inflate the failure total" 0 0 0 \
  ' 12 │ inspect(message, content="failed: 99")
Total tests: 1, passed: 1, failed: 0.'

expect_status "owned failures are rejected even within the baseline" 1 7 1 \
  '[dowdiness/canopy] test core/example_test.mbt:5 (#0) failed: assertion failed
Total tests: 1, passed: 0, failed: 1. [js]'

expect_status "known vendored failure remains within the baseline" 0 1 1 \
  '[dowdiness/pretty] test layout_test.mbt:5 (#0) failed: assertion failed
Total tests: 1, passed: 0, failed: 1. [wasm]'

expect_status "vendored failures accumulate across targets" 1 1 1 \
  '[dowdiness/pretty] test layout_test.mbt:5 (#0) failed: assertion failed
Total tests: 1, passed: 0, failed: 1. [wasm]
[dowdiness/pretty] test layout_test.mbt:5 (#0) failed: assertion failed
Total tests: 1, passed: 0, failed: 1. [js]'

expect_status "vendored path failure remains within the baseline" 0 1 1 \
  '[dowdiness/markdown] test /checkout/deps/loom/examples/markdown/example_test.mbt:5 (#0) failed: assertion failed
Total tests: 1, passed: 0, failed: 1.'

expect_status "owned failure without an index is not hidden by vendored failures" 1 7 1 \
  '[dowdiness/pretty] test layout_test.mbt:5 (#0) failed: assertion failed
[dowdiness/canopy] test core/example_test.mbt:5 failed
Total tests: 2, passed: 0, failed: 2.'

expect_status "compilation errors retain their exit status" 255 7 255 \
  'Error: failed when checking project'
