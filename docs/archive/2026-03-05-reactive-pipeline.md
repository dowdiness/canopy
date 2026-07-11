# Reactive Pipeline Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `ParsedEditor`'s manual dirty-flag + string-diff caching with loom's `ReactiveParser`, eliminating `parse_dirty`, `cached_text`, `cached_errors`, and `reparse()`.

**Architecture:** Strategy A from Design §2 — use `ReactiveParser[SyntaxNode]` via `@loom.new_reactive_parser("", @parser.lambda_grammar)`. After each text mutation, call `parser.set_source(new_text)`; the `Signal`/`Memo` internals handle lazy invalidation. `get_ast()` calls `parser.term()` (O(1) on cache hit) then runs the existing `syntax_node_to_ast_node()` conversion.

**Tech Stack:** MoonBit, `dowdiness/loom` (`ReactiveParser`, `new_reactive_parser`), `dowdiness/lambda` (`lambda_grammar`, `SyntaxNode`), `dowdiness/event-graph-walker/text` (sync protocol)

---

## Reference: Key APIs

`ReactiveParser[Ast]` lives in `dowdiness/loom` (re-exported from `loom/loom/src/loom.mbt`):
```moonbit
pub fn[T, K, Ast : Eq] new_reactive_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ReactiveParser[Ast]

pub fn[Ast] ReactiveParser::set_source(self, source : String) -> Unit
pub fn[Ast : Eq] ReactiveParser::term(self) -> Ast         // Memoized — O(1) on cache hit
pub fn[Ast] ReactiveParser::diagnostics(self) -> Array[String]  // Memoized via cst_memo
```

`lambda_grammar` is in `dowdiness/lambda` (alias `@parser`) producing `ReactiveParser[@parser.SyntaxNode]`.

## Files to Change

| File | Change |
|------|--------|
| `editor/moon.pkg` | Add `"dowdiness/loom" @loom` import |
| `editor/parsed_editor.mbt` | Replace `ImperativeParser` with `ReactiveParser`; remove dirty fields |
| `editor/parsed_editor_test.mbt` | Verify tests pass unchanged (behavior is identical) |

`crdt.mbt` already calls `ed.mark_dirty()` which we keep as a thin wrapper — no change needed there.

---

### Task 1: Add `dowdiness/loom` dependency to `editor/moon.pkg`

**Files:**
- Modify: `editor/moon.pkg`

**Step 1: Open and read the current file**

```
editor/moon.pkg currently contains:
  "dowdiness/loom/core" @loom_core
```

**Step 2: Add the import**

Replace the contents of `editor/moon.pkg` with:

```
import {
  "dowdiness/event-graph-walker/text",
  "dowdiness/lambda" @parser,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loom_core,
  "moonbitlang/core/quickcheck",
}

options(
  is_main: false,
)
```

**Step 3: Verify it compiles**

Run: `moon check`
Expected: `Finished. moon: ran N tasks, now up to date` (no errors)

**Step 4: Commit**

```bash
git add editor/moon.pkg
git commit -m "chore(editor): add dowdiness/loom dependency for ReactiveParser"
```

---

### Task 2: Rewrite `ParsedEditor` struct and constructor

**Files:**
- Modify: `editor/parsed_editor.mbt` (lines 1–29)

**Background:** The current struct has five fields; we replace the four manual-cache fields with a single `ReactiveParser`:

| Remove | Reason |
|--------|--------|
| `parser : @parser.ImperativeParser[@parser.SyntaxNode]` | Replaced by ReactiveParser |
| `mut ast : @ast.AstNode?` | Memoized inside ReactiveParser |
| `mut parse_dirty : Bool` | Handled by Signal invalidation |
| `mut cached_text : String` | Tracked inside Signal |
| `mut cached_errors : Array[String]` | Derived from diagnostics() |

**Step 1: Write the failing test**

Add to `editor/parsed_editor_test.mbt`:

```moonbit
///|
test "ReactiveParser: no dirty flag — get_ast() twice without change is idempotent" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("x + 1")
  let ast1 = pe.get_ast()
  let ast2 = pe.get_ast() // second call — must not re-parse
  inspect(@ast.print_ast_node(ast1), content="(x + 1)")
  inspect(@ast.print_ast_node(ast2), content="(x + 1)")
}
```

**Step 2: Run test to verify it fails (or passes with old impl)**

Run: `moon test --filter "ReactiveParser"`
Note: It may pass with the old implementation too — that's fine. The test documents the invariant.

**Step 3: Replace the struct and constructor**

Replace lines 1–29 of `editor/parsed_editor.mbt` with:

```moonbit
// ParsedEditor: Integration of CRDT text editor with reactive parser
// Combines Editor (CRDT text) and ReactiveParser (AST) using loom's Signal/Memo pipeline

///|
/// ParsedEditor wraps the CRDT editor and a ReactiveParser.
/// Lazy AST evaluation is handled by the Signal/Memo pipeline — no manual
/// dirty flags needed. Call set_source after any text mutation.
pub struct ParsedEditor {
  editor : Editor // CRDT text editor
  parser : @loom.ReactiveParser[@parser.SyntaxNode] // Reactive incremental parser
}

///|
/// Create a new ParsedEditor with the given agent ID
pub fn ParsedEditor::new(agent_id : String) -> ParsedEditor {
  let editor = Editor::new(agent_id)
  let parser = @loom.new_reactive_parser("", @parser.lambda_grammar)
  { editor, parser }
}
```

**Step 4: Run tests**

Run: `moon check && moon test`
Expected: compilation errors in the methods that reference the removed fields — those are fixed in Tasks 3–6.

---

### Task 3: Rewrite mutation methods (insert / delete / backspace / apply_sync / mark_dirty)

**Files:**
- Modify: `editor/parsed_editor.mbt` (lines 31–83, 142–153)

**Pattern:** Every method that previously set `parse_dirty = true` now calls `self.parser.set_source(self.editor.get_text())` after the mutation. `ReactiveParser.set_source` does an equality check — identical text is a no-op.

**Step 1: Replace the five mutation methods**

Replace lines 31–83 and 142–153 with:

```moonbit
///|
/// Insert text at the current cursor position
pub fn ParsedEditor::insert(self : ParsedEditor, text : String) -> Unit raise {
  self.editor.insert(text)
  self.parser.set_source(self.editor.get_text())
}

///|
/// Delete character at cursor position (forward delete)
/// Returns true if deletion succeeded, false if at end of document
pub fn ParsedEditor::delete(self : ParsedEditor) -> Bool {
  let result = self.editor.delete()
  if result {
    self.parser.set_source(self.editor.get_text())
  }
  result
}

///|
/// Delete character before cursor (backspace)
/// Returns true if deletion succeeded, false if at start of document
pub fn ParsedEditor::backspace(self : ParsedEditor) -> Bool {
  let result = self.editor.backspace()
  if result {
    self.parser.set_source(self.editor.get_text())
  }
  result
}

///|
/// Move cursor to specific position
pub fn ParsedEditor::move_cursor(self : ParsedEditor, position : Int) -> Unit {
  self.editor.move_cursor(position)
}

///|
/// Get current cursor position
pub fn ParsedEditor::get_cursor(self : ParsedEditor) -> Int {
  self.editor.get_cursor()
}

///|
/// Get the current text content
pub fn ParsedEditor::get_text(self : ParsedEditor) -> String {
  self.editor.get_text()
}

///|
/// Notify the parser that text changed (e.g. after undo/redo on the raw doc).
/// Calls set_source — a no-op if the text is unchanged.
pub fn ParsedEditor::mark_dirty(self : ParsedEditor) -> Unit {
  self.parser.set_source(self.editor.get_text())
}

///|
/// Apply a sync message from a remote peer and update local state.
pub fn ParsedEditor::apply_sync(
  self : ParsedEditor,
  msg : @text.SyncMessage,
) -> Unit raise {
  self.editor.apply_sync(msg)
  self.parser.set_source(self.editor.get_text())
}
```

**Step 2: Run check**

Run: `moon check`
Expected: remaining errors only in `get_ast`, `get_errors`, `is_parse_valid`, `reparse` — fixed next.

---

### Task 4: Rewrite read methods (get_ast / get_errors / is_parse_valid) and remove reparse

**Files:**
- Modify: `editor/parsed_editor.mbt` (lines 85–140)

**Background:**
- `get_ast()`: call `parser.term()` (returns `SyntaxNode`, memoized) then convert via existing `syntax_node_to_ast_node`
- `get_errors()`: call `parser.diagnostics()` (memoized via cst_memo) directly
- `is_parse_valid()`: `parser.diagnostics().is_empty()`
- `reparse()`: **deleted entirely**

**Step 1: Replace lines 85–140 with**

```moonbit
///|
/// Get the AST (lazy — recomputes only if source changed since last call)
pub fn ParsedEditor::get_ast(self : ParsedEditor) -> @ast.AstNode {
  let syntax_node = self.parser.term()
  let counter = Ref::new(0)
  @parser.syntax_node_to_ast_node(syntax_node, counter)
}

///|
/// Get parse errors from the current source
pub fn ParsedEditor::get_errors(self : ParsedEditor) -> Array[String] {
  self.parser.diagnostics()
}

///|
/// Check if the current parse tree is valid (no errors)
pub fn ParsedEditor::is_parse_valid(self : ParsedEditor) -> Bool {
  self.parser.diagnostics().is_empty()
}
```

**Step 2: Run check**

Run: `moon check`
Expected: `Finished. moon: no work to do` (zero errors)

---

### Task 5: Verify all tests pass and update snapshots if needed

**Files:**
- Read: `editor/parsed_editor_test.mbt`

**Step 1: Run tests**

Run: `moon test`
Expected: `Total tests: N, passed: N, failed: 0`

If any `inspect(...)` snapshot tests fail because AST output changed slightly, update them:

Run: `moon test --update`

**Step 2: Verify no manual dirty-flag references remain**

Run: `grep -rn "parse_dirty\|cached_text\|cached_errors\|reparse()" editor/`
Expected: no output (zero occurrences)

**Step 3: Run with deny-warn**

Run: `moon check --deny-warn`
Expected: `Finished. moon: ran N tasks, now up to date`

---

### Task 6: Update interfaces and format

**Files:**
- Modify: `editor/editor.mbti` (auto-generated)
- Modify: `editor/parsed_editor.mbt` (formatting)

**Step 1: Regenerate interfaces**

Run: `moon info`
Expected: `Finished.` — updates `editor/pkg.generated.mbti`

**Step 2: Check the diff**

Run: `git diff editor/*.mbti`

Expected removals:
- `parse_dirty`, `cached_text`, `cached_errors`, `ast` field lines
- `reparse` method

Expected: `mark_dirty` signature unchanged (same public API)

**Step 3: Format**

Run: `moon fmt`

**Step 4: Final check**

Run: `moon check --deny-warn && moon test`
Expected: zero warnings, all tests pass

**Step 5: Commit**

```bash
git add editor/parsed_editor.mbt editor/moon.pkg editor/parsed_editor_test.mbt editor/*.mbti
git commit -m "refactor(editor): replace ImperativeParser dirty-flags with ReactiveParser Signal/Memo

Remove parse_dirty, cached_text, cached_errors, ast fields and reparse().
ReactiveParser.set_source() is called after each text mutation; term() and
diagnostics() are memoized — no manual cache invalidation needed.

Implements Design §2 Strategy A."
```

---

## Status: COMPLETE

Merged via PR #16 (2026-03-05). All 13 tasks completed. Key outcomes:
- `ParsedEditor` uses `ReactiveParser` with Signal/Memo (no dirty flags)
- `projection/` package created with `CanonicalModel`, `ProjNode`, text/tree lenses
- `syntax_to_proj_node` walks `@seam.SyntaxNode` directly for accurate per-node spans
- `rebuild_kind` keeps `ProjNode.kind` in sync with `.children` after tree mutations
- 185/185 tests passing

## Success Criteria

1. `grep -rn "parse_dirty\|cached_text\|cached_errors\|fn reparse" editor/` → zero results
2. `moon check --deny-warn` → no warnings
3. `moon test` → all tests pass (185/185)
4. `editor/ParsedEditor` struct has exactly 2 fields: `editor` and `parser`

## What This Does NOT Change

- Public API of `ParsedEditor` is identical — all callers (`crdt.mbt`, tests) unchanged
- `edit_bridge.mbt` / `merge_to_edits` retained for future Strategy B/C (op-level edits)
- `@parser.syntax_node_to_ast_node` conversion is still called on each `get_ast()` — caching it is a future optimization
- `mark_dirty()` is kept as a public method (thin wrapper over `set_source`) so `crdt.mbt` callers need no changes

## Dependencies

- **Depends on:** Design §1 Edit Bridge (merged in PR #15) ✅
- **Depended on by:** Design §3 Unified Editor
