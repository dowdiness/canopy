# Project TODO

Improvement proposals for the eg-walker CRDT Lambda Calculus Editor.

## Priority Legend

- **Impact:** High / Medium / Low
- **Effort:** High / Medium / Low
- **Status:** Not Started / In Progress / Done

---

## 1. CI/CD & Automation

**Impact:** High | **Effort:** Low-Medium | **Status:** ✅ Done

- [x] Add GitHub Actions workflow to run `moon test` for both modules on push/PR
- [x] Add `moon check` and `moon fmt --check` to CI pipeline
- [x] Add benchmark regression detection (store baselines, compare on PR)
- [x] Automate JS build verification (`moon build --target js`)
- [x] Add deployment workflow for GitHub Pages
- [x] Add release automation workflow
- [x] Add Dependabot configuration for dependency updates
- [x] Add Makefile for common development tasks
- [x] Add helper scripts (build-web.sh, test-all.sh, check-all.sh)
- [x] Add pre-commit hook installation script

---

## 2. Collaboration Features

**Impact:** High | **Effort:** High

- [ ] Complete WebSocket client integration (sync protocol designed, TypeScript API stub exists)
- [x] Fix P2-1: Remote sync pollutes undo history — `UndoManager.set_tracking()` implemented; valtio TS layer suppresses tracking during remote op application (see `event-graph-walker/docs/UNDO_MANAGER_DESIGN.md`)
- [x] Fix P2-2: Position-based undo replays stale positions after concurrent edits — replaced with LV-based UndoManager; tombstone revival restores characters at exact CRDT position regardless of concurrent edits (Phase 1+2 complete, see `event-graph-walker/docs/UNDO_MANAGER_DESIGN.md`)
- [x] Wire `apply_sync` to suppress undo tracking — `SyncEditor::apply_sync` now disables tracking before applying remote ops
- [x] Sync undo/redo ops to peers — `SyncEditor::undo_and_export()`/`redo_and_export()` capture inverse ops via `export_since()` for peer broadcast; JS bindings `undo_and_export_json`/`redo_and_export_json` added
- [ ] Add remote cursor/selection tracking

---

## 3. Incremental Parsing Optimization

**Impact:** Medium | **Effort:** Medium

- [ ] Implement selective cache invalidation by range instead of full reparse fallback (loom incremental engine)
- [x] Implement LCS matching for AST child reconciliation instead of positional matching (`projection/text_lens.mbt:219`)

---

## 4. Rabbita Projection Editor Performance

**Impact:** High | **Effort:** High

Tracked by:

- `docs/performance/RABBITA_PROJECTION_EDITOR_ISSUES.md`
- `docs/archive/2026-03-11-rabbita-projection-editor-performance-plan.md` (Complete)

- [x] Add baseline timing instrumentation for text edit application, parser update, projection refresh, `TreeEditorState::refresh`, and Rabbita render/update — ✅ Done. `BenchmarkSession::deferred_full_cycle_timed()` provides per-phase breakdown (text_input_ms, get_proj_node_ms, get_source_map_ms, tree_refresh_ms) in `examples/rabbita/main/benchmark_support.mbt`
- [x] Add an edit-based `SyncEditor` text API for typing (`apply_text_edit(...)`) and stop using whole-string replacement from Rabbita `TextInput` — ✅ Done. `SyncEditor::apply_text_edit()` in `editor/sync_editor_text.mbt`; Rabbita `TextInput` handler uses `compute_text_change` + `apply_text_edit` instead of `set_text`
- [x] Feed incremental text edits into the parser layer instead of rebuilding from the entire source string on every keystroke — ✅ Done. `SyncEditor` uses `ImperativeParser` with `parser.edit(edit, new_source)` in `editor/sync_editor_parser.mbt`, not `set_source()` full reparse
- [x] Split UI-only tree actions (`Select`, `Collapse`, `Expand`) from structural tree edits so they do not trigger parser/projection refresh — ✅ Done. `is_ui_only_tree_edit(op)` guard in Rabbita update loop returns early with only `tree_state.apply_edit(op)`, skipping `apply_tree_edit` and `refresh`
- [x] Introduce an explicit projection refresh boundary so text edits and structural tree refresh can be coalesced — ✅ Done. `TextInput` sets `projection_dirty: true` and schedules `RefreshProjection` via `delay(dispatch(RefreshProjection), deferred_refresh_ms)`, coalescing rapid keystrokes
- [x] Reduce `TreeEditorState::refresh` rebuild scope to changed subtrees where possible — ✅ Done (PR #42). Lazy structural indexes + Phase 2 subtree skip. 3-4x speedup for unchanged projections, 2-2.6x for single-def changes. See `docs/performance/2026-03-20-lazy-tree-refresh-benchmarks.md`
- [ ] Reduce Rabbita tree rerender/diff work for insert/reorder-heavy trees with keyed or identity-aware child rendering
- [ ] Remove redundant render-time tree scans such as sidebar selection lookup from the full rendered tree

---

## 5. Memory & Scalability

**Impact:** Medium | **Effort:** High

- [ ] Apply RLE memory optimization across full pipeline (estimated 50-80% reduction, Phase 2 TextSpan done)
- [ ] Implement lazy loading for 100k+ operation documents (load causal graph skeleton, hydrate on demand)
- [ ] Add B-tree indexing for FugueTree (O(n) → O(log n) random-access character lookup)

---

## 6. Testing Gaps

**Impact:** Medium | **Effort:** Low-Medium

- [x] Add CRDT convergence fuzz testing — multi-agent (2-5) property tests with random insert/delete/undo/redo/partial-sync, verifying all replicas converge after full sync
- [x] Add sync-order-independence property test — verifies convergence regardless of sync direction
- [x] Add undo-under-concurrency property test — agent undoes while another edits concurrently
- [x] Fix Delete/Undelete convergence bug found by fuzz testing — LWW conflict resolution with Lamport timestamps and add-wins semantics (`event-graph-walker/internal/fugue/tree.mbt`)
- [ ] Add parser fuzz testing — random byte streams, verify no panics/aborts
- [ ] Add E2E browser tests with Playwright (already a devDependency, no automated tests yet)
- [ ] Add error path tests — malformed sync messages, corrupted operation logs, network interruptions

---

## 7. Tree Edit Bridge Tech Debt

**Impact:** Medium | **Effort:** Medium-High

Known concerns from the `editor/tree_edit_bridge.mbt` roundtrip implementation (text CRDT approach per §5).

### Dual-state architecture (SyncEditor + CanonicalModel)

- [x] **Encapsulate CanonicalModel inside SyncEditor** — ✅ Done. `CanonicalModel` fully retired. `SyncEditor::apply_tree_edit` computes span-level text edits via FlatProj. ProjNode reconciliation, node registry, and source map are all memo-derived on SyncEditor.
- [x] **Double parse per tree edit** — ✅ Done. Single parse pipeline via SyncEditor memo chain (FlatProj → cached ProjNode → registry/source map).

### Diff logic triplication

- [x] **Consolidate prefix/suffix diff** — Already resolved: `projection/text_lens.mbt` was removed (only `text_lens_regression_wbtest.mbt` remains for regression tests). Both `set_text_and_record` and `compute_edit` now delegate to the shared `@text_change.compute_text_change()` in `lib/text-change/`. The remaining `compute_text_edits` in `editor/text_diff.mbt` is a separate LCS-based multi-edit diff for batch remote merges — not a duplicate.

### TextInput path efficiency

- [x] **`set_text` is brute-force O(n)** — ✅ No longer used for typing. `TextInput` uses `apply_text_edit(start, delete_len, inserted)` which applies only the changed span. `set_text` still exists as a fallback but is not on the hot path.

### CRDT API limitations

- [x] **Char-by-char delete for range deletions** — ✅ Done. `TextDoc` now exposes `replace_range` in `event-graph-walker/text/text_doc.mbt`.
- [x] **No undo tracking for tree edits** — ✅ Done. `apply_tree_edit` now uses `apply_text_edit_internal` with `record_undo=true`. Tree edits are undoable via `SyncEditor.undo()`.

### Resolved: CRDT position ordering bug

- [x] **`apply_projection_edits` used insert-first ordering** — `text_lens_diff` produces edits with insert-before-delete and adjusted positions. FugueMax's position semantics require delete-first ordering; insert-first caused position drift producing corrupted text. **Fixed:** replaced with `set_text(new_text)` which uses proven delete-all + insert approach.

---

## 8. Code Cleanup

**Impact:** Low | **Effort:** Low

- [ ] Convert `abort()` calls in test files to proper assertions (`assert_true` / `inspect`) for better error messages

---

## 9. Developer Experience

**Impact:** Low-Medium | **Effort:** Low | **Status:** ✅ Done

- [x] Add top-level `Makefile` or `justfile` wrapping both-module test commands into a single invocation
- [x] Add pre-commit hook running `moon check && moon fmt --check`
- [x] Script the web build workflow (`moon build --target js && cp _build/js/release/build/crdt.js examples/web/public/`)

---

## Priority Ranking

| # | Proposal | Effort | Impact |
|---|----------|--------|--------|
| 1 | CI test automation | Low | High |
| 2 | ~~Fix undo/redo (P2-1, P2-2)~~ ✅ Done | ~~Medium~~ | ~~High~~ |
| 2a | ~~Wire apply_sync tracking suppression + sync undo ops to peers~~ ✅ Done | ~~Low-Medium~~ | ~~High~~ |
| 3 | Complete WebSocket collaboration | High | High |
| 4 | E2E browser tests | Low | Medium |
| 5 | Benchmark regression CI | Medium | Medium |
| 6 | Rabbita projection editor performance | High | High |
| 7 | Tree edit bridge tech debt | Medium-High | Medium |
| 8 | Incremental parsing TODOs | Medium | Medium |
| 9 | Single-command test runner | Low | Low-Med |
| 10 | Code cleanup | Low | Low |
| 11 | Memory optimization | High | Medium |
| 12 | ~~CRDT convergence fuzz testing~~ ✅ Done (+ bug found & fixed) | ~~Medium~~ | ~~Medium~~ |
| 12a | Parser fuzz testing | Low | Medium |
