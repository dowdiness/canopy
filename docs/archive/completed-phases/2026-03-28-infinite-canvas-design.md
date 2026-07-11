# Infinite Canvas — Design Spec

**Date:** 2026-03-28
**Scope:** `examples/canvas/` demo package
**Status:** Complete

## Goal

Build a standalone infinite canvas demo in MoonBit that proves out the canvas primitive: pan, zoom, and node drag over a set of static shape and text nodes. No CRDT, no persistence, no editor integration yet.

This is the foundation for the long-term goal: bidirectional embedding of the block editor and canvas (editor-in-canvas and canvas-in-editor).

---

## Architecture

### Rendering approach: DOM + CSS transforms

The canvas viewport is a `<div id="world">` with a single CSS transform:

```
transform: translate(panX px, panY px) scale(scale)
transform-origin: 0 0
```

Nodes are `position: absolute` children of `#world`, positioned at their world coordinates. Pan and zoom change only the transform string on `#world` — node styles are not touched during viewport movement, only during node drag.

This approach is chosen over Canvas 2D because Canopy's nodes will eventually be live editor blocks (rich DOM content). CSS-transformed DOM nodes are the natural substrate for that future. Canvas 2D would require a DOM overlay hack for every interactive block.

### Hybrid upgrade path (future)

A `<canvas id="overlay">` sits above `#world` with `pointer-events: none`. It is present as a stub from day one. When selection handles, arrows, or decorations are needed, the render loop gains a `drawOverlay(state)` step without restructuring the DOM or the MoonBit state machine. This is the "hybrid" path: DOM for node content, Canvas 2D for decorations.

---

## Package structure

Standalone MoonBit module, mirroring `examples/ideal`:

```
examples/canvas/
├── moon.mod.json          # module: "dowdiness/canopy-canvas", preferred-target: js
├── main/
│   ├── moon.pkg           # is-main: true, exports list
│   ├── canvas_state.mbt   # Types: CanvasState, Viewport, CanvasNode, InteractionState
│   ├── canvas_update.mbt  # Pure update functions: pan, zoom, drag, select
│   ├── canvas_init.mbt    # create_canvas() entry point, seed nodes
│   └── ffi.mbt            # JS externs (minimal)
└── web/
    ├── index.html
    ├── package.json
    ├── vite.config.ts
    └── src/
        └── main.ts        # Bootstrap, event wiring, RAF render loop
```

MoonBit owns all state and logic. TypeScript is a thin shell: forwards events in, reads state out, applies DOM changes on each animation frame.

---

## Data model

```moonbit
type NodeId Int  // newtype, not a type alias — matches projection/types.mbt pattern

struct Viewport {
  x     : Double  // pan x (world origin in canvas-local screen space)
  y     : Double  // pan y
  scale : Double  // zoom level, clamped to [0.1, 8.0]
}

struct CanvasNode {
  id   : NodeId
  x    : Double  // world coordinates
  y    : Double
  w    : Double
  h    : Double
  kind : NodeKind
}

enum NodeKind {
  Shape(color : String)   // filled rect
  Text(content : String)  // label
}

struct DragState {
  node_id  : NodeId
  offset_x : Double  // cursor-to-node-origin offset in world coords
  offset_y : Double
}

struct PanState {
  start_screen_x : Double  // canvas-local screen coords at pan start
  start_screen_y : Double
  start_pan_x    : Double  // viewport pan at pan start
  start_pan_y    : Double
}

struct InteractionState {
  dragging     : DragState?
  panning      : PanState?
  selected     : NodeId?
  pointer_down : Bool  // true from pointerdown until pointerup, used for click-vs-drag
  did_move     : Bool  // true once pointermove fires during current pointer session
}

struct CanvasState {
  viewport    : Viewport
  nodes       : Array[CanvasNode]
  interaction : InteractionState
}
```

---

## Coordinate system

Two coordinate spaces:

- **World space** — where nodes live. Invariant to pan/zoom.
- **Canvas-local screen space** — what the user sees, origin at top-left of `#canvas-root`.

TypeScript subtracts `canvas.getBoundingClientRect()` from raw `clientX/clientY` before passing any coordinates to MoonBit. MoonBit never receives raw page coordinates.

Conversions:

```
screen = world * scale + pan
world  = (screen - pan) / scale
```

Zoom toward cursor (keeps the point under cursor fixed):

```
new_scale = clamp(old_scale * factor, 0.1, 8.0)
pan.x     = cx + (pan.x - cx) * (new_scale / old_scale)
pan.y     = cy + (pan.y - cy) * (new_scale / old_scale)
scale     = new_scale
```

where `cx, cy` are canvas-local screen coordinates.

---

## Interaction model

### Pan
- `pan_start(handle, screen_x, screen_y)` — on `pointerdown` on background; saves `start_screen` and `start_pan` in `PanState`
- `pan_move(handle, screen_x, screen_y)` — on `pointermove` while panning:
  `viewport.x = start_pan.x + (screen_x - start_screen.x)` (absolute, avoids float drift)
- `pointer_up(handle)` — clears `PanState`

### Zoom
- `zoom(handle, delta, cx, cy)` — on `wheel` event; computes new scale; adjusts pan per formula above
- Wheel-to-scale mapping: `factor = delta > 0 ? 0.9 : 1/0.9` (per `deltaY` sign)

### Node drag
- `node_drag_start(handle, node_id, world_x, world_y)` — on `pointerdown` on a node; sets `DragState { node_id, offset = node_pos - cursor_world }` and `did_move = false`
- `node_drag_move(handle, world_x, world_y)` — on `pointermove` while dragging; sets `did_move = true`; updates `node.x = world_x + offset.x, node.y = world_y + offset.y`
- `pointer_up(handle)` — clears `DragState`

### Selection
- On `pointer_up`: if `pointer_down && !did_move && there is a node under pointer` → set `selected = Some(node_id)`
- TypeScript passes `node_id` (or `0` for none) into `pointer_up(handle, node_id)`
- Visual highlight only (CSS class on the selected node div). No action attached in this demo.

### Pointer capture
TypeScript calls `element.setPointerCapture(e.pointerId)` on `pointerdown` so `pointermove` and `pointerup` are reliably received even when the pointer leaves `#canvas-root`.

---

## Render loop & JS bridge

**RAF-batched, not immediate.** Each event mutates MoonBit state, then schedules one `requestAnimationFrame` if not already pending. The frame callback calls `get_render_state(handle)` and patches the DOM once per frame. Matches the pattern in `examples/ideal/web/src/bridge.ts`.

MoonBit exports (in `main/moon.pkg` `link.js.exports`):

```
create_canvas() -> Int                                    // returns handle, sets up state + seed nodes
pan_start(handle: Int, sx: Double, sy: Double) -> Unit
pan_move(handle: Int, sx: Double, sy: Double) -> Unit
zoom(handle: Int, delta: Double, cx: Double, cy: Double) -> Unit
node_drag_start(handle: Int, id: Int, wx: Double, wy: Double) -> Unit
node_drag_move(handle: Int, wx: Double, wy: Double) -> Unit
pointer_up(handle: Int, node_id: Int) -> Unit             // node_id=0 means background
get_render_state(handle: Int) -> String                   // JSON (see schema below)
```

### `get_render_state` JSON schema

```json
{
  "viewport": { "x": 0.0, "y": 0.0, "scale": 1.0 },
  "nodes": [
    { "id": 1, "x": 100.0, "y": 100.0, "w": 200.0, "h": 120.0,
      "kind": ["Shape", "#8250df"] },
    { "id": 2, "x": 350.0, "y": 100.0, "w": 200.0, "h": 80.0,
      "kind": ["Text", "Hello, Canopy"] }
  ],
  "selected": 1
}
```

`NodeKind` uses MoonBit's `derive(ToJson)` array-based enum encoding: `["Shape", color]` / `["Text", content]`. `selected` is `null` when nothing is selected.

### TypeScript DOM patch (per RAF frame)

1. Set `#world` CSS transform: `translate(${vp.x}px, ${vp.y}px) scale(${vp.scale})`
2. For each node: `left`, `top`, `width`, `height` on the matching `div` (only changes if different)
3. Add/remove node `div`s when the node list changes (demo: never changes after init)
4. Toggle `.selected` CSS class on the selected node div

Pan and zoom do **not** trigger step 2 (node styles unchanged) — only `#world` transform is updated.

---

## Demo content

`canvas_init.mbt` provides `create_canvas()` which allocates state with hardcoded seed nodes: a mix of colored rectangles and text labels arranged around the world origin. No add/delete UI. The demo loads, you can pan/zoom/drag, done.

---

## Scope

**In scope:**
- Pan, zoom (clamped to [0.1, 8.0]), node drag
- Shape nodes (filled rect with color)
- Text nodes (label with content)
- Click-to-select (visual only — CSS `.selected` class)
- Hybrid overlay stub (`<canvas id="overlay">` + no-op `drawOverlay`)
- Pointer capture for reliable drag/pan outside container

**Out of scope for this demo:**
- Add/delete nodes
- Undo
- Persistence or CRDT
- Resize handles
- Multi-select
- Connectors / arrows
- Rabbita or block editor integration
