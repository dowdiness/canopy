# Project TODO

Improvement proposals for the eg-walker CRDT Lambda Calculus Editor.

## Priority Legend

- **Impact:** High / Medium / Low
- **Effort:** High / Medium / Low
- **Status:** Not Started / In Progress / Done

---

## 1. CI/CD & Automation

**Impact:** High | **Effort:** Low-Medium | **Status:** Done

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

### 2026-03-21 audit follow-up

- [x] Repair release workflow path drift after repo/layout rename (`parser/` → `loom/`, `web/` → `examples/web/`, `_build/.../canopy.js`, no root `moon.pkg.json`)
- [x] Replace obsolete local copy-based web helpers (`crdt.js` → `examples/web/public/`) with the Vite plugin + `_build/js/release/build/canopy.js` flow
- [x] Make the supported target matrix explicit in release/docs: native + JS supported, wasm not supported yet
- [ ] If wasm support is added later, add a dedicated wasm implementation and CI job; current supported targets are native and JS only
- [x] Unify TypeScript path aliases and generated artifact names across `examples/web` and `examples/demo-react` (`canopy.{js,d.ts}` under `_build`)
- [x] Make release/deploy jobs call shared scripts or `make` targets instead of hard-coding duplicate module paths and artifact locations
- [x] Point Loom CI/local helpers at the actual module root (`loom/loom`) and make the shared module runner reject non-module paths
- [x] Keep benchmark base-branch comparison self-contained after the second checkout instead of assuming helper scripts exist on the base ref
- [x] Fix local `fmt-check` to use `moon fmt --check` instead of mutating the worktree and diffing git state

---

## 2. Collaboration Features

**Impact:** High | **Effort:** High

- [ ] Complete WebSocket client integration (sync protocol designed, TypeScript API stub exists)
- [ ] Implement `SyncRequest`/`SyncResponse` recovery so malformed/incompatible `CrdtOps` does not leave peers diverged silently
- [ ] Reject duplicate/invalid relay peer IDs in `RelayRoom` instead of trusting caller uniqueness
- [x] Fix P2-1: Remote sync pollutes undo history — `UndoManager.set_tracking()` implemented; valtio TS layer suppresses tracking during remote op application (see `event-graph-walker/docs/UNDO_MANAGER_DESIGN.md`)
- [x] Fix P2-2: Position-based undo replays stale positions after concurrent edits — replaced with LV-based UndoManager; tombstone revival restores characters at exact CRDT position regardless of concurrent edits (Phase 1+2 complete, see `event-graph-walker/docs/UNDO_MANAGER_DESIGN.md`)
- [x] Wire `apply_sync` to suppress undo tracking — `SyncEditor::apply_sync` now disables tracking before applying remote ops
- [x] Sync undo/redo ops to peers — `SyncEditor::undo_and_export()`/`redo_and_export()` capture inverse ops via `export_since()` for peer broadcast; JS bindings `undo_and_export_json`/`redo_and_export_json` added
- [x] Add remote cursor/selection tracking — CM6 peer cursor decorations with colored carets, name labels, selection highlights via EphemeralHub
- [x] Cursor-preserving remote sync — replaced full-document replacement with minimal prefix/suffix diff in `syncCmFromCrdt()`
- [x] Show sync connection status in PEERS panel — `SyncStatus` enum (Offline/Connecting/Connected/Error) with colored dot indicator

---

## 3. Incremental Parsing Optimization

**Impact:** Medium | **Effort:** Medium

- [x] Implement selective cache invalidation by range instead of full reparse fallback (loom incremental engine) — ✅ Done. Size-threshold skip (Phase 1), balanced RepeatGroups (Phase 2), block reparse (Phase 3) all implemented. Phase 0 (SyntaxNode boundary enforcement in test/benchmark code) remains as cleanup
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
- [x] Reduce Rabbita tree rerender/diff work for insert/reorder-heavy trees — ✅ Confirmed non-issue via browser profiling: avg 0.54ms, P95 1.00ms per frame. Well under 16ms 60fps budget. Keyed children available via `Map[String, Html]` if needed for larger trees.
- [ ] Remove redundant render-time tree scans such as sidebar selection lookup from the full rendered tree — low priority, full frame is <1ms

---

## 5. Memory & Scalability

**Impact:** Medium | **Effort:** High

- [x] Apply RLE memory optimization across CRDT pipeline — ✅ Done. Phases 0-3 merged: OpLog compressed to `Rle[OpRun]`, Document position cache to `Rle[VisibleRun]`, walker output to `Rle[LvRange]`, sync wire format compressed. See `event-graph-walker/docs/benchmarks/2026-03-18-rle-all-phases-complete.md`
- [x] **Fix FugueTree stack overflow at ~500 nodes** — ✅ Done. Converted `traverse_tree` from recursive to iterative (explicit stack, 3-phase state machine). 500 defs: 12.84ms (60fps). 1000 defs: 36.83ms (30fps). (`event-graph-walker/internal/fugue/tree.mbt`)
- [x] **Profile CRDT at 500+ def scale** — ✅ Done (two rounds of profiling). Key findings:
  - **`traverse_tree` is NOT the bottleneck** — isolated benchmark: 0.19ms at 1000 nodes. Most nodes have 0-1 children, so sorting is effectively free.
  - **Incremental position cache update is NOT viable** — FugueMax CRDT resolves inserts to positions determined by tree structure (parent/side/timestamp), not the caller's requested position. Attempted Rle::insert at caller position but CRDT ordering semantics made it incorrect (test failure: items placed at wrong positions).
  - **CRDT-only is slower than full pipeline** — `get_text()` (45.8ms at 1000 defs) is more expensive than `get_proj_node() + get_source_map()` (39.1ms) because `to_text()` does string concatenation from 1000 individual chars.
  - **Actual bottleneck is immutable HashMap overhead** — FugueTree uses `@immut/hashmap.HashMap` for both `items` and `children`. Each insert creates new HAMT nodes. At 1000 nodes, the cumulative cost of immutable data structure operations (insert, lookup, copy-on-write) dominates.
  - **Per-keystroke breakdown at 1000 defs (~39ms full pipeline):** CRDT data structure ops (~20ms), position cache rebuild via RLE construction (~5ms), LCA index rebuild (~5ms), parser incremental (~2ms), projection pipeline (~5ms), SourceMap token spans (~2ms)
- [ ] **Reduce CRDT data structure overhead** — The dominant cost at 1000 defs is immutable HashMap operations in FugueTree (`@immut/hashmap.HashMap[Lv, Item[T]]` for items, `@immut/hashmap.HashMap[Lv, Array[Lv]]` for children). Options: (a) switch to mutable HashMap (`Map[Lv, Item[T]]`) — simplest, biggest win, but breaks undo snapshot semantics, (b) structural sharing with copy-on-write at branch boundaries only, (c) persistent array-mapped trie with cheaper updates
- [ ] **Memo Eq backdating cost** — `registry_memo` and `source_map_memo` use `derive(Eq)` for backdating, causing O(all_nodes) deep structural comparison per keystroke. Add versioned wrapper type or `physical_equal` fast-path in the Memo system. (`loom/incr/cells/memo.mbt`, `editor/projection_memo.mbt`)
- [ ] Implement lazy loading for 100k+ operation documents (load causal graph skeleton, hydrate on demand)
- [ ] Add B-tree indexing for FugueTree (O(n) → O(log n) random-access character lookup)

---

## 6. Testing Gaps

**Impact:** Medium | **Effort:** Low-Medium

- [x] Add CRDT convergence fuzz testing — multi-agent (2-5) property tests with random insert/delete/undo/redo/partial-sync, verifying all replicas converge after full sync
- [x] Add sync-order-independence property test — verifies convergence regardless of sync direction
- [x] Add undo-under-concurrency property test — agent undoes while another edits concurrently
- [x] Fix Delete/Undelete convergence bug found by fuzz testing — LWW conflict resolution with Lamport timestamps and add-wins semantics (`event-graph-walker/internal/fugue/tree.mbt`)
- [x] Add parser fuzz testing — random byte streams, verify no panics/aborts — ✅ Done. 7 fuzz tests in `loom/examples/lambda/src/parser_byte_fuzz_test.mbt`: raw BMP byte streams, control chars, high Unicode, mixed syntax, incremental edits with raw bytes
- [x] Add E2E browser tests with Playwright — `examples/demo-react` now has Playwright coverage
- [x] Run existing Playwright E2E in CI and pick a canonical browser app under test (`examples/demo-react`)
- [x] Add error path tests — malformed sync messages, corrupted operation logs, network interruptions — ✅ Done. `editor/error_path_wbtest.mbt` (20 tests: wire protocol, ws_on_message, apply_sync, export), `relay/error_path_wbtest.mbt` (9 tests: duplicate peers, non-existent peers, empty rooms)

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

**Impact:** Medium | **Effort:** Medium

- [ ] Convert `abort()` calls in test files to proper assertions (`assert_true` / `inspect`) for better error messages
- [x] Replace singleton JS FFI export state in `crdt.mbt` with a handle → `SyncEditor` map plus explicit destroy/dispose API
- [x] Split `projection/tree_editor.mbt` into focused files (render model, refresh/reuse logic, UI/edit operations, tree indexes) — ✅ Done. `tree_editor.mbt` (edit ops), `tree_editor_model.mbt` (types + state + constructors), `tree_editor_refresh.mbt` (refresh/reuse/indexes)
- [x] Split `crdt.mbt` into focused FFI files (editor core, undo, presence, relay, websocket) — ✅ Done. Split into 6 files: `crdt.mbt` (core), `crdt_undo.mbt`, `crdt_ephemeral.mbt`, `crdt_relay.mbt`, `crdt_websocket.mbt`, `crdt_projection.mbt`
- [x] Split `projection/text_edit.mbt` (1,348 lines) into focused modules — ✅ Done. Split into `text_edit.mbt` (1,064), `text_edit_rename.mbt` (231), `text_edit_utils.mbt` (51)
- [x] Decompose `text_edit.mbt` into handler chain — ✅ Done (PR #54). 1,064-line match → 96-line router + 8 handler files + `EditMiddleware` trait. Shared helpers extracted (`find_def_index`, `binding_delete_range`). Bug fixes: move-binding scoping, cursor positions, defensive guards.
- [x] Split `editor/ephemeral_hub.mbt` (19 methods) into focused files — ✅ Done. Split into `ephemeral_hub.mbt` (core), `ephemeral_hub_state.mbt` (typed writes), `ephemeral_hub_readers.mbt` (typed reads)

---

## 8b. Handler Chain Follow-ups

**Impact:** Medium | **Effort:** Low-Medium

From SuperOOP analysis and handler chain refactor (PR #54):

- [ ] **Term enum extensibility** — Term (10 variants, 24 match sites) is the biggest Expression Problem hotspot. If new language features are planned (let-rec, match, records), consider two-layer architecture: Finally Tagless traits for extensible operations + concrete enum for pattern matching. See `docs/plans/2026-03-23-handler-chain-design.md` SuperOOP analysis.
- [ ] **AST transform pipeline** — The `EditMiddleware` trait is ready for composable AST-to-AST transforms (constant folding, dead code elimination, simplification). Each pass becomes a middleware impl that intercepts before `core_dispatch`.
- [x] **Coordinate arithmetic audit** — ✅ Done. Audited all 9 `MoveCursor` sites across handler files. The two bugs (unwrap cursor, inline_definition cursor) were already fixed in PR #54. Remaining sites are correct: single-edit cases have no shift issues, multi-edit cases have cursor before or at the other edit's position.
- [x] **Parent lookup index** — ✅ Done. Extracted `find_parent` helper to `text_edit_utils.mbt` with early return. Replaces inline O(n) loop in `compute_delete` that didn't break on match. Reusable by other handlers.

---

## 9. Developer Experience

**Impact:** Low-Medium | **Effort:** Low-Medium | **Status:** Done

- [x] Add top-level `Makefile` or `justfile` wrapping both-module test commands into a single invocation
- [x] Add pre-commit hook running `moon check && moon fmt --check`
- [x] Script the web build workflow
- [x] Refresh stale integration docs and examples that still refer to `crdt.js`, `target/js`, or old JS loading patterns after the canopy rename and JS build flow

---

## 10. Ideal Editor

**Impact:** High | **Effort:** Medium

- [x] Outline refresh on text change — replaced broken deferred dispatch with immediate `refresh(model)`
- [x] Graphviz SVG rendering — DOT→SVG via MoonBit graphviz submodule, dark theme, after_render effect
- [x] Sync connection status — SyncStatus in PEERS panel with colored dot
- [x] Mobile layout — drawer panels, 44px touch targets, safe areas, scrim, landscape mode
- [x] CSS design system audit — zero raw values outside `:root`, 45 custom properties
- [ ] Inspector panel — wire up node details (type, source range, children) on outline click
- [ ] Structure mode — test and polish PM block editor, verify lazy-loading works
- [ ] Graphviz SVG theming — SVG uses hardcoded `Arial` from submodule; needs `pub(all) struct SvgConfig` to customize
- [ ] Grammar: interleaved let/expr — `Module` AST supports `ModuleItem` in parser already, but `FlatProj` storage change caused 2x regression from MoonBit enum boxing. Alternative: add helper methods on existing `FlatProj` for interleaved views.

---

## Priority Ranking

| # | Proposal | Effort | Impact |
|---|----------|--------|--------|
| 1 | ~~Fix FugueTree stack overflow~~ | ~~Low~~ | ~~Critical~~ | ✅ Done |
| 2 | ~~Profile CRDT at scale~~ | ~~Low~~ | ~~High~~ | ✅ Done |
| 3 | **Reduce CRDT data structure overhead** — immutable HashMap is dominant cost at 1000 defs | Medium | High |
| 4 | **Memo Eq backdating** — eliminate O(n) comparison per keystroke | Medium | High |
| 5 | Future wasm support, currently unsupported | Low-Medium | High |
| 6 | Complete WebSocket collaboration + recovery | High | High |
| 7 | Rabbita projection editor performance | High | High | Mostly done |
| 8 | Memory optimization (lazy loading, B-tree indexing) | High | Medium |
| 9 | Code cleanup | Medium | Medium | Mostly done |
