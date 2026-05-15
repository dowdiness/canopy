# Canvas Handles And Edges

**Status:** Complete in branch `codex/canvas-handles-edges`.
**Implementation:** `d18a14f feat(canvas): add node handles and edges`
**Scope:** `examples/canvas/`

No ADR needed: this is a demo-only extension of the existing infinite canvas
example. It does not change the framework architecture, public editor API, CRDT
model, parser pipeline, or cross-package contracts.

## Goal

Extend the infinite canvas demo from pan/zoom/drag/select into a minimal
node-graph prototype:

- show input and output handles on each node
- render persistent edges between demo nodes
- allow dragging from an output handle to create a new edge
- show an in-flight edge preview while connecting
- reject self-loops and duplicate edges

The feature remains deliberately local to the canvas example. There is no
persistence, CRDT sync, node add/delete UI, edge delete UI, or editor embedding
yet.

## Design

MoonBit remains the owner of canvas state and interaction rules. TypeScript
remains a thin browser shell that forwards pointer events into MoonBit, reads
`get_render_state(handle)`, and patches DOM/SVG during the RAF render loop.

The old future `#overlay` canvas stub is replaced by an SVG edge layer:

```html
<svg id="edges"></svg>
<div id="world"></div>
```

Both `#edges` and `#world` receive the same viewport transform:

```text
translate(viewport.x px, viewport.y px) scale(viewport.scale)
```

This keeps node positions, handle anchors, and edge paths in the same world
coordinate space.

## State Model

New MoonBit state:

```moonbit
struct EdgeId(Int)

struct Edge {
  id : EdgeId
  source : NodeId
  target : NodeId
}

struct ConnectState {
  from_node : NodeId
  cursor_x : Double
  cursor_y : Double
}
```

`CanvasState` now carries:

```moonbit
edges : Array[Edge]
next_edge_id : Int
```

`InteractionState` now carries:

```moonbit
connecting : ConnectState?
```

Each node has one implicit output handle at right-center and one implicit input
handle at left-center. Handles are not stored in MoonBit state; they are derived
from node bounds in TypeScript.

## Interaction Rules

Pointer-down on an output handle starts a connection gesture:

```moonbit
pointer_down_handle(handle, node_id, sx, sy)
```

The bridge converts screen coordinates to world coordinates and stores:

```moonbit
ConnectState {
  from_node: node_id,
  cursor_x: world_x,
  cursor_y: world_y,
}
```

Pointer-move while `connecting` is active updates only the cursor world
position. It does not drag a node or pan the viewport.

Pointer-up ends the gesture:

- released over another node: add `Edge(source, target)`
- released over the source node: cancel, no self-loop
- released over the background: cancel
- released over an already-connected target: cancel duplicate

Pointer capture means `pointerup` event targets are unreliable. The TypeScript
bridge uses `document.elementFromPoint(clientX, clientY)` on release to identify
the actual node or handle under the pointer.

## Render State JSON

`get_render_state(handle)` now includes `edges` and optional `connecting`:

```json
{
  "viewport": { "x": 520, "y": 300, "scale": 1 },
  "nodes": [],
  "edges": [
    { "id": 1, "source": 1, "target": 4 }
  ],
  "selected": 1,
  "connecting": {
    "from": 1,
    "cursor_x": 120,
    "cursor_y": 80
  }
}
```

`selected` and `connecting` are omitted when inactive, following MoonBit
`derive(ToJson)` optional-field behavior.

## Rendering

TypeScript derives anchors from node bounds:

```typescript
outputAnchor(node) = [node.x + node.w, node.y + node.h / 2]
inputAnchor(node)  = [node.x, node.y + node.h / 2]
```

Edges are rendered as SVG cubic Bezier paths with horizontal handles. Existing
edge paths are reused by `EdgeId`; missing paths are added; stale paths are
removed. The in-flight edge uses a single `edge-pending` path.

Nodes now contain:

- `.handle.input`
- `.handle.output`
- `.node-label`

Keeping label text inside `.node-label` avoids replacing handle elements when
the node label changes.

## Tests

Whitebox tests cover:

- connection start stores source node and cursor world position
- connection move updates cursor position
- connection end commits a source-to-target edge
- self-loops are rejected
- background release cancels the gesture
- duplicate source/target edges are rejected
- render JSON includes seeded demo edges

Playwright smoke coverage in `examples/canvas/web/e2e/canvas-handles.spec.ts`
drives the actual browser UI and verifies:

- output-handle drag shows a pending SVG edge
- background release cancels without adding an edge
- valid handle-to-handle release creates an edge
- duplicate and self-edge gestures are rejected
- input-handle drag is inert and does not pan the viewport

Validation run for the implementation:

```bash
moon check
moon check --deny-warn --warn-list @a
moon test
cd examples/canvas/web && npm run build
cd examples/canvas/web && npm exec tsc -- --noEmit
make test-canvas-e2e
git diff --cached --check
markdownlint-cli2 docs/README.md docs/archive/completed-phases/2026-05-14-canvas-handles-edges.md
```

Initial implementation validation passed on 2026-05-14. The Playwright smoke
follow-up was added on 2026-05-15 and validated with `make test-canvas-e2e`.
`npm install` in `examples/canvas/web` reported three moderate npm audit
warnings, but produced no tracked changes.

## Follow-Ups

- Edge deletion and selection.
- Node add/delete UI and edge cleanup for removed nodes.
- Persist canvas graph state.
- Decide whether canvas graph state should eventually share the editor CRDT
  model or remain a separate example-specific data model.
