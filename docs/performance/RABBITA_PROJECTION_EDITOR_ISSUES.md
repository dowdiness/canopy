# Rabbita Projection Editor Performance Issues

**Date:** 2026-03-11
**Status:** Partially resolved (updated 2026-03-20)
**Scope:** `examples/rabbita` projectional editor responsiveness

## Executive Summary

The Rabbita projectional editor is slow because a single user action triggers multiple whole-document and whole-tree passes on the main UI thread.

The dominant costs were (items 1-2 now fixed, 3-4 remain):

1. ~~Text input replaces the full CRDT document on every keystroke.~~ ✅ Fixed: `apply_text_edit()` with splice
2. ~~Each edit reparses the entire source through the reactive parser path.~~ ✅ Fixed: `ImperativeParser.edit()` incremental path
3. Each refresh rebuilds the full projectional tree UI state. **Still open** — stamp-based reuse exists but structural indexes are rebuilt from scratch
4. The view layer rerenders and diffs the full tree synchronously.

Items 1-2 addressed the front of the pipeline. The remaining bottleneck is tree refresh (item 3) — `TreeEditorState::refresh` walks the entire tree to rebuild `preorder_ids`, `parent_by_child`, and `preorder_range_by_root` even for unchanged subtrees.

## Observed Update Path

For ordinary text typing in `examples/rabbita/main/main.mbt`, the current path is:

1. `textarea` emits `TextInput(new_text)`.
2. ~~`model.editor.set_text(new_text)` replaces the full CRDT document.~~ → Now: `compute_text_change` + `apply_text_edit(start, delete_len, inserted)` applies only the changed span.
3. Projection refresh is **deferred** via `delay(dispatch(RefreshProjection), deferred_refresh_ms)`, coalescing rapid keystrokes.
4. On `RefreshProjection`: `tree_state.refresh(editor.get_proj_node(), editor.get_source_map())` rebuilds projection-backed tree state.
5. Rabbita rerenders the full tree view and diffs it on the main thread.

Relevant call sites:

- `TextInput` handler: `examples/rabbita/main/main.mbt`
- `SyncEditor::apply_text_edit`: `editor/sync_editor_text.mbt`
- `SyncEditor::apply_local_text_change` → `parser.edit()`: `editor/sync_editor_parser.mbt`
- `TreeEditorState::refresh`: `projection/tree_editor.mbt`

## Prioritized Issues

### ~~P1. Text input performs full-document replacement~~ ✅ FIXED

`TextInput(new_text)` now uses `compute_text_change` + `SyncEditor::apply_text_edit(start, delete_len, inserted)` to apply only the changed span. The old `set_text()` brute-force path is no longer used for typing.

**Fix:** `examples/rabbita/main/main.mbt` L186-191, `editor/sync_editor_text.mbt`

### ~~P1. Live typing uses the full-source reactive parser path~~ ✅ FIXED

`SyncEditor` now uses `ImperativeParser` and calls `parser.edit(edit, new_source)` — the incremental edit path — not `set_source()` full reparse. The edit shape is passed through from `apply_text_edit` via `apply_local_text_change` → `sync_parser_after_text_change`.

**Fix:** `editor/sync_editor_parser.mbt` L34

### ~~P1. Tree refresh rebuilds the full interactive tree state~~ ✅ FIXED

`TreeEditorState::refresh` now uses lazy structural indexes and Phase 2 subtree skip. Unchanged subtrees are reused entirely — no stamp construction, no InteractiveTreeNode allocation, no UI state lookups. Structural indexes (preorder, parent map) are computed on-demand only when tree operations need them, never during typing.

**Benchmark results (PR #42):**

| Tree size | Before | After | Speedup |
|-----------|--------|-------|---------|
| 80 defs (unchanged) | 62 µs | 18 µs | **3.5x** |
| 320 defs (unchanged) | 287 µs | 72 µs | **4.0x** |
| 1000 defs (unchanged) | 1.18 ms | 279 µs | **4.2x** |
| 1000 defs (1 changed) | 1.24 ms | 469 µs | **2.6x** |

**Fix:** `projection/tree_editor.mbt` — `refresh_node_minimal`, `can_skip_subtree`, lazy `build_preorder_from_tree`/`build_parent_map_from_tree`

### P2. All expensive work runs synchronously on the UI thread

Rabbita’s TEA runtime processes messages, updates model state, computes the next view, diffs the VDOM, and flushes DOM work on the main thread.

There is no debounce, scheduling boundary, worker offload, or deferred projection rebuild in the Rabbita example.

**Impact**

- Expensive parse and tree rebuild work directly becomes input lag.
- The editor cannot remain responsive under moderate tree sizes because there is no yielding between typing and recomputation.

**Evidence**

- `examples/rabbita/.mooncakes/moonbit-community/rabbita/tea.mbt#L273`
- `examples/rabbita/.mooncakes/moonbit-community/rabbita/internal/runtime/sandbox.mbt#L80`

### P2. Tree rendering is fully recursive and diffed positionally

The example reconstructs the view for every tree node on each refresh in `view_tree_node`.

Rabbita’s array child diff matches children positionally rather than by stable keys. Inserts or reorders near the start of a sibling list therefore force more diff work across the rest of that list.

**Impact**

- Reorders and inserts are more expensive than necessary.
- Large homogeneous child lists amplify rerender cost.

**Evidence**

- `examples/rabbita/main/main.mbt#L152`
- `examples/rabbita/.mooncakes/moonbit-community/rabbita/internal/runtime/vdom.mbt#L513`

### ~~P2. UI-only tree operations still trigger full refresh work~~ ✅ FIXED

The Rabbita update loop now checks `is_ui_only_tree_edit(op)` and returns early with only `tree_state.apply_edit(op)`, skipping `apply_tree_edit` and `refresh`. `Expand` is also handled separately with `expand_node` for hydration.

**Fix:** `examples/rabbita/main/main.mbt` L216-235

### P2. Structural tree edits do multiple full-tree passes

Projectional edits are not local tree mutations. `apply_tree_edit`:

1. computes a new `ProjNode`
2. unparses the entire term back to text
3. writes that text through the editor
4. reparses and reconciles memo state

Some operations also parse fresh snippets during the tree-edit step itself, such as wrap or commit-edit helpers in `projection/tree_lens.mbt`.

**Impact**

- Tree edits are more expensive than they appear from the UI.
- Operations such as wrapping, inserting, or committing a new value pay repeated conversion costs.

**Evidence**

- `editor/tree_edit_bridge.mbt#L11`
- `projection/tree_lens.mbt#L55`
- `projection/tree_lens.mbt#L89`

### P3. Sidebar selection lookup adds another full tree walk

The selection sidebar uses `find_selected` to recursively rescan the rendered tree even though selection is already tracked separately in editor state.

This is not the main bottleneck, but it adds more O(n) work to every render.

**Impact**

- Extra render-time tree walk for information the model already knows.

**Evidence**

- `examples/rabbita/main/main.mbt#L60`
- `examples/rabbita/main/main.mbt#L245`

## Why The Editor Feels Bad

The experience is poor because the current update path compounds several heavyweight operations:

1. full-document CRDT rewrite
2. full-source parse
3. full projection derivation
4. full interactive tree rebuild
5. full recursive view regeneration
6. synchronous diff and DOM update

That stack happens in one input cycle. Even if each individual step is merely linear, the combined latency becomes visible very quickly.

## Recommended Fix Order

### ~~1. Stop full-document replacement for typing~~ ✅ DONE

`TextInput` now uses `compute_text_change` + `apply_text_edit` to apply only the changed span.

### ~~2. Use an actually incremental parse/update path for live text edits~~ ✅ DONE

`SyncEditor` uses `ImperativeParser` with `parser.edit(edit, new_source)`.

### ~~3. Skip projection refresh for UI-only tree actions~~ ✅ DONE

`is_ui_only_tree_edit(op)` guard returns early without parser/projection work.

### ~~4. Decouple typing from full tree refresh~~ ✅ DONE

`TextInput` defers projection refresh via `delay(dispatch(RefreshProjection), deferred_refresh_ms)`.

### ~~5. Reduce tree refresh scope~~ ✅ DONE

Lazy structural indexes + Phase 2 subtree skip (PR #42). `TreeEditorState::refresh` now skips unchanged subtrees entirely and defers index construction to when tree operations need them. 3-4x speedup for unchanged projections, 2-2.6x for single-def changes. See `docs/performance/2026-03-20-lazy-tree-refresh-benchmarks.md`.

### 6. Reduce Rabbita VDOM rerender scope — REMAINING

Prefer keyed or identity-aware tree rendering in Rabbita view layer. The tree refresh is now fast, but the VDOM diff still walks the full rendered tree.

### 6. Remove redundant render-time traversals — REMAINING

Sidebar selection details should come from the already-tracked selected node state, not from a new full tree scan.

## Suggested Follow-Up Measurements

This investigation was based on static code analysis rather than browser profiling. The next useful measurements are:

1. keystroke-to-paint latency for text input on small, medium, and large trees
2. time breakdown for `set_text`, parser rebuild, `TreeEditorState::refresh`, and view diff
3. cost difference between text edits and UI-only tree actions
4. subtree size sensitivity for node insertion and sibling reorder operations

## Current Benchmark Status

The current `examples/rabbita/perf_report` harness is now easier to drive than the original version:

- `moon run perf_report medium`
- `moon run perf_report large`
- `moon run perf_report large 1`

However, current branch measurements still show that the harness is not yet a reliable large-tree reporter.

Latest bounded runs on this branch:

- `timeout 60s moon run perf_report medium 1`
  - emitted one completed line before timing out:
    - `medium legacy set_text + refresh: ~336 ms/edit`
  - did not complete the remaining medium cases within `60s`
- `timeout 60s moon run perf_report large 1`
  - emitted no completed report lines before timing out

Practical interpretation:

- medium performance is still in the hundreds of milliseconds per edit on the eager legacy path
- large-tree behavior remains effectively non-interactive
- the benchmark harness still needs timeout-aware per-case reporting and phase breakdowns before it can serve as the primary diagnostic tool for large-tree stalls
- the subtree reuse / elision / hydration work should therefore be read as an incremental win in architecture and medium-path behavior, not as a worst-case large-tree fix
- the most likely remaining bottleneck is still the structural pipeline:
  - projection rebuild / reconcile
  - source map rebuild
  - `TreeEditorState::refresh(...)`
  - deferred full-cycle reducer work around those steps

That harness redesign is tracked separately in:

- `docs/archive/2026-03-11-rabbita-perf-harness-redesign.md` (Complete)

## Conclusion

All identified pipeline bottlenecks have been addressed:
- ~~Full-doc CRDT replacement~~ → `apply_text_edit` with splice
- ~~Full-source reparse~~ → `ImperativeParser.edit()` incremental path
- ~~UI-only refresh bypass~~ → `is_ui_only_tree_edit` guard
- ~~Deferred projection refresh~~ → `delay(dispatch(RefreshProjection), ms)`
- ~~Tree refresh full rebuild~~ → lazy indexes + subtree skip (3-4x speedup)

The remaining optimization target is Rabbita's VDOM diff scope for large trees — the tree refresh is now fast, but the view layer still walks the full rendered tree on every projection update.

## Roadmap To Stable 60fps

If the eventual goal is stable `60fps` UI response, the next work should be ordered around frame-budget control rather than more isolated tree-editor tweaks.

**Caveat:** This roadmap is meant to complement the linked recovery plan, not supersede it. If the implementation phases change, this section should be revised so the investigation note and the execution plan do not drift apart.

### Practical Priority Order

1. Instrument the full deferred path end to end.
   Add coarse timings for:
   - text edit application
   - parser / syntax update
   - `ProjNode` rebuild / reconcile
   - `SourceMap::from_ast(...)`
   - `TreeEditorState::refresh(...)`
   - Rabbita update / render work

   Until this breakdown exists, optimization decisions remain speculative.

2. Identify the single worst large-tree hotspot and fix that first.
   The large-tree harness still behaves as effectively non-interactive, so the next step is to find which slice dominates that path instead of assuming the remaining bottleneck is still tree-node allocation.

3. Incrementalize projection metadata rebuilds.
   Stable `60fps` is unlikely if every meaningful edit still rebuilds:
   - preorder indexes
   - parent links
   - source maps
   - full projection snapshots

   After the subtree reuse/elision work, this is the most likely remaining scaling wall.

4. Keep UI-only actions strictly local and synchronous.
   `Select`, `Collapse`, `Expand`, drag hover, and sidebar updates should stay inside the visible-tree budget and avoid triggering parser or whole-projection work.

5. Push structural refresh off the immediate interaction budget when needed.
   If a structural refresh cannot reliably fit inside one frame, preserve immediate local UI response and treat projection refresh as deferred/coalesced work with explicit stale-view rules.

6. Optimize render scope only after compute costs are understood.
   Once the compute pipeline is measured and bounded, then revisit Rabbita diff/render costs such as large array-child diffs and subtree rerender scope.

7. Track frame-budget metrics instead of averages alone.
   Throughput benchmarks are useful, but `60fps` work should be judged by thresholds such as:
   - p50 / p95 / p99 for UI-only actions
   - p50 / p95 for deferred structural refresh
   - explicit `< 16ms` and `< 50ms` budgets by scenario size

### What This Means For The Current Branch

The subtree reuse, collapsed-descendant elision, and targeted expand hydration work is a meaningful incremental win, especially for medium deferred interactions, but it is not yet the final answer for worst-case slowness. The current evidence still points toward full-tree projection metadata work as the next major focus area.
