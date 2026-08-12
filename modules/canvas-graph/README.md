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
Its scale is always finite and positive: internal construction uses
`Viewport::validated`, while untrusted input can use `try_from_scale` without
creating an invalid value.

The GraphOperation V2 JSON wire shape remains `{x, y, scale}`. The
`graph_model` serialization boundary owns its strict encoding and decoding;
non-finite coordinates and non-finite or non-positive scales raise
`@json.JsonDecodeError`. Invalid viewport operations are rejected before
replay, so they are neither normalized nor retained in `action_log`. The
`spatial` package itself has no JSON dependency.
