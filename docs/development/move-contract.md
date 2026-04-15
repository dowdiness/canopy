# Shared Move Contract

How nodes are relocated across Canopy editors. Both the ideal (lambda) editor
and the block editor share the same payload shape but differ in supported
positions and backend execution.

## Payload Shape

Every move originates as a browser event and arrives as JSON:

```json
{
  "type": "Drop",
  "source": 42,
  "target": 17,
  "position": "Before"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `source` | `NodeId` (int) | The node being moved |
| `target` | `NodeId` (int) | The reference node |
| `position` | `"Before" \| "After" \| "Inside"` | Where to place source relative to target |

MoonBit types: `DropPosition` in `core/types.mbt`, `GenericTreeOp::Drop` in
`core/generic_tree_op.mbt`.

## Position Semantics

| Position | Meaning | Lambda editor | Block editor |
|----------|---------|:---:|:---:|
| `Before` | Insert source as preceding sibling of target | Yes | Planned |
| `After` | Insert source as following sibling of target | Yes | Planned |
| `Inside` | Exchange source and target content | Yes | No (appends to parent) |

### Position Detection (browser)

Mouse Y within the target bounding box determines position
(`structure-nodeview.ts:computeDropPosition`):

- **Top 25%** -> Before
- **Bottom 25%** -> After
- **Middle 50%** -> Inside

Special case: hovering over a compound node's header always maps to Inside
(exchange).

## Legality Rules

Three checks apply universally. A drop that fails any check is rejected
without modifying the document.

### 1. Self-drop

Source and target must be different nodes.

```
source != target
```

### 2. Descendant-drop

Target must not be a descendant of source (would create a cycle).

| Editor | Detection method |
|--------|-----------------|
| Lambda | Text span containment: `tgt_range` inside `src_range` |
| Block | Tree cycle check: `tree.would_create_cycle(target, parent)` |

### 3. Ancestor exchange (Inside only)

For exchange, source must also not be inside target. Swapping a node with
its own ancestor would lose the subtree.

## Backend Execution

### Lambda editor: `SyncEditor::move_node`

All three positions produce `SpanEdit` arrays applied in reverse document order.

**Inside (exchange):**
1. Strip leading whitespace from both spans to find expression boundaries
2. Swap the expression text, preserving leading separators
3. Two edits: replace source expression with target's, replace target's with source's

**Before / After (move):**
1. Extract source expression text from the source map (whitespace-aware)
2. Replace source expression with `Renderable::placeholder()` (e.g., `0` for Int, `a` for Var)
3. Insert source text at target boundary (`tgt_range.start` for Before, `tgt_range.end` for After)

The placeholder keeps surrounding syntax valid. Without it, removing a node
from `let id = \x. x` would leave `let id = ` (invalid).

### Block editor: `BlockDoc::move_block`

Currently only supports reparenting (no sibling positioning):

1. Validate target exists and parent is valid
2. Check for cycles
3. Compute position after last child via fractional indexing
4. Create `TreeMoveOp` and apply to CRDT tree

To support Before/After, `move_block` needs a `position` parameter and
the ability to compute fractional indices between siblings rather than
always appending.

## Drag Lifecycle (state machine)

Managed by `TreeEditorState` in `projection/tree_editor.mbt`:

```
StartDrag(node_id)
  -> dragging: Some(node_id)

DragOver(target, position)
  -> validates: not self, not descendant
  -> drop_target: Some(target), drop_position: Some(position)

Drop(source, target, position)
  -> validates: source matches dragging, not self, not descendant
  -> executes move, clears drag state, selects source node

Cancel / invalid drop
  -> clears drag state, no tree change
```

## Adding Move Support to a New Editor

1. **Parse the payload** — accept the JSON shape above, map `position` to `DropPosition`
2. **Implement legality** — self-drop and descendant-drop at minimum
3. **Execute the move** — either via `SyncEditor::move_node` (text-based) or the container tree API
4. **Wire the browser** — dispatch `structural-edit-request` with `type: "Drop"` from drag event handlers
5. **Emit position visuals** — add `drop-before` / `drop-after` / `drop-inside` CSS classes during dragover
