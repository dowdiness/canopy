# Incremental Parser Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Complete

**Goal:** Make loom's incremental parser faster than batch for flat let-chains by skipping reuse overhead on small nodes.

**Architecture:** Phase 0 migrates external CstNode.children access to SyntaxNode methods (prerequisite for future balanced trees). Phase 1 adds a size-threshold check to `ReuseCursor::try_reuse()` that skips the reuse protocol for nodes below a configurable byte threshold.

**Tech Stack:** MoonBit, moon test/bench, loom parser framework, seam CST library

**Spec:** `docs/plans/2026-03-21-incremental-parser-optimization-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `loom/loom/src/core/reuse_cursor.mbt` | Modify | Add size-threshold early exit to `try_reuse()` |
| `loom/loom/src/core/parser.mbt` | Modify | Add `reuse_size_threshold` field to `LanguageSpec` |
| `loom/loom/src/incremental/perf_instrumentation.mbt` | Modify | Add `size_threshold_skips` counter to `PerfStats` |
| `loom/examples/lambda/src/cst_tree_test.mbt` | Modify | Migrate `cst.children` → `SyntaxNode` methods |
| `loom/examples/lambda/src/benchmarks/profiling_benchmark.mbt` | Modify | Migrate `cst.children` → `SyntaxNode` methods |
| `loom/examples/lambda/src/benchmarks/let_chain_benchmark.mbt` | Modify | Add deep-tree regression benchmark |
| `loom/loom/src/grammar.mbt` | Modify | Pass threshold through Grammar to LanguageSpec |
| `loom/loom/src/factories.mbt` | Modify | Pass threshold through to ReuseCursor creation |

---

## Task 1: Audit CstNode.children access (Phase 0)

**Files:**
- Read: `loom/examples/lambda/src/cst_tree_test.mbt`
- Read: `loom/examples/lambda/src/benchmarks/profiling_benchmark.mbt`
- Read: `loom/loom/src/viz/dot_tree_node.mbt`

- [ ] **Step 1: Grep for direct CstNode.children access outside loom/seam internals**

Run from `loom/`:
```bash
cd loom && grep -rn '\.children' --include='*.mbt' examples/ | grep -v '_build' | grep -v 'node_modules' | head -40
```

Document every instance. Categorize as:
- (a) CstNode.children — must migrate
- (b) SyntaxNode.children() — already correct
- (c) Other struct.children (ProjNode, DotNode) — no action needed

- [ ] **Step 2: Commit audit notes as a comment in the plan**

No code change. Just confirm the scope before migrating.

---

## Task 2: Migrate cst_tree_test.mbt (Phase 0)

**Files:**
- Modify: `loom/examples/lambda/src/cst_tree_test.mbt`

The test file accesses `cst.children[0]`, `cst.children.length()`, etc. These tests verify CST structure directly — they intentionally test the raw CstNode. For Phase 0, these tests are **allowed to keep raw access** because they test seam internals, not consumer behavior.

- [ ] **Step 1: Verify cst_tree_test.mbt is testing seam internals**

Read the file and confirm tests are verifying CstNode structure (kind, children shape, hash). These are internal tests that should keep raw access. No migration needed for this file.

- [ ] **Step 2: Document decision**

These tests verify CstNode construction correctness — raw `cst.children` access is intentional and appropriate. Mark as "no action needed" in audit.

---

## Task 3: Migrate profiling_benchmark.mbt (Phase 0)

**Files:**
- Modify: `loom/examples/lambda/src/benchmarks/profiling_benchmark.mbt`

This benchmark iterates `cst.children` to count nodes for tree-build benchmarks. It should use `SyntaxNode` methods where possible, but benchmark code that measures CST construction internals may need raw access.

- [ ] **Step 1: Read the benchmark and identify each `cst.children` access**

```bash
cd loom && grep -n '\.children' examples/lambda/src/benchmarks/profiling_benchmark.mbt
```

- [ ] **Step 2: For each access, determine if it can use SyntaxNode**

Tree-build benchmarks that construct `CstNode` directly and count children are testing seam internals — keep raw access. Iterator benchmarks comparing `SyntaxNode` vs raw can keep both paths.

- [ ] **Step 3: Migrate where appropriate and run tests**

```bash
cd loom/examples/lambda && moon test && moon bench --release -p dowdiness/lambda/benchmarks -f profiling_benchmark.mbt
```

- [ ] **Step 4: Commit**

```bash
git add loom/examples/lambda/src/benchmarks/profiling_benchmark.mbt
git commit -m "refactor: migrate profiling benchmark to SyntaxNode where appropriate"
```

---

## Task 4: Add `reuse_size_threshold` to LanguageSpec

**Files:**
- Modify: `loom/loom/src/core/parser.mbt:58-72` (LanguageSpec struct)

- [ ] **Step 1: Add the field to LanguageSpec struct**

In `loom/loom/src/core/parser.mbt`, add to the `LanguageSpec` struct (after line 63):

```moonbit
  reuse_size_threshold : Int  // nodes with text_len below this skip reuse (0 = disabled)
```

- [ ] **Step 2: Update `LanguageSpec::new()` constructor (line 76-96)**

The constructor uses labelled arguments with defaults. Add a default parameter:

```moonbit
  reuse_size_threshold~ : Int = 64,
```

This is the primary construction site — without it, all callers fail to compile.

- [ ] **Step 3: Fix remaining LanguageSpec construction sites**

Find everywhere `LanguageSpec` is constructed directly (not via `::new()`) and add `reuse_size_threshold: 64`:

```bash
cd loom && grep -rn 'LanguageSpec' --include='*.mbt' | grep -v '_build'
```

Key locations:
- `loom/loom/src/grammar.mbt` — Grammar struct construction
- `loom/loom/src/factories.mbt` — factory functions
- Any test files that construct LanguageSpec directly

- [ ] **Step 3: Verify compilation**

```bash
cd loom/loom && moon check
```

- [ ] **Step 4: Commit**

```bash
git add loom/loom/src/core/parser.mbt loom/loom/src/grammar.mbt loom/loom/src/factories.mbt
git commit -m "feat(loom): add reuse_size_threshold field to LanguageSpec"
```

---

## Task 5: Add `size_threshold_skips` counter to PerfStats

**Files:**
- Modify: `loom/loom/src/incremental/perf_instrumentation.mbt:15-25`

- [ ] **Step 1: Add the counter field**

In the `PerfStats` struct (line 15), add after `fast_path_skips`:

```moonbit
  size_threshold_skips : Ref[Int]
```

- [ ] **Step 2: Initialize in PerfStats::new()**

In the `PerfStats::new()` function (line 28), add:

```moonbit
  size_threshold_skips: Ref::new(0),
```

- [ ] **Step 3: Add reset in perf_reset()**

In `perf_reset()` (line 51), add:

```moonbit
  perf_stats.size_threshold_skips.val = 0
```

- [ ] **Step 4: Update perf_report() (line 68)**

Add the new counter to the report output string:

```moonbit
  "size_threshold_skips: \{perf_stats.size_threshold_skips.val}"
```

- [ ] **Step 5: Verify compilation**

```bash
cd loom/loom && moon check
```

- [ ] **Step 6: Commit**

```bash
git add loom/loom/src/incremental/perf_instrumentation.mbt
git commit -m "feat(loom): add size_threshold_skips counter to PerfStats"
```

---

## Task 6: Write failing test for size-threshold skip

**Files:**
- Modify: `loom/loom/src/core/reuse_cursor.mbt` (read only for now)
- Create or modify: test file in `loom/examples/lambda/src/` for incremental behavior

- [ ] **Step 1: Write a test that verifies small nodes are skipped**

Add to `loom/examples/lambda/src/imperative_parser_test.mbt`:

Note: perf functions are in `@incremental`, not `@loom`. The lambda test package already imports `"dowdiness/loom/incremental" @incremental`. PerfStats fields are `Ref[Int]` — access via `.val`.

```moonbit
///|
/// Verify that size-threshold skip reduces reuse attempts for small nodes.
/// With threshold=64, a 4-token LetDef (~12 bytes) should NOT be reused —
/// instead it should be reparsed from scratch.
test "incremental - size threshold skips small LetDef nodes" {
  let source = "let x = 0\nlet y = 1\nlet z = 2\nz"
  let edited = "let x = 0\nlet y = 1\nlet z = 9\nz"
  let edit_pos = source.length() - "2\nz".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  @incremental.perf_enable()
  @incremental.perf_reset()
  let _ = parser.edit(edit, edited)
  let stats = @incremental.perf_snapshot()
  @incremental.perf_disable()
  // With threshold=64, all LetDef nodes (~12 bytes each) should be skipped
  // so size_threshold_skips should be > 0
  inspect(stats.size_threshold_skips.val > 0, content="true")
  // And reuse hits should be 0 for these small nodes
  inspect(stats.try_reuse_hits.val == 0, content="true")
}
```

Also add a test for threshold=0 (disabled mode) to verify no regression:

```moonbit
///|
/// Verify that reuse_size_threshold=0 disables the skip (preserves default behavior).
test "incremental - size threshold disabled when 0" {
  // This test requires temporarily setting threshold to 0.
  // If LanguageSpec uses a default of 64, construct a grammar with threshold=0
  // and verify that try_reuse_hits > 0 (nodes ARE reused).
  // Implementation detail: may need a custom Grammar construction.
  // Verify by checking that size_threshold_skips.val == 0 with default grammar
  // when all nodes are above threshold (use a large enough source).
}
```

The exact implementation depends on how the Grammar/LanguageSpec construction works. The key invariant: when `reuse_size_threshold == 0`, no nodes are skipped.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd loom/examples/lambda && moon test -f imperative_parser_test.mbt -t "incremental - size threshold skips small LetDef nodes"
```

Expected: compilation error — `size_threshold_skips` not yet accessible via `perf_snapshot()`, and the threshold logic doesn't exist yet.

- [ ] **Step 3: Commit the failing test**

```bash
git add loom/examples/lambda/src/imperative_parser_test.mbt
git commit -m "test(loom): add failing test for size-threshold reuse skip"
```

---

## Task 7a: Add threshold to ReuseCursor and implement skip logic

**Files:**
- Modify: `loom/loom/src/core/reuse_cursor.mbt` (struct, new(), try_reuse(), snapshot())
- Modify: `loom/loom/src/incremental/perf_instrumentation.mbt` (record function)

- [ ] **Step 1: Add threshold field to ReuseCursor struct**

Find the `ReuseCursor` struct definition and add:

```moonbit
  reuse_size_threshold : Int
```

- [ ] **Step 2: Accept threshold in ReuseCursor::new()**

In `ReuseCursor::new()` (line 104), add a `reuse_size_threshold : Int` parameter and store it in the struct literal (lines 121-137).

- [ ] **Step 3: Update ReuseCursor::snapshot() (line 456-484)**

The snapshot function manually copies every field into a new struct. Add `reuse_size_threshold` to the copy. Without this, speculative parsing (checkpoint/restore) would silently disable the threshold.

- [ ] **Step 4: Add size-threshold check in try_reuse()**

In `try_reuse()` (line 375), after the `seek_node_at` call succeeds (line 388), add the threshold check before the damage/leading/trailing checks:

```moonbit
    Some((node, node_offset)) => {
      // Skip reuse for small nodes — reparsing is cheaper than the protocol
      if self.reuse_size_threshold > 0 && node.text_len < self.reuse_size_threshold {
        @perf.record_size_threshold_skip()
        return None
      }
      let node_end = node_offset + node.text_len
      // ... existing checks ...
```

- [ ] **Step 5: Add `record_size_threshold_skip` to perf instrumentation**

In `loom/loom/src/incremental/perf_instrumentation.mbt`, add:

```moonbit
///|
pub fn record_size_threshold_skip() -> Unit {
  if perf_stats.enabled.val {
    perf_stats.size_threshold_skips.val = perf_stats.size_threshold_skips.val + 1
  }
}
```

- [ ] **Step 6: Verify compilation**

```bash
cd loom/loom && moon check
```

- [ ] **Step 7: Commit**

```bash
git add loom/loom/src/core/reuse_cursor.mbt loom/loom/src/incremental/perf_instrumentation.mbt
git commit -m "feat(loom): add size-threshold skip logic to ReuseCursor::try_reuse"
```

---

## Task 7b: Wire threshold through factories

**Files:**
- Modify: `loom/loom/src/factories.mbt` (pass threshold to ReuseCursor::new)

- [ ] **Step 1: Find ReuseCursor::new() call in factories.mbt**

```bash
cd loom && grep -n 'ReuseCursor::new' loom/src/factories.mbt
```

- [ ] **Step 2: Pass `spec.reuse_size_threshold` as the new parameter**

Add the threshold argument to the `ReuseCursor::new()` call.

- [ ] **Step 3: Verify compilation**

```bash
cd loom/loom && moon check
cd loom/examples/lambda && moon check
```

- [ ] **Step 4: Commit**

```bash
git add loom/loom/src/factories.mbt
git commit -m "feat(loom): wire reuse_size_threshold through factory to ReuseCursor"
```

---

## Task 8: Run the failing test — verify it passes

**Files:** None (test-only)

- [ ] **Step 1: Run the size-threshold test**

```bash
cd loom/examples/lambda && moon test -f imperative_parser_test.mbt -t "incremental - size threshold skips small LetDef nodes"
```

Expected: PASS

- [ ] **Step 2: Run all existing incremental parser tests**

```bash
cd loom/examples/lambda && moon test
```

Expected: All pass. No regressions.

- [ ] **Step 3: Run loom framework tests**

```bash
cd loom/loom && moon test
```

Expected: All pass.

- [ ] **Step 4: Run seam tests**

```bash
cd loom/seam && moon test
```

Expected: All pass.

---

## Task 9: Add deep-tree regression benchmark

**Files:**
- Modify: `loom/examples/lambda/src/benchmarks/let_chain_benchmark.mbt`

Phase 1's threshold must not regress performance for deep trees where reuse is valuable.

- [ ] **Step 1: Add a deep-tree benchmark**

Add to `let_chain_benchmark.mbt`:

Note: `profiling_benchmark.mbt` in the same package already defines `make_deep_let_chain(n, depth, tail)`. Use a different name to avoid collision.

```moonbit
///|
fn make_lambda_let_chain(count : Int) -> String {
  let segments : Array[String] = []
  for i = 0; i < count; i = i + 1 {
    segments.push("let x\{i} = (λf.λx.f (f x)) (λg.g)")
  }
  segments.push("\nx\{count - 1}")
  segments.join("\n")
}

///|
test "let-chain: 20 lambda lets - incremental single edit at tail" (b : @bench.T) {
  let source = make_lambda_let_chain(20)
  // Edit: change the last init expression's final character
  // Find the last "g)" which is in the last LetDef's init
  let edit_target = source.length() - "\nx19".length() - 1  // position of last ')' before tail
  let edited = source.substring(0, edit_target) + "x" + source.substring(edit_target + 1)
  let edit = @core.Edit::replace(edit_target, edit_target + 1, edit_target + 1)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let _ = parser.parse()
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}

///|
test "let-chain: 20 lambda lets - full reparse" (b : @bench.T) {
  let source = make_lambda_let_chain(20)
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}
```

- [ ] **Step 2: Run the benchmark to establish baseline**

```bash
cd loom/examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f let_chain_benchmark.mbt
```

Record the deep-tree incremental vs full reparse ratio. This is the regression guard.

- [ ] **Step 3: Commit**

```bash
git add loom/examples/lambda/src/benchmarks/let_chain_benchmark.mbt
git commit -m "bench(loom): add deep-tree let-chain regression benchmark"
```

---

## Task 10: Run full benchmark suite and verify improvement

**Files:** None (benchmark-only)

- [ ] **Step 1: Run let-chain benchmarks**

```bash
cd loom/examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f let_chain_benchmark.mbt
```

Record results for:
- `80 lets - edit-only at tail` — target: within 1.2x of full reparse
- `320 lets - edit-only at tail` — target: within 1.2x of full reparse
- `80 lets - 50-edit session incremental` — target: within 1.1x of full reparse
- `20 deep lets - incremental` — target: no regression vs full reparse

- [ ] **Step 2: Run full canopy pipeline benchmark**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon bench --release
```

Verify projection pipeline keystroke latency hasn't regressed.

- [ ] **Step 3: If threshold needs tuning, adjust and re-run**

Try values 32, 64, 128 in `LanguageSpec` construction and re-run benchmarks. Pick the value that:
- Makes flat let-chain incremental ≤ 1.2x of batch
- Does not regress deep-tree incremental

- [ ] **Step 4: Commit final threshold value if changed**

```bash
git add loom/loom/src/grammar.mbt
git commit -m "tune: set reuse_size_threshold to optimal value"
```

---

## Task 11: Update interfaces and format

**Files:** All modified files

- [ ] **Step 1: Update .mbti interfaces**

```bash
cd loom/loom && moon info
cd loom/seam && moon info
cd loom/examples/lambda && moon info
```

- [ ] **Step 2: Format**

```bash
cd loom/loom && moon fmt
cd loom/seam && moon fmt
cd loom/examples/lambda && moon fmt
```

- [ ] **Step 3: Verify no unexpected API changes**

```bash
cd loom && git diff *.mbti
```

Expected changes: `LanguageSpec` gains `reuse_size_threshold`, `PerfStats` gains `size_threshold_skips`, `perf_snapshot` return type updated.

- [ ] **Step 4: Run all tests one final time**

```bash
cd loom/loom && moon test
cd loom/seam && moon test
cd loom/examples/lambda && moon test
```

- [ ] **Step 5: Commit**

```bash
git add loom/loom/src/ loom/seam/ loom/examples/lambda/src/
git commit -m "chore(loom): update interfaces and format after size-threshold optimization"
```

---

## Notes

- **CST/diagnostic correctness:** The existing `imperative_differential_fuzz_test.mbt` property tests verify that incremental and batch parsing produce identical CST and diagnostics. These tests run as part of `moon test` and cover the correctness criteria from the spec.
- **Phase 0 validation scope:** The spec says "zero direct `CstNode.children` access outside loom/seam." In practice, `cst_tree_test.mbt` and some benchmarks intentionally test seam internals with raw access. The Phase 0 validation criterion applies to *consumer* code, not internal tests.
- **`tree_diff` and `cst_fold` audit:** These loom internals access `CstNode.children` directly. They will need RepeatGroup-awareness in Phase 2 but are not modified in this plan.

## Summary

| Task | Phase | Description | Risk |
|------|-------|-------------|------|
| 1 | 0 | Audit CstNode.children access | Low |
| 2 | 0 | Verify cst_tree_test.mbt (no migration needed) | Low |
| 3 | 0 | Migrate profiling_benchmark.mbt | Low |
| 4 | 1 | Add reuse_size_threshold to LanguageSpec + constructor | Low |
| 5 | 1 | Add size_threshold_skips to PerfStats + report | Low |
| 6 | 1 | Write failing tests (threshold skip + disabled mode) | Low |
| 7a | 1 | Implement threshold in ReuseCursor (struct, try_reuse, snapshot) | Low |
| 7b | 1 | Wire threshold through factories | Low |
| 8 | 1 | Verify tests pass + no regressions | Low |
| 9 | 1 | Add deep-tree regression benchmark | Low |
| 10 | 1 | Run full benchmarks, tune threshold | Low |
| 11 | 1 | Update interfaces and format | Low |
