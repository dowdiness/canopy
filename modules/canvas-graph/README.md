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

## Viewport replay compatibility

`GraphOperation` version 2 keeps its existing JSON shape and preserves the
semantics of valid `SetViewport` operations during replay. Older persisted
state can contain a non-finite or non-positive scale because the legacy
`CanvasState` boundary is open. The graph model normalizes those malformed
values to `1.0` when materializing state, while retaining the original
operation in `action_log` for audit and provenance. This is recovery for an
out-of-invariant legacy value, not a change to valid version-2 replay.
