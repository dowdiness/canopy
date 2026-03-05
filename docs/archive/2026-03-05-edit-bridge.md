# Edit Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the local `compute_edit` string-diff in `ParsedEditor.reparse()` with loom's existing `TextDelta` API (`text_to_delta` → `to_edits`), housed in a new `edit_bridge.mbt` file that will later be extended with direct `Op → Edit` conversion.

**Architecture:** Create `editor/edit_bridge.mbt` with a `merge_to_edits(old, new)` function that calls loom's `text_to_delta` + `to_edits` — the same algorithm as `compute_edit` but returning `Array[Edit]` instead of a single `Edit`. Update `ParsedEditor.reparse()` to use it. The local `compute_edit` is kept as a reference baseline for parity tests (per design §2: "Keep as fallback until op-aware bridge is available").

**Tech Stack:** MoonBit, `dowdiness/loom/core` (`TextDelta`, `to_edits`, `text_to_delta`), `dowdiness/lambda` (`ImperativeParser`, `Edit`)

**Reference docs:** `docs/design/01-edit-bridge.md`, `docs/design/02-reactive-pipeline.md`

---

## Package dependency note

`to_edits` and `text_to_delta` live in **`dowdiness/loom/core`**, not in the `dowdiness/loom` facade. The `editor` package already imports `downdiness/event-graph-walker/core` without an alias (accessible as `@core`), so we must give `loom/core` a distinct alias: **`@loom_core`**.

`@loom_core.Edit` and `@parser.Edit` are the same concrete type — `dowdiness/lambda` re-exports `Edit` from `dowdiness/loom/core` via `pub using @core {type Edit}`.

---

### Task 1: Add `dowdiness/loom/core` dependency and write the failing test

**Files:**
- Modify: `editor/moon.pkg`
- Create: `editor/edit_bridge_test.mbt`

**Step 1: Add the import to `editor/moon.pkg`**

Open `editor/moon.pkg` and add `"dowdiness/loom/core" @loom_core,` to the import block. Result:

```
import {
  "dowdiness/event-graph-walker/core",
  "dowdiness/event-graph-walker/text",
  "dowdiness/lambda" @parser,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/loom/core" @loom_core,
  "moonbitlang/core/quickcheck",
}

options(
  is_main: false,
)
```

**Step 2: Create `editor/edit_bridge_test.mbt` with parity tests**

These tests verify that `merge_to_edits` (to be created) produces the same edit as `compute_edit` for every case in `text_diff_test.mbt`. They also verify the no-change case returns an empty array.

```moonbit
// Parity tests: merge_to_edits must produce the same Edit as compute_edit
// for single-change (old, new) pairs.
// For no-change pairs, merge_to_edits returns [] (loom optimization).

///|
test "merge_to_edits - insert at start" {
  let edits = merge_to_edits("abc", "xabc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "xabc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - insert at end" {
  let edits = merge_to_edits("abc", "abcx")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "abcx")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - insert in middle" {
  let edits = merge_to_edits("abc", "aXbc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXbc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete at start" {
  let edits = merge_to_edits("abc", "bc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "bc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete at end" {
  let edits = merge_to_edits("abc", "ab")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "ab")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete in middle" {
  let edits = merge_to_edits("abc", "ac")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "ac")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - replace single char" {
  let edits = merge_to_edits("abc", "aXc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - replace multiple chars" {
  let edits = merge_to_edits("abc", "aXYc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXYc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - no change returns empty array" {
  // loom's text_to_delta optimizes identical strings to []
  // (unlike compute_edit which returns a no-op Edit at the end)
  let edits = merge_to_edits("abc", "abc")
  inspect(edits.length(), content="0")
}

///|
test "merge_to_edits - empty to text" {
  let edits = merge_to_edits("", "abc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  inspect(e.start, content="0")
  inspect(e.old_len, content="0")
  inspect(e.new_len, content="3")
}

///|
test "merge_to_edits - text to empty" {
  let edits = merge_to_edits("abc", "")
  inspect(edits.length(), content="1")
  let e = edits[0]
  inspect(e.start, content="0")
  inspect(e.old_len, content="3")
  inspect(e.new_len, content="0")
}

///|
test "merge_to_edits - both empty returns empty array" {
  let edits = merge_to_edits("", "")
  inspect(edits.length(), content="0")
}

///|
test "merge_to_edits - lambda expression edit" {
  let edits = merge_to_edits("λx.x", "λx.x + 1")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("λx.x", "λx.x + 1")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "property: merge_to_edits matches compute_edit for all single-char inserts" {
  let bases : Array[String] = @quickcheck.samples(30)
  for base in bases {
    // Test inserting "X" at the start
    let new_text = "X" + base
    let expected = compute_edit(base, new_text)
    let edits = merge_to_edits(base, new_text)
    inspect(edits.length(), content="1")
    let e = edits[0]
    assert_eq(e.start, expected.start)
    assert_eq(e.old_len, expected.old_len)
    assert_eq(e.new_len, expected.new_len)
  }
}

///|
test "property: merge_to_edits matches compute_edit for all single-char deletes" {
  let bases : Array[String] = @quickcheck.samples(30)
  for base in bases {
    if base.is_empty() {
      continue
    }
    // Test deleting the first character
    let new_text = try base[1:] catch { _ => "" } noraise { v => v.to_string() }
    let expected = compute_edit(base, new_text)
    let edits = merge_to_edits(base, new_text)
    inspect(edits.length(), content="1")
    let e = edits[0]
    assert_eq(e.start, expected.start)
    assert_eq(e.old_len, expected.old_len)
    assert_eq(e.new_len, expected.new_len)
  }
}
```

**Step 3: Run the tests — expect them to fail**

```bash
cd /path/to/crdt && moon test -p dowdiness/crdt/editor
```

Expected: compile error — `merge_to_edits` is not defined.

---

### Task 2: Implement `edit_bridge.mbt`

**Files:**
- Create: `editor/edit_bridge.mbt`

**Step 1: Create the file**

```moonbit
// Edit Bridge: converts (old_text, new_text) pairs to Array[Edit]
// for the incremental parser, using loom's TextDelta API.
//
// This is the fallback path for batch remote merges (Design §1).
// The direct Op → Edit path (O(1)) will be added in a later phase
// once event-graph-walker/text exposes lv_to_position and insert_with_op.

///|
/// Convert an (old_text, new_text) pair into parser Edits using loom's
/// TextDelta API instead of a bespoke string diff.
///
/// Returns an empty array when old == new (no edit needed).
/// Returns exactly one Edit for any single contiguous change (the common case
/// for both local keystrokes and batch remote merges).
pub fn merge_to_edits(
  old_text : String,
  new_text : String,
) -> Array[@loom_core.Edit] {
  @loom_core.to_edits(@loom_core.text_to_delta(old_text, new_text))
}
```

**Step 2: Run the tests — expect them to pass**

```bash
moon test -p dowdiness/crdt/editor
```

Expected: all tests in `edit_bridge_test.mbt` pass. All pre-existing tests in `text_diff_test.mbt`, `parsed_editor_test.mbt`, `editor_test.mbt` continue to pass.

**Step 3: Commit**

```bash
git add editor/moon.pkg editor/edit_bridge.mbt editor/edit_bridge_test.mbt
git commit -m "feat(editor): add edit_bridge using loom TextDelta API

merge_to_edits(old, new) replaces bespoke compute_edit by delegating
to loom's text_to_delta → to_edits pipeline. Parity tests confirm
identical Edit values for all single-change cases in text_diff_test.mbt.

Refs: docs/design/01-edit-bridge.md"
```

---

### Task 3: Wire `ParsedEditor.reparse()` to use `merge_to_edits`

**Files:**
- Modify: `editor/parsed_editor.mbt`

**Step 1: Read `reparse()` in `parsed_editor.mbt` (lines 101–125)**

The current implementation uses a three-way if:
- both empty → `Edit::new(0, 0, 0)`
- old empty → `Edit::new(0, 0, new_len)`
- else → `compute_edit(old, new)` (single Edit)

`merge_to_edits` handles all three cases: both-empty and no-change both return `[]`; all real edits return `[Edit{...}]`. The new code applies the array, with an explicit fallback for the empty array (no-op edit to get the current SyntaxNode).

**Step 2: Verify the existing tests still pass before touching anything**

```bash
moon test -p dowdiness/crdt/editor
```

Expected: all pass. Baseline confirmed.

**Step 3: Replace `reparse()` body**

In `editor/parsed_editor.mbt`, replace lines 101–125 with:

```moonbit
///|
/// Incremental reparse using the Edit Bridge.
/// Converts old→new text via loom's TextDelta API and applies the resulting
/// edits to the incremental parser.
fn ParsedEditor::reparse(self : ParsedEditor) -> Unit {
  let old_text = self.cached_text
  let new_text = self.editor.get_text()
  let edits = merge_to_edits(old_text, new_text)
  let syntax_node = if edits.is_empty() {
    // No textual change (e.g., identical text or failed op).
    // Apply a no-op edit at position 0 to obtain the current SyntaxNode.
    self.parser.edit(@parser.Edit::new(0, 0, 0), new_text)
  } else {
    let mut node = self.parser.edit(edits[0], new_text)
    let mut i = 1
    while i < edits.length() {
      node = self.parser.edit(edits[i], new_text)
      i = i + 1
    }
    node
  }
  let counter = Ref::new(0)
  let ast = @parser.syntax_node_to_ast_node(syntax_node, counter)
  self.ast = Some(ast)
  self.cached_errors = @parser.collect_errors(ast)
  self.cached_text = new_text
  self.parse_dirty = false
}
```

**Step 4: Run all editor tests**

```bash
moon test -p dowdiness/crdt/editor
```

Expected: all tests pass — including `parsed_editor_test.mbt` (convergence, incremental parsing, cursor tracking, etc.). The behaviour is identical because `merge_to_edits` uses the same prefix/suffix algorithm as `compute_edit`.

**Step 5: Run full module test suite**

```bash
moon test
```

Expected: all tests pass.

**Step 6: Commit**

```bash
git add editor/parsed_editor.mbt
git commit -m "refactor(editor): wire ParsedEditor.reparse to edit_bridge

Replace three-way if / compute_edit with merge_to_edits from the
Edit Bridge. ParsedEditor now uses loom's TextDelta pipeline for
its string-diff fallback path. All existing tests pass unchanged.

Refs: docs/design/01-edit-bridge.md, docs/design/02-reactive-pipeline.md"
```

---

### Task 4: Update interfaces and format

**Files:**
- Modify: `editor/pkg.generated.mbti` (auto-generated)

**Step 1: Regenerate interface file**

```bash
moon info && moon fmt
```

**Step 2: Review the diff**

```bash
git diff editor/pkg.generated.mbti
```

Expected: `merge_to_edits` appears as a new `pub fn` in the interface. No other unexpected changes.

**Step 3: Commit**

```bash
git add editor/pkg.generated.mbti
git commit -m "chore(editor): regenerate .mbti and format after edit_bridge"
```

---

## Status: COMPLETE

Merged via PR #15 (2026-03-05). Tasks 1-2, 4 completed as planned. Task 3 (wire `reparse()` to `merge_to_edits`) was superseded by the Reactive Pipeline plan (PR #16), which removed `reparse()` entirely in favor of `ReactiveParser.set_source()`.

## Success criteria

1. `moon test -p dowdiness/crdt/editor` — all tests pass
2. `moon test` — full module test suite passes (185/185)
3. `grep -r "compute_edit" editor/parsed_editor.mbt` — returns nothing (`reparse()` removed entirely by reactive pipeline)
4. `grep -r "merge_to_edits" editor/parsed_editor.mbt` — superseded: `reparse()` no longer exists; `ReactiveParser.set_source()` handles re-parsing internally
5. `merge_to_edits` is exported in `editor/pkg.generated.mbti`

## What this does NOT change (out of scope)

- `compute_edit` in `text_diff.mbt` is kept as the reference baseline for parity tests (per §2: "Keep as fallback until op-aware bridge is available")
- No changes to `event-graph-walker/text` API (the direct `Op → Edit` path is Phase 1 step 2, requires `insert_with_op`/`lv_to_position` additions to TextDoc)
- No changes to loom (Strategy A: use `ReactiveParser.set_source` — next phase)
- No changes to `CanonicalModel` or `projection/` (Phase 2/3)
