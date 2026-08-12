# Canopy Canvas Graph

Reusable graph model and pure interaction core for Canopy canvas workflows.

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
internal construction uses `Viewport::validated`, while untrusted input uses
`Viewport::from_scale` and handles its typed `ViewportError`. Screen/world point
values expose `is_finite` so host input boundaries can reject non-finite
coordinates before starting pan, zoom, or drag transitions. `Pan::start`,
`Pan::viewport_at`, `Drag::start`, and `Drag::positions_at` raise typed spatial
errors; reducers and hosts catch those errors and leave state unchanged.

The GraphOperation V2 JSON wire shape remains `{x, y, scale}`. The
`graph_model` serialization boundary owns its strict encoding and decoding;
non-finite coordinates and non-finite or non-positive scales raise
`@json.JsonDecodeError`. Invalid viewport operations are rejected before
replay, so they are neither normalized nor retained in `action_log`. The
`spatial` package itself has no JSON dependency. The trusted
`Viewport::validated` constructor uses `try!` only for values established by
internal invariants; browser and wire inputs use the explicit raising
constructors instead.
