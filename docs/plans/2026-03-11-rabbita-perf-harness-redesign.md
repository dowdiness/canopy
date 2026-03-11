# Design: Rabbita Perf Harness Redesign

**Parent:** [Rabbita Projection Editor Performance Recovery](./2026-03-11-rabbita-projection-editor-performance-plan.md)
**Related:** [Performance Issues](../performance/RABBITA_PROJECTION_EDITOR_ISSUES.md)
**Status:** Proposed
**Date:** 2026-03-11

---

## Problem

The current Rabbita performance harness is adequate for rough medium-size throughput numbers, but it is weak at diagnosing the large-tree failures that now matter most.

Current limitations:

- it reports one average `ms/edit` number per scenario with no phase breakdown
- it runs medium scenarios before large ones by default, which delays large-case diagnosis
- it does not report progress per benchmark line, so stalls are ambiguous
- it has no timeout-aware result model, so pathological cases look like hangs
- it does not distinguish parser/projection/tree-refresh costs inside deferred full-cycle runs

Recent harness improvements already landed:

- `moon run perf_report large`
- `moon run perf_report medium`
- `moon run perf_report large 1`

Those changes make the harness easier to drive, but they do not yet make it diagnostic.

## Goal

Turn the Rabbita harness into a diagnostic benchmark tool for large-tree responsiveness, not just a single-number throughput reporter.

The redesigned harness should answer:

1. Which named scenario is slow?
2. Which phase inside that scenario is slow?
3. Did the run complete, or time out?
4. Is the regression in parser/projection work, tree refresh, or surrounding reducer logic?

## Non-Goals

- Browser frame-by-frame profiling
- Replacing the current `BenchmarkSession` model
- Solving the underlying large-tree performance issue in this document
- Designing a generic benchmark framework for the whole repository

## Success Criteria

### Functional

- Large-only and medium-only runs remain supported.
- Iteration override remains supported.
- Each benchmark case reports its own start and end status.
- A timed-out case produces a structured result instead of appearing to hang indefinitely.

### Diagnostic

- Deferred full-cycle runs are split into sub-phase timings.
- Output can be consumed by both humans and scripts.
- Large-tree stalls can be attributed to a named phase.

### Operational

- One command can run a single large scenario with `1` iteration and a timeout budget.
- Benchmark results are usable without editing source between runs.

---

## Current Harness

Current files:

- `examples/rabbita/perf_report/main.mbt`
- `examples/rabbita/main/benchmark_support.mbt`

Current strengths:

- goes through the real Rabbita reducer path
- supports `medium`, `large`, and `all`
- supports per-run iteration override

Current weakness:

- `BenchmarkSession::deferred_full_cycle(...)` returns one undifferentiated elapsed number even though it includes several meaningful internal steps

---

## Design Direction

## 1. Benchmark Cases Become Explicit Data

The current `main` function prints ad hoc lines. Replace that with explicit benchmark case data so the harness can filter, time, and report cases uniformly.

Suggested shape:

```moonbit
struct BenchmarkCase {
  scenario : Scenario
  label : String
  operation : String
  timeout_ms : Int?
  run : (@app.BenchmarkSession, String) -> BenchmarkMeasurement
}
```

This makes it easy to:

- filter to one named operation
- print progress consistently
- add timeout policy per case
- emit structured output

## 2. Measurements Become Structured

Replace the single `Int` average with a richer result type.

Suggested shape:

```moonbit
struct BenchmarkMeasurement {
  total_ms : Int
  phases : Array[(String, Int)]
}

struct BenchmarkResult {
  scenario : String
  label : String
  iterations : Int
  timed_out : Bool
  total_ms : Int?
  average_ms : Int?
  phases : Array[(String, Int)]
}
```

This still keeps the harness simple, but it makes it capable of real diagnosis.

## 3. Deferred Full Cycle Must Be Split Into Phases

The large-case problem is currently opaque because the harness only reports one total.

For deferred full-cycle runs, the harness should time at least:

- `text_input_ms`
- `refresh_projection_ms`

If practical, split `refresh_projection_ms` further into:

- `get_proj_node_ms`
- `get_source_map_ms`
- `tree_refresh_ms`

This can be done inside `BenchmarkSession` without changing product behavior.

Suggested direction in `examples/rabbita/main/benchmark_support.mbt`:

```moonbit
pub fn BenchmarkSession::deferred_full_cycle_timed(
  self : BenchmarkSession,
  new_text : String,
) -> BenchmarkMeasurement
```

## 4. Timeout Is A First-Class Result

Large-tree runs must stop looking like harness hangs.

Each benchmark case should optionally declare a timeout budget. If the budget is exceeded:

- stop the case
- emit a `timed_out = true` result
- include the case name and configured budget in output

The timeout does not need to be implemented inside MoonBit itself. A JS-side watchdog or outer process timeout is acceptable, as long as the result is attributable to one named case.

## 5. Human And Machine Output

The harness should emit:

- readable log lines for terminal use
- JSON lines for comparison scripts

Human example:

```text
START large deferred full cycle iterations=1 timeout_ms=30000
DONE  large deferred full cycle total=28450 avg=28450 refresh_projection_ms=28120 tree_refresh_ms=19000
```

Timed-out example:

```text
START large deferred full cycle iterations=1 timeout_ms=30000
TIMEOUT large deferred full cycle elapsed_ms=30000
```

JSON example:

```json
{"scenario":"large","label":"deferred full cycle","iterations":1,"timed_out":true,"elapsed_ms":30000}
```

---

## Plan

### Phase 1. Make Benchmark Cases Explicit

Refactor `perf_report/main.mbt` so each benchmark line is described by a `BenchmarkCase` value rather than open-coded print calls.

Deliverables:

- benchmark case struct
- mode filter (`all`, `medium`, `large`)
- optional operation filter
- shared case runner

### Phase 2. Add Progress Logging

Before running each case, print a `START` line with:

- scenario
- operation label
- iterations
- timeout if present

After completion, print `DONE` or `TIMEOUT`.

Deliverables:

- clear progress logging per case
- no more ambiguous long-running silent periods

### Phase 3. Add Structured Measurements

Change benchmark operations to return `BenchmarkMeasurement` instead of a single `Int`.

Start with:

- total elapsed time
- phase map for deferred full-cycle runs

Deliverables:

- `BenchmarkMeasurement`
- updated session helpers
- formatted phase output

### Phase 4. Add Timeout-Aware Results

Introduce optional timeout budgeting per case.

Initial default policy:

- no timeout for medium cases
- timeout for large cases, especially deferred full cycle

Deliverables:

- timeout field in benchmark case
- timeout-aware result printing
- timed-out runs emitted as results, not silent hangs

### Phase 5. Emit JSON Lines

After the text summary, emit one JSON line per result so regression comparison can be scripted.

Deliverables:

- JSON result emission
- stable field names for scripts

### Phase 6. Add Large Diagnostic Cases

The current large suite is too narrow. Add cases that isolate likely bottlenecks:

- `large deferred text input only`
- `large deferred full cycle`
- `large legacy set_text + refresh` only if still useful for comparison
- `large select-only`
- `large collapse-only`
- `large expand-hydrate`

Deliverables:

- expanded large-case menu
- ability to isolate UI-only costs from structural refresh costs

---

## CLI Shape

The current CLI is:

```bash
moon run perf_report
moon run perf_report medium
moon run perf_report large
moon run perf_report large 1
```

Target CLI after redesign:

```bash
moon run perf_report
moon run perf_report large
moon run perf_report large 1
moon run perf_report large deferred-full-cycle
moon run perf_report large deferred-full-cycle 1
```

Interpretation:

- arg 1: scenario mode
- arg 2: either iteration override or operation filter
- arg 3: iteration override if arg 2 is an operation filter

If this becomes awkward, switch to explicit flags in JS extern parsing. The immediate goal is practical operation, not perfect CLI elegance.

---

## Implementation Notes

### BenchmarkSession Boundary

Keep `BenchmarkSession` as the integration point. The harness should not duplicate Rabbita reducer logic in `perf_report/main.mbt`.

### Use Real Reducer Paths

Do not replace reducer-driven measurement with synthetic direct calls into `TreeEditorState`. The harness must keep exercising the real editor integration path.

### Prefer Additive Instrumentation

Add timed helper methods alongside existing methods first, then migrate the harness to them. That keeps call sites readable and lowers risk.

### Timeout Policy Must Be Per Case

Do not apply one global timeout to the whole harness. Large-only diagnostic runs need case-level attribution.

---

## Open Questions

1. Should timeout be enforced inside the JS benchmark process or by an outer shell wrapper?
2. Do we want phase timing only for deferred full cycle, or for all cases?
3. Should JSON output be always on, or behind a mode like `--json`?
4. Is `large = 320 lets` still the right stress size once timeout-aware reporting exists?

---

## Recommended First Patch

The first implementation patch should include only:

1. explicit benchmark case data
2. progress logging
3. structured timing for deferred full cycle
4. timeout-aware result reporting for large cases

That is the smallest patch that turns the harness from “rough throughput reporter” into a useful large-tree diagnostic tool.
