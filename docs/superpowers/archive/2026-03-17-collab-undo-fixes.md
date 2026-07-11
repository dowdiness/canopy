# Collaboration Undo Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire undo tracking suppression into `SyncEditor::apply_sync` and make `SyncEditor::undo()`/`redo()` return sync ops for peer broadcast.

**Architecture:** Two small changes in `editor/`: (1) `apply_sync` disables undo tracking before applying remote ops, re-enables after. (2) `undo()`/`redo()` capture the version before calling the UndoManager, then use `export_since()` to collect the inverse ops for peer sync.

**Tech Stack:** MoonBit, `event-graph-walker/text`, `event-graph-walker/undo`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `editor/sync_editor_sync.mbt` | Add tracking suppression to `apply_sync` |
| Modify | `editor/sync_editor_undo.mbt` | Make `undo()`/`redo()` return sync ops |
| Modify | `editor/sync_editor_test.mbt` | Tests for both fixes |
| Modify | `crdt.mbt` | Update JS bindings for new return types |
| Update | `editor/pkg.generated.mbti` | `moon info` regeneration |

---

### Task 1: Suppress undo tracking in apply_sync

**Files:**
- Modify: `editor/sync_editor_sync.mbt`
- Modify: `editor/sync_editor_test.mbt`

- [ ] **Step 1: Write failing test**

In `editor/sync_editor_test.mbt`, append:

```moonbit
///|
test "SyncEditor: apply_sync does not pollute undo stack" {
  let se1 = @editor.SyncEditor::new("alice", capture_timeout_ms=500)
  let se2 = @editor.SyncEditor::new("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync to Bob
  try! se2.apply_sync(try! se1.export_all())

  // Bob's undo stack should be empty — remote ops must not be tracked
  inspect(se2.can_undo(), content="false")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/editor -f sync_editor_test.mbt -i 0`
Expected: FAIL — `can_undo()` returns `true` because remote ops are recorded.

- [ ] **Step 3: Add tracking suppression to apply_sync**

In `editor/sync_editor_sync.mbt`, modify `apply_sync`:

```moonbit
///|
pub fn SyncEditor::apply_sync(
  self : SyncEditor,
  msg : @text.SyncMessage,
) -> Unit raise {
  let old_source = self.doc.text()
  self.undo.set_tracking(false)
  self.doc.sync().apply(msg)
  self.undo.set_tracking(true)
  self.adjust_cursor()
  self.sync_parser_after_text_change(old_source, self.doc.text(), None)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/editor -f sync_editor_test.mbt -i 0`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add editor/sync_editor_sync.mbt editor/sync_editor_test.mbt
git commit -m "fix(editor): suppress undo tracking during apply_sync

Remote ops applied via SyncEditor::apply_sync no longer pollute
the local undo stack. Fixes the SyncEditor-level half of P2-1."
```

---

### Task 2: Make undo/redo return sync ops

**Files:**
- Modify: `editor/sync_editor_undo.mbt`
- Modify: `editor/sync_editor_test.mbt`

- [ ] **Step 1: Write failing test**

In `editor/sync_editor_test.mbt`, append:

```moonbit
///|
test "SyncEditor: undo returns sync message for peer broadcast" {
  let se = @editor.SyncEditor::new("alice", capture_timeout_ms=500)

  // Type some text
  try! se.insert_and_record("hello", 1000)
  let ver_before_undo = se.get_version()

  // Undo
  let msg = se.undo_and_export()
  inspect(se.get_text(), content="")

  // The returned message should contain ops
  match msg {
    Some(m) => inspect(m.is_empty(), content="false")
    None => inspect(false, content="true") // should have returned Some
  }
}

///|
test "SyncEditor: undo sync ops can be applied to peer" {
  let se1 = @editor.SyncEditor::new("alice", capture_timeout_ms=500)
  let se2 = @editor.SyncEditor::new("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync initial state to Bob
  try! se2.apply_sync(try! se1.export_all())
  inspect(se2.get_text(), content="hello")

  // Alice undoes and gets sync ops
  let msg = se1.undo_and_export()
  inspect(se1.get_text(), content="")

  // Apply undo ops to Bob
  match msg {
    Some(m) => try! se2.apply_sync(m)
    None => ()
  }

  // Bob should converge with Alice
  inspect(se2.get_text(), content="")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/editor -f sync_editor_test.mbt -i 0`
Expected: FAIL — `undo_and_export` not defined.

- [ ] **Step 3: Implement undo_and_export / redo_and_export**

In `editor/sync_editor_undo.mbt`, add:

```moonbit
///|
/// Undo and return a SyncMessage containing the inverse ops for peer broadcast.
/// Returns None if undo stack is empty or undo fails.
pub fn SyncEditor::undo_and_export(self : SyncEditor) -> @text.SyncMessage? {
  let ver_before = self.doc.version()
  let success = try {
    self.undo.undo(self.doc)
    self.adjust_cursor()
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
  if not(success) {
    return None
  }
  try {
    Some(self.doc.sync().export_since(ver_before))
  } catch {
    _ => None
  }
}

///|
/// Redo and return a SyncMessage containing the ops for peer broadcast.
/// Returns None if redo stack is empty or redo fails.
pub fn SyncEditor::redo_and_export(self : SyncEditor) -> @text.SyncMessage? {
  let ver_before = self.doc.version()
  let success = try {
    self.undo.redo(self.doc)
    self.adjust_cursor()
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
  if not(success) {
    return None
  }
  try {
    Some(self.doc.sync().export_since(ver_before))
  } catch {
    _ => None
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/canopy/editor -f sync_editor_test.mbt -i 0`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add editor/sync_editor_undo.mbt editor/sync_editor_test.mbt
git commit -m "feat(editor): add undo_and_export / redo_and_export

SyncEditor::undo_and_export() captures the document version before
undoing, then returns a SyncMessage via export_since() containing
the inverse ops for peer broadcast. Same for redo_and_export()."
```

---

### Task 3: Update JS bindings + moon info

**Files:**
- Modify: `crdt.mbt`
- Update: `editor/pkg.generated.mbti`

- [ ] **Step 1: Add JS bindings for new methods**

In `crdt.mbt`, add after the existing `undo_manager_undo`:

```moonbit
///|
/// Undo and return sync ops as JSON for peer broadcast.
pub fn undo_and_export_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) =>
      match ed.undo_and_export() {
        Some(msg) => msg.to_json_string() catch { _ => "" }
        None => ""
      }
    None => ""
  }
}

///|
/// Redo and return sync ops as JSON for peer broadcast.
pub fn redo_and_export_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) =>
      match ed.redo_and_export() {
        Some(msg) => msg.to_json_string() catch { _ => "" }
        None => ""
      }
    None => ""
  }
}
```

- [ ] **Step 2: Also suppress tracking in apply_sync_json**

In `crdt.mbt`, update `apply_sync_json` to use the tracking-suppressed `apply_sync` (which already handles this after Task 1):

Verify the existing `apply_sync_json` calls `ed.apply_sync(msg)` — it does, so no change needed here. The fix in Task 1 covers this path.

- [ ] **Step 3: moon info + moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 4: Review .mbti changes**

Run: `git diff *.mbti`

Expected new entries in `editor/pkg.generated.mbti`:
- `pub fn SyncEditor::undo_and_export(Self) -> @text.SyncMessage?`
- `pub fn SyncEditor::redo_and_export(Self) -> @text.SyncMessage?`

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add crdt.mbt editor/pkg.generated.mbti pkg.generated.mbti
git commit -m "feat: add JS bindings for undo/redo with sync export"
```

---

## Post-implementation notes

**Not done yet (follow-up):**
1. **Update valtio TypeScript API** — Wire `undo_and_export_json` / `redo_and_export_json` into `egwalker_api_sync.ts` and `egwalker_bridge.mbt` to replace the current `undo_sync_ops` pattern.
2. **Update TODO.md** — Mark the two new collaboration items as done.
