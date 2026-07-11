# GUI Layer Integration Report

Date: 2026-05-31

This note records the current UI surfaces in Canopy and the design direction
for a GUI layer where structural editing and text editing stay synchronized.
The immediate target is a node-graph UI that can become the authoring surface
for a Canopy DSL lowering into MoonDsp, while still using Canopy's protocol,
CRDT, and incremental computation pipeline.

## What the GUI layer must do

The GUI layer should be defined by required behavior before choosing a
framework:

- Show the same document as source text, structure, formatted output, debug
  state, and graph topology without each view owning a separate document.
- Convert user gestures into serializable operations, then lower those
  operations into Canopy edits or domain-specific graph edits.
- Apply engine output as patches so unrelated UI state, selection, hover,
  viewport, and focused text are not destroyed by every recomputation.
- Preserve stable IDs across text and structure roundtrips so selection,
  diagnostics, collaboration cursors, and undo/redo remain meaningful.
- Keep pointer-heavy UI state, such as graph hover, drag, pan, and zoom,
  separate from durable document state.
- Route expensive parsing, projection, graph lowering, and MoonDsp template
  analysis outside the audio callback. Audio preview may consume only prepared
  runtime data.

The design consequence is that the editor needs two operation layers:

- A stable protocol layer: `ViewPatch` output and `UserIntent` input.
- A domain layer for graph operations whose payloads are typed enough for
  undo/redo, collaboration, replay, and tests.

## Existing UI surfaces

| Surface | Role today | Useful pieces | Limits for node-graph work |
| --- | --- | --- | --- |
| `examples/web` | Vite demos for Lambda, JSON, and Markdown. | Simple text-to-model sync, `HTMLAdapter`, JSON structural toolbar, Graphviz SVG preview, markdown block/preview modes. | Mostly direct FFI calls; JSON structural toolbar bypasses `UserIntent` for richer edit payloads. |
| `examples/ideal` | Main integrated editor shell. | Rabbita app state, CodeMirror text mode, ProseMirror structure mode, outline, inspector, bottom panels, CRDT bridge, RAF reconcile, performance taps. | Structure mode currently failed in the local browser smoke test with a ProseMirror content error; fix before using it as the graph integration host. |
| `examples/prosemirror` | Minimal protocol-pure structural editor. | `ViewPatch[] -> PMAdapter`, `UserIntent -> engine` loop, protocol-only keymap. | Generic tree rendering only; not suited to free-form graph pan/zoom. |
| `examples/canvas` | Workflow node canvas prototype. | MoonBit-owned `CanvasState`, typed `WorkflowAction`, ports, edges, validation, pan/zoom, drag, connection gestures, action log, DOM maps keyed by node/edge IDs. | Not connected to `SyncEditor`, `ViewPatch`, source maps, or Canopy language companions yet. |
| `examples/block-editor` | Block-level document editor. | contenteditable blocks keyed by IDs, drag handles, focused-block preservation, Markdown import/export path. | Document model is block CRDT-specific and not protocol-driven. |
| `examples/codemirror_demo` and `lib/rabbita_codemirror` | Rabbita binding smoke test for CodeMirror. | Function-based MoonBit API, `Cmd`/`Sub` lifecycle, editor handle registry, guarded programmatic updates. | Text surface only; use for source pane and inline fields, not graph topology. |
| `adapters/editor-adapter` | Framework-agnostic patch/intent boundary. | `EditorAdapter`, `CM6Adapter`, `PMAdapter`, `HTMLAdapter`, stable TS protocol types. | README explicitly scopes non-text custom surfaces out of this package; graph work should be a separate adapter. |
| `graphviz` and `lib/visualizer` | DOT parse/layout/render to SVG. | Read-only graph inspection, diagnostics and history visualization. | SVG Graphviz is not an interactive graph editor; do not use it as the primary node canvas. |

Browser smoke observations:

- `examples/web` ran Lambda, JSON, and Markdown pages. JSON selection enabled
  structural toolbar buttons, and Markdown rendered block/preview content.
- `examples/ideal` ran the integrated shell, text editor, outline, inspector,
  and bottom panels. Switching to Structure mode logged
  `RangeError: Invalid content for node module: <>` from the ProseMirror
  structure path in this environment.
- `examples/canvas` ran the workflow canvas. Adding a node updated the visible
  canvas and the action count, confirming the operation-log path is live.
- `examples/block-editor` ran the contenteditable block editor with import and
  export controls.
- `examples/prosemirror` ran the minimal protocol editor and displayed the
  Lambda structure through `PMAdapter`.

The local `examples/web` dev server also hit the OS file-watch limit after its
initial MoonBit build. That is a development environment issue, but it makes
long-running multi-demo investigation noisy.

## Protocol implications

`protocol/README.md`, `protocol/view_node.mbt`,
`protocol/view_patch.mbt`, and `protocol/user_intent.mbt` define the current
wire boundary:

- `ViewNode` is a tree node with stable-looking `id`, `kind_tag`, `label`,
  optional editable `text`, `text_range`, token spans, CSS class, children, and
  annotations.
- `ViewPatch` is output-only from engine to UI. It supports text changes, tree
  replacement, child insertion/removal, node updates, decorations,
  diagnostics, selection, and full-tree replacement.
- `UserIntent` is the only bidirectional protocol type. It supports
  `TextEdit`, generic `StructuralEdit`, selection, cursor, undo/redo, and
  commit edit.
- `StructuralEdit` currently carries `params: Map[String, String]`. That is
  enough for simple toolbar commands, but not enough for graph operations that
  need numbers, arrays, edges, positions, typed values, or nested payloads.

For the node graph, treat `UserIntent::StructuralEdit` as a bridge, not the
authoritative graph operation schema. The graph UI should emit typed domain
operations first, serialize them for logs/tests/collaboration, then lower them
to either:

- `UserIntent` for operations that already fit the protocol.
- A language-specific graph edit API for richer payloads.
- Source-map-based `TextEdit` / `SpanEdit` sequences when text must remain the
  canonical storage format.

## ViewMode and ViewNode usage

The `Printable` family described in
`docs/architecture/multi-representation-system.md` gives the representation
contract:

| Mode | Source | GUI use |
| --- | --- | --- |
| `Structure` | Projection/renderable tree | Main AST or graph topology view; best target for selection and structural editing. |
| `Formatted` | `Pretty` layout rendered by `layout_to_view_tree` | Readable code/document display; useful side pane, not ideal as edit target today. |
| `Debug` | `Debug` output | Inspector and troubleshooting panels. |
| `Source` | `Source` output or current CRDT text | CodeMirror/source pane and exact roundtrip testing. |

Important caveat: `protocol/formatted_view.mbt::layout_to_view_tree` emits a
synthetic root `formatted-text` and per-line nodes with sequential IDs. That is
appropriate for display and token styling, but those IDs are not semantic graph
or projection IDs. A mixed UI should therefore use:

- `Structure` IDs for durable selection, graph nodes, patch targeting, and
  collaboration.
- `Formatted` IDs only for display-local line rendering unless the renderer is
  extended to preserve source/projection identity.
- `Source` for exact text edits and syntax roundtrip.
- `Debug` for side panels, logs, and developer inspection.

## Framework evaluation

| Technology | Recommendation | Reasoning |
| --- | --- | --- |
| Rabbita | Use for the application shell, panels, state coordination, and subscriptions. | `examples/ideal` already uses Rabbita to coordinate mode tabs, outline, inspector, bottom panels, CRDT state, and refresh commands. |
| CodeMirror 6 | Use for source text, inline expression fields, and possibly editable graph parameter fields. | `CM6Adapter` and `rabbita_codemirror` already guard programmatic updates and emit document/cursor changes. |
| ProseMirror | Keep for structured tree editing, not for node graph topology. | It is good at document/tree selection and node views, but free-form pan/zoom/ports fit poorly. |
| Canvas DOM + SVG from `examples/canvas` | Use as the first node graph substrate. | It already has pan, zoom, nodes, ports, edges, validation, action logs, RAF scheduling, and keyed DOM/SVG maps. |
| Graphviz/SVG | Use for read-only inspectors and debug graph exports. | Layout is useful for history/dependency visualization, but direct manipulation requires a separate interaction layer. |
| `adapters/editor-adapter` | Reuse the interface shape, but create a separate GraphAdapter. | The package intentionally excludes non-text custom surfaces. A graph adapter can still expose `applyPatches`, `onIntent`, and `destroy`. |

The pragmatic split is:

```text
Rabbita shell
  -> CodeMirror source pane
  -> GraphAdapter canvas pane
  -> Inspector / Problems / Op log / Incr graph / Audio preview panels

GraphAdapter
  -> pointer/keyboard gestures
  -> typed GraphOperation values
  -> engine bridge
  -> patch/diff application back to keyed DOM/SVG nodes
```

## Proposed operation model

Start from the `examples/canvas/main/canvas_state.mbt` precedent:
`WorkflowAction` already models durable actions such as `AddNode`,
`MoveNodes`, `ConnectPorts`, `SelectNodes`, and `SetViewport`.

For a DSP graph UI, use a typed operation set like:

| Operation | Durable? | Notes |
| --- | --- | --- |
| `AddNode(kind, position, initial_params)` | Yes | Creates a graph node with a stable authoring ID. |
| `DeleteNode(node_id)` | Yes | Removes node and incident edges, preserving enough data for undo. |
| `MoveNodes(Array[NodePosition])` | Usually yes at gesture end | Pointer moves should be ephemeral or throttled; commit final positions on pointerup. |
| `ConnectPorts(source, source_port, target, target_port)` | Yes | Validate self-loops, duplicate edges, direction, and signal type. |
| `DisconnectEdge(edge_id)` | Yes | Prefer edge ID over recomputing by endpoint tuple. |
| `SetParam(node_id, field, value)` | Yes | `value` must be typed: number, unit value, enum, string, control binding, or expression. |
| `RenameNode(node_id, label)` | Yes | Useful for stable user-facing labels independent of source identifiers. |
| `SelectNodes(ids)` | Ephemeral or session durable | Do not put every selection move into CRDT history by default. |
| `SetViewport(viewport)` | Ephemeral or user preference | Keep out of document CRDT unless collaborative viewport sharing is explicit. |
| `StartPreview` / `StopPreview` | Ephemeral | Audio runtime control, not document content. |

Each operation should have:

- A JSON shape with a version field for replay compatibility.
- A deterministic validation function.
- A lowering function to Canopy text/structure edits or to a graph-specific
  document mutation.
- A log entry that records operation type, target IDs, timestamp, author, and
  validation result.
- Tests that replay operation logs into the same graph state.

Do not send every pointermove as a CRDT operation. During a drag, keep
interaction state local and update the visual preview with RAF. Commit one
`MoveNodes` operation at the end, or at a coarse throttle only if remote live
dragging is required.

## Roundtrip integration design

The synchronized editing loop should be:

```text
Source text
  -> Loom/parser
  -> Canopy projection + SourceMap
  -> semantic graph + diagnostics
  -> normalized graph view model
  -> GraphAdapter patches

Graph gesture
  -> GraphOperation
  -> validation
  -> graph edit or SourceMap-backed SpanEdit
  -> SyncEditor
  -> updated source text
  -> parser/projection recomputation
  -> ViewPatch / GraphPatch back to UI
```

Use last-good state semantics for invalid intermediate text:

- The source pane may show parse errors immediately.
- The graph pane should either show the last valid graph with diagnostics, or
  show recoverable holes for invalid/missing nodes.
- MoonDsp preview should keep the last valid compiled template alive.

For the first prototype, source text should remain canonical. Graph operations
can lower to source edits through source maps. A later phase can decide whether
graph layout metadata belongs in source, a sidecar document, or CRDT metadata.

## Performance and measurement

Existing useful patterns:

- `examples/ideal/main/main.mbt` already measures refresh stages such as total
  refresh, projection, source map, tree editor refresh, scope map, and
  highlight set.
- `examples/canvas/web/src/main.ts` schedules rendering through
  `requestAnimationFrame`, stores DOM nodes in `Map<NodeId, HTMLElement>`, and
  stores edge paths in `Map<EdgeId, SVGPathElement>`.
- `examples/canvas/main/canvas_update.mbt` computes pan/drag from absolute
  start positions to avoid floating-point accumulation.
- `CM6Adapter` remaps unchanged decorations across document changes instead of
  rebuilding everything.
- `BlockInput` avoids re-rendering during IME composition.

The node graph prototype should record these timings:

| Metric | Target question |
| --- | --- |
| Gesture handling time | Are pointermove handlers staying below a frame budget? |
| Operation validation time | Can typed graph operations validate synchronously? |
| Source edit lowering time | Does source-map-backed graph editing stay cheap? |
| Parser/projection recomputation time | Which stage is invalidated by each operation? |
| Graph normalization/lowering time | Is whole-graph lowering enough, or is per-node `DerivedMap` needed? |
| Patch diff and DOM apply time | Are keyed node/edge updates avoiding full redraw? |
| MoonDsp analyze/compile time | Can topology changes stage before an audio block boundary? |

For audio preview, the UI target is not "compile in the audio callback." The
target is "compile or analyze on the control side, then atomically stage a
prepared runtime snapshot at a block boundary." Parameter-only changes should
prefer MoonDsp control bindings rather than graph recompilation.

## Reuse plan

Reuse directly:

- `examples/canvas` data model and interaction logic as the first graph UI
  substrate.
- `examples/ideal` shell concepts: mode tabs, outline, inspector, bottom
  panels, patch/op logs, performance taps, and CRDT bridge shape.
- `CM6Adapter` or `rabbita_codemirror` for the source pane.
- `ViewNode`, `ViewPatch`, diagnostics, decorations, and selection patches for
  tree/text surfaces.
- `Graphviz` for read-only graph/debug exports.
- `BlockInput`'s focused-edit preservation pattern for inline editable graph
  fields.

Build new:

- `GraphAdapter`: framework-specific node graph renderer with `applyPatches`,
  `onOperation`, `destroy`, and keyed DOM/SVG updates.
- Typed `GraphOperation` / `GraphIntent` values with JSON roundtrip tests.
- A normalized graph view model separate from MoonDsp `DspNode[]`.
- A lowering layer from graph operations to source edits and/or a typed graph
  document mutation.
- Source/graph roundtrip tests: text edit updates graph; graph operation
  updates text; reparsing returns equivalent graph.
- A small performance harness for graph operations and patch application.

## Current gaps

- `UserIntent::StructuralEdit` is too stringly typed for graph payloads.
  Either add a graph-domain operation channel or widen a later protocol layer
  after an explicit compatibility decision.
- `layout_to_view_tree` creates display-local IDs. It should not be used as
  the primary identity source for graph editing.
- `examples/ideal` Structure mode must be fixed or bypassed before it can host
  a graph pane reliably.
- There is no graph-specific patch type yet. `ViewPatch` can drive tree views,
  but node graph updates need positions, ports, edge routes, hover/selection
  state, and validation overlays.
- Source-map-backed graph edits need stable token roles for every editable DSL
  field.
- Graph layout metadata ownership is undecided: source text, CRDT sidecar,
  local preference, or generated layout.
- Collaboration policy for viewport, hover, selection, and live drag is not
  defined. Default should be local-only except selection/cursors.
- Audio preview needs a clear handoff boundary: graph topology compile on the
  control side, parameter changes through validated control bindings, block
  boundary commit into MoonDsp.

## Tracking issues

| Repository | Issue | Responsibility |
| --- | --- | --- |
| Canopy | [#428](https://github.com/dowdiness/canopy/issues/428) | Fix `examples/ideal` Structure mode before using it as the graph-editor host. |
| Canopy | [#429](https://github.com/dowdiness/canopy/issues/429) | Extract the canvas operation model and GraphAdapter prototype. |
| Canopy | [#430](https://github.com/dowdiness/canopy/issues/430) | Add source/graph roundtrip smoke tests for the audio graph UI. |
| incr | [#143](https://github.com/dowdiness/incr/issues/143) | Benchmark durable vs ephemeral graph-editor recomputation paths. |
| MoonDsp | [#121](https://github.com/dowdiness/moondsp/issues/121) | Define the editor-facing audio preview handoff for topology and control edits. |
| loom | [#205](https://github.com/dowdiness/loom/issues/205) | Add a source-map/token-role example for graph DSL operation lowering. |

## Recommended next work

1. Fix or isolate the `examples/ideal` Structure-mode ProseMirror content
   error so the integrated editor shell is trustworthy.
2. Extract the `examples/canvas` operation model into a reusable
   graph-operation package or module with JSON roundtrip tests.
3. Build a `GraphAdapter` prototype that accepts a normalized graph view model
   and emits typed `GraphOperation` values.
4. Define the first audio graph DSL's editable token roles and source-map edit
   rules, then implement graph operation -> source edit lowering for
   `AddNode`, `SetParam`, and `ConnectPorts`.
5. Add a roundtrip smoke test: source edit changes graph, graph edit changes
   source, and reparse returns the same normalized graph.
6. Add a small performance harness measuring graph operation validation,
   source edit lowering, parser/projection recomputation, graph diffing, and
   DOM patch application.
7. Decide where persistent graph layout metadata lives before collaboration
   work begins.
