# Editor Drag-and-Drop Foundation

## Why

Both `examples/ideal` and `examples/block-editor` need relocation UX, but the
hard part is not the browser gesture. The missing foundation is a canonical
move contract and backend support for safe, undoable, model-level relocation.

Today:

- `examples/block-editor` renders a flat root-level block list and exposes
  create/delete/type/text operations, but it does not expose positioned moves
  for sibling reorder.
- `examples/ideal` already has drag-related tree edit variants and text-edit
  support for `Drop`, but its JSON/bridge/event path is incomplete and the
  drop path needs legality validation before it becomes a UI feature.

This task prepares both editors so later drag UI work is thin and local rather
than pushing correctness into DOM event handlers.

## Scope

In:
- `examples/block-editor/main/`
- `examples/block-editor/web/src/`
- `examples/ideal/main/`
- `examples/ideal/web/src/`
- `editor/`
- `lang/lambda/edits/`
- `projection/`
- `event-graph-walker/tree/`
- `docs/TODO.md`

Out:
- Full polished drag UI for either editor
- Mobile/touch gesture design beyond foundation hooks
- Cross-editor shared UI package or design system work
- Remote drag-presence UX beyond preserving room for it in the data model

## Current State

- `examples/block-editor/main/block_doc.mbt` exposes `create_block_after(...)`
  but `move_block(...)` only moves to a parent as last child, so root-level
  reorder is not a first-class model operation.
- `examples/block-editor/main/block_init.mbt` emits a flat render payload from
  `get_render_state(...)` with no parent/depth/path metadata for drop targeting.
- `examples/block-editor/web/src/main.ts` renders direct `contenteditable`
  blocks and has no dedicated drag handle or drop-indicator state.
- `lang/lambda/edits/tree_lens.mbt` already declares `StartDrag`, `DragOver`,
  and `Drop`.
- `lang/lambda/edits/text_edit_drop.mbt` computes text splices for `Drop`, but
  it does not enforce self/descendant/invalid-target rules.
- `editor/tree_edit_json.mbt` does not parse `Drop`, so web clients cannot send
  drag/drop tree edits through the existing JSON bridge.
- `examples/ideal/web/src/bridge.ts` only exposes a narrow
  `handleStructuralEdit(opType, nodeId, extra?)` path oriented around
  `{ type, node_id }`.
- `examples/ideal/main/main.mbt` only resolves `"WrapInLambda"` and `"Delete"`
  from `StructuralEditRequested`, so the MoonBit-side event path is not yet a
  general structural edit router.

## Desired State

- Both editors use the same conceptual drag/drop contract:
  `source`, `target`, `position`, legality, preview, and commit.
- `block-editor` has model-level positioned move primitives suitable for
  sibling reorder and future nesting work.
- `block-editor` render state exposes enough structural metadata to compute
  drop targets without inferring them from the DOM alone.
- `ideal` accepts validated `Drop` edits through the existing tree-edit bridge
  without requiring ad hoc code paths for drag/drop.
- Drop legality is enforced at the editor/model boundary, not only in the web
  event layer.
- The first real drag UI for each editor can be implemented by adding handles,
  hover state, and commit calls on top of the prepared APIs.

## Steps

1. Define the canonical move contract shared by both editors.
   Record the payload shape and the supported drop positions for each editor.
   Keep `Before`/`After` as the minimum common contract and treat `Inside` as
   opt-in where the backend can prove it is valid.
2. Add positioned move primitives to the movable-tree path used by
   `examples/block-editor`.
   Prefer `move_before` / `move_after` or a single `move_between` primitive
   that reuses the same fractional-index logic as `create_node_after(...)`.
3. Expose block-editor relocation state cleanly.
   Add FFI wrappers and expand render metadata so the web layer knows each
   block's structural context without encoding DOM-only heuristics as truth.
4. Complete the `ideal` drag/drop wire path.
   Parse `Drop` in `editor/tree_edit_json.mbt`, widen the web bridge so it can
   submit structured tree-edit payloads, and make the Rabbita event path accept
   drag/drop edits through the canonical structural edit boundary.
5. Add legality validation for structural drops.
   Reject self-drops, descendant drops, and any editor-specific invalid targets
   in middleware or equivalent shared validation so all callers get the same
   safety guarantees.
6. Add tests for reorder legality and edit semantics before enabling UI polish.
   Cover sibling reorder, invalid target rejection, undo grouping, and
   convergence/reconciliation after relocation.

## Acceptance Criteria

- [ ] A single documented move contract exists for drag/drop preparation across
      `examples/ideal` and `examples/block-editor`.
- [ ] `examples/block-editor` exposes model-level positioned block moves for
      sibling reorder instead of relying on append-only parent moves.
- [ ] `examples/block-editor` render state includes enough structural metadata
      for future drop targeting.
- [ ] `editor/tree_edit_json.mbt` and the `ideal` web bridge accept `Drop`
      through the canonical tree-edit path.
- [ ] Structural drop legality is enforced before text/model mutation runs.
- [ ] Automated tests cover valid reorder and invalid drop cases for the new
      foundation APIs.

## Validation

```bash
moon check
moon test
cd event-graph-walker && moon test
```

If web-side drag hooks or bridge behavior change materially, also validate the
affected example app manually in the browser and add/update focused browser
tests where the interaction becomes user-visible.

## Risks

- `examples/block-editor` may need tree-layer API expansion in
  `event-graph-walker`, not just local wrapper changes.
- `ideal` currently routes structural edits through text transformations, so
  naive `Drop` support can create syntactically valid but semantically wrong
  rewrites if legality checks remain too weak.
- ProseMirror/native drag behavior may conflict with custom handles if the UI
  layer does not keep drag sensing separate from editable content.

## Notes

- Browser-native drag-and-drop is input plumbing, not the canonical move model.
- Prefer dedicated drag handles over making the editable surface itself
  draggable.
- Leave room for future ephemeral drag presence by keeping source/target/
  position payloads explicit instead of encoding them in DOM state.
