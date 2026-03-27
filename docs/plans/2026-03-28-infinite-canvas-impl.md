# Infinite Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone `examples/canvas/` MoonBit module with pan/zoom/drag on a CSS-transformed DOM canvas.

**Architecture:** MoonBit owns a pure state machine (CanvasState). TypeScript is a thin shell: forwards events in, reads state via `get_render_state(handle)`, patches the DOM on each RAF frame. Nodes are absolutely-positioned divs inside a CSS-transformed `#world` container.

**Tech Stack:** MoonBit (compiled to JS), TypeScript, Vite, `examples/web/vite-plugin-moonbit.ts`

---

## File Map

| File | Responsibility |
|------|---------------|
| `examples/canvas/moon.mod.json` | Module declaration |
| `examples/canvas/main/moon.pkg` | Package config + JS export list |
| `examples/canvas/main/canvas_state.mbt` | All types: CanvasState, Viewport, CanvasNode, NodeKind, NodeId, DragState, PanState, InteractionState |
| `examples/canvas/main/canvas_update.mbt` | Pure update functions (package-private, tested via wbtest) |
| `examples/canvas/main/canvas_update_wbtest.mbt` | Whitebox tests for update functions |
| `examples/canvas/main/canvas_init.mbt` | Handle registry, `create_canvas()`, exported bridge wrappers, seed nodes, `get_render_state()` |
| `examples/canvas/main/ffi.mbt` | Stub file for future JS externs |
| `examples/canvas/web/index.html` | HTML shell with `#canvas-root`, `#world`, `#overlay` stub |
| `examples/canvas/web/src/main.ts` | Bootstrap, event wiring, RAF render loop, DOM patching |
| `examples/canvas/web/tsconfig.json` | TypeScript config with `@moonbit/canopy-canvas` path mapping |
| `examples/canvas/web/vite.config.ts` | Vite config (mirrors examples/ideal/web/vite.config.ts) |
| `examples/canvas/web/package.json` | npm scripts |

---

### Task 1: Scaffold the module

**Files:**
- Create: `examples/canvas/moon.mod.json`
- Create: `examples/canvas/main/moon.pkg`
- Create: `examples/canvas/main/ffi.mbt`
- Create: `examples/canvas/web/package.json`
- Create: `examples/canvas/web/tsconfig.json`
- Create: `examples/canvas/web/vite.config.ts`
- Create: `examples/canvas/web/index.html`

- [ ] **Step 1: Create moon.mod.json**

```json
{
  "name": "dowdiness/canopy-canvas",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
```

Save to: `examples/canvas/moon.mod.json`

- [ ] **Step 2: Create main/moon.pkg**

`moonbitlang/core/json` is required for `derive(ToJson)` and `.to_json()`. Exports are filled in Task 9.

```
import {
  "moonbitlang/core/json",
}

options(
  "is-main": true,
  link: {
    "js": {
      "exports": [],
    },
  },
)
```

Save to: `examples/canvas/main/moon.pkg`

- [ ] **Step 3: Create ffi.mbt stub**

```moonbit
// JS externs go here when needed (future: drawOverlay, etc.)
```

Save to: `examples/canvas/main/ffi.mbt`

- [ ] **Step 4: Create web/package.json**

```json
{
  "name": "canopy-canvas",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "prebuild:moonbit": "cd ../.. && moon build --target js --release"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vite": "^5.4.0"
  }
}
```

Save to: `examples/canvas/web/package.json`

- [ ] **Step 5: Create web/tsconfig.json**

The `paths` entry tells TypeScript where to find the virtual `@moonbit/canopy-canvas` module that Vite resolves at runtime.

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "paths": {
      "@moonbit/canopy-canvas": ["../../_build/js/release/build/main/main.js"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

Save to: `examples/canvas/web/tsconfig.json`

- [ ] **Step 6: Create web/vite.config.ts**

```typescript
import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/canopy-canvas',
          path: '..',
          output: '_build/js/release/build/main/main.js'
        }
      ]
    }) as PluginOption
  ],
  server: {
    fs: {
      allow: ['../../..']
    }
  },
  build: {
    target: 'esnext'
  },
  optimizeDeps: {
    exclude: ['@moonbit/canopy-canvas']
  }
});
```

Save to: `examples/canvas/web/vite.config.ts`

- [ ] **Step 7: Create web/index.html**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Canopy Canvas</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: #0f0f1a; }

    #canvas-root {
      width: 100vw;
      height: 100vh;
      overflow: hidden;
      position: relative;
      cursor: grab;
    }
    #canvas-root.panning { cursor: grabbing; }

    #world {
      position: absolute;
      top: 0; left: 0;
      transform-origin: 0 0;
      /* transform set by JS */
    }

    /* Future hybrid: Canvas 2D overlay for selection handles, arrows */
    #overlay {
      position: absolute;
      top: 0; left: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
      display: none; /* enable when drawOverlay is implemented */
    }

    .canvas-node {
      position: absolute;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      user-select: none;
    }
    .canvas-node.selected {
      box-shadow: 0 0 0 2px #fff, 0 0 0 4px #8250df;
    }
    .canvas-node[data-kind="Text"] {
      font-family: 'Inter', sans-serif;
      font-size: 16px;
      font-weight: 500;
      color: #e8e8f0;
      background: rgba(130, 160, 255, 0.08);
      border: 1px solid rgba(130, 160, 255, 0.2);
    }
  </style>
</head>
<body>
  <div id="canvas-root">
    <div id="world"></div>
    <canvas id="overlay"></canvas>
  </div>
  <script type="module" src="/src/main.ts"></script>
</body>
</html>
```

Save to: `examples/canvas/web/index.html`

- [ ] **Step 8: Verify moon check passes**

```bash
cd examples/canvas && moon check
```

Expected: no errors (empty package is valid).

- [ ] **Step 9: Commit scaffold**

```bash
git add examples/canvas/
git commit -m "feat: scaffold examples/canvas standalone MoonBit module"
```

---

### Task 2: Define all types (canvas_state.mbt)

**Files:**
- Create: `examples/canvas/main/canvas_state.mbt`

- [ ] **Step 1: Write canvas_state.mbt**

Note:
- `NodeId` follows the `pub struct NodeId(Int)` tuple-struct pattern from `projection/types.mbt`
- Struct construction uses `({ ... } : TypeName)` or `let s : TypeName = { ... }` — never `TypeName { ... }`
- `pub(all)` on structs allows construction from test files (whitebox tests are same package, but explicit)

```moonbit
///|
/// Opaque integer ID for canvas nodes.
/// Uses tuple-struct pattern from projection/types.mbt.
pub struct NodeId(Int) derive(Show, Eq, ToJson)

///|
/// Visual kind of a node.
pub enum NodeKind {
  /// Filled rectangle. `color` is a CSS color string (e.g. "#8250df").
  Shape(String)
  /// Text label. `content` is the displayed string.
  Text(String)
} derive(Show, Eq, ToJson)

///|
/// Pan and zoom state of the canvas viewport.
/// `x` and `y` are the world origin in canvas-local screen space.
pub(all) struct Viewport {
  x     : Double
  y     : Double
  scale : Double
} derive(Show, Eq, ToJson)

///|
/// A single node on the canvas. Coordinates are in world space.
pub(all) struct CanvasNode {
  id   : NodeId
  x    : Double
  y    : Double
  w    : Double
  h    : Double
  kind : NodeKind
} derive(Show, Eq)

///|
/// State captured at the start of a node drag gesture.
pub(all) struct DragState {
  node_id  : NodeId
  /// Offset from cursor world position to node origin (node.x - cursor.x at drag start).
  offset_x : Double
  offset_y : Double
} derive(Show, Eq)

///|
/// State captured at the start of a pan gesture.
pub(all) struct PanState {
  start_screen_x : Double
  start_screen_y : Double
  start_pan_x    : Double
  start_pan_y    : Double
} derive(Show, Eq)

///|
pub(all) struct InteractionState {
  dragging     : DragState?
  panning      : PanState?
  selected     : NodeId?
  /// True from pointerdown until pointerup.
  pointer_down : Bool
  /// True once pointermove fires during the current pointer session.
  did_move     : Bool
} derive(Show, Eq)

///|
pub(all) struct CanvasState {
  viewport    : Viewport
  nodes       : Array[CanvasNode]
  interaction : InteractionState
} derive(Show)
```

Save to: `examples/canvas/main/canvas_state.mbt`

- [ ] **Step 2: Verify types compile**

```bash
cd examples/canvas && moon check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add examples/canvas/main/canvas_state.mbt
git commit -m "feat(canvas): define CanvasState type hierarchy"
```

---

### Task 3: Pan update functions + tests

**Files:**
- Create: `examples/canvas/main/canvas_update.mbt`
- Create: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 1: Write the failing tests first**

Codebase test conventions:
- Use `inspect(value, content="expected_string")` — not `assert_eq!`
- Use `guard x is Some(p)` for Option unpacking — not `let Some(p) = x`

```moonbit
///|
fn make_test_state() -> CanvasState {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes: [
      { id: NodeId(1), x: 100.0, y: 100.0, w: 200.0, h: 100.0, kind: NodeKind::Shape("#8250df") },
      { id: NodeId(2), x: 400.0, y: 200.0, w: 150.0, h:  80.0, kind: NodeKind::Text("hello") },
    ],
    interaction: {
      dragging:     None,
      panning:      None,
      selected:     None,
      pointer_down: false,
      did_move:     false,
    },
  }
}

///|
test "pan_start records start screen position and current pan" {
  let state = make_test_state()
  let s = update_pan_start(state, 150.0, 250.0)
  guard s.interaction.panning is Some(p)
  inspect(p.start_screen_x, content="150.0")
  inspect(p.start_screen_y, content="250.0")
  inspect(p.start_pan_x, content="0.0")
  inspect(p.start_pan_y, content="0.0")
  inspect(s.interaction.pointer_down, content="true")
  inspect(s.interaction.did_move, content="false")
}

///|
test "pan_move translates viewport by delta from start" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 100.0, 100.0)
  // Move pointer to (160, 140) → delta (60, 40)
  let s1 = update_pan_move(s0, 160.0, 140.0)
  inspect(s1.viewport.x, content="60.0")
  inspect(s1.viewport.y, content="40.0")
  inspect(s1.viewport.scale, content="1.0")
}

///|
test "pan_move is absolute not cumulative" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pan_move(s0, 50.0, 30.0)
  let s2 = update_pan_move(s1, 80.0, 50.0)
  // Second move uses original start_pan (0,0), not the intermediate position
  inspect(s2.viewport.x, content="80.0")
  inspect(s2.viewport.y, content="50.0")
}

///|
test "pan_move is no-op when not panning" {
  let state = make_test_state()
  let s = update_pan_move(state, 999.0, 999.0)
  inspect(s.viewport.x, content="0.0")
  inspect(s.viewport.y, content="0.0")
}
```

Save to: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd examples/canvas && moon test
```

Expected: compilation error — `update_pan_start` and `update_pan_move` not defined.

- [ ] **Step 3: Implement pan functions in canvas_update.mbt**

Struct construction uses `let s : TypeName = { ... }` — not `TypeName { ... }`.

```moonbit
///|
fn update_pan_start(
  state    : CanvasState,
  screen_x : Double,
  screen_y : Double
) -> CanvasState {
  let pan : PanState = {
    start_screen_x: screen_x,
    start_screen_y: screen_y,
    start_pan_x:    state.viewport.x,
    start_pan_y:    state.viewport.y,
  }
  let new_interaction : InteractionState = {
    ..state.interaction,
    panning:      Some(pan),
    pointer_down: true,
    did_move:     false,
  }
  { ..state, interaction: new_interaction }
}

///|
/// Pan is computed as absolute offset from start_pan to avoid
/// float accumulation across multiple move events.
fn update_pan_move(
  state    : CanvasState,
  screen_x : Double,
  screen_y : Double
) -> CanvasState {
  match state.interaction.panning {
    None => state
    Some(pan) => {
      let new_viewport : Viewport = {
        ..state.viewport,
        x: pan.start_pan_x + (screen_x - pan.start_screen_x),
        y: pan.start_pan_y + (screen_y - pan.start_screen_y),
      }
      { ..state, viewport: new_viewport }
    }
  }
}
```

Save to: `examples/canvas/main/canvas_update.mbt`

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd examples/canvas && moon test
```

Expected: all 4 pan tests pass.

- [ ] **Step 5: Commit**

```bash
git add examples/canvas/main/canvas_update.mbt examples/canvas/main/canvas_update_wbtest.mbt
git commit -m "feat(canvas): implement pan update with tests"
```

---

### Task 4: Zoom update + tests

**Files:**
- Modify: `examples/canvas/main/canvas_update.mbt`
- Modify: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 1: Add failing zoom tests**

Append to `examples/canvas/main/canvas_update_wbtest.mbt`:

```moonbit
///|
test "zoom out (delta > 0) decreases scale" {
  let state = make_test_state()
  let s = update_zoom(state, 1.0, 500.0, 400.0)
  // scale should be less than 1.0
  inspect(s.viewport.scale < 1.0, content="true")
}

///|
test "zoom in (delta < 0) increases scale" {
  let state = make_test_state()
  let s = update_zoom(state, -1.0, 500.0, 400.0)
  inspect(s.viewport.scale > 1.0, content="true")
}

///|
test "zoom clamps to min 0.1" {
  let state : CanvasState = { ..make_test_state(), viewport: { x: 0.0, y: 0.0, scale: 0.11 } }
  let s = update_zoom(state, 1.0, 0.0, 0.0)
  inspect(s.viewport.scale, content="0.1")
}

///|
test "zoom clamps to max 8.0" {
  let state : CanvasState = { ..make_test_state(), viewport: { x: 0.0, y: 0.0, scale: 7.5 } }
  let s = update_zoom(state, -1.0, 0.0, 0.0)
  inspect(s.viewport.scale, content="8.0")
}

///|
test "zoom keeps cursor world position fixed" {
  let state = make_test_state() // pan=(0,0), scale=1.0
  let cx = 300.0
  let cy = 200.0
  let world_x_before = (cx - state.viewport.x) / state.viewport.scale
  let s = update_zoom(state, 1.0, cx, cy)
  let world_x_after = (cx - s.viewport.x) / s.viewport.scale
  // Difference should be negligible (float precision)
  inspect((world_x_before - world_x_after).abs() < 1.0e-9, content="true")
}
```

- [ ] **Step 2: Run tests to confirm new ones fail**

```bash
cd examples/canvas && moon test
```

Expected: fails with `update_zoom` not defined.

- [ ] **Step 3: Implement zoom in canvas_update.mbt**

Append to `examples/canvas/main/canvas_update.mbt`:

```moonbit
///|
/// Zoom the viewport toward cursor position `(cx, cy)` in canvas-local screen coords.
/// delta > 0 = zoom out (factor 0.9), delta < 0 = zoom in (factor 1/0.9).
fn update_zoom(
  state : CanvasState,
  delta : Double,
  cx    : Double,
  cy    : Double
) -> CanvasState {
  let factor = if delta > 0.0 { 0.9 } else { 1.0 / 0.9 }
  let old_scale = state.viewport.scale
  let raw = old_scale * factor
  let new_scale = if raw < 0.1 {
    0.1
  } else if raw > 8.0 {
    8.0
  } else {
    raw
  }
  let ratio = new_scale / old_scale
  let new_viewport : Viewport = {
    ..state.viewport,
    scale: new_scale,
    x:     cx + (state.viewport.x - cx) * ratio,
    y:     cy + (state.viewport.y - cy) * ratio,
  }
  { ..state, viewport: new_viewport }
}
```

- [ ] **Step 4: Run all tests to confirm they pass**

```bash
cd examples/canvas && moon test
```

Expected: all tests pass including the 5 new zoom tests.

- [ ] **Step 5: Commit**

```bash
git add examples/canvas/main/canvas_update.mbt examples/canvas/main/canvas_update_wbtest.mbt
git commit -m "feat(canvas): implement zoom toward cursor with tests"
```

---

### Task 5: Node drag update + tests

**Files:**
- Modify: `examples/canvas/main/canvas_update.mbt`
- Modify: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 1: Add failing node drag tests**

Append to `examples/canvas/main/canvas_update_wbtest.mbt`:

```moonbit
///|
test "node_drag_start records offset from cursor to node origin" {
  let state = make_test_state()
  // Node 1 is at (100, 100). Grab at world (110, 120).
  // offset = node_pos - cursor = (100-110, 100-120) = (-10, -20)
  let s = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  guard s.interaction.dragging is Some(d)
  inspect(d.node_id, content="NodeId(1)")
  inspect(d.offset_x, content="-10.0")
  inspect(d.offset_y, content="-20.0")
  inspect(s.interaction.pointer_down, content="true")
  inspect(s.interaction.did_move, content="false")
}

///|
test "node_drag_start is no-op for unknown node id" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId(99), 0.0, 0.0)
  inspect(s.interaction.dragging, content="None")
}

///|
test "node_drag_move updates node position" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  // offset = (-10, -20). Move cursor to world (200, 300).
  // new pos = cursor + offset = (200 + -10, 300 + -20) = (190, 280)
  let s1 = update_node_drag_move(s0, 200.0, 300.0)
  inspect(s1.nodes[0].x, content="190.0")
  inspect(s1.nodes[0].y, content="280.0")
  inspect(s1.interaction.did_move, content="true")
}

///|
test "node_drag_move does not affect other nodes" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  let s1 = update_node_drag_move(s0, 200.0, 300.0)
  inspect(s1.nodes[1].x, content="400.0")
  inspect(s1.nodes[1].y, content="200.0")
}

///|
test "node_drag_move is no-op when not dragging" {
  let state = make_test_state()
  let s = update_node_drag_move(state, 999.0, 999.0)
  inspect(s.nodes[0].x, content="100.0")
  inspect(s.nodes[0].y, content="100.0")
}
```

- [ ] **Step 2: Run tests to confirm new ones fail**

```bash
cd examples/canvas && moon test
```

Expected: fails with `update_node_drag_start` / `update_node_drag_move` not defined.

- [ ] **Step 3: Implement node drag in canvas_update.mbt**

Append to `examples/canvas/main/canvas_update.mbt`:

```moonbit
///|
fn find_node(nodes : Array[CanvasNode], id : NodeId) -> CanvasNode? {
  for node in nodes {
    if node.id == id {
      return Some(node)
    }
  }
  None
}

///|
fn update_node_drag_start(
  state   : CanvasState,
  node_id : NodeId,
  world_x : Double,
  world_y : Double
) -> CanvasState {
  match find_node(state.nodes, node_id) {
    None => state
    Some(node) => {
      let drag : DragState = {
        node_id,
        offset_x: node.x - world_x,
        offset_y: node.y - world_y,
      }
      let new_interaction : InteractionState = {
        ..state.interaction,
        dragging:     Some(drag),
        pointer_down: true,
        did_move:     false,
      }
      { ..state, interaction: new_interaction }
    }
  }
}

///|
fn update_node_drag_move(
  state   : CanvasState,
  world_x : Double,
  world_y : Double
) -> CanvasState {
  match state.interaction.dragging {
    None => state
    Some(drag) => {
      let new_nodes = state.nodes.map(fn(node) {
        if node.id == drag.node_id {
          ({ ..node, x: world_x + drag.offset_x, y: world_y + drag.offset_y } : CanvasNode)
        } else {
          node
        }
      })
      let new_interaction : InteractionState = { ..state.interaction, did_move: true }
      { ..state, nodes: new_nodes, interaction: new_interaction }
    }
  }
}
```

- [ ] **Step 4: Run all tests to confirm they pass**

```bash
cd examples/canvas && moon test
```

Expected: all tests pass including the 5 new drag tests.

- [ ] **Step 5: Commit**

```bash
git add examples/canvas/main/canvas_update.mbt examples/canvas/main/canvas_update_wbtest.mbt
git commit -m "feat(canvas): implement node drag with tests"
```

---

### Task 6: Pointer up + selection + tests

**Files:**
- Modify: `examples/canvas/main/canvas_update.mbt`
- Modify: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 1: Add failing pointer_up tests**

Append to `examples/canvas/main/canvas_update_wbtest.mbt`:

```moonbit
///|
test "pointer_up clears panning state" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pointer_up(s0, 0)
  inspect(s1.interaction.panning, content="None")
  inspect(s1.interaction.pointer_down, content="false")
}

///|
test "pointer_up clears dragging state" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 0.0, 0.0)
  let s1 = update_pointer_up(s0, 1)
  inspect(s1.interaction.dragging, content="None")
  inspect(s1.interaction.pointer_down, content="false")
}

///|
test "pointer_up on node without movement selects it" {
  let state = make_test_state()
  // pointerdown on node 1, no movement → did_move stays false
  let s0 = update_node_drag_start(state, NodeId(1), 100.0, 100.0)
  let s1 = update_pointer_up(s0, 1)
  inspect(s1.interaction.selected, content="Some(NodeId(1))")
}

///|
test "pointer_up after drag movement does not change selection" {
  let state : CanvasState = {
    ..make_test_state(),
    interaction: { ..make_test_state().interaction, selected: Some(NodeId(2)) },
  }
  let s0 = update_node_drag_start(state, NodeId(1), 100.0, 100.0)
  let s1 = update_node_drag_move(s0, 200.0, 200.0) // sets did_move = true
  let s2 = update_pointer_up(s1, 1)
  // Selection unchanged because movement occurred (it was a drag, not a click)
  inspect(s2.interaction.selected, content="Some(NodeId(2))")
}

///|
test "pointer_up on background deselects" {
  let state : CanvasState = {
    ..make_test_state(),
    interaction: { ..make_test_state().interaction, selected: Some(NodeId(1)) },
  }
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pointer_up(s0, 0)
  inspect(s1.interaction.selected, content="None")
}
```

- [ ] **Step 2: Run tests to confirm new ones fail**

```bash
cd examples/canvas && moon test
```

Expected: fails with `update_pointer_up` not defined.

- [ ] **Step 3: Implement pointer_up in canvas_update.mbt**

Append to `examples/canvas/main/canvas_update.mbt`:

```moonbit
///|
/// Handle pointer release. `node_id_int` is the canvas node id under the pointer,
/// or 0 if released over the background.
/// A "click" = pointer_down was true AND no movement occurred → select the node.
fn update_pointer_up(
  state       : CanvasState,
  node_id_int : Int
) -> CanvasState {
  let hovered : NodeId? = if node_id_int == 0 { None } else { Some(NodeId(node_id_int)) }
  let new_selected : NodeId? = if state.interaction.pointer_down &&
    not(state.interaction.did_move) {
    hovered
  } else {
    state.interaction.selected
  }
  let new_interaction : InteractionState = {
    ..state.interaction,
    dragging:     None,
    panning:      None,
    pointer_down: false,
    did_move:     false,
    selected:     new_selected,
  }
  { ..state, interaction: new_interaction }
}
```

- [ ] **Step 4: Run all tests to confirm they pass**

```bash
cd examples/canvas && moon test
```

Expected: all tests pass (14+ tests total).

- [ ] **Step 5: Commit**

```bash
git add examples/canvas/main/canvas_update.mbt examples/canvas/main/canvas_update_wbtest.mbt
git commit -m "feat(canvas): implement pointer_up and click-to-select with tests"
```

---

### Task 7: Handle registry + bridge functions + seed nodes

**Files:**
- Create: `examples/canvas/main/canvas_init.mbt`

- [ ] **Step 1: Create canvas_init.mbt**

```moonbit
///|
/// Global handle registry. Index = handle (Int returned by create_canvas).
let _registry : Array[CanvasState] = []

///|
fn make_initial_state() -> CanvasState {
  {
    // Center the world origin roughly in a 1440×800 browser viewport
    viewport: { x: 520.0, y: 300.0, scale: 1.0 },
    nodes: [
      { id: NodeId(1), x: -320.0, y: -160.0, w: 200.0, h: 120.0, kind: NodeKind::Shape("#8250df") },
      { id: NodeId(2), x:  -60.0, y: -160.0, w: 200.0, h: 120.0, kind: NodeKind::Shape("#c792ea") },
      { id: NodeId(3), x:  200.0, y: -160.0, w: 200.0, h: 120.0, kind: NodeKind::Shape("#82aaff") },
      { id: NodeId(4), x: -320.0, y:   20.0, w: 200.0, h:  60.0, kind: NodeKind::Text("Canopy Canvas") },
      { id: NodeId(5), x:  -60.0, y:   20.0, w: 200.0, h:  60.0, kind: NodeKind::Text("Pan · Zoom · Drag") },
      { id: NodeId(6), x:  200.0, y:   20.0, w: 200.0, h:  60.0, kind: NodeKind::Text("∞") },
    ],
    interaction: {
      dragging:     None,
      panning:      None,
      selected:     None,
      pointer_down: false,
      did_move:     false,
    },
  }
}

///|
pub fn create_canvas() -> Int {
  _registry.push(make_initial_state())
  _registry.length() - 1
}

///|
pub fn pan_start(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle] = update_pan_start(_registry[handle], sx, sy)
}

///|
pub fn pan_move(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle] = update_pan_move(_registry[handle], sx, sy)
}

///|
pub fn zoom(handle : Int, delta : Double, cx : Double, cy : Double) -> Unit {
  _registry[handle] = update_zoom(_registry[handle], delta, cx, cy)
}

///|
pub fn node_drag_start(
  handle  : Int,
  node_id : Int,
  world_x : Double,
  world_y : Double
) -> Unit {
  _registry[handle] = update_node_drag_start(
    _registry[handle], NodeId(node_id), world_x, world_y,
  )
}

///|
pub fn node_drag_move(handle : Int, world_x : Double, world_y : Double) -> Unit {
  _registry[handle] = update_node_drag_move(_registry[handle], world_x, world_y)
}

///|
pub fn pointer_up(handle : Int, node_id : Int) -> Unit {
  _registry[handle] = update_pointer_up(_registry[handle], node_id)
}
```

Save to: `examples/canvas/main/canvas_init.mbt`

- [ ] **Step 2: Verify moon check**

```bash
cd examples/canvas && moon check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add examples/canvas/main/canvas_init.mbt
git commit -m "feat(canvas): handle registry and bridge wrapper functions"
```

---

### Task 8: get_render_state JSON serialization + test

**Files:**
- Modify: `examples/canvas/main/canvas_init.mbt`
- Modify: `examples/canvas/main/canvas_update_wbtest.mbt`

- [ ] **Step 1: Add serialization test first**

The test uses exact `inspect` snapshot — run with `moon test --update` on first run to capture the actual output, then lock it in.

Append to `examples/canvas/main/canvas_update_wbtest.mbt`:

```moonbit
///|
test "get_render_state returns correct JSON shape" {
  // create_canvas returns handle 0 on first call in test process
  let handle = create_canvas()
  let json_str = get_render_state(handle)
  // Run `moon test --update` on first run to capture actual snapshot.
  inspect(json_str, content="")
}
```

- [ ] **Step 2: Run tests to confirm the test fails**

```bash
cd examples/canvas && moon test
```

Expected: compilation error — `get_render_state` not defined.

- [ ] **Step 3: Implement get_render_state in canvas_init.mbt**

Append to `examples/canvas/main/canvas_init.mbt`:

```moonbit
///|
/// Serializable node snapshot. Uses plain Int for `id` to avoid
/// the NodeId newtype wrapper appearing in JSON output.
struct NodeJson {
  id   : Int
  x    : Double
  y    : Double
  w    : Double
  h    : Double
  kind : NodeKind
} derive(ToJson)

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected` is null (None) when no node is selected.
struct RenderStateJson {
  viewport : Viewport
  nodes    : Array[NodeJson]
  selected : Int?
} derive(ToJson)

///|
pub fn get_render_state(handle : Int) -> String {
  let state = _registry[handle]
  let selected : Int? = match state.interaction.selected {
    None => None
    Some(NodeId(id)) => Some(id)
  }
  let nodes = state.nodes.map(fn(n) {
    let NodeId(id) = n.id
    ({ id, x: n.x, y: n.y, w: n.w, h: n.h, kind: n.kind } : NodeJson)
  })
  let rs : RenderStateJson = { viewport: state.viewport, nodes, selected }
  rs.to_json().to_string()
}
```

- [ ] **Step 4: Run tests and capture snapshot**

```bash
cd examples/canvas && moon test --update
```

Expected: tests pass, `inspect` snapshot in `canvas_update_wbtest.mbt` updated with the actual JSON string. Verify the captured snapshot looks like:

```json
{"viewport":{"x":520.0,"y":300.0,"scale":1.0},"nodes":[{"id":1,"x":-320.0,...}],"selected":null}
```

If the snapshot content is wrong, inspect it manually and correct in the test file.

- [ ] **Step 5: Run tests again to confirm locked snapshot passes**

```bash
cd examples/canvas && moon test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add examples/canvas/main/canvas_init.mbt examples/canvas/main/canvas_update_wbtest.mbt
git commit -m "feat(canvas): get_render_state JSON serialization with snapshot test"
```

---

### Task 9: Update moon.pkg exports + build

**Files:**
- Modify: `examples/canvas/main/moon.pkg`

- [ ] **Step 1: Update moon.pkg with full export list**

Replace `examples/canvas/main/moon.pkg`:

```
import {
  "moonbitlang/core/json",
}

options(
  "is-main": true,
  link: {
    "js": {
      "exports": [
        "create_canvas",
        "pan_start",
        "pan_move",
        "zoom",
        "node_drag_start",
        "node_drag_move",
        "pointer_up",
        "get_render_state",
      ],
    },
  },
)
```

- [ ] **Step 2: Build for JS**

```bash
cd examples/canvas && moon build --target js --release
```

Expected: no errors. Output at `_build/js/release/build/main/main.js`.

- [ ] **Step 3: Verify exported symbols in built JS**

```bash
grep -c "create_canvas\|pan_start\|pan_move\|node_drag_start\|node_drag_move\|pointer_up\|get_render_state" examples/canvas/_build/js/release/build/main/main.js
```

Expected: a count > 0 (all symbols appear in the output).

- [ ] **Step 4: Run moon test to confirm nothing broke**

```bash
cd examples/canvas && moon test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add examples/canvas/main/moon.pkg
git commit -m "feat(canvas): configure JS exports in moon.pkg"
```

---

### Task 10: TypeScript implementation (main.ts)

**Files:**
- Create: `examples/canvas/web/src/main.ts`

- [ ] **Step 1: Create web/src/main.ts**

Notes:
- `localCoords` accepts `MouseEvent` (not `PointerEvent`) so it works for both `PointerEvent` and `WheelEvent` (both extend `MouseEvent`)
- `// (Future) drawOverlay(state)` stub marks the hybrid Canvas 2D upgrade point
- The render loop always patches node divs on each frame. This is a no-op for node style properties during pan/zoom (values don't change), which is acceptable for a 6-node demo

```typescript
type CanvasModule = {
  create_canvas:   () => number;
  pan_start:       (h: number, sx: number, sy: number) => void;
  pan_move:        (h: number, sx: number, sy: number) => void;
  zoom:            (h: number, delta: number, cx: number, cy: number) => void;
  node_drag_start: (h: number, id: number, wx: number, wy: number) => void;
  node_drag_move:  (h: number, wx: number, wy: number) => void;
  pointer_up:      (h: number, nodeId: number) => void;
  get_render_state:(h: number) => string;
};

type Viewport   = { x: number; y: number; scale: number };
type NodeKind   = ['Shape', string] | ['Text', string];
type NodeData   = { id: number; x: number; y: number; w: number; h: number; kind: NodeKind };
type RenderState = { viewport: Viewport; nodes: NodeData[]; selected: number | null };

let mb: CanvasModule;
let handle = -1;
let rafPending = false;
// Cached viewport — used by screenToWorld without re-parsing JSON
let lastViewport: Viewport = { x: 0, y: 0, scale: 1 };

const root     = document.getElementById('canvas-root') as HTMLDivElement;
const world    = document.getElementById('world') as HTMLDivElement;
const nodeDivs = new Map<number, HTMLDivElement>();

// ─── RAF render loop ─────────────────────────────────────────────────────────

function scheduleRender(): void {
  if (rafPending) return;
  rafPending = true;
  requestAnimationFrame(render);
}

function render(): void {
  rafPending = false;
  const state: RenderState = JSON.parse(mb.get_render_state(handle));
  lastViewport = state.viewport;

  // 1. Update world transform (pan + zoom — only #world touched, not node divs)
  const { x, y, scale } = state.viewport;
  world.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;

  // 2. Sync node divs (only meaningful changes during node drag)
  const seen = new Set<number>();
  for (const node of state.nodes) {
    seen.add(node.id);
    let div = nodeDivs.get(node.id);
    if (!div) {
      div = document.createElement('div');
      div.className = 'canvas-node';
      div.dataset.nodeId = String(node.id);
      world.appendChild(div);
      nodeDivs.set(node.id, div);
    }
    div.style.left   = `${node.x}px`;
    div.style.top    = `${node.y}px`;
    div.style.width  = `${node.w}px`;
    div.style.height = `${node.h}px`;

    const [kind, value] = node.kind;
    if (kind === 'Shape') {
      div.style.backgroundColor = value;
      div.dataset.kind = 'Shape';
      div.textContent = '';
    } else {
      div.style.backgroundColor = '';
      div.dataset.kind = 'Text';
      div.textContent = value;
    }
    div.classList.toggle('selected', state.selected === node.id);
  }

  // 3. Remove divs for deleted nodes (future: add/delete support)
  for (const [id, div] of nodeDivs) {
    if (!seen.has(id)) { div.remove(); nodeDivs.delete(id); }
  }

  // 4. (Future) drawOverlay(state);
}

// ─── Coordinate helpers ───────────────────────────────────────────────────────

/** Pointer/wheel position in canvas-local screen space.
 *  Accepts MouseEvent so it works for both PointerEvent and WheelEvent. */
function localCoords(e: MouseEvent): [number, number] {
  const rect = root.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

/** Convert canvas-local screen coords to world coords. */
function screenToWorld(sx: number, sy: number): [number, number] {
  const { x, y, scale } = lastViewport;
  return [(sx - x) / scale, (sy - y) / scale];
}

/** Walk up the DOM from event target to find data-node-id. Returns 0 for background. */
function nodeIdFromTarget(target: EventTarget | null): number {
  let el = target as HTMLElement | null;
  while (el && el !== world) {
    if (el.dataset?.nodeId) return parseInt(el.dataset.nodeId);
    el = el.parentElement;
  }
  return 0;
}

// ─── Event wiring ─────────────────────────────────────────────────────────────

type Interaction = 'none' | 'pan' | 'drag';
let activeInteraction: Interaction = 'none';
let activePointerId = -1;

root.addEventListener('pointerdown', (e: PointerEvent) => {
  root.setPointerCapture(e.pointerId);
  activePointerId = e.pointerId;
  const [sx, sy] = localCoords(e);
  const nodeId = nodeIdFromTarget(e.target);

  if (nodeId !== 0) {
    const [wx, wy] = screenToWorld(sx, sy);
    mb.node_drag_start(handle, nodeId, wx, wy);
    activeInteraction = 'drag';
  } else {
    mb.pan_start(handle, sx, sy);
    activeInteraction = 'pan';
    root.classList.add('panning');
  }
  scheduleRender();
});

root.addEventListener('pointermove', (e: PointerEvent) => {
  if (e.pointerId !== activePointerId) return;
  const [sx, sy] = localCoords(e);
  if (activeInteraction === 'pan') {
    mb.pan_move(handle, sx, sy);
  } else if (activeInteraction === 'drag') {
    const [wx, wy] = screenToWorld(sx, sy);
    mb.node_drag_move(handle, wx, wy);
  }
  scheduleRender();
});

root.addEventListener('pointerup', (e: PointerEvent) => {
  if (e.pointerId !== activePointerId) return;
  const nodeId = nodeIdFromTarget(e.target);
  mb.pointer_up(handle, nodeId);
  activeInteraction = 'none';
  activePointerId = -1;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('pointercancel', () => {
  if (activePointerId === -1) return;
  mb.pointer_up(handle, 0);
  activeInteraction = 'none';
  activePointerId = -1;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('wheel', (e: WheelEvent) => {
  e.preventDefault();
  const [cx, cy] = localCoords(e); // WheelEvent extends MouseEvent ✓
  mb.zoom(handle, e.deltaY, cx, cy);
  scheduleRender();
}, { passive: false });

// ─── Bootstrap ────────────────────────────────────────────────────────────────

async function init(): Promise<void> {
  const mod = await import('@moonbit/canopy-canvas') as CanvasModule;
  mb = mod;
  handle = mb.create_canvas();
  render(); // initial render
}

init();
```

Save to: `examples/canvas/web/src/main.ts`

- [ ] **Step 2: Commit**

```bash
git add examples/canvas/web/src/main.ts
git commit -m "feat(canvas): TypeScript bootstrap, event wiring, RAF render loop"
```

---

### Task 11: Run dev server + smoke test

- [ ] **Step 1: Install npm dependencies**

```bash
cd examples/canvas/web && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 2: Start dev server**

```bash
cd examples/canvas/web && npm run dev
```

Expected: Vite prints a local URL (typically `http://localhost:5173`).

- [ ] **Step 3: Verify the canvas loads**

Open the URL. Expected:
- Dark background fills the viewport
- 6 nodes visible: 3 colored rectangles (purple/lavender/blue) and 3 text labels
- No console errors

- [ ] **Step 4: Verify pan**

Click and drag on the background. Expected:
- All nodes move together as the viewport pans
- Cursor changes to `grabbing`
- Nodes return to normal cursor on release

- [ ] **Step 5: Verify zoom**

Scroll the mouse wheel (or pinch on trackpad). Expected:
- Nodes scale around the cursor position
- Scale clamped — can't zoom past 8× or below 0.1×

- [ ] **Step 6: Verify node drag**

Click and drag a colored rectangle. Expected:
- Only that node moves
- Other nodes stay in place

- [ ] **Step 7: Verify click-to-select**

Click (no drag) on a node. Expected:
- Node gains a purple double-ring outline
- Clicking another node transfers selection
- Clicking background deselects

- [ ] **Step 8: Final commit**

```bash
git add examples/canvas/
git commit -m "feat: infinite canvas demo — pan, zoom, drag, select"
```

---

## Self-Review

**Spec coverage:**
- ✅ Pan, zoom (clamped [0.1, 8.0]), node drag
- ✅ Shape nodes (filled rect), text nodes (label)
- ✅ Click-to-select (CSS `.selected` class)
- ✅ Hybrid overlay stub (`#overlay` + `// (Future) drawOverlay` comment)
- ✅ Pointer capture (`setPointerCapture`)
- ✅ Standalone module layout (moon.mod.json + main/moon.pkg + web/)
- ✅ Handle-first bridge
- ✅ Canvas-local coordinates (`localCoords` subtracts `getBoundingClientRect`)
- ✅ RAF-batched render
- ✅ JSON schema matches spec (NodeKind array-encoded, selected null or Int)
- ✅ `moonbitlang/core/json` imported in moon.pkg
- ✅ `tsconfig.json` with `@moonbit/canopy-canvas` path

**Placeholder scan:** No TBDs. Task 8 Step 4 explicitly instructs to run `--update` and lock the snapshot — intentional, not a placeholder.

**Type consistency:**
- `NodeId(n)` construction and `let NodeId(id) = n.id` destructuring — consistent with `pub struct NodeId(Int)` tuple-struct definition
- `update_pointer_up(state, node_id_int: Int)` and bridge `pointer_up(handle, node_id)` — both use plain Int for node id
- `find_node` defined in `canvas_update.mbt`, used in `update_node_drag_start` — same file
- `_registry` array defined once in `canvas_init.mbt`, accessed only there
- `NodeJson` / `RenderStateJson` defined in `canvas_init.mbt`, not exposed outside
