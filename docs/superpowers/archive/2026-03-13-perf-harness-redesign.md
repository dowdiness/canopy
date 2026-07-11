# Perf Harness Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Rabbita perf harness from a single-number throughput reporter into a diagnostic benchmark tool with per-phase timing, progress logging, timeout-aware results, and JSON output.

**Architecture:** Add `BenchmarkMeasurement` type and `deferred_full_cycle_timed` method to `benchmark_support.mbt` for phase-level timing. Rewrite `perf_report/main.mbt` with explicit `BenchmarkCase` structs, a shared case runner with START/DONE/TIMEOUT logging, and JSON output. Keep `BenchmarkSession` as the integration boundary — all measurements go through the real Rabbita reducer path.

**Tech Stack:** MoonBit (JS target), JS externs for `performance.now()` and CLI arg parsing.

**Spec:** `docs/plans/2026-03-11-rabbita-perf-harness-redesign.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `examples/rabbita/main/benchmark_support.mbt` | Modify | Add `now_ms` extern, `BenchmarkMeasurement` struct, `deferred_full_cycle_timed` method |
| `examples/rabbita/perf_report/main.mbt` | Rewrite | Explicit `BenchmarkCase`/`BenchmarkResult` types, case runner, progress logging, timeout, JSON output, CLI operation filter |

No new files needed. Both files are in the existing package structure.

**Package relationships:**
- `examples/rabbita/main/` (package `main`, imported as `@app` by perf_report)
- `examples/rabbita/perf_report/` (package `perf_report`, imports `main` as `@app`)

---

## Chunk 1: Measurement Infrastructure

### Task 1: Add BenchmarkMeasurement and Timed Method to benchmark_support.mbt

**Files:**
- Modify: `examples/rabbita/main/benchmark_support.mbt`

- [ ] **Step 1: Add `now_ms` JS extern and `BenchmarkMeasurement` struct**

Add to `examples/rabbita/main/benchmark_support.mbt` after the existing `BenchmarkSession::projection_dirty` method (end of file):

```moonbit
///|
pub extern "js" fn now_ms() -> Int =
  #|() => {
  #|  const clock = globalThis.performance?.now?.bind(globalThis.performance);
  #|  return Math.round(clock ? clock() : Date.now());
  #|}

///|
pub(all) struct BenchmarkMeasurement {
  total_ms : Int
  phases : Array[(String, Int)]
}
```

**Note:** `pub(all)` (not just `pub`) is required because `perf_report/main.mbt` needs to construct `@app.BenchmarkMeasurement` values cross-package. With plain `pub`, fields are readonly from outside the package.

- [ ] **Step 2: Add `deferred_full_cycle_timed` method**

This method manually performs the same work as `deferred_full_cycle` + `refresh`, but with timing points between each sub-phase. It does NOT go through `update(RefreshProjection)` — instead it calls the editor and tree state APIs directly so each phase can be timed independently.

Add after the `BenchmarkMeasurement` struct:

```moonbit
///|
pub fn BenchmarkSession::deferred_full_cycle_timed(
  self : BenchmarkSession,
  new_text : String,
) -> BenchmarkMeasurement {
  // Phase 1: text input (apply_text_edit via Rabbita update)
  let t0 = now_ms()
  self.deferred_text_input(new_text)
  let t1 = now_ms()
  // Phase 2: get_proj_node (triggers reactive parse + projection memo)
  let proj_node = self.model.editor.get_proj_node()
  let t2 = now_ms()
  // Phase 3: get_source_map
  let source_map = self.model.editor.get_source_map()
  let t3 = now_ms()
  // Phase 4: tree_refresh
  let text_view = self.model.editor.get_text()
  let tree_state = self.model.tree_state.refresh(proj_node, source_map)
  let t4 = now_ms()
  // Update model (equivalent to refresh() helper)
  self.model = {
    ..self.model,
    text_view,
    tree_state,
    projection_dirty: false,
    refresh_scheduled: false,
  }
  {
    total_ms: t4 - t0,
    phases: [
      ("text_input_ms", t1 - t0),
      ("get_proj_node_ms", t2 - t1),
      ("get_source_map_ms", t3 - t2),
      ("tree_refresh_ms", t4 - t3),
    ],
  }
}
```

**Why these 4 phases:**
- `text_input_ms`: cost of CRDT edit application via `update(TextInput(...))`
- `get_proj_node_ms`: cost of reactive parser + projection memo evaluation
- `get_source_map_ms`: cost of source map memo evaluation
- `tree_refresh_ms`: cost of `TreeEditorState::refresh` (subtree rebuild, node reconciliation)

- [ ] **Step 3: Run `moon check` in the rabbita module**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon check`
Expected: No errors. If there are type/syntax issues, fix them.

- [ ] **Step 4: Run `moon info && moon fmt`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon info && moon fmt`
Expected: Updates `.mbti` interface file with new public types. Verify `BenchmarkMeasurement`, `now_ms`, and `deferred_full_cycle_timed` appear in the generated interface.

- [ ] **Step 5: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign
git add examples/rabbita/main/benchmark_support.mbt
git commit -m "feat(perf): add BenchmarkMeasurement type and phase-timed deferred full cycle"
```

---

## Chunk 2: Perf Report Rewrite

### Task 2: Rewrite perf_report/main.mbt with Explicit Cases, Progress Logging, Timeout, and JSON Output

**Files:**
- Rewrite: `examples/rabbita/perf_report/main.mbt`

This is a complete rewrite of the file. The current file is ~179 lines. The new file will be ~250-300 lines.

- [ ] **Step 1: Write the new perf_report/main.mbt**

Replace the entire contents of `examples/rabbita/perf_report/main.mbt` with:

```moonbit
///|
pub extern "js" fn now_ms() -> Int =
  #|() => {
  #|  const clock = globalThis.performance?.now?.bind(globalThis.performance);
  #|  return Math.round(clock ? clock() : Date.now());
  #|}

///|
pub extern "js" fn cli_mode() -> String =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  const mode = argv.find((arg) => arg.length > 0) ?? "all";
  #|  return mode.toLowerCase();
  #|}

///|
pub extern "js" fn cli_iterations() -> Int? =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  // argv[1]: if it's a number, it's the iteration override
  #|  if (argv.length >= 2) {
  #|    const p1 = Number.parseInt(argv[1], 10);
  #|    if (Number.isFinite(p1) && p1 > 0) return p1;
  #|  }
  #|  // argv[2]: if argv[1] was a filter string, check argv[2]
  #|  if (argv.length >= 3) {
  #|    const p2 = Number.parseInt(argv[2], 10);
  #|    if (Number.isFinite(p2) && p2 > 0) return p2;
  #|  }
  #|  return undefined;
  #|}

///|
pub extern "js" fn cli_operation_filter() -> String? =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  if (argv.length < 2) return undefined;
  #|  const parsed = Number.parseInt(argv[1], 10);
  #|  if (Number.isFinite(parsed) && parsed > 0) return undefined;
  #|  return argv[1].replace(/-/g, " ");
  #|}

// ── Types ────────────────────────────────────────────────────────────

///|
enum Operation {
  LegacySetTextRefresh
  IncrementalEagerRefresh
  DeferredTextInput
  DeferredFullCycle
}

///|
struct BenchmarkCase {
  scenario : String
  label : String
  operation : Operation
  iterations : Int
  timeout_ms : Int?
}

///|
struct BenchmarkResult {
  scenario : String
  label : String
  iterations : Int
  completed : Int
  timed_out : Bool
  total_ms : Int
  average_ms : Int
  phases : Array[(String, Int)]
}

// ── Source generation ────────────────────────────────────────────────

///|
fn benchmark_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = 0 in ")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal} in x\{let_count - 1}")
  segments.join("")
}

// ── Case registry ───────────────────────────────────────────────────

///|
fn medium_cases(iterations : Int) -> Array[BenchmarkCase] {
  [
    {
      scenario: "medium",
      label: "legacy set_text + refresh",
      operation: LegacySetTextRefresh,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "incremental apply_text_edit + refresh",
      operation: IncrementalEagerRefresh,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "deferred text input only",
      operation: DeferredTextInput,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "deferred full cycle",
      operation: DeferredFullCycle,
      iterations,
      timeout_ms: None,
    },
  ]
}

///|
fn large_cases(iterations : Int) -> Array[BenchmarkCase] {
  [
    {
      scenario: "large",
      label: "deferred text input only",
      operation: DeferredTextInput,
      iterations,
      timeout_ms: Some(30000),
    },
    {
      scenario: "large",
      label: "deferred full cycle",
      operation: DeferredFullCycle,
      iterations,
      timeout_ms: Some(60000),
    },
  ]
}

// ── Operation runner ────────────────────────────────────────────────

///|
fn run_operation(
  op : Operation,
  session : @app.BenchmarkSession,
  text : String,
) -> @app.BenchmarkMeasurement {
  match op {
    DeferredFullCycle => session.deferred_full_cycle_timed(text)
    LegacySetTextRefresh => {
      let t0 = now_ms()
      session.legacy_set_text_refresh(text)
      { total_ms: now_ms() - t0, phases: [] }
    }
    IncrementalEagerRefresh => {
      let t0 = now_ms()
      session.incremental_eager_refresh(text)
      { total_ms: now_ms() - t0, phases: [] }
    }
    DeferredTextInput => {
      let t0 = now_ms()
      session.deferred_text_input(text)
      { total_ms: now_ms() - t0, phases: [] }
    }
  }
}

// ── Phase averaging ─────────────────────────────────────────────────

///|
fn average_phases(
  measurements : Array[@app.BenchmarkMeasurement],
) -> Array[(String, Int)] {
  if measurements.is_empty() || measurements[0].phases.is_empty() {
    return []
  }
  let n = measurements.length()
  let result : Array[(String, Int)] = []
  for i = 0; i < measurements[0].phases.length(); i = i + 1 {
    let (name, _) = measurements[0].phases[i]
    let mut sum = 0
    for m in measurements {
      sum = sum + m.phases[i].1
    }
    result.push((name, sum / n))
  }
  result
}

// ── Output formatting ───────────────────────────────────────────────

///|
fn format_phases(phases : Array[(String, Int)]) -> String {
  if phases.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  for phase in phases {
    parts.push(" \{phase.0}=\{phase.1}")
  }
  parts.join("")
}

///|
fn emit_json(result : BenchmarkResult) -> Unit {
  let phases_json = if result.phases.is_empty() {
    ""
  } else {
    let parts : Array[String] = []
    for phase in result.phases {
      parts.push("\"\{phase.0}\":\{phase.1}")
    }
    ",\{parts.join(",")}"
  }
  println(
    "{\"scenario\":\"\{result.scenario}\",\"label\":\"\{result.label}\",\"iterations\":\{result.completed},\"timed_out\":\{result.timed_out},\"total_ms\":\{result.total_ms},\"average_ms\":\{result.average_ms}\{phases_json}}",
  )
}

// ── Case runner ─────────────────────────────────────────────────────

///|
fn run_case(
  case_ : BenchmarkCase,
  source : String,
  edited_source : String,
) -> BenchmarkResult {
  // START line
  let timeout_str = match case_.timeout_ms {
    Some(ms) => " timeout_ms=\{ms}"
    None => ""
  }
  println(
    "START \{case_.scenario} \{case_.label} iterations=\{case_.iterations}\{timeout_str}",
  )
  // Warmup
  let warmup = @app.BenchmarkSession::new(source)
  let _ = run_operation(case_.operation, warmup, edited_source)
  // Measure
  let measurements : Array[@app.BenchmarkMeasurement] = []
  let mut total_elapsed = 0
  let mut timed_out = false
  let mut i = 0
  while i < case_.iterations && not(timed_out) {
    let base = if i % 2 == 0 { source } else { edited_source }
    let next = if i % 2 == 0 { edited_source } else { source }
    let session = @app.BenchmarkSession::new(base)
    let m = run_operation(case_.operation, session, next)
    total_elapsed = total_elapsed + m.total_ms
    measurements.push(m)
    match case_.timeout_ms {
      Some(budget) =>
        if total_elapsed > budget {
          timed_out = true
        }
      None => ()
    }
    i = i + 1
  }
  let completed = measurements.length()
  let average = if completed > 0 { total_elapsed / completed } else { 0 }
  let avg_phases = average_phases(measurements)
  // DONE / TIMEOUT line
  if timed_out {
    println(
      "TIMEOUT \{case_.scenario} \{case_.label} elapsed_ms=\{total_elapsed} completed=\{completed}/\{case_.iterations}",
    )
  } else {
    let phase_str = format_phases(avg_phases)
    println(
      "DONE  \{case_.scenario} \{case_.label} total=\{total_elapsed} avg=\{average}\{phase_str}",
    )
  }
  {
    scenario: case_.scenario,
    label: case_.label,
    iterations: case_.iterations,
    completed,
    timed_out,
    total_ms: total_elapsed,
    average_ms: average,
    phases: avg_phases,
  }
}

// ── Main ────────────────────────────────────────────────────────────

///|
fn main {
  let mode = cli_mode()
  let iterations = cli_iterations()
  let op_filter = cli_operation_filter()
  let medium_source = benchmark_source(80, "0")
  let medium_edited = benchmark_source(80, "1")
  let large_source = benchmark_source(320, "0")
  let large_edited = benchmark_source(320, "1")
  // Build case list
  let default_iters = match iterations {
    Some(n) => n
    None => 5
  }
  let mut cases : Array[BenchmarkCase] = []
  match mode {
    "medium" => cases = medium_cases(default_iters)
    "large" => cases = large_cases(default_iters)
    "all" => {
      for c in medium_cases(default_iters) {
        cases.push(c)
      }
      for c in large_cases(default_iters) {
        cases.push(c)
      }
    }
    _ => {
      println("Unknown mode '\{mode}', expected one of: all, medium, large")
      return
    }
  }
  // Apply operation filter
  match op_filter {
    Some(filter) =>
      cases = cases.filter(fn(c) { c.label.contains(filter) })
    None => ()
  }
  // Header
  println("Rabbita performance report")
  println("Source sizes: medium=80 lets, large=320 lets")
  println("Mode: \{mode}")
  match iterations {
    Some(n) => println("Iterations override: \{n}")
    None => ()
  }
  match op_filter {
    Some(filter) => println("Operation filter: \{filter}")
    None => ()
  }
  println("Cases: \{cases.length()}")
  println("")
  // Run cases
  let results : Array[BenchmarkResult] = []
  for case_ in cases {
    let (source, edited) = if case_.scenario == "medium" {
      (medium_source, medium_edited)
    } else {
      (large_source, large_edited)
    }
    results.push(run_case(case_, source, edited))
    println("")
  }
  // JSON summary
  println("--- JSON ---")
  for result in results {
    emit_json(result)
  }
}
```

- [ ] **Step 2: Run `moon check` in the rabbita module**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon check`
Expected: No errors. Fix any type/syntax issues.

Common issues to watch for:
- Tuple destructuring `let (a, b) = ...` — if it fails, split into separate lets with `.0`/`.1` access
- `Array::filter` — if not available, use a manual loop
- `String::contains` — already used in the codebase, should work

- [ ] **Step 3: Run `moon fmt`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon fmt`
Expected: File is formatted. Review any changes `moon fmt` made.

- [ ] **Step 4: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign
git add examples/rabbita/perf_report/main.mbt
git commit -m "feat(perf): rewrite perf harness with explicit cases, progress logging, timeout, and JSON output"
```

---

## Chunk 3: Verification

### Task 3: Integration Verification

**Files:** None (read-only verification)

- [ ] **Step 1: Build for JS target**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon build --target js`
Expected: Build succeeds with no errors.

- [ ] **Step 2: Run medium benchmark with 1 iteration**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && timeout 120s moon run perf_report medium 1`
Expected output pattern:
```text
Rabbita performance report
Source sizes: medium=80 lets, large=320 lets
Mode: medium
Iterations override: 1
Cases: 4

START medium legacy set_text + refresh iterations=1
DONE  medium legacy set_text + refresh total=XXX avg=XXX

START medium incremental apply_text_edit + refresh iterations=1
DONE  medium incremental apply_text_edit + refresh total=XXX avg=XXX

START medium deferred text input only iterations=1
DONE  medium deferred text input only total=XXX avg=XXX

START medium deferred full cycle iterations=1
DONE  medium deferred full cycle total=XXX avg=XXX text_input_ms=XX get_proj_node_ms=XX get_source_map_ms=XX tree_refresh_ms=XX

--- JSON ---
{"scenario":"medium","label":"legacy set_text + refresh",...}
{"scenario":"medium","label":"incremental apply_text_edit + refresh",...}
{"scenario":"medium","label":"deferred text input only",...}
{"scenario":"medium","label":"deferred full cycle",...,"text_input_ms":XX,...}
```

Key things to verify:
- All 4 cases produce START + DONE lines
- "deferred full cycle" DONE line includes phase timings
- JSON section has one line per case
- "deferred full cycle" JSON includes phase fields

- [ ] **Step 3: Run with operation filter**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && timeout 120s moon run perf_report medium deferred-full-cycle 1`
Expected: Only the "deferred full cycle" case runs. Output should show `Cases: 1` and only one START/DONE pair.

- [ ] **Step 4: Run large benchmark with 1 iteration (bounded)**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && timeout 120s moon run perf_report large 1`
Expected: Either DONE or TIMEOUT lines for each large case. The harness should NOT hang silently — if a case exceeds its timeout budget, it prints a TIMEOUT line with elapsed time.

- [ ] **Step 5: Run existing tests to verify no regressions**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.claude/worktrees/perf-harness-redesign/examples/rabbita && moon test`
Expected: All existing tests in `main/main.mbt` pass (Collapse, Select, StartEdit, Expand, WrapInLambda, Delete, TextInput, RefreshProjection tests).

- [ ] **Step 6: Final commit with verification note**

Only if any fixes were needed during verification. Otherwise skip.

---

## CLI Reference (After Implementation)

```bash
# Run all cases (medium + large)
moon run perf_report

# Run only medium cases
moon run perf_report medium

# Run only large cases
moon run perf_report large

# Override iteration count
moon run perf_report medium 1
moon run perf_report large 1

# Filter to specific operation (dashes become spaces)
moon run perf_report medium deferred-full-cycle
moon run perf_report large deferred-full-cycle 1

# With external timeout for safety
timeout 120s moon run perf_report large 1
```
