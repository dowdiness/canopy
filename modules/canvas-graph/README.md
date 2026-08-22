# Canopy Canvas Graph

Reusable graph model and pure interaction core for Canopy canvas workflows.

Spatial geometry is provided by the independent `dowdiness/canvas-spatial`
module, which graph consumers import directly.

The library owns:

- stable node/edge/port identifiers
- durable `CanvasState` / `CanvasDocument` graph snapshots
- versioned `GraphOperation` JSON round-tripping and replay
- typed connection validation and operation application
- pure pan, zoom, drag, selection, connect, and pointer release reducers
- the small runtime seam (`SelectionState`, `DragPreview`, document/state
  conversion helpers) shared by the hand-built canvas and source-backed mode

The library does **not** own browser DOM/SVG rendering, TypeScript event
listeners, JS handle registries, or demo-specific workflow validation copy. The
`apps/canvas` package keeps the incr runtime, JSON DTO lowering, inspector
text, and FFI exports so applications can choose their own rendering and
validation surfaces while reusing the model and reducers here.

## Viewport invariants

`CanvasState` and `SetViewport` use `@spatial.Viewport` directly.
Its origin coordinates and scale are always finite, and its scale is positive:
`ScreenPoint`, `WorldPoint`, and `Scale` constructors reject invalid raw values,
while `Viewport::from_scale` accepts only those validated values. Screen/world
points expose coordinate accessors, not a caller-side finiteness obligation.
`Pan::start` and `Drag::start` capture validated snapshots; their evaluation
methods raise `CoordinateError` when derived arithmetic overflows, and
reducers and hosts catch that error and leave state unchanged.

The GraphOperation V2 JSON wire shape remains `{x, y, scale}`. The
`graph_model` serialization boundary owns its strict encoding and decoding;
non-finite coordinates and non-finite or non-positive scales raise
`@json.JsonDecodeError`. Invalid viewport operations are rejected before
replay, so they are neither normalized nor retained in `action_log`. The
`spatial` package itself has no JSON dependency. Browser and wire inputs use the
explicit raising constructors before entering the durable graph state.
