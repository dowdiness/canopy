# Project TODO

Improvement proposals for the eg-walker CRDT Lambda Calculus Editor.

## How To Read This File

`docs/TODO.md` is the active backlog index, not the full implementation spec.

For coding-agent-friendly execution:

- keep each active item short,
- link one canonical plan doc in `docs/plans/` for non-trivial work,
- define an observable exit condition,
- move completed or superseded execution detail to `docs/archive/`.

Tracking guide: [Task Tracking](development/task-tracking.md)
Plan template: [Plan Template](plans/TEMPLATE.md)

## Priority Legend

- **Impact:** High / Medium / Low
- **Effort:** High / Medium / Low
- **Status:** Not Started / In Progress / Done

## Preferred Item Format

```md
- [ ] <task title>
  Why: <why it matters>
  Plan: `docs/plans/<date>-<slug>.md` or GitHub issue
  Exit: <observable done state>
```

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

- [ ] Complete WebSocket client integration
  Why: the wire protocol exists, but the supported browser-side integration path is not yet treated as a finished, documented workflow.
  Plan: `docs/plans/2026-03-29-websocket-client-integration.md`
  Exit: one canonical client flow is implemented, documented, and validated.
- [ ] Implement `SyncRequest`/`SyncResponse` recovery so malformed/incompatible `CrdtOps` does not leave peers diverged silently
  Why: recovery semantics should be finalized after the container implementation defines the next sync boundary, not against the current pre-container transport assumptions.
  Plan: `docs/plans/2026-03-29-sync-recovery-followup.md`
  Exit: revisit after container implementation; then align retry, buffering, and failure behavior with the new sync boundary.
- [ ] Reject duplicate/invalid relay peer IDs in `RelayRoom`
  Why: `RelayRoom` still trusts caller uniqueness and membership correctness, but hardening this boundary should wait until the container implementation defines the next sync boundary clearly.
  Plan: `docs/plans/2026-03-29-relay-peer-validation.md`
  Exit: revisit after container implementation; then define and test duplicate peer IDs and invalid membership behavior against the new sync boundary.
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
- [x] Implement LCS matching for AST child reconciliation instead of positional matching (`projection/reconcile_ast.mbt`)
- [x] **Incremental parse overhead reduced** — (2026-03-24) Three fixes brought tail-edit overhead from 1.29x to 1.01x batch at 40 realistic defs, and 0.90x (faster) at 160 defs. Block edits remain 13µs regardless of size. See loom PR #49.
  - [x] **Persistent OldTokenCache** — cache flattened old-token array across edits with delta-adjusted lookups. Eliminates O(n) `collect_old_tokens` rebuild per edit (~50µs savings).
  - [x] **ctx.node() for LetDef/MemberNode** — replaced mark/start_at with ctx.node() so try_reuse is called for individual definitions/members.
  - [x] **reuse_size_threshold=0** — default 64-byte threshold was blocking reuse of most definitions (<64 bytes).
  - [x] **Realistic benchmarks** — added benchmarks exercising full grammar (blocks, lambdas, if-then-else, application) for both lambda and JSON. Old trivial `let x = 0` benchmarks were misleading.
  - [ ] **Remaining: flat edits on tiny nodes** — JSON 20-member flat edit is 2x batch. Per-node reuse overhead exceeds parse cost for 3-token members. Grammar-level tradeoff, not a framework bug. Options: (a) accept for tiny structures, (b) batch-reparse fallback when reuse count is zero, (c) amortized threshold that learns from reuse hit rate

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
- [x] **Reduce CRDT data structure overhead (Phase 2b)** — ✅ Done. Replaced immutable HashMap with dense Array storage: `items: Array[Item[T]?]`, `children: Array[Array[Lv]]` + `root_children`, `LcaIndex.first: Array[Int]` + `root_first`. Delete/undelete use in-place field mutation. `@immut/hashmap` dependency removed from fugue package. Result: 1000-char append 1.61ms → 1.05ms (1.5x), delete 2.66ms → 1.51ms (1.76x), text() 285µs → 154µs (1.85x). See `docs/archive/completed-phases/2026-03-23-fugue-store-array-design.md`.
- [x] **LCA index rebuild on every insert** — ✅ Done (PR #11). Replaced Euler Tour + Sparse Table with binary lifting jump pointers. O(log depth) per insert and query, no rebuild ever. Eliminated `batch_inserting` mode. **Post-mortem:** The claimed "3-5ms at 1000 items" was stale (measured before Phase 2b Array migration) and included full-pipeline cost, not just LCA rebuild. The `batch_inserting` mode already mitigated all hot paths. Actual improvement was negligible at current scale — the optimization was architecturally clean but not a real bottleneck. **Lesson:** Always reproduce the bottleneck in a microbenchmark before designing an optimization. See `docs/archive/completed-phases/2026-03-24-incremental-lca-binary-lifting.md`.
- [x] **Position cache full rebuild on non-sequential inserts** — ✅ Done. Removed unnecessary `invalidate_cache()` from cursor-miss and partial-cursor-hit paths; cache maintained incrementally via `OrderTree.insert_at`. Also fixed `find_parent_and_side` to match Fugue paper Algorithm 1 (insert at pos 0 was placing chars at end). Added property test L5.8 (position round-trip). Jump-to-middle: 115ms → 2.56ms (45x). See `event-graph-walker/docs/decisions/2026-03-31-fugue-find-parent-and-side-fix.md`.
- [x] **Memo Eq backdating cost** — ✅ Done. `BackdateEq` trait added to `loom/incr`; `Memo::new_memo` (uses `BackdateEq`, O(1) revision stamp) and `Memo::new_no_backdate` constructors added. `editor/projection_memo.mbt`: `proj_memo` uses `new_memo` with `VersionedFlatProj : BackdateEq`; `registry_memo` and `source_map_memo` use `new_no_backdate`. Per-benchmark: ~0.5–1ms savings at 1000 defs — real but modest.
- [ ] Implement lazy loading for 100k+ operation documents (load causal graph skeleton, hydrate on demand)
- [ ] Add B-tree indexing for FugueTree (O(n) → O(log n) random-access character lookup)
- [ ] **`zipper-gen` — code generation for tree zippers** — Build a morm-style pre-build code generator (`zipper-gen`) that reads MoonBit enum definitions annotated with `#zipper.derive` and generates zipper types (Frame, Zipper) + navigation functions (descend, ascend, to_root, modify, sibling navigation). Uses `@moonbitlang/parser` for AST extraction and `moon.pkg` `pre-build` for build integration, following the same pattern as [oboard/morm](https://github.com/oboard/morm)'s `mormgen`. Applicable tree types: `OrderNode[T]` (order-tree), `CstNode` (loom/seam). The generated mechanical layer (frame types, navigation, plug/reconstruct) eliminates boilerplate like `block_reparse.splice_tree` path-copy code, while domain-specific hooks (Walker's prepare/propagate, ReuseCursor's reuse checks) remain hand-written on top. Based on the Huet Zipper / "derivative of a type = one-hole context" theory (McBride 2001). Trigger: build when adding the next tree type (e.g., `EulerTourNode` for incremental LCA) so it pays for itself immediately. Ref: [Parsing with Zippers](https://github.com/stereobooster/powderizer) for the zipper-as-parser-cursor pattern.

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

- [x] **Consolidate prefix/suffix diff** — Already resolved: `projection/text_lens.mbt` was removed. Both `set_text_and_record` and `compute_edit` now delegate to the shared `@text_change.compute_text_change()` in `lib/text-change/`. The remaining `compute_text_edits` in `editor/text_diff.mbt` is a separate LCS-based multi-edit diff for batch remote merges — not a duplicate.

### TextInput path efficiency

- [x] **`set_text` is brute-force O(n)** — ✅ No longer used for typing. `TextInput` uses `apply_text_edit(start, delete_len, inserted)` which applies only the changed span. `set_text` still exists as a fallback but is not on the hot path.

### CRDT API limitations

- [x] **Char-by-char delete for range deletions** — ✅ Done. `TextState` now exposes `replace_range` in `event-graph-walker/text/text_doc.mbt`.
- [x] **No undo tracking for tree edits** — ✅ Done. `apply_tree_edit` now uses `apply_text_edit_internal` with `record_undo=true`. Tree edits are undoable via `SyncEditor.undo()`.

### Resolved: CRDT position ordering bug

- [x] **`apply_projection_edits` used insert-first ordering** — `text_lens_diff` produces edits with insert-before-delete and adjusted positions. FugueMax's position semantics require delete-first ordering; insert-first caused position drift producing corrupted text. **Fixed:** replaced with `set_text(new_text)` which uses proven delete-all + insert approach.

---

## 8. Code Cleanup

**Impact:** Medium | **Effort:** Medium

- [x] Introduce typed `editor/` boundary errors
  Why: `editor/` still mixes typed low-level errors, generic failures, raw strings, and silent catches across protocol, ephemeral, and tree-edit boundaries.
  Plan: `docs/plans/2026-03-29-error-taxonomy.md`
  Exit: `editor/` uses explicit boundary error types and root FFI remains the primary error-flattening edge.
  Note: tree-edit, ephemeral, and websocket/protocol slices are implemented; contributor and API docs now describe the current boundary strategy. A future wrapper-type decision can be tracked separately if needed.
- [ ] Convert `abort()` calls in test files to proper assertions
  Why: assertion-style failures currently use `abort(...)` in many tests, which makes diagnostics harsher and less informative than explicit assertions.
  Plan: `docs/plans/2026-03-29-test-abort-cleanup.md`
  Exit: targeted test-side `abort(...)` checks are replaced with assertion-based failures and affected suites stay green.
  Progress: paused; first pass covered main-module helpers and parser fixtures, and the second pass completed parser-oriented slices in `loom/examples/json` and `loom/examples/lambda`. Remaining cleanup is concentrated mostly in `loom/` and `graphviz/`.
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

- [x] **Term enum extensibility** — ✅ Done. (a) `TermSym` Finally Tagless trait + `replay` in loom submodule. (b) Framework extraction complete (Phases 1–4): `framework/core/` has generic types (NodeId, ProjNode, SourceMap, reconcile); `TreeNode`/`Renderable` traits in `loom/core` with impls in `lambda/ast`; lambda-specific code in `lang/lambda/proj/` and `lang/lambda/edits/`; `projection/` is a re-export facade. Acid test: `framework/core/` has zero `@ast` imports. See PRs #60, #62, #66, #69.
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
- [x] Inspector panel
  Why: the Ideal editor already has partial inspector UI, but the backlog item is still unfinished until outline selection reliably shows the intended node details, including source range.
  Plan: `docs/plans/2026-04-01-inspector-panel-design.md`
  Exit: outline click reliably populates the inspector with kind/type, source range, source text preview, token spans, and child information.
- [ ] Structure mode — test and polish PM block editor, verify lazy-loading works
- [ ] Graphviz SVG theming — SVG uses hardcoded `Arial` from submodule; needs `pub(all) struct SvgConfig` to customize
- [ ] Grammar: interleaved let/expr — `Module` AST supports `ModuleItem` in parser already, but `FlatProj` storage change caused 2x regression from MoonBit enum boxing. Alternative: add helper methods on existing `FlatProj` for interleaved views.

---

## 11. Editor Drag-and-Drop Foundation

**Impact:** High | **Effort:** Medium-High

- [ ] Prepare drag-and-drop foundations for `examples/ideal` and `examples/block-editor`
  Why: both editors need relocation UX, but the real missing pieces are a canonical move contract, backend legality checks, and model-level positioned move APIs rather than DOM-only gesture code.
  Plan: `docs/plans/2026-03-30-editor-drag-drop-foundation.md`
  Exit: `block-editor` exposes positioned block moves plus structural render metadata, and `ideal` accepts validated `Drop` edits through the canonical tree-edit bridge.

---

## 12. Multi-Language Support

**Impact:** High | **Effort:** Medium

- [x] **Framework extraction** — ✅ Done (Phases 1–4, PRs #60, #62, #66, #69). `framework/core/` has generic types; traits in `loom/core`.
- [x] **TestExpr proof** — ✅ Done (PR #77). Framework works with non-lambda AST type. ADR: `docs/decisions/2026-03-29-framework-genericity-contract.md`.
- [x] **JSON projectional editor** — ✅ Done (PR #100). Second language consumer: `lang/json/proj/` + `lang/json/edits/`. Shared SpanEdit/FocusHint in framework/core. SyncEditor::new_generic (no FlatProj). 8 benchmarks.
- [x] **JSON web editor** — ✅ Done (PR #104). `crdt_json.mbt` FFI exports, `examples/web/json.html` + `json-editor.ts` with structural editing toolbar, tree view, inline key/type input. Vite multi-page build. All 9 JsonEditOp variants supported.
- [ ] **JSON FlatProj optimization** — 1000-member objects at 28ms exceed 16ms budget. Add incremental per-member derivation when needed.
- [ ] **loomgen design update** — Update `docs/design/07-loomgen-design.md` with learnings from lambda + JSON. Two real examples now inform the generator.
- [ ] **Markdown editor** — Third language for the block editor. Depends on loomgen or manual implementation.

---

## 13. Pretty-Printer Engine

**Impact:** High | **Effort:** Done (engine) / Medium (integration)

- [x] **Wadler-Lindig engine** — ✅ Done (PR #106). `canopy/pretty/` with generic `Layout[A]`, suffix-aware group flattening, two renderers (`render_string`, `render_spans`), 7 property-based tests.
  Design: `docs/plans/2026-03-31-pretty-printer-design.md`
  Impl: `docs/plans/2026-03-31-pretty-printer-impl.md`
- [x] **Lambda TermSym integration** — ✅ Done. `PrettyLayout` wrapper with precedence tracking in `lang/lambda/proj/pretty_layout.mbt`.
- [x] **JSON pretty-printing** — ✅ Done. `json_to_layout` with string escaping in `lang/json/proj/pretty_layout.mbt`.
- [ ] **Wire into REPL** — Use `render_string` in `cmd/main/` for formatted AST output.
  Exit: REPL displays width-aware formatted expressions.
- [ ] **Wire into web editor** — Use `render_spans` to feed annotated output to the projectional editor UI.
  Exit: editor renders syntax-highlighted, width-aware formatted code.
- [ ] **Πe extension** — Add `Choice` constructor and cost-factory resolver for more expressive layout decisions.
  Exit: layout engine supports user-defined cost functions per "A Pretty Expressive Printer" (OOPSLA 2023).

---

## 14. EditorProtocol — Framework-Agnostic Integration Layer

**Impact:** High | **Effort:** High

- [ ] Framework-agnostic integration layer to eliminate duplicated TS logic
  Why: examples/ apps duplicate ProjNode conversion, reconciliation, and SourceMap caching in TS. MoonBit already knows what changed but exports full snapshots.
  Plan: `docs/plans/2026-04-01-editor-protocol-design.md`
  Exit: `examples/ideal` and `examples/prosemirror` use EditorProtocol with thin TS adapters; no duplicated conversion/reconciliation code.

---

## Priority Ranking

| # | Proposal | Effort | Impact |
|---|----------|--------|--------|
| 1 | ~~Fix FugueTree stack overflow~~ | ~~Low~~ | ~~Critical~~ | ✅ Done |
| 2 | ~~Profile CRDT at scale~~ | ~~Low~~ | ~~High~~ | ✅ Done |
| 3 | ~~Reduce CRDT data structure overhead~~ | ~~Medium~~ | ~~High~~ | ✅ Done (Phase 2b) |
| 4 | ~~LCA index rebuild per insert~~ | ~~Medium~~ | ~~High~~ | ✅ Done (binary lifting). Post-mortem: bottleneck was stale — batch_inserting already mitigated. |
| 5 | ~~Incremental parser slower than batch~~ | ~~Medium~~ | ~~Medium~~ | ✅ Done (persistent cache + ctx.node + threshold=0). Tail edit 1.01x at 40 defs, 0.90x at 160 defs. Flat tiny-node case (JSON 2x) is a known tradeoff. |
| 6 | ~~Memo Eq backdating~~ | ~~Medium~~ | ~~High~~ | ✅ Done (BackdateEq trait + Memo::new_memo/new_no_backdate in loom/incr; projection_memo.mbt updated) |
| 7 | Future wasm support, currently unsupported | Low-Medium | High |
| 8 | Complete WebSocket collaboration + recovery | High | High |
| 9 | Rabbita projection editor performance | High | High | Mostly done |
| 10 | Memory optimization (lazy loading, B-tree indexing) | High | Medium |
| 11 | `zipper-gen` code generation for tree zippers | Medium | Medium | Trigger: next tree type |
| 12 | Code cleanup | Medium | Medium | Mostly done |
| 14 | EditorProtocol integration layer | High | High |
