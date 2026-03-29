# Zipper Keyboard Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard-driven structural navigation and editing to the ideal editor's outline tree using the zipper package.

**Architecture:** Arrow keys navigate via `@zipper.navigate()`, Delete triggers `editor.apply_tree_edit()`, `.` opens the existing action overlay. Three new Msg variants keep keyboard paths separate from the existing click/JS-global paths. All work is in `examples/ideal/main/`.

**Tech Stack:** MoonBit, Rabbita (Elm architecture), zipper package (`lang/lambda/zipper/`)

**Design spec:** `docs/plans/2026-03-29-zipper-keyboard-integration.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `examples/ideal/main/moon.pkg` | Modify | Add `@zipper` import |
| `examples/ideal/main/msg.mbt` | Modify | Add 3 new Msg variants |
| `examples/ideal/main/view_outline.mbt` | Modify | Add `tabindex` + `on_keydown` to tree container |
| `examples/ideal/main/main.mbt` | Modify | Add 3 update handlers |
| `examples/ideal/main/bridge_ffi.mbt` | Modify | Add 2 new FFI functions |
| `examples/ideal/main/view_actions.mbt` | Modify | Add `on_keydown` to overlay panel |

---

### Task 1: Add @zipper import to moon.pkg

**Files:**
- Modify: `examples/ideal/main/moon.pkg`

- [ ] **Step 1: Add zipper package import**

In `examples/ideal/main/moon.pkg`, add to the import block:

```
  "dowdiness/canopy/lang/lambda/zipper" @zipper,
```

- [ ] **Step 2: Verify compilation**

Run: `cd examples/ideal && moon check`
Expected: PASS (no errors)

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/moon.pkg
git commit -m "chore: add @zipper import to ideal editor"
```

---

### Task 2: Add Msg variants and update handlers

Msg variants and handlers are added together to avoid non-exhaustive match errors.

**Files:**
- Modify: `examples/ideal/main/msg.mbt`
- Modify: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Add three new Msg variants**

In `examples/ideal/main/msg.mbt`, add after `OutlineNodeClicked(String)`:

```moonbit
  // Keyboard navigation in outline — updates selection without stealing editor focus
  OutlineNavigate(String)
  // Keyboard structural edit in outline — CRDT round-trip
  OutlineStructuralEdit(@lambda_edits.TreeEditOp)
  // Open action overlay anchored to outline row, node from model.selected_node
  OpenActionOverlayFromOutline
```

---

### Task 3: Add FFI functions

**Files:**
- Modify: `examples/ideal/main/bridge_ffi.mbt`

- [ ] **Step 1: Add js_get_outline_selected_rect**

Add at the end of `bridge_ffi.mbt`:

```moonbit
///|
/// Get bounding rect of the selected outline row for overlay anchoring.
extern "js" fn js_get_outline_selected_rect() -> String =
  #| function() {
  #|   var sel = document.querySelector('.outline-panel .tree-row.selected');
  #|   if (!sel) return '{}';
  #|   var r = sel.getBoundingClientRect();
  #|   return JSON.stringify({ top: Math.round(r.top), left: Math.round(r.left), bottom: Math.round(r.bottom), right: Math.round(r.right) });
  #| }
```

- [ ] **Step 2: Add js_scroll_outline_to_selected**

```moonbit
///|
/// Scroll the selected outline row into view.
extern "js" fn js_scroll_outline_to_selected() -> Unit =
  #| function() {
  #|   var sel = document.querySelector('.outline-panel .tree-row.selected');
  #|   if (sel) sel.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  #| }
```

- [ ] **Step 3: Add js_focus_outline_overlay**

The existing `js_focus_overlay_panel()` looks inside `canopy-editor.shadowRoot` but the Rabbita overlay is in the page DOM. Add a new function that targets the page DOM:

```moonbit
///|
/// Focus the action overlay panel in the page DOM (not shadow DOM).
/// Used when overlay is opened from outline keyboard context.
extern "js" fn js_focus_outline_overlay() -> Unit =
  #| function() {
  #|   var panel = document.querySelector('.action-overlay-panel');
  #|   if (panel) panel.focus();
  #| }
```

- [ ] **Step 4: Verify compilation**

Run: `cd examples/ideal && moon check`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/bridge_ffi.mbt
git commit -m "feat: add outline keyboard FFI (rect, scroll, focus)"
```

- [ ] **Step 2: Add OutlineNavigate handler**

In the `update` function's Msg match, add after the `OutlineNodeClicked` handler (around line 494):

```moonbit
    OutlineNavigate(node_id_str) => {
      // Update selection without touching editor focus — outline keeps keyboard focus
      let new_selected = if node_id_str == "" { None } else { Some(node_id_str) }
      // Also update outline_state.selection for visual highlighting
      let outline_state = match new_selected {
        Some(s) => {
          let nid_int = @strconv.parse_int(s) catch { _ => return (none, model) }
          let nid = @proj.NodeId::from_int(nid_int)
          model.outline_state.apply_edit(@lambda_edits.Select(node_id=nid))
        }
        None => model.outline_state
      }
      let scroll_cmd = @rabbita_cmd.raw_effect(
        fn(_) { js_scroll_outline_to_selected() },
        kind=@rabbita_cmd.after_render,
      )
      (scroll_cmd, { ..model, selected_node: new_selected, outline_state })
    }
```

- [ ] **Step 2: Add OutlineStructuralEdit handler**

Add after the `OutlineNavigate` handler:

```moonbit
    OutlineStructuralEdit(tree_op) => {
      match model.editor.apply_tree_edit(tree_op, model.next_timestamp) {
        Ok(_) => {
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
          })
          // Relocate selection to where FocusHint placed the text cursor
          let new_selected = match new_model.editor.get_source_map().innermost_node_at(
            new_model.editor.get_cursor(),
          ) {
            Some(nid) => Some(nid.0.to_string())
            None => None
          }
          let text = new_model.editor.get_text()
          let cmd = @rabbita.effect(fn() { js_reconcile_editor_with_text(text) })
          (cmd, { ..new_model, selected_node: new_selected })
        }
        Err(_) => (none, model)
      }
    }
```

- [ ] **Step 3: Add OpenActionOverlayFromOutline handler**

Add after the `OutlineStructuralEdit` handler:

```moonbit
    OpenActionOverlayFromOutline => {
      let node_id_str = match model.selected_node {
        Some(s) => s
        None => return (none, model)
      }
      let ctx = match detect_action_context(model.editor, node_id_str) {
        Some(c) => c
        None => return (none, model)
      }
      let proj_ctx = to_proj_context(ctx)
      let actions = @proj.get_actions_for_node(ctx.kind, proj_ctx)
      if actions.is_empty() {
        return (none, model)
      }
      let rect_json = js_get_outline_selected_rect()
      let (anchor_top, anchor_left) = parse_anchor_rect(rect_json)
      js_set_overlay_open(true)
      let new_model = {
        ..model,
        overlay: {
          visible: true,
          actions,
          node_context: Some(ctx),
          submenu: None,
          pending_action: None,
          name_value: "",
          name_error: "",
          anchor_top,
          anchor_left,
        },
      }
      let focus_cmd = @rabbita_cmd.raw_effect(
        fn(_) { js_focus_outline_overlay() },
        kind=@rabbita_cmd.after_render,
      )
      (focus_cmd, new_model)
    }
```

- [ ] **Step 4: Fix ActionKeyPressed to use its argument**

The current handler (around line 531) ignores the `_key_arg` parameter and reads from `js_take_action_key()`. Change it to use the argument when non-empty:

Find this line:
```moonbit
    ActionKeyPressed(_key_arg) => {
      let key = js_take_action_key()
```

Replace with:
```moonbit
    ActionKeyPressed(key_arg) => {
      let key = if key_arg != "" { key_arg } else { js_take_action_key() }
```

This makes the handler work for both:
- ProseMirror keymap (argument is empty, key in JS global)
- Rabbita `on_keydown` (argument has the key)

- [ ] **Step 5: Verify compilation**

Run: `cd examples/ideal && moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/main.mbt
git commit -m "feat: add OutlineNavigate, OutlineStructuralEdit, OpenActionOverlayFromOutline handlers"
```

---

### Task 4: Add on_keydown to overlay panel

**Files:**
- Modify: `examples/ideal/main/view_actions.mbt`

- [ ] **Step 1: Add on_keydown to the overlay panel div**

In `view_action_overlay` (around line 195), find the overlay panel div:

```moonbit
    @html.div(
      class="action-overlay-panel",
      attrs=@html.Attrs::build()
        .role("menu")
        .aria_label("Structural editing actions")
        .tabindex(-1)
        .style_attr(position_style),
      [content],
    ),
```

Add `on_keydown` to capture mnemonic keys:

```moonbit
    @html.div(
      class="action-overlay-panel",
      on_keydown=fn(kb : @html.Keyboard) {
        let key = kb.key()
        if key == "Escape" {
          dispatch(CloseActionOverlay)
        } else {
          dispatch(ActionKeyPressed(key))
        }
      },
      attrs=@html.Attrs::build()
        .role("menu")
        .aria_label("Structural editing actions")
        .tabindex(-1)
        .style_attr(position_style),
      [content],
    ),
```

This means when the overlay panel has focus (via `js_focus_outline_overlay()`), key presses go directly to `ActionKeyPressed` with the key as the argument — no JS global needed.

- [ ] **Step 2: Verify compilation**

Run: `cd examples/ideal && moon check`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/view_actions.mbt
git commit -m "feat: add on_keydown to overlay panel for keyboard mnemonic dispatch"
```

---

### Task 5: Add keydown handler to outline tree

**Files:**
- Modify: `examples/ideal/main/view_outline.mbt`

- [ ] **Step 1: Add navigate_outline helper function**

Add at the top of `view_outline.mbt`:

```moonbit
///|
/// Compute structural navigation from the current selection.
fn navigate_outline(
  model : Model,
  direction : @zipper.Direction,
) -> String? {
  let node_id_str = match model.selected_node {
    Some(s) => s
    None => return None
  }
  let n = @strconv.parse_int(node_id_str) catch { _ => return None }
  let node_id = @proj.NodeId::from_int(n)
  let proj_root = match model.editor.get_proj_node() {
    Some(p) => p
    None => return None
  }
  let term = model.editor.get_ast()
  match @zipper.navigate(node_id, direction, term, proj_root) {
    Some(new_id) => Some(new_id.0.to_string())
    None => None
  }
}

///|
/// Get the NodeId of the currently selected outline node.
fn get_selected_node_id(model : Model) -> @proj.NodeId? {
  let s = match model.selected_node {
    Some(s) => s
    None => return None
  }
  let n = match @strconv.parse_int?(s) {
    Ok(n) => n
    Err(_) => return None
  }
  Some(@proj.NodeId::from_int(n))
}
```

- [ ] **Step 2: Add keydown handler to view_outline_content**

Replace the `view_outline_content` function:

```moonbit
///|
/// Render outline tree content with keyboard navigation.
fn view_outline_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  let handle_keydown = fn(kb : @html.Keyboard) {
    let key = kb.key()
    match key {
      "ArrowUp" =>
        match navigate_outline(model, @zipper.Direction::Up) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowDown" =>
        match navigate_outline(model, @zipper.Direction::Down) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowLeft" =>
        match navigate_outline(model, @zipper.Direction::Left) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowRight" =>
        match navigate_outline(model, @zipper.Direction::Right) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "Enter" =>
        match get_selected_node_id(model) {
          Some(nid) => {
            let op = if model.outline_state.collapsed_nodes.contains(nid) {
              @lambda_edits.Expand(node_id=nid)
            } else {
              @lambda_edits.Collapse(node_id=nid)
            }
            dispatch(TreeEdited(op))
          }
          None => @rabbita.none
        }
      "Delete" | "Backspace" =>
        match get_selected_node_id(model) {
          Some(nid) =>
            dispatch(
              OutlineStructuralEdit(
                @zipper.to_tree_edit_op(nid, @zipper.EditAction::Delete),
              ),
            )
          None => @rabbita.none
        }
      "." =>
        match model.selected_node {
          Some(_) => dispatch(OpenActionOverlayFromOutline)
          None => @rabbita.none
        }
      "Escape" =>
        if model.overlay.visible {
          dispatch(CloseActionOverlay)
        } else {
          dispatch(OutlineNavigate(""))
        }
      _ => @rabbita.none
    }
  }
  match model.outline_state.tree {
    Some(root) =>
      div(
        class="tree-rows",
        on_keydown=handle_keydown,
        attrs=@html.Attrs::build().tabindex(0),
        [view_outline_node(dispatch, root, 0, model.selected_node)],
      )
    None => @html.p(class="no-tree-note", "No AST available")
  }
}
```

Key changes from the original `view_outline_content`:
- `.tree-rows` div now has `tabindex(0)` and `on_keydown`
- Keydown closure captures `model` and `dispatch`
- Arrow keys → `navigate_outline()` → `OutlineNavigate`
- Enter → expand/collapse via `TreeEdited`
- Delete → `OutlineStructuralEdit` with `to_tree_edit_op`
- `.` → `OpenActionOverlayFromOutline`
- Escape → close overlay or clear selection (empty string clears)

- [ ] **Step 3: Verify compilation**

Run: `cd examples/ideal && moon check`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add examples/ideal/main/view_outline.mbt
git commit -m "feat: add keyboard navigation to outline tree via zipper"
```

---

### Task 6: Finalize — moon info, moon fmt, test

**Files:**
- Various generated files

- [ ] **Step 1: Update interfaces and format**

Run: `cd examples/ideal && moon info && moon fmt`

- [ ] **Step 2: Run tests**

Run: `cd examples/ideal && moon check && moon test`
Expected: PASS

- [ ] **Step 3: Review .mbti changes**

Run: `git diff -- '**/*.mbti'`
Expected: New Msg variants in the public enum. FFI functions are private and won't appear.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: update interfaces for keyboard integration"
```

---

## Notes for Implementer

1. **Rabbita event types.** `on_keydown` receives `@html.Keyboard` (not `KeyboardEvent`). Use `kb.key()` for the key name string.

2. **`@rabbita.none`** is the no-op command. Return it when the keydown handler doesn't match a key.

3. **`@rabbita_cmd.raw_effect(fn, kind=after_render)`** schedules a side effect after Rabbita finishes rendering. Used for focus and scroll-into-view.

4. **`@strconv.parse_int`** uses MoonBit's error handling. Use `@strconv.parse_int(str) catch { _ => ... }` (not `parse_int?`).

5. **Existing action overlay flow.** The `ActionKeyPressed` handler now checks its argument first, then falls back to `js_take_action_key()`. This means the overlay works from both ProseMirror keymap (JS global) and Rabbita `on_keydown` (argument).

6. **Collapsed nodes.** The Enter key checks `model.outline_state.collapsed_nodes.contains(nid)` to decide between Expand and Collapse. This uses the immutable hashset from TreeEditorState.

8. **Qualified enum variants.** Zipper enums must be fully qualified from outside the package: `@zipper.Direction::Up` (not `@zipper.Up`), `@zipper.EditAction::Delete` (not `@zipper.Delete`).

7. **Manual testing checklist:**
   - Click outline container background → focus ring appears
   - Arrow keys → selection moves structurally (↑=parent, ↓=child, ←/→=siblings)
   - Delete on a leaf → `_` hole appears in text
   - `.` → overlay opens at the selected row
   - Mnemonic key in overlay → action executes
   - Escape → overlay closes, then clears selection
   - CM6/PM does NOT steal focus during keyboard navigation
