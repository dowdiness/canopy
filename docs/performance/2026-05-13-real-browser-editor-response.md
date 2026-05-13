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

## Next Measurement Work

Add phase timings around the real browser benchmark before optimizing:

- `handle_text_intent` duration in `canopy-editor.ts`.
- Time from `text-changed` dispatch to Rabbita `EditorTextChanged`.
- `refresh(model)` total time.
- Sub-timings inside `refresh(model)`:
  - `get_proj_node`
  - `get_source_map`
  - `TreeEditorState::refresh`
  - `build_scope_map`
  - `compute_highlight_set`
  - `bottom_render_cmd`

Then add release MoonBit benchmarks for:

- `ideal refresh(100 defs)` and `ideal refresh(500 defs)`.
- `build_scope_map(100 defs)` and `build_scope_map(500 defs)`.
- `TreeEditorState::refresh` with real lambda projection trees.

## Optimization Candidates

Do not start by optimizing event-graph-walker. Current browser results point at
over-refreshing projection/UI state per keystroke.

Likely useful changes:

1. Skip or defer `scope_map` rebuilding unless outline/scope UI needs it.
2. Batch projection refresh to animation frames so text updates immediately and
   outline/projection work runs at most once per frame.
3. Avoid bottom-panel render work when panels are closed, and update only the
   active tab when open.
4. Move the ideal editor toward incremental view patches instead of broad model
   refreshes for every text edit.
