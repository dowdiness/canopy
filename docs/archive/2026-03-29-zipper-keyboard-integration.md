# Zipper Keyboard Integration for Ideal Editor

**Date:** 2026-03-29
**Status:** Ready

## Goal

Add keyboard-driven structural navigation and editing to the ideal editor's outline tree, using the zipper package for navigation and the existing action overlay for structural editing.

## Scope

**In scope:**
- Outline tree becomes focusable (Rabbita `tabindex` attr, focus styling)
- Arrow keys navigate the AST structure via `@zipper.navigate()`
- Delete key triggers structural edit via `editor.apply_tree_edit()`
- `.` key opens the existing action overlay anchored to the selected outline row
- Overlay panel gets `on_keydown` for mnemonic key dispatch from keyboard
- Enter toggles expand/collapse
- Escape closes overlay or clears selection
- Selection cleared/reseated after structural edits

**Out of scope:**
- Text ↔ tree cursor sync (Phase 3 — needs CM6 cursor position events)
- New action types or overlay redesign
- `LambdaEditorState` wrapper (YAGNI — keyboard works without it)
- HoleRegistry integration (deferred — no UI consumes hole metadata yet)

## Key Design Decisions (from Codex review)

1. **Navigation needs its own Msg** — `OutlineNodeClicked` calls `js_set_editor_selected_node()` which focuses CM6/PM, stealing outline focus. Keyboard navigation uses a separate `OutlineNavigate(String)` Msg that updates selection without touching editor focus.

2. **Structural edits need the real CRDT path** — `TreeEdited(...)` only handles UI-state ops (Select/Collapse/Expand). Structural edits (Delete, Wrap, etc.) must go through `editor.apply_tree_edit()` + refresh. Add `OutlineStructuralEdit(@lambda_edits.TreeEditOp)` Msg.

3. **Action overlay needs a keyboard-aware open path** — The existing `OpenActionOverlay` consumes a JS global set by the web component. For keyboard triggers, the node ID is already known from `model.selected_node`. Add `OpenActionOverlayFromOutline` Msg that reads from model state and anchors to the outline row rect.

4. **Overlay panel needs `on_keydown`** — Currently mnemonic keys go through ProseMirror's keymap (`ActionKeyPressed` in `keymap.ts`). The Rabbita overlay panel needs its own `on_keydown` handler that dispatches `ActionKeyPressed` directly.

5. **Anchor source must be explicit** — Can't infer from `model.mode` since the outline exists in both Text and Structure modes. The new `OpenActionOverlayFromOutline` Msg explicitly uses outline row rect.

## Architecture

### New Msg Variants

```moonbit
// In msg.mbt, add:
OutlineNavigate(String)              // Keyboard navigation — updates selection without editor focus
OutlineStructuralEdit(@lambda_edits.TreeEditOp)  // Keyboard structural edit — CRDT round-trip
OpenActionOverlayFromOutline         // Open overlay anchored to outline row, node from model.selected_node
```

### Event Flow

```
Outline tree on_keydown (Rabbita @html.Keyboard)
  → match e.key():
      "ArrowUp"    → compute @zipper.navigate(cursor, Up, ...) → dispatch(OutlineNavigate(new_id))
      "ArrowDown"  → compute @zipper.navigate(cursor, Down, ...) → dispatch(OutlineNavigate(new_id))
      "ArrowLeft"  → compute @zipper.navigate(cursor, Left, ...) → dispatch(OutlineNavigate(new_id))
      "ArrowRight" → compute @zipper.navigate(cursor, Right, ...) → dispatch(OutlineNavigate(new_id))
      "Delete" | "Backspace" → dispatch(OutlineStructuralEdit(@zipper.to_tree_edit_op(cursor, Delete)))
      "Enter"      → dispatch(TreeEdited(Expand/Collapse(node_id=cursor)))
      "."          → dispatch(OpenActionOverlayFromOutline)
      "Escape"     → dispatch(CloseActionOverlay) or clear selection
```

### Update Handlers

**`OutlineNavigate(node_id_str)`:**
1. Set `selected_node = Some(node_id_str)`
2. Update `outline_state` selection: parse to NodeId, set `outline_state.selection`
3. Do NOT call `js_set_editor_selected_node()` — outline keeps focus
4. Dispatch `raw_effect` → `js_scroll_outline_to_selected()`

**`OutlineStructuralEdit(tree_op)`:**
1. Call `editor.apply_tree_edit(tree_op, timestamp)`
2. On success: `refresh(model)` to rebuild outline
3. Relocate selection: use `editor.get_cursor()` → `source_map.innermost_node_at()` → new NodeId → update `selected_node`
4. Sync JS side: call `js_reconcile_editor_with_text(editor.get_text())` — this syncs BOTH CM6 (text mode) and PM (structure mode). Do NOT use `js_reconcile_after_tree_edit()` which only syncs PM.

**`OpenActionOverlayFromOutline`:**
1. Get node ID from `model.selected_node` (no JS global needed)
2. Parse to NodeId, build `NodeActionContext`
3. Get anchor rect via `js_get_outline_selected_rect()` (new FFI)
4. Populate `overlay` state with actions + anchor
5. Set `overlay.visible = true`
6. Dispatch `raw_effect` → focus the overlay panel

### Changes by File

**`examples/ideal/main/msg.mbt`**
- Add `OutlineNavigate(String)`
- Add `OutlineStructuralEdit(@lambda_edits.TreeEditOp)`
- Add `OpenActionOverlayFromOutline`

**`examples/ideal/main/view_outline.mbt`**
- Add `on_keydown` handler to `.tree-rows` container
- Set `tabindex` via Rabbita's `Attrs::build().tabindex(0)` (not string attribute)
- Keydown closure captures `model` and `dispatch`, computes navigation inline
- Import `@zipper` for `navigate()` and `to_tree_edit_op()`

**`examples/ideal/main/main.mbt`**
- Add `OutlineNavigate` handler: update `selected_node` + `outline_state.selection`, scroll into view
- Add `OutlineStructuralEdit` handler: `editor.apply_tree_edit()` + refresh + relocate selection
- Add `OpenActionOverlayFromOutline` handler: build context from `model.selected_node`, anchor from outline rect
- After structural edits (existing path too): reseat `selected_node` to surviving/new NodeId

**`examples/ideal/main/view_actions.mbt`**
- Add `on_keydown` to the overlay panel div for mnemonic key dispatch
- Handler maps key → `dispatch(ActionKeyPressed(key))`
- Panel needs `tabindex` for keyboard event reception

**`examples/ideal/main/main.mbt`** (ActionKeyPressed handler)
- Current handler ignores its String argument and reads from `js_take_action_key()` (JS global set by ProseMirror keymap)
- Fix: use the argument when non-empty, fall back to JS global only when empty
- This makes the handler work for both Rabbita `on_keydown` (argument has the key) and ProseMirror keymap (argument is empty, key in JS global)

**`examples/ideal/main/bridge_ffi.mbt`** (overlay focus)
- Current `js_focus_overlay_panel()` looks inside `canopy-editor.shadowRoot` — wrong DOM tree for Rabbita-rendered overlay
- Fix: add `js_focus_outline_overlay_panel()` that targets the page DOM overlay (`.action-overlay-panel` without shadowRoot scoping)
- Use this FFI when overlay is opened from outline context

**`examples/ideal/main/bridge_ffi.mbt`**
- Add `js_get_outline_selected_rect() -> String` — bounding rect of `.tree-row.selected`
- Add `js_scroll_outline_to_selected() -> Unit` — scroll selected row into view

**`examples/ideal/main/moon.pkg`**
- Add `"dowdiness/canopy/lang/lambda/zipper" @zipper`

### Navigation Logic

```
fn navigate_outline(model : Model, direction : @zipper.Direction) -> String? {
  let node_id_str = match model.selected_node {
    Some(s) => s
    None => return None
  }
  let n = match @strconv.parse_int?(node_id_str) {
    Ok(n) => n
    Err(_) => return None
  }
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
```

Computed inside the keydown closure where `model` is captured.

### Selection Reseating After Structural Edits

After any structural edit that goes through `editor.apply_tree_edit()`:
1. Get text cursor position: `editor.get_cursor()`
2. Get source map: `editor.get_source_map()`
3. Find node at cursor: `source_map.innermost_node_at(cursor_pos)`
4. Update `selected_node` to the new NodeId string

This uses the same FocusHint-based relocation strategy from the zipper design plan — the text cursor is already positioned correctly by `apply_tree_edit`.

## Keyboard Mapping

| Key | Action | Msg |
|-----|--------|-----|
| ↑ | Navigate to parent | `OutlineNavigate` |
| ↓ | Navigate to first child | `OutlineNavigate` |
| ← | Navigate to left sibling | `OutlineNavigate` |
| → | Navigate to right sibling | `OutlineNavigate` |
| Enter | Toggle expand/collapse | `TreeEdited(Expand/Collapse)` |
| Delete / Backspace | Delete node (CRDT round-trip) | `OutlineStructuralEdit` |
| `.` | Open action overlay | `OpenActionOverlayFromOutline` |
| Escape | Close overlay, or clear selection | `CloseActionOverlay` / clear |

Note: ↑↓ map to `go_up`/`go_down` (parent/child), not prev/next visual row. This is structural navigation.

## Testing

- Manual: focus outline, arrow-key through an AST, verify selection updates and outline keeps focus
- Manual: Delete on a node, verify `_` replaces it, text updates, selection reseats to hole
- Manual: press `.`, verify overlay opens anchored to the selected outline row
- Manual: press mnemonic key in overlay, verify structural edit applies
- Manual: verify CM6/PM does NOT steal focus during keyboard navigation
- Automated: `moon check` and `moon test` pass for the ideal editor module

## Acceptance Criteria

1. Clicking the `.tree-rows` container gives it focus (visible focus ring). Note: clicking a tree ROW still triggers `OutlineNodeClicked` which focuses the editor — to start keyboard mode after a click, the user clicks the container background or presses Tab to the outline. This is acceptable for Phase 1; a future refinement could modify `OutlineNodeClicked` to keep outline focus.
2. Arrow keys navigate the AST structure (not visual list order)
3. Outline retains focus during keyboard navigation (CM6/PM does not steal it)
4. Selection highlight moves and the inspector updates
5. Delete key replaces the selected node with `_` (hole) via CRDT round-trip
6. After Delete, selection reseats to the new node at the cursor position
7. `.` opens the action overlay anchored to the selected outline row
8. Mnemonic keys work in the overlay when triggered from keyboard
9. Escape closes overlay or clears selection
10. Navigation scrolls the outline to keep the selected node visible

## Validation Commands

```bash
cd examples/ideal && moon check
cd examples/ideal && moon test
# Manual: open dev server, click outline, use arrow keys + Delete + "."
```
