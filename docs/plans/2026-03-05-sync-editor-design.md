# SyncEditor Unified Facade — Implementation Plan

> **Status:** COMPLETE (PR #17)

**Goal:** Replace `ParsedEditor` + separate `UndoManager` global with a single `SyncEditor` facade that composes `TextDoc`, `UndoManager`, and `ReactiveParser` directly.

**Architecture:** `SyncEditor` owns `TextDoc` (CRDT source of truth), `UndoManager` (undo/redo), and `ReactiveParser` (lazy incremental parser). It exposes the same public API as `ParsedEditor` plus undo methods. The FFI layer (`crdt.mbt`) switches from two globals (`editor` + `undo_mgr`) to one (`editor: Ref[SyncEditor?]`).

**Tech Stack:** MoonBit, eg-walker CRDT (`@text.TextDoc`), loom (`@loom.ReactiveParser`), eg-walker undo (`@undo.UndoManager`)

**Parent design:** [Design 03: Unified Editor](../design/03-unified-editor.md)

---

## Task 1: Create `SyncEditor` struct and constructor

**Files:**
- Create: `editor/sync_editor.mbt`

**Step 1: Write the struct and `new` constructor**

The `editor/moon.pkg` already imports `dowdiness/event-graph-walker/text`, `dowdiness/loom`, and `dowdiness/lambda`. It does NOT import `dowdiness/event-graph-walker/undo` yet — that must be added.

First, add the undo import to `editor/moon.pkg`:

```moonbit
// editor/moon.pkg — add this import
import {
  "dowdiness/event-graph-walker/text",
  "dowdiness/event-graph-walker/undo",   // NEW
  "dowdiness/lambda" @parser,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loom_core,
  "dowdiness/seam",
  "moonbitlang/core/quickcheck",
}
```

Then create `editor/sync_editor.mbt`:

```moonbit
// SyncEditor: Unified facade composing TextDoc + UndoManager + ReactiveParser
// Replaces ParsedEditor + separate UndoManager global

///|
pub struct SyncEditor {
  doc : @text.TextDoc
  undo : @undo.UndoManager
  parser : @loom.ReactiveParser[@parser.SyntaxNode]
  mut cursor : Int
}

///|
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor {
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser: @loom.new_reactive_parser("", @parser.lambda_grammar),
    cursor: 0,
  }
}
```

**Step 2: Run `moon check` to verify it compiles**

Run: `moon check`
Expected: PASS (no errors)

**Step 3: Commit**

```bash
git add editor/moon.pkg editor/sync_editor.mbt
git commit -m "feat(editor): add SyncEditor struct and constructor"
```

---

## Task 2: Add editing methods to `SyncEditor`

**Files:**
- Modify: `editor/sync_editor.mbt`

**Step 1: Add `insert`, `delete`, `backspace`, `move_cursor` methods**

These compose `TextDoc` directly (not through `Editor`). After each text mutation, call `parser.set_source()`.

```moonbit
///|
pub fn SyncEditor::insert(self : SyncEditor, text : String) -> Unit raise {
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor = self.cursor + text.length()
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::delete(self : SyncEditor) -> Bool {
  try self.doc.delete(@text.Pos::at(self.cursor)) catch {
    _ => false
  } noraise {
    _ => {
      self.parser.set_source(self.doc.text())
      true
    }
  }
}

///|
pub fn SyncEditor::backspace(self : SyncEditor) -> Bool {
  if self.cursor > 0 {
    self.cursor = self.cursor - 1
    try self.doc.delete(@text.Pos::at(self.cursor)) catch {
      _ => {
        self.cursor = self.cursor + 1
        false
      }
    } noraise {
      _ => {
        self.parser.set_source(self.doc.text())
        true
      }
    }
  } else {
    false
  }
}

///|
pub fn SyncEditor::move_cursor(self : SyncEditor, position : Int) -> Unit {
  let text_len = self.doc.len()
  if position < 0 {
    self.cursor = 0
  } else if position > text_len {
    self.cursor = text_len
  } else {
    self.cursor = position
  }
}
```

**Step 2: Run `moon check`**

Run: `moon check`
Expected: PASS

**Step 3: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "feat(editor): add SyncEditor editing methods"
```

---

## Task 3: Add query methods to `SyncEditor`

**Files:**
- Modify: `editor/sync_editor.mbt`

**Step 1: Add `get_text`, `get_cursor`, `get_ast`, `get_errors`, `is_parse_valid`, `mark_dirty`**

```moonbit
///|
pub fn SyncEditor::get_text(self : SyncEditor) -> String {
  self.doc.text()
}

///|
pub fn SyncEditor::get_cursor(self : SyncEditor) -> Int {
  self.cursor
}

///|
pub fn SyncEditor::mark_dirty(self : SyncEditor) -> Unit {
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::get_ast(self : SyncEditor) -> @ast.Term {
  let syntax_node = self.parser.term()
  @parser.syntax_node_to_term(syntax_node)
}

///|
pub fn SyncEditor::get_errors(self : SyncEditor) -> Array[String] {
  self.parser.diagnostics()
}

///|
pub fn SyncEditor::is_parse_valid(self : SyncEditor) -> Bool {
  self.get_errors().is_empty()
}
```

**Step 2: Run `moon check`**

Run: `moon check`
Expected: PASS

**Step 3: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "feat(editor): add SyncEditor query methods"
```

---

## Task 4: Add sync methods to `SyncEditor`

**Files:**
- Modify: `editor/sync_editor.mbt`

**Step 1: Add `apply_sync`, `get_version`, `export_all`, `export_since`**

```moonbit
///|
fn SyncEditor::adjust_cursor(self : SyncEditor) -> Unit {
  let text_len = self.doc.len()
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
pub fn SyncEditor::apply_sync(
  self : SyncEditor,
  msg : @text.SyncMessage,
) -> Unit raise {
  self.doc.sync().apply(msg)
  self.adjust_cursor()
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::get_version(self : SyncEditor) -> @text.Version {
  self.doc.version()
}

///|
pub fn SyncEditor::export_all(self : SyncEditor) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
pub fn SyncEditor::export_since(
  self : SyncEditor,
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}
```

**Step 2: Run `moon check`**

Run: `moon check`
Expected: PASS

**Step 3: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "feat(editor): add SyncEditor sync methods"
```

---

## Task 5: Add undo methods to `SyncEditor`

**Files:**
- Modify: `editor/sync_editor.mbt`

**Step 1: Add undo/redo convenience methods and record+edit methods**

These internalize the `UndoManager` calls that were previously split across `crdt.mbt`:

```moonbit
///|
pub fn SyncEditor::insert_and_record(
  self : SyncEditor,
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  self.doc.insert_and_record(
    @text.Pos::at(self.cursor),
    text,
    self.undo,
    timestamp_ms~,
  )
  self.cursor = self.cursor + text.length()
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::delete_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  try {
    self.doc.delete_and_record(
      @text.Pos::at(self.cursor),
      self.undo,
      timestamp_ms~,
    )
    self.parser.set_source(self.doc.text())
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::backspace_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  if self.cursor > 0 {
    let new_pos = self.cursor - 1
    try {
      self.doc.delete_and_record(
        @text.Pos::at(new_pos),
        self.undo,
        timestamp_ms~,
      )
      self.cursor = new_pos
      self.parser.set_source(self.doc.text())
      true
    } catch {
      _ => false
    }
  } else {
    false
  }
}

///|
pub fn SyncEditor::undo(self : SyncEditor) -> Bool {
  try {
    self.undo.undo(self.doc)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::redo(self : SyncEditor) -> Bool {
  try {
    self.undo.redo(self.doc)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::can_undo(self : SyncEditor) -> Bool {
  self.undo.can_undo()
}

///|
pub fn SyncEditor::can_redo(self : SyncEditor) -> Bool {
  self.undo.can_redo()
}

///|
pub fn SyncEditor::set_tracking(self : SyncEditor, enabled : Bool) -> Unit {
  self.undo.set_tracking(enabled)
}

///|
pub fn SyncEditor::clear_undo(self : SyncEditor) -> Unit {
  self.undo.clear()
}
```

**Step 2: Run `moon check`**

Run: `moon check`
Expected: PASS

**Step 3: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "feat(editor): add SyncEditor undo methods"
```

---

## Task 6: Write `SyncEditor` tests

**Files:**
- Create: `editor/sync_editor_test.mbt`

**Step 1: Write tests ported from `parsed_editor_test.mbt` + new undo tests**

Port all 14 tests from `editor/parsed_editor_test.mbt`, changing `ParsedEditor::new` to `SyncEditor::new`. Add undo-specific tests.

```moonbit
// Tests for SyncEditor

///|
test "SyncEditor: create and insert text" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  inspect(se.get_text(), content="x")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="x")
}

///|
test "SyncEditor: sequential inserts update AST" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  inspect(@ast.print_term(se.get_ast()), content="x")
  try! se.insert(" + 1")
  inspect(@ast.print_term(se.get_ast()), content="(x + 1)")
}

///|
test "SyncEditor: delete updates AST" {
  let se = SyncEditor::new("agent1")
  try! se.insert("123")
  inspect(se.get_text(), content="123")
  let deleted = se.backspace()
  inspect(deleted, content="true")
  inspect(se.get_text(), content="12")
}

///|
test "SyncEditor: parse error handling" {
  let se = SyncEditor::new("agent1")
  try! se.insert("λ.")
  let _ast = se.get_ast()
  inspect(se.is_parse_valid(), content="false")
}

///|
test "SyncEditor: cursor tracking" {
  let se = SyncEditor::new("agent1")
  inspect(se.get_cursor(), content="0")
  try! se.insert("abc")
  inspect(se.get_cursor(), content="3")
  se.move_cursor(1)
  inspect(se.get_cursor(), content="1")
}

///|
test "SyncEditor: concurrent edits converge" {
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="x")
  inspect(se2.get_text(), content="x")
  try! se1.insert(" + 1")
  try! se2.insert(" - 2")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  let text1 = se1.get_text()
  let text2 = se2.get_text()
  inspect(text1 == text2, content="true")
  inspect(
    @ast.print_term(se1.get_ast()) == @ast.print_term(se2.get_ast()),
    content="true",
  )
}

///|
test "SyncEditor: collaborative lambda editing" {
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
  try! se1.insert("λx.")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="λx.")
  inspect(se2.get_text(), content="λx.")
  try! se1.insert("x + 1")
  try! se2.insert("x - 1")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text() == se2.get_text(), content="true")
  inspect(
    @ast.print_term(se1.get_ast()) == @ast.print_term(se2.get_ast()),
    content="true",
  )
}

///|
test "SyncEditor: incremental parsing vs full reparse" {
  let se = SyncEditor::new("agent1")
  try! se.insert("λf.λx.if f x then x + 1 else x - 1")
  let _ast1 = se.get_ast()
  se.move_cursor(34)
  let _deleted = se.backspace()
  try! se.insert("2")
  let ast2 = se.get_ast()
  inspect(
    @ast.print_term(ast2),
    content="(λf. (λx. if (f x) then (x + 1) else (x - 2)))",
  )
}

///|
test "SyncEditor: empty document" {
  let se = SyncEditor::new("agent1")
  inspect(se.get_text(), content="")
  let _ast = se.get_ast()
}

///|
test "SyncEditor: backspace at start returns false" {
  let se = SyncEditor::new("agent1")
  try! se.insert("abc")
  se.move_cursor(0)
  inspect(se.backspace(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: delete at end returns false" {
  let se = SyncEditor::new("agent1")
  try! se.insert("abc")
  se.move_cursor(3)
  inspect(se.delete(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: export_all produces non-empty message" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  let msg = try! se.export_all()
  inspect(msg.op_count() > 0, content="true")
}

///|
test "SyncEditor: lazy AST evaluation" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  let _ast1 = se.get_ast()
  let ast2 = se.get_ast()
  inspect(@ast.print_term(ast2), content="x")
}

///|
test "SyncEditor: merge invalidates AST cache" {
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  let _ast1 = se1.get_ast()
  try! se2.insert("y")
  try! se1.apply_sync(try! se2.export_all())
  let _ast2 = se1.get_ast()
  inspect(se1.get_text(), content="xy")
}

///|
test "SyncEditor: insert_and_record + undo roundtrip" {
  let se = SyncEditor::new("agent1")
  try! se.insert_and_record("hello", 1000)
  inspect(se.get_text(), content="hello")
  inspect(se.can_undo(), content="true")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="")
  inspect(se.can_redo(), content="true")
  let redone = se.redo()
  inspect(redone, content="true")
  inspect(se.get_text(), content="hello")
}

///|
test "SyncEditor: backspace_and_record + undo" {
  let se = SyncEditor::new("agent1")
  try! se.insert_and_record("abc", 1000)
  let deleted = se.backspace_and_record(2000)
  inspect(deleted, content="true")
  inspect(se.get_text(), content="ab")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: clear_undo empties stacks" {
  let se = SyncEditor::new("agent1")
  try! se.insert_and_record("x", 1000)
  inspect(se.can_undo(), content="true")
  se.clear_undo()
  inspect(se.can_undo(), content="false")
}
```

**Step 2: Run tests to verify they pass**

Run: `moon test -f sync_editor_test.mbt`
Expected: All 17 tests PASS

**Step 3: Commit**

```bash
git add editor/sync_editor_test.mbt
git commit -m "test(editor): add SyncEditor tests"
```

---

## Task 7: Switch `crdt.mbt` FFI to `SyncEditor`

**Files:**
- Modify: `crdt.mbt`

**Step 1: Replace `ParsedEditor` + `undo_mgr` globals with `SyncEditor`**

Change the global refs:

```moonbit
// Before (lines 7-11):
let editor : Ref[@editor.ParsedEditor?] = { val: None }
let undo_mgr : Ref[@undo.UndoManager?] = { val: None }

// After:
let editor : Ref[@editor.SyncEditor?] = { val: None }
```

**Step 2: Update `create_editor` and `create_editor_with_undo`**

```moonbit
// Before:
pub fn create_editor(agent_id : String) -> Int {
  editor.val = Some(@editor.ParsedEditor::new(agent_id))
  1
}

pub fn create_editor_with_undo(agent_id : String, capture_timeout_ms : Int) -> Int {
  editor.val = Some(@editor.ParsedEditor::new(agent_id))
  undo_mgr.val = Some(@undo.UndoManager::new(agent_id, capture_timeout_ms~))
  1
}

// After:
pub fn create_editor(agent_id : String) -> Int {
  editor.val = Some(@editor.SyncEditor::new(agent_id))
  1
}

pub fn create_editor_with_undo(agent_id : String, capture_timeout_ms : Int) -> Int {
  editor.val = Some(@editor.SyncEditor::new(agent_id, capture_timeout_ms~))
  1
}
```

**Step 3: Update all undo-integrated FFI functions**

The key change: replace `match (editor.val, undo_mgr.val)` with `match editor.val`, and call `SyncEditor` methods directly.

`insert_and_record`:
```moonbit
// Before: match (editor.val, undo_mgr.val) { (Some(ed), Some(mgr)) => ...ed.editor.doc.insert_and_record(..., mgr, ...)
// After:
pub fn insert_and_record(_handle : Int, text : String, timestamp_ms : Int) -> Unit {
  match editor.val {
    Some(ed) => try! ed.insert_and_record(text, timestamp_ms)
    None => ()
  }
}
```

`delete_and_record`:
```moonbit
pub fn delete_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.delete_and_record(timestamp_ms)
    None => false
  }
}
```

`backspace_and_record`:
```moonbit
pub fn backspace_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.backspace_and_record(timestamp_ms)
    None => false
  }
}
```

`set_text_and_record` — this function does raw diff+insert/delete on `ed.editor.doc`. It must now use `ed.doc` directly:
```moonbit
pub fn set_text_and_record(_handle : Int, new_text : String, timestamp_ms : Int) -> Unit {
  match editor.val {
    Some(ed) => {
      let old_text = ed.get_text()
      if old_text == new_text {
        return
      }
      let old_len = old_text.length()
      let new_len = new_text.length()
      let mut prefix = 0
      while prefix < old_len && prefix < new_len && old_text[prefix] == new_text[prefix] {
        prefix = prefix + 1
      }
      let mut suffix = 0
      while suffix < old_len - prefix && suffix < new_len - prefix && old_text[old_len - 1 - suffix] == new_text[new_len - 1 - suffix] {
        suffix = suffix + 1
      }
      let del_count = old_len - prefix - suffix
      let ins_len = new_len - prefix - suffix
      for _i = 0; _i < del_count; _i = _i + 1 {
        ed.doc.delete_and_record(@text.Pos::at(prefix), ed.undo, timestamp_ms~) catch { _ => () }
      }
      if ins_len > 0 {
        let inserted = new_text[prefix:prefix + ins_len].to_string() catch { _ => "" }
        if inserted.length() > 0 {
          ed.doc.insert_and_record(@text.Pos::at(prefix), inserted, ed.undo, timestamp_ms~) catch { _ => () }
        }
      }
      ed.mark_dirty()
    }
    None => ()
  }
}
```

`set_text` — same change, use `ed.doc` instead of `ed.editor.doc`:
```moonbit
pub fn set_text(_handle : Int, new_text : String) -> Unit {
  match editor.val {
    Some(ed) => {
      let old_text = ed.get_text()
      if old_text == new_text {
        return
      }
      let old_len = old_text.length()
      ed.move_cursor(0)
      for _i = 0; _i < old_len; _i = _i + 1 {
        let _ = ed.delete()
      }
      if new_text.length() > 0 {
        try! ed.insert(new_text)
      }
    }
    None => ()
  }
}
```

`undo_manager_undo` / `redo`:
```moonbit
pub fn undo_manager_undo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.undo()
    None => false
  }
}

pub fn undo_manager_redo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.redo()
    None => false
  }
}
```

`undo_manager_can_undo` / `can_redo` / `set_tracking` / `clear`:
```moonbit
pub fn undo_manager_can_undo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.can_undo()
    None => false
  }
}

pub fn undo_manager_can_redo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.can_redo()
    None => false
  }
}

pub fn undo_manager_set_tracking(_handle : Int, enabled : Bool) -> Unit {
  match editor.val {
    Some(ed) => ed.set_tracking(enabled)
    None => ()
  }
}

pub fn undo_manager_clear(_handle : Int) -> Unit {
  match editor.val {
    Some(ed) => ed.clear_undo()
    None => ()
  }
}
```

**Step 4: Remove `undo` import from root `moon.pkg`**

The root `moon.pkg` currently imports `dowdiness/event-graph-walker/undo`. Since `SyncEditor` owns the `UndoManager` internally, `crdt.mbt` no longer needs direct access. Remove the import:

```moonbit
// moon.pkg — remove "dowdiness/event-graph-walker/undo"
import {
  "dowdiness/crdt/editor",
  "dowdiness/event-graph-walker/text",
  "dowdiness/lambda" @parser,
  "moonbitlang/core/json",
}
```

**Note:** If `set_text_and_record` still accesses `ed.doc` and `ed.undo` directly (which are `@text.TextDoc` and `@undo.UndoManager`), you may still need the imports. Check `moon check` — if it fails because `@text.Pos` or `ed.doc.delete_and_record` needs the undo import, keep it.

**Step 5: Run `moon check`**

Run: `moon check`
Expected: PASS

**Step 6: Run all tests**

Run: `moon test`
Expected: All tests PASS (existing + new SyncEditor tests)

**Step 7: Commit**

```bash
git add crdt.mbt moon.pkg
git commit -m "refactor(ffi): switch crdt.mbt from ParsedEditor+UndoManager to SyncEditor"
```

---

## Task 8: Delete `ParsedEditor`

**Files:**
- Delete: `editor/parsed_editor.mbt`
- Delete: `editor/parsed_editor_test.mbt`

**Step 1: Delete both files**

```bash
rm editor/parsed_editor.mbt editor/parsed_editor_test.mbt
```

**Step 2: Run `moon check`**

Run: `moon check`
Expected: PASS — no other file references `ParsedEditor`

If `moon check` fails, grep for remaining `ParsedEditor` references and fix them.

**Step 3: Run all tests**

Run: `moon test`
Expected: All tests PASS

**Step 4: Update interfaces**

Run: `moon info && moon fmt`
Check: `git diff editor/pkg.generated.mbti` — verify `ParsedEditor` is gone and `SyncEditor` is present

**Step 5: Commit**

```bash
git add -A editor/
git commit -m "refactor(editor): remove ParsedEditor, replaced by SyncEditor"
```

---

## Task 9: Final verification

**Files:** None (verification only)

**Step 1: Run full test suite**

Run: `moon test`
Expected: All tests PASS

**Step 2: Run `moon check` and `moon fmt`**

Run: `moon check && moon fmt`
Expected: Clean

**Step 3: Verify no dual state remains**

Run: `grep -r "parse_dirty\|cached_text\|ParsedEditor" editor/ crdt.mbt`
Expected: No matches

**Step 4: Build JS target**

Run: `moon build --target js`
Expected: Builds successfully

**Step 5: Verify JS exports unchanged**

Check that `moon.pkg` still exports all the same FFI functions. The JS API is unchanged — no JavaScript modifications needed.

**Step 6: Commit any final fixups**

```bash
git add -A
git commit -m "chore: final cleanup after SyncEditor migration"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | SyncEditor struct + constructor | `editor/sync_editor.mbt`, `editor/moon.pkg` |
| 2 | Editing methods | `editor/sync_editor.mbt` |
| 3 | Query methods | `editor/sync_editor.mbt` |
| 4 | Sync methods | `editor/sync_editor.mbt` |
| 5 | Undo methods | `editor/sync_editor.mbt` |
| 6 | Tests | `editor/sync_editor_test.mbt` |
| 7 | Switch `crdt.mbt` FFI | `crdt.mbt`, `moon.pkg` |
| 8 | Delete `ParsedEditor` | `editor/parsed_editor.mbt`, `editor/parsed_editor_test.mbt` |
| 9 | Final verification | (none — verification only) |
