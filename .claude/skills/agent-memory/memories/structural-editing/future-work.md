---
summary: "Future work proposals for structural editing UI — outline selection bridge, unified edit paths, typed ActionId, stronger e2e assertions"
created: 2026-03-22
status: backlog
tags: [structural-editing, ideal-editor, future-work]
related: [examples/ideal/main/main.mbt, examples/ideal/web/src/keymap.ts, projection/actions.mbt, examples/ideal/web/e2e/structural-editing.spec.ts]
---

# Structural Editing — Future Work

Identified during implementation and review of PR #48 (backend) and PR #49 (Rabbita UI).

## 1. Outline selection → overlay bridge

**Problem:** Clicking a node in the outline panel sets Rabbita's `model.selected_node` but does NOT create a ProseMirror `NodeSelection`. The Space key handler in `keymap.ts` requires a PM NodeSelection to fire, so the overlay only opens when nodes are clicked inside the PM editor area.

**Fix:** When the outline dispatches `OutlineNodeClicked(node_id)`, the update handler should also set the PM NodeSelection via `js_set_editor_selected_node`. Or add a separate overlay trigger from the outline (e.g., right-click or Space when outline has focus).

**Impact:** Currently users must click nodes in the structure view (center panel), not the outline (left panel), to use the overlay.

## 2. Unify structural edit code paths

**Problem:** Two independent paths exist for applying structural edits:
- **Legacy:** `StructuralEditRequested` → `apply_structural_edit_request` in `main.mbt`. Only supports "WrapInLambda" and "Delete". Used by inspector action buttons and existing keyboard shortcuts.
- **New:** `ActionKeyPressed`/`ActionTapped` → `execute_action` → `build_tree_edit_op`. Supports all 17 actions.

The two use different string conventions ("WrapInLambda" vs "wrap_lambda"), different reconciliation FFI, and different state cleanup.

**Fix:** Route inspector buttons and `keymap.ts` shortcuts through `execute_action`. Retire `apply_structural_edit_request` and the `StructuralEditRequested` message.

## 3. Typed ActionId enum

**Problem:** Action IDs flow as raw strings ("delete", "extract_to_let", etc.) through multiple layers. A typo silently falls through to `Err("Unknown action")` at runtime with no compile-time protection.

**Fix:** Define an `ActionId` enum in `projection/actions.mbt` with variants `Delete`, `ExtractToLet`, `Inline`, `Rename`, etc. Use it as the type of `Action.id`. Then `build_tree_edit_op` becomes an exhaustive match.

**Impact:** Maintenance safety. Currently 17 string-matched arms in `action_model.mbt`.

## 4. Stronger e2e assertions

**Problem:** Current e2e tests verify overlay UI transitions (visible/hidden, prompt appears) but don't assert that structural edits actually mutate the AST. For example, "d key deletes" only checks the overlay closed, not that the node was removed.

**Fix:** After each action, verify the AST changed by checking:
- Outline tree content (node labels)
- Text content via `page.evaluate` reading from the CRDT
- Inspector state (node kind/label)

**Also missing:**
- Successful rename with typed text + Enter verifying the rename took effect
- Typing in prompt doesn't trigger overlay mnemonics (key isolation)
- Repeated open/close cycles and state reset
- Non-var node coverage (Int nodes activate inline CM6 editors instead of NodeSelection)
