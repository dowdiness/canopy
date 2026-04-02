# Test Abort Cleanup

## Why

Many test files still use `abort(...)` for expected-shape failures. That makes
failures harsher and less informative than assertion-based output, especially
when agents are debugging failures across multiple modules.

## Scope

In:
- test files in this repo that currently use `abort(...)`
- related submodule test files when the root backlog item is applied there

Out:
- production error handling
- replacing legitimate panic tests that intentionally exercise abort behavior

## Current State

- The active backlog still lists conversion of `abort()`-based tests to proper
  assertions as open work.
- Current usage spans multiple modules and submodules.
- Execution is paused after the main-module pass plus focused `loom/examples`
  slices, rather than being the active task.

## Progress

Completed in the first pass:

- main-module test helpers that were using `abort(...)` as assertion logic now
  use `fail(...)` with explicit `raise` signatures where needed
- parser fixture helpers in the main module no longer use `abort("parse failed")`

Remaining work:

- similar cleanup in submodules such as `graphviz/`, `loom/`, and other focused
  test packages
- any remaining assertion-like `abort(...)` uses outside the first-pass main
  module files
- resume only when this becomes the active cleanup task again; current remaining
  footprint is concentrated mostly in `loom/` and `graphviz/`

Completed in the second pass:

- `loom/examples/json` parser, error-recovery, and incremental tests now use
  `try!` / `fail(...)` instead of assertion-style `abort(...)`
- `loom/examples/lambda` parser, error-recovery, and CRDT peer tests now use
  helper-based `fail(...)` / `try!` expectation failures instead of
  assertion-style `abort(...)`

## Desired State

- Routine expectation failures in tests use assertions or snapshots rather than
  raw `abort(...)`.
- Failure output is more actionable without changing tested behavior.

## Steps

1. Identify test-side `abort(...)` calls that are acting as assertions.
2. Replace them with `assert_*`, `inspect`, or equivalent explicit checks.
3. Leave intentional panic-path tests alone.
4. Run affected test suites.

## Acceptance Criteria

- [x] Assertion-like `abort(...)` calls are removed from the targeted main-module test files in the first pass.
- [ ] Intentional panic tests remain explicit and correct.
- [x] Affected test suites still pass.

## Validation

```bash
moon test
make test-all
```

## Risks

- Some existing aborts may be serving as compact exhaustiveness guards; those
  should only be rewritten when the replacement stays equally clear.

## Notes

- Candidate files can be found with:

```bash
rg -n "abort\\(" . -g '*_test.mbt' -g '*_wbtest.mbt'
```
