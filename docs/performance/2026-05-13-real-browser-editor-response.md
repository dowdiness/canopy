# Real Browser Editor Response Baseline

**Date:** 2026-05-13
**Command:** `make benchmark-ideal-editor-response`
**Benchmark:** `examples/ideal/web/e2e/editor-response.perf.spec.ts`

This note records the first browser-level editor response benchmark for the
ideal editor. Unlike MoonBit microbenchmarks, this runs Chromium against the
real `examples/ideal/web` app and measures the local text-mode input path:

1. CodeMirror receives text input.
2. `canopy-editor.ts` applies the edit through `handle_text_intent`.
3. The Web Component dispatches `text-changed`.
4. Rabbita handles `EditorTextChanged`.
5. The ideal model refreshes projection/outline state.
6. The benchmark waits two animation frames to include browser paint scheduling.

The perf run disables WebSocket sync startup with `VITE_CANOPY_SKIP_SYNC=1`.
This keeps the measurement focused on local editor/projection response rather
than offline collaboration reconnect work.

## Results

| Scenario | Source size | Samples | Text-change p50 | Text-change p95 | Paint p50 | Paint p95 | Paint max |
|---|---:|---:|---:|---:|---:|---:|---:|
| medium text edit | 1,283 chars | 30 | 5.9 ms | 9.5 ms | 30.6 ms | 31.4 ms | 38.6 ms |
| large text edit | 7,284 chars | 30 | 20.2 ms | 21.3 ms | 37.2 ms | 39.0 ms | 67.8 ms |

## Interpretation

The editor is interactive, but the large case is not yet comfortably under a
single-frame compute budget. For a "really smooth" typing experience, target:

| Metric | Current large case | Good | Smooth target | Stretch |
|---|---:|---:|---:|---:|
| Text-change p95 | 21.3 ms | <16 ms | <8-10 ms | <4 ms |
| Paint p95 | 39.0 ms | <50 ms | <32 ms | <16-20 ms |
| Paint max | 67.8 ms | <100 ms | <50 ms | <32 ms |

This implies roughly a 2x improvement in the editor/projection update path,
not another large CRDT-engine win. The event-graph-walker regression that
triggered this discussion is fixed; the remaining smoothness work is likely in
Canopy's projection/editor refresh path.

## Suspected Hot Path

The text edit path currently runs:

- `examples/ideal/web/src/canopy-editor.ts`
  - CM6 update listener calls `handle_text_intent`.
  - Dispatches `text-changed`.
- `examples/ideal/web/src/main.ts`
  - `text-changed` clicks the hidden Rabbita trigger.
- `examples/ideal/main/main.mbt`
  - `EditorTextChanged` calls `refresh(model)`.
  - `refresh(model)` reads `get_proj_node()` and `get_source_map()`, refreshes
    `TreeEditorState`, rebuilds `scope_map`, and recomputes highlights.

The most plausible costs to measure first are:

1. `TreeEditorState::refresh` on real lambda projection trees.
2. `build_scope_map(editor)`, which currently walks the whole projected tree
   and backfills usages on every refresh.
3. `get_proj_node()` / `get_source_map()` memo forcing after single-character
   edits.
4. `bottom_render_cmd(new_model)`, especially when bottom panels are hidden or
   inactive.

## Phase Timing Results

Follow-up browser benchmark on 2026-05-14 split the large text edit result into
measured phases. The command was still `make benchmark-ideal-editor-response`.

| Large edit phase | p50 | p95 | max | Notes |
|---|---:|---:|---:|---|
| `handleTextIntent` | 12.6 ms | 14.7 ms | 14.8 ms | Dominant cost; wraps the Web Component text edit path through `handle_text_intent`. |
| `dispatchTextChanged` | 1.2 ms | 1.8 ms | 3.0 ms | Includes listener dispatch after the editor state update. |
| `textChangedToRabbitaTrigger` | 1.1 ms | 1.7 ms | 2.9 ms | Browser event bridge from `text-changed` to the Rabbita trigger. |
| `editorTextChangedTotal` | 1.0 ms | 1.6 ms | 2.9 ms | Rabbita `EditorTextChanged` handler. |
| `refreshTotal` | 1.0 ms | 1.6 ms | 2.9 ms | Full ideal model refresh. |
| `getProjNode` | 0.4 ms | 0.6 ms | 0.7 ms | Projection memo forcing after the edit. |
| `getSourceMap` | 0.3 ms | 0.4 ms | 2.1 ms | Usually small, with one local max spike. |
| `treeEditorRefresh` | 0.3 ms | 0.4 ms | 0.4 ms | Tree editor state refresh. |
| `buildScopeMap` | 0.1 ms | 0.2 ms | 0.3 ms | Not the current bottleneck. |
| `bottomRenderCmd` | 0.0 ms | 0.1 ms | 0.1 ms | Not material in this benchmark. |

This changes the optimization priority. The measured browser path is dominated
by `handle_text_intent`, while the Rabbita projection refresh work is around
1-2 ms at the current large-document scale. The scope-map and tree-refresh
hypotheses were useful to test, but they are not where this benchmark spends
most of its time.

## Next Measurement Work

Add deeper phase timings or focused release benchmarks for the
`handle_text_intent` path before changing projection refresh:

- Split `handle_text_intent` into CodeMirror update handling, edit translation,
  CRDT/sync-editor mutation, and post-edit state publication.
- Add a focused browser benchmark that records per-keystroke p95 for repeated
  edits in the same large document, not just isolated sampled edits.
- Keep the existing projection phase timers as regression guards, because they
  prove refresh/scope work is not currently the dominant browser-level cost.

Then add release MoonBit benchmarks for:

- `ideal refresh(100 defs)` and `ideal refresh(500 defs)`.
- `build_scope_map(100 defs)` and `build_scope_map(500 defs)`.
- `TreeEditorState::refresh` with real lambda projection trees.

## Optimization Candidates

Do not start by optimizing event-graph-walker or the projection refresh path.
Current browser phase timings point first at the text-intent/edit-application
path.

Likely useful changes:

1. Split and optimize `handle_text_intent`, especially edit translation and
   sync-editor mutation after a single-character CodeMirror input.
2. Check whether the Web Component publishes or normalizes more editor state
   than the browser needs synchronously for each keystroke.
3. Keep scope-map, tree-refresh, and bottom-panel work measured, but treat them
   as secondary until the text-intent p95 is below the smooth target.
4. If projection work grows with larger examples, batch projection refresh to
   animation frames so text updates immediately and outline/projection work runs
   at most once per frame.
