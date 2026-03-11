# Rabbita Projection Editor Performance Issues

**Date:** 2026-03-11
**Status:** Initial investigation
**Scope:** `examples/rabbita` projectional editor responsiveness

## Executive Summary

The Rabbita projectional editor is slow because a single user action triggers multiple whole-document and whole-tree passes on the main UI thread.

The dominant costs are:

1. Text input replaces the full CRDT document on every keystroke.
2. Each edit reparses the entire source through the reactive parser path.
3. Each refresh rebuilds the full projectional tree UI state.
4. The view layer rerenders and diffs the full tree synchronously.

This is not one isolated hotspot. The lag is the compounded effect of several O(n) or worse operations stacked in one synchronous update cycle.

## Observed Update Path

For ordinary text typing in `examples/rabbita/main/main.mbt`, the current path is:

1. `textarea` emits `TextInput(new_text)`.
2. `model.editor.set_text(new_text)` replaces the full CRDT document.
3. `tree_state.refresh(editor.get_proj_node(), editor.get_source_map())` rebuilds projection-backed tree state.
4. Rabbita rerenders the full tree view and diffs it on the main thread.

Relevant call sites:

- `TextInput` handler: `examples/rabbita/main/main.mbt`
- `SyncEditor::set_text`: `editor/sync_editor.mbt`
- `TreeEditorState::refresh`: `projection/tree_editor.mbt`
- Rabbita runtime message drain: `examples/rabbita/.mooncakes/moonbit-community/rabbita/internal/runtime/sandbox.mbt`

## Prioritized Issues

### P1. Text input performs full-document replacement

`TextInput(new_text)` currently calls `editor.set_text(new_text)` in `examples/rabbita/main/main.mbt`.

`SyncEditor::set_text` in `editor/sync_editor.mbt` deletes the old document from the start position one character at a time and then inserts the entire replacement string. That means a one-character user edit is implemented as:

- `old_len` deletes
- one full-string insert

This is the worst possible edit path for interactive typing latency in a CRDT-backed editor.

**Impact**

- Keystroke cost scales with total document length, not edit size.
- The expensive text rewrite invalidates downstream parser and projection state.

**Evidence**

- `examples/rabbita/main/main.mbt#L112`
- `editor/sync_editor.mbt#L186`

### P1. Live typing uses the full-source reactive parser path

`SyncEditor` is constructed with `new_reactive_parser("", @parser.lambda_grammar)` in `editor/sync_editor.mbt`.

The reactive parser factory in `loom/loom/src/factories.mbt` rebuilds token state from the full source string, reparses the CST, and then reconstructs the term representation from that result. For live typing, this means each keystroke goes through:

- full retokenization
- full parse
- full AST / projection derivation

This discards the main benefit expected from incremental editing.

**Impact**

- Parsing cost scales with whole-document size.
- Small text edits pay the same structural recomputation tax as large edits.

**Evidence**

- `editor/sync_editor.mbt#L21`
- `loom/loom/src/factories.mbt#L182`

### P1. Tree refresh rebuilds the full interactive tree state

After every text change, Rabbita calls `tree_state.refresh(editor.get_proj_node(), editor.get_source_map())`.

`TreeEditorState::refresh` in `projection/tree_editor.mbt`:

- traverses the entire AST to collect valid node IDs
- prunes stale UI state
- recursively rebuilds the full `InteractiveTreeNode` tree

This means typing cost includes a complete UI-state regeneration pass over the whole projection tree.

**Impact**

- Refresh cost scales with tree size, not changed subtree size.
- Node-rich programs will feel disproportionately slow even for tiny edits.

**Evidence**

- `examples/rabbita/main/main.mbt#L115`
- `projection/tree_editor.mbt#L184`
- `projection/tree_editor.mbt#L64`

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

### P2. UI-only tree operations still trigger full refresh work

In `TreeEdited(op)`, Rabbita first updates local tree state with `tree_state.apply_edit(op)`, but then still calls `editor.apply_tree_edit(...)` and `refresh(model)` on every successful operation.

In `editor/tree_edit_bridge.mbt`, operations where the produced text is unchanged return early. That includes stateful UI actions such as selection and collapse/expand. Even so, the example still performs the expensive refresh path after success.

**Impact**

- Non-structural UI actions pay for parser + projection + tree refresh work they do not need.
- This makes the editor feel sluggish even when no source text changed.

**Evidence**

- `examples/rabbita/main/main.mbt#L121`
- `editor/tree_edit_bridge.mbt#L35`

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

### 1. Stop full-document replacement for typing

Replace `TextInput -> set_text(new_text)` with an edit-based path that applies only the actual inserted or deleted span.

This is the highest-value fix because it shrinks the work at the very front of the pipeline.

### 2. Use an actually incremental parse/update path for live text edits

Either:

- feed incremental edits into the parser layer, or
- use the imperative incremental parser path for interactive typing rather than reparsing from the entire source string

Without this change, text editing will continue to pay whole-source parser costs.

### 3. Skip projection refresh for UI-only tree actions

Do not call the expensive editor refresh path after `Select`, `Collapse`, `Expand`, and similar operations when text has not changed.

### 4. Decouple typing from full tree refresh

Text editing and projection-tree rebuilding do not need to happen at the same cadence. Typing should update immediately, while projection/tree recomputation should be deferred, debounced, or incrementally updated.

### 5. Reduce rerender scope

Prefer keyed or identity-aware tree rendering and avoid rebuilding unchanged subtrees where possible.

### 6. Remove redundant render-time traversals

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

- `docs/plans/2026-03-11-rabbita-perf-harness-redesign.md`

## Conclusion

The Rabbita projectional editor is currently structured around whole-document and whole-tree recomputation. That architecture explains both the poor responsiveness and the awkward editing feel. The first meaningful improvement will come from changing the text input path to incremental edits and preventing unnecessary full refreshes for UI-only actions.

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
