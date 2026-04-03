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
  Blocked by: container implementation (`docs/plans/2026-03-29-container-design.md`, `docs/plans/2026-03-29-container-phase1-tree.md`)
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

### StringView threading follow-ups (2026-04-02)

- [x] **StringView threading through parse pipeline** — ✅ Done. `token_text_at` → `ParseEvent::Token` → `Interner` all use `StringView`. Full parse 10-23% faster (long identifiers: 45.81 → 35.35 µs). 7 commits on loom/main.
  Plan: `docs/plans/2026-04-02-stringview-threading-design.md`
- [x] **Interner tuple struct** — ✅ Done. Single-field wrapper unboxed on JS target (~4% faster in controlled benchmark). Committed.
- [x] **NodeInterner → tuple struct** — ✅ Done. No measurable perf win (single-level HashMap, V8 optimizes away the dereference), but keeps consistency with Interner. Committed.
- [ ] **Scan for other single-field wrapper structs on hot paths**
  Why: any `struct Foo { field : T }` on a hot path pays wrapper + dereference cost on JS. Tuple struct eliminates both.
  Exit: all single-field wrappers on parse/intern/build_tree paths are tuple structs.
- [x] **Lexer accumulator cleanup: drop O(n²) string building** — ✅ Done (PR #70). Lambda and JSON lexers return position only, no string accumulation. Tokenize 15-17% faster for identifiers.
- [x] **Remove `cst_token_matches` from LanguageSpec** — ✅ Done (PR #70). Framework handles token matching internally. Payload-free Token enums. Incremental parsing 8-19% faster.
- [ ] **Markdown Token payload removal**
  Why: `HeadingMarker(Int)`, `CodeFenceOpen(Int, String)`, `Text(String)`, `CodeText(String)` still carry payloads. Some are semantic (heading level, info string) not just raw text — needs design thought on how to derive from source.
  Exit: markdown Token is payload-free where possible, semantic info extracted at point-of-use.
- [ ] **`TokenBuffer::get_view` helper**
  Why: the `get_text` closure for `ReuseCursor::new` is duplicated across 4 production callsites (factories.mbt, lambda/cst_parser.mbt, json/cst_parser.mbt, markdown/cst_parser.mbt). Worth extracting now that markdown is a 4th consumer.
  Exit: `TokenBuffer::get_view(source, i) -> StringView` replaces inline closures.
- [x] **Token::to_raw ↔ SyntaxKind::to_raw round-trip test** — ✅ Done. `token_rawkind_test.mbt` in both lambda and json verifies all Token/SyntaxKind pairs match.
- [ ] **Unify Token and SyntaxKind into single enum (rowan style)**
  Why: Token and SyntaxKind overlap — every Token variant has a corresponding SyntaxKind variant. Two independent to_raw() impls with hardcoded integers can desynchronize. The payload removal (PR #70) made Token pure tags, identical in structure to SyntaxKind's token subset. Merging eliminates the synchronization problem entirely — the lexer produces SyntaxKind directly, no conversion needed.
  Prerequisite: payload-free Token enums (done). Practical trigger: loomgen, which can generate the single enum from a grammar definition.
  Exit: `ParserContext[SyntaxKind, SyntaxKind]` — one type for both T and K. IsTrivia/IsEof impls on SyntaxKind. Lexer produces SyntaxKind.

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

### SourceMap bugs (from GitHub issues)

- [x] `SourceMap::apply_edit` leaves `token_spans` stale (GitHub #70) — ✅ Done. `apply_edit` iterates `token_spans` and calls `shift_range()` on each span.
- [x] `SourceMap::apply_edit` overlap branch doesn't clamp start positions (GitHub #71) — ✅ Done. `shift_range` clamps `new_start` to `edit_start` in the overlap branch.

### FlatProj / ProjNode bugs (from GitHub issues)

- [x] FlatProj ↔ ProjNode round-trip drops binding IDs (GitHub #72) — ✅ Done. `from_proj_node` preserves original NodeId; `reconcile_flat_proj` carries forward old entry's NodeId on match.
- [x] FlatProj `key_match` should use stable identity, not just name (GitHub #73) — ✅ Done. `key_match` uses `Eq + Hash` constraint with cursor-based matching; `reconcile_flat_proj` preserves old NodeId.

---

## 8. Code Cleanup

**Impact:** Medium | **Effort:** Medium

- [x] Introduce typed `editor/` boundary errors
  Why: `editor/` still mixes typed low-level errors, generic failures, raw strings, and silent catches across protocol, ephemeral, and tree-edit boundaries.
  Plan: `docs/plans/2026-03-29-error-taxonomy.md`
  Exit: `editor/` uses explicit boundary error types and root FFI remains the primary error-flattening edge.
  Note: tree-edit, ephemeral, and websocket/protocol slices are implemented; contributor and API docs now describe the current boundary strategy. A future wrapper-type decision can be tracked separately if needed.
- [x] Convert `abort()` calls in test files to proper assertions — ✅ Done. Verified 2026-04-02: zero `abort()` in any .mbt file across entire repo. Plan archived.
- [ ] Parse recovery should produce `Error` nodes, not coerce to `Int(0)`/`Plus` (GitHub #74)
  Exit: malformed expressions produce `Error(...)` nodes in the AST.
- [ ] `parse_to_proj_node` should return `Result` instead of aborting (GitHub #75)
  Exit: projection pipeline returns errors instead of calling `abort()`.
- [ ] Tighten `ActionRecord` visibility (GitHub #97)
  Exit: `ActionRecord` fields use appropriate visibility modifiers.
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
- [ ] **Zipper keyboard integration** — Wire zipper navigation into ideal editor keyboard handling.
  Plan: `docs/plans/2026-03-29-zipper-keyboard-integration.md`, `docs/plans/2026-03-30-zipper-keyboard-impl.md`
  Exit: arrow keys navigate the outline tree via zipper in ideal editor.
- [ ] **Cache Zipper between keystrokes** to avoid double DFS (GitHub #91)
  Exit: zipper is cached and reused across consecutive keystrokes.
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
- [x] Inspector panel — Done. Plans archived to `docs/archive/`.
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
- [ ] **loomgen design update** — Update `docs/design/07-loomgen-design.md` with learnings from lambda + JSON + markdown. Three real examples now inform the generator.
- [x] **Loom lex modes** — ✅ Done. `ModeLexer[T, M]` with type erasure via `erase_mode_lexer`, convergence-based incremental re-lex. `loom/loom/src/core/mode_lexer.mbt`. All 194 loom tests pass.
  Plan: `loom/docs/plans/2026-04-01-loom-lex-modes-design.md`, `loom/docs/plans/2026-04-01-loom-lex-modes-impl.md`
- [x] **Markdown parser (loom)** — ✅ Done. Two-level AST (Block + Inline), 3 lex modes (LineStart, Inline, CodeBlock), error recovery, source fidelity. 28 tests pass. `loom/examples/markdown/`.
  Plan: `loom/docs/plans/2026-04-01-markdown-parser-design.md`, `loom/docs/plans/2026-04-01-markdown-parser-impl.md`
- [ ] **Markdown Canopy integration** — Wire `loom/examples/markdown/` into `lang/markdown/` with projection, editor support, and block editor integration.
  Exit: `lang/markdown/` package with projection + edit ops, block editor renders markdown via ViewNode protocol.

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
- [x] **Wire into web editor via ViewNode bridge** — ✅ Done (PR #109). `layout_to_view_tree` in `protocol/` converts `Layout[SyntaxCategory]` → per-line ViewNode tree with token_spans. HTMLAdapter renders syntax-highlighted lines. Property tests validate roundtrip and span coverage.
  Architecture: `docs/architecture/multi-representation-system.md`
  Design: `docs/plans/2026-04-02-pretty-printer-viewnode-bridge-design.md`
- [ ] **Structure-format projections from semantic model** — Rather than generalizing DOT/JSON/S-expr as tree-annotation IRs, build projections that query the semantic model (egglog knowledge base + incr reactive graph). Current DOT rendering needs `Resolution` (a semantic fact about scope), not a tree annotation. The right answer is richer semantics, not a better annotation mechanism.
  Why: the structure-format problem is "how to represent program meaning so projections render from it," not "how to annotate trees." See vision doc.
  Architecture: `docs/architecture/vision-projectional-bridge.md`, `docs/architecture/multi-representation-system.md`
  Research: Trees That Grow (Najd 2017), Cofree comonads, Attributed Grammars, MLIR dialects — each addresses a fragment of this. The semantic model approach (egglog) subsumes them.
  Prerequisite: evaluator Phase 1 (egglog relational evaluation) validates the semantic model approach.
  Exit: at least one structure-format projection (DOT or typed view) queries the semantic model instead of threading ad-hoc data.

### Concrete semantic projection candidates

- [ ] **Scope-colored tree view** — Color variables by binding status (bound/free/shadowed) in the structural tree view. Resolution already exists and is used for DOT; this flows it through the ViewNode protocol instead of an ad-hoc path. First projection that delivers semantic data through the framework.
  Why: lowest effort, proves the semantic-data-through-protocol pattern. If Resolution flows through ViewNode cleanly, types and eval results follow the same path.
  Semantic data: Resolution (available now)
  Exit: tree view shows bound variables colored by binder, free variables highlighted as warnings.
- [ ] **Live inline evaluation** — Show evaluation results next to definitions in the pretty-print view. The evaluator (Phase 2) is done; this connects it to the user's eyes.
  Why: highest user-visible impact. "See the values" experience (Bret Victor). Closes the syntax→semantics gap directly.
  Semantic data: eval results (available now via `loom/examples/lambda/src/eval/`)
  Exit: pretty-print view shows `→ 10` or `→ ‹closure›` next to each evaluated definition.
- [ ] **Type annotations overlay** — Show inferred types next to bindings and expressions. Egglog typing rules already exist in `loom/egglog/examples/lambda/`.
  Why: types are the canonical "explicit semantics" — they make invisible meaning visible. First projection requiring the egglog semantic model.
  Semantic data: type inference (needs egglog Phase 1)
  Prerequisite: evaluator Phase 1 (egglog relational evaluation)
  Exit: bindings show inferred types (e.g., `double : Int → Int`).
- [ ] **Πe extension** — Add `Choice` constructor and cost-factory resolver for more expressive layout decisions.
  Exit: layout engine supports user-defined cost functions per "A Pretty Expressive Printer" (OOPSLA 2023).

---

## 14. EditorProtocol — Framework-Agnostic Integration Layer

**Impact:** High | **Effort:** High

- [x] Framework-agnostic integration layer to eliminate duplicated TS logic — ✅ Done (Phases 0-6). Protocol types (`ViewPatch`, `ViewNode`, `UserIntent`), ViewUpdater, 3 adapters (HTML, CM6, PM). `examples/web`, `examples/ideal`, `examples/prosemirror`, `examples/demo-react` all migrated.
  Plan: `docs/plans/2026-04-01-editor-protocol-design.md`
- [ ] BlockAdapter + `examples/block-editor` migration (Phase 7)
  Why: block-editor has its own parallel FFI surface; migrating to protocol enables Markdown editing with zero new TS code.
  Plan: `docs/plans/2026-04-01-editor-protocol-design.md` §Phase 7
  Exit: block-editor uses BlockAdapter with ViewNode tree; autoformat detection moved to MoonBit.

---

## 15. Lambda Evaluator

**Impact:** Medium | **Effort:** Medium

- [x] **Phase 2: Direct evaluator** — ✅ Done (PR loom#69). Tree-walking `eval` in `loom/examples/lambda/src/eval/`. 31 tests, all Term variants, fuel-limited divergence. Educational comments.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-phase2-impl.md`
- [x] **Phase 0: Egglog API extensions** — ✅ Done (egglog PR #5). Added `Database::scan` and `Database::row_count`. 5 tests.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 0
- [ ] **Phase 1: Egglog relational evaluator** — Datalog + Bridge hybrid evaluation with demand-driven rules.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 1
  Exit: egglog example with partial evaluation, composition with typing, 20+ tests.
- [ ] **Phase 3: Editor integration** — Wire Tier 1 + Tier 2 into incr reactive graph with batch escalation.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 3
  Exit: Memo[EvalResult] per definition, Tier 2 batch escalation for incomplete programs.
- [ ] **Phase 3b: Incremental egglog–incr unification** — Make egglog Database a persistent incr cell with incremental fact insertion/retraction, instead of rebuilding from scratch each Memo recompute. Currently egglog creates a throwaway `@incr.Runtime` per `Saturate` call — no reactive connection between egglog facts and incr Memos. Requires: persistent Database across revisions, fact retraction, delta-driven escalation from Tier 1 Stuck results.
  Why: Phase 3 rebuilds the entire egglog Database on every edit. Fine for small programs but blocks the incremental compiler vision at scale.
  Depends on: Phase 0 + Phase 1 (validates the relational model first).
  Exit: Tier 2 re-derives only affected `Eval` facts when a single `Term` changes, not full re-seed.

---

## 16. Incremental Parsing — Convergence Relex

**Impact:** Medium | **Effort:** Low-Medium

- [ ] **Convergence relex** — Ensure incremental relex converges with batch lex.
  Plan: `docs/plans/2026-04-02-convergence-relex-impl.md`
  Exit: property test confirms incremental relex always produces same tokens as full lex.

---

## 17. Example App Consolidation

**Impact:** Medium | **Effort:** High

- [ ] **Archive `examples/rabbita/`** — superseded by `examples/ideal/`. Move to `docs/archive/` or remove.
  Exit: `rabbita/` removed from active tree, no broken references.
- [ ] **Migrate `demo-react/` E2E + features to `web/`** — add Playwright to `web/`, port `e2e/single-editor.spec.ts` and `e2e/collaborative-demo.spec.ts`, migrate any React-only features.
  Why: `web/` is the canonical lightweight demo (vanilla JS, shows EditorProtocol directly). `demo-react/` duplicates it in React.
  Exit: `web/` has Playwright E2E covering lambda + JSON editors; `demo-react/` retired.
- [ ] **Retire `demo-react/`** — remove after migration complete.
  Exit: 6 example apps remain, each with distinct purpose.

- [ ] **Design E2E test strategy** — decide how to manage Playwright across multiple example apps. Current state: `demo-react/` and `ideal/` each have independent Playwright setups with no shared infrastructure.
  Why: after consolidation, `web/` and `ideal/` both need E2E. Shared page objects, test helpers, and CI configuration would reduce duplication and make it easier to add E2E to new apps.
  Considerations: shared Playwright config vs per-app, common assertion helpers for ViewNode/ViewPatch behavior, CI matrix for multiple apps, whether `prosemirror/` and `block-editor/` need E2E.
  Exit: design doc in `docs/plans/` defining the E2E test architecture.

Post-consolidation app inventory:

| App | Purpose |
|-----|---------|
| `web/` | Canonical demo — vanilla JS, lambda + JSON editors |
| `ideal/` | Flagship full-featured editor (Rabbita) |
| `prosemirror/` | Reference integration — PMAdapter proof |
| `canvas/` | Future infinite canvas app |
| `block-editor/` | Block editor demo (pending Phase 7) |
| `relay-server/` | Signaling server infrastructure |

---

## 18. Documentation & Demo Polish

**Impact:** High (first impressions) | **Effort:** Low-High

### Medium effort (no new features needed)

- [ ] **Record a GIF of the current editor** — pretty-printer + syntax highlighting + tree update is already visual. Embed at top of README. Imperfect GIF now is better than perfect GIF later.
  Exit: README has a GIF that shows the editor experience in under 5 seconds.
- [ ] **Promote product vision visibility** — add `VISION.md` symlink at repo root pointing to `docs/architecture/product-vision.md`, or expand README "Bigger Picture" section with the cold pitch text.
  Exit: a visitor who reads only the README encounters the product vision, not just the framework description.
- [ ] **Unify voice across architecture docs** — README and product-vision speak product language; projectional-bridge and structure-format-research speak academic language. One editing pass to make them consistent.
  Exit: all architecture docs feel like they were written by the same person for the same audience.

### Requires new features

- [ ] **Live inline evaluation display** — makes the GIF compelling ("→ 10" appearing as you type). See §13 concrete projection candidates.
  Exit: demo shows evaluation results inline while typing.
- [ ] **Scope-colored tree view** — makes the structural view visually meaningful. See §13 concrete projection candidates.
  Exit: demo shows bound/free variables colored in the tree view.
- [ ] **Deploy updated web demo** — the current live demo URL points to rabbita, not the new web editor with pretty-printer.
  Exit: live demo link in README shows the current canonical `web/` editor.

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
