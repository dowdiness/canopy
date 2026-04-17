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
- [ ] Reduce CRDT JS bundle size (currently 648 kB as of 2026-04-18; exceeds 500 kB threshold)
  Why: large bundle impacts initial page load for web editors.
  Plan: `docs/plans/2026-04-18-crdt-bundle-split.md` (split `ffi/` into per-entry `ffi/{lambda,json,markdown}/` packages)
  Exit: CRDT bundle under 500 kB ungzipped for json.html and markdown.html; lambda floor (~515 kB) tracked as follow-up per plan §7.

---

## 2. Collaboration Features

**Impact:** High | **Effort:** High

- [ ] Complete WebSocket client integration
  Why: the wire protocol exists, but the supported browser-side integration path is not yet treated as a finished, documented workflow.
  Plan: `docs/plans/2026-03-29-websocket-client-integration.md`
  Exit: one canonical client flow is implemented, documented, and validated.
- [ ] Implement `SyncRequest`/`SyncResponse` recovery so malformed/incompatible `CrdtOps` does not leave peers diverged silently
  Why: now unblocked — container Phase 3 (unified sync) shipped via egw#21, so retry/buffering/failure semantics can be aligned against the Document-level sync boundary.
  Plan: `docs/plans/2026-03-29-sync-recovery-followup.md`
  Exit: malformed/incompatible ops trigger defined recovery (retry, buffering, or surfaced failure) against the Document sync boundary rather than silent divergence.
- [x] Reject duplicate/invalid relay peer IDs in `RelayRoom` — ✅ Done (PR #188). `on_connect` returns `Bool`, rejects empty and duplicate IDs. `on_message` drops non-member senders. `on_disconnect` no-ops for non-members (prevents ghost `PeerLeft` from clearing ephemeral state). CF Worker closes rejected duplicates with application code 4001. Archive plan: `docs/archive/2026-03-29-relay-peer-validation.md`.
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
  Plan: (design doc no longer exists — work completed directly)
- [x] **Interner tuple struct** — ✅ Done. Single-field wrapper unboxed on JS target (~4% faster in controlled benchmark). Committed.
- [x] **NodeInterner → tuple struct** — ✅ Done. No measurable perf win (single-level HashMap, V8 optimizes away the dereference), but keeps consistency with Interner. Committed.
- ~~**Convert `EventBuffer` to tuple struct**~~ — Dropped. `EventBuffer` is allocated once per parse, not per token. Hot-path methods (`push`, `mark`, `start_at`) operate on the inner Array — wrapper shape doesn't affect cost. `NodeInterner` (higher call frequency) already showed no measurable win. `self.events` is clearer than `self.0` across 10+ methods.
- [x] **Lexer accumulator cleanup: drop O(n²) string building** — ✅ Done (PR #70). Lambda and JSON lexers return position only, no string accumulation. Tokenize 15-17% faster for identifiers.
- [x] **Remove `cst_token_matches` from LanguageSpec** — ✅ Done (PR #70). Framework handles token matching internally. Payload-free Token enums. Incremental parsing 8-19% faster.
- [ ] **Markdown Token payload removal**
  Why: `HeadingMarker(Int)`, `CodeFenceOpen(Int, String)`, `Text(String)`, `CodeText(String)` still carry payloads. Some are semantic (heading level, info string) not just raw text — needs design thought on how to derive from source.
  Exit: markdown Token is payload-free where possible, semantic info extracted at point-of-use.
- [x] **`TokenBuffer::get_view` helper** — ✅ Done. `TokenBuffer::get_view(self, i) -> StringView` exists in `loom/loom/src/core/token_buffer.mbt`. Production path (`factories.mbt`) already uses `buffer.get_view(i)`. Lambda/JSON `make_reuse_cursor` are test helpers operating on raw arrays, not production duplication.
- [x] **Token::to_raw ↔ SyntaxKind::to_raw round-trip test** — ✅ Done. `token_rawkind_test.mbt` in both lambda and json verifies all Token/SyntaxKind pairs match.
- [ ] **`SyntaxNode::find[K : ToRawKind]` generic method** (low priority)
  Why: 16 `find_token(...to_raw())` callsites remain, but views pattern + `token_text()` already reduce the ergonomic pain. Nice-to-have polish.
  Exit: `pub fn[K : ToRawKind] SyntaxNode::find(self, kind : K) -> SyntaxToken?` in seam.
- [x] **`SyntaxNode::tokens()` method** — ✅ Done. `seam/syntax_node.mbt:306`. Returns all direct child leaf tokens via `walk_children_flat`.
- ~~**`SyntaxNode::content_range` method**~~ — Dropped. Actual projection patterns use `all_children()` state machines (markdown) or `token_text()` (JSON), not simple prefix-skipping. `tight_span()` already covers the trivia-exclusion case. Proposed signature doesn't match ground truth.
- [x] **`SourceMap::set_span_from_token` convenience method** — ✅ Done. `core/source_map.mbt`. Lambda and Markdown migrated.
- ~~**Generic parallel tree walk for `populate_token_spans`**~~ — Dropped. `build_projection_memos` already captured the main duplication. Remaining `min(len_a, len_b)` pattern only fits markdown (Document, UnorderedList) and JSON Array. JSON Object uses selective filtering; lambda dispatches by expression type. ~10 lines saved across codebase — not worth a new public API.
- [x] **Generic 3-memo projection builder** — ✅ Done. `core/projection_memo.mbt` provides `build_projection_memos[T]`. JSON and Markdown migrated.
- [x] **`SourceMap::set_span_from_token` convenience method** — ✅ Done. `core/source_map.mbt`. Lambda and Markdown migrated.
- [ ] **`lib/range` foundational package**
  Why: Range (`{ start: Int, end: Int }`) is defined twice (loom/core, event-graph-walker/text) and represented implicitly in seam (SyntaxToken/SyntaxNode have `.start()`/`.end()` but no `.range()`). A shared `lib/range` package at the bottom of the dependency graph would: (a) unify the duplicate definitions, (b) enable `SyntaxToken::range()` and `SyntaxNode::range()` in seam, (c) retire rle's `FromRange` trait (a workaround for the missing type), (d) use MoonBit custom constructor `Range(start~, end~)`.
  Touches: lib/range (new), seam, loom/core, rle, canopy/core, event-graph-walker/text. Cross-submodule refactoring.
  Exit: one Range type used by all layers. `SyntaxToken::range()` and `SyntaxNode::range()` exist in seam.
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
- [ ] **Cheaper `FugueTree::lv_to_position`** — Current impl allocates full visible-items array then linearly scans. Replace with tree walk that counts visible items and exits early when target LV found. No allocation, O(n/2) average. ~20 lines in `event-graph-walker/internal/fugue/tree.mbt`. Bottleneck for incremental remote cache updates (each remote insert calls this).
- [x] **Generic tree libraries** — Extract reusable tree libraries from existing code.
  Why: ProjNode is a rose tree, OrderTree is a B-tree. Both are generic in `T` without codegen (McBride 2001). Supersedes the `zipper-gen` codegen plan.
  Libraries:
  - `rose-zipper[T]` — ✅ Done (`lib/zipper/`, PR #130). `RoseNode[T]`, `RoseCtx[T]`, `RoseZipper[T]`. Immutable/persistent — zipper is the primary API (navigation, focus, modify).
  - `btree[T]` — ✅ Done (`lib/btree/`, PRs #138–#141). Generic B-tree library. Node types, counted navigation, insert/delete with rebalancing, range operations. Cursor/zipper is an internal implementation detail (mutable, ephemeral). Consumer: `OrderTree[T]` (CRDT positioning).
  ProjNode navigation uses direct path arithmetic in `core/proj_zipper.mbt` (`navigate_proj`). The old `lang/lambda/zipper/` (Term-level Huet zipper) was removed in PR #133.
  Exit: `lib/btree` extracted as standalone package, `order-tree/src/` refactored to use it.

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
- [ ] **E2E tests for outline tree panel** — `examples/ideal` outline tree operations (select, collapse, expand, drag-and-drop) have no E2E coverage. Unit tests in `projection/tree_editor_wbtest.mbt` (67 tests) cover the logic, but no browser-level verification exists for the Rabbita-based outline UI.

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
- [x] Parse recovery should produce `Error` nodes, not coerce to `Int(0)`/`Plus` (GitHub #74) — ✅ Done. `syntax_to_proj_node` in `lang/lambda/proj/proj_node.mbt`: unparseable int literals (e.g. overflow) emit `Error("invalid integer literal")`; operand/operator mismatch in `BinaryExpr` emits `Error("missing binary operator")` instead of fabricating `Plus`.
- [x] `parse_to_proj_node` should return `Result` instead of aborting (GitHub #75) — ✅ Done. Lambda and JSON now propagate `LexError` via `raise`, matching Markdown. 807 tests pass.
- [ ] Tighten `ActionRecord` visibility (GitHub #97)
  Exit: `ActionRecord` fields use appropriate visibility modifiers.
- [x] Replace singleton JS FFI export state in `crdt.mbt` with a handle → `SyncEditor` map plus explicit destroy/dispose API
- [x] Split `projection/tree_editor.mbt` into focused files (render model, refresh/reuse logic, UI/edit operations, tree indexes) — ✅ Done. `tree_editor.mbt` (edit ops), `tree_editor_model.mbt` (types + state + constructors), `tree_editor_refresh.mbt` (refresh/reuse/indexes)
- [x] Split `crdt.mbt` into focused FFI files (editor core, undo, presence, relay, websocket) — ✅ Done. Split into 6 files: `crdt.mbt` (core), `crdt_undo.mbt`, `crdt_ephemeral.mbt`, `crdt_relay.mbt`, `crdt_websocket.mbt`, `crdt_projection.mbt`
- [x] Split `projection/text_edit.mbt` (1,348 lines) into focused modules — ✅ Done. Split into `text_edit.mbt` (1,064), `text_edit_rename.mbt` (231), `text_edit_utils.mbt` (51)
- [x] Decompose `text_edit.mbt` into handler chain — ✅ Done (PR #54). 1,064-line match → 96-line router + 8 handler files + `EditMiddleware` trait. Shared helpers extracted (`find_def_index`, `binding_delete_range`). Bug fixes: move-binding scoping, cursor positions, defensive guards.
- [x] Split `editor/ephemeral_hub.mbt` (19 methods) into focused files — ✅ Done. Split into `ephemeral_hub.mbt` (core), `ephemeral_hub_state.mbt` (typed writes), `ephemeral_hub_readers.mbt` (typed reads)
- [ ] DRY seam's three `build_tree` variants (`seam/event.mbt`)
  Why: `build_tree`, `build_tree_interned`, `build_tree_fully_interned` are ~80 lines each of near-identical stack-based tree construction. They differ only in token creation and node wrapping (plain vs interner vs node_interner). Discovered during error handling audit (loom PR #75).
  Exit: shared core function parameterized by token/node creation callbacks; three variants are thin wrappers.

---

## 8b. Handler Chain Follow-ups

**Impact:** Medium | **Effort:** Low-Medium

From SuperOOP analysis and handler chain refactor (PR #54):

- [x] **Term enum extensibility** — ✅ Done. (a) `TermSym` Finally Tagless trait + `replay` in loom submodule. (b) Framework extraction complete (Phases 1–4): `framework/core/` has generic types (NodeId, ProjNode, SourceMap, reconcile); `TreeNode`/`Renderable` traits in `loom/core` with impls in `lambda/ast`; lambda-specific code in `lang/lambda/proj/` and `lang/lambda/edits/`; `projection/` is a re-export facade. Acid test: `framework/core/` has zero `@ast` imports. See PRs #60, #62, #66, #69.
- [ ] **AST transform pipeline** — The `EditMiddleware` trait is ready for composable AST-to-AST transforms (constant folding, dead code elimination, simplification). Each pass becomes a middleware impl that intercepts before `core_dispatch`.
- [x] **Outline keyboard navigation** — ✅ Done (PRs #132, #133). Arrow keys navigate the outline tree via `core/navigate_proj` (path arithmetic on ProjNode). Old Term-level zipper removed; navigation is now generic over any `ProjNode[T]`.
  Plan: `docs/archive/2026-03-29-zipper-keyboard-integration.md`, `docs/archive/2026-03-30-zipper-keyboard-impl.md`
- [ ] **Cache navigation path between keystrokes** to avoid O(n) DFS per keystroke (GitHub #91)
  Exit: path or zipper is cached in editor state and reused across consecutive keystrokes.
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

- [x] Wire ideal editor drag-drop end-to-end (PR #174)
  Done: JSON parser for Drop/StartDrag/DragOver, legality checks (self-drop, descendant-drop), browser event handlers on structure view, readonly guard.

### Follow-ups: Correctness

- [x] **Position detection (Before/After/Inside)**
  Why: v1 hardcodes `"After"`. Users need to control where the node lands.
  Exit: mouse Y within target bounding box determines Before/After/Inside; visual indicator shows landing position.

- [x] **Semantic-aware drop** (PR #179)
  Done: Before/After replaces source with placeholder via `Renderable::placeholder()`, inserts source text from source map. Exchange unchanged. Playwright E2E tests cover all positions.

- [x] **Unit tests for drag-drop JSON parser and legality**
  Why: no test coverage for `StartDrag`/`DragOver`/`Drop` parsing or self-drop/descendant-drop guards.
  Exit: tests in `tree_edit_json_test.mbt` and `text_edit_wbtest.mbt` cover valid payloads, missing fields, bad position strings, self-drop, and descendant-drop.

### Follow-ups: UX

- [x] **Drop indicator line**
  Why: highlighting the whole target block doesn't communicate where the node will land.
  Exit: a visible line appears between nodes during dragover showing the insertion point.

- [x] **Restrict drag initiation to grip handle**
  Why: entire block is draggable, which can interfere with text selection or child interactions.
  Exit: only the grip handle (≡) initiates drag; clicking elsewhere in the block does not start a drag.

### Follow-ups: Block Editor & Shared Contract

- [ ] Prepare drag-and-drop foundations for `examples/block-editor`
  Why: `move_block` only appends as last child; needs `move_before`/`move_after` for sibling reorder.
  Plan: `docs/plans/2026-03-30-editor-drag-drop-foundation.md` (steps 2-3)
  Exit: `block-editor` exposes positioned block moves plus structural render metadata.

- [x] **Shared move contract documentation**
  Done: `docs/development/move-contract.md` — payload shape, position semantics, legality rules, backend execution, drag lifecycle, new-editor checklist.

- [ ] **Convergence tests for concurrent drag-drop**
  Why: concurrent relocations across CRDT peers need convergence guarantees.
  Exit: property tests covering concurrent drop, undo grouping after relocation, and reconciliation.

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
- [x] **Markdown Canopy integration** — ✅ Done (PRs #115, #117, #121, #123). `lang/markdown/` with projection + 7 edit ops, `examples/web/markdown.html` with raw/block/preview modes.
  Plan: `docs/archive/2026-04-04-markdown-block-editor-design.md`

---

## 13. Pretty-Printer Engine

**Impact:** High | **Effort:** Done (engine) / Medium (integration)

- [x] **Wadler-Lindig engine** — ✅ Done (PR #106). `canopy/pretty/` with generic `Layout[A]`, suffix-aware group flattening, two renderers (`render_string`, `render_spans`), 7 property-based tests.
  Design: `docs/archive/2026-03-31-pretty-printer-design.md`
  Impl: `docs/archive/2026-03-31-pretty-printer-impl.md`
- [x] **Lambda TermSym integration** — ✅ Done. `PrettyLayout` wrapper with precedence tracking in `lang/lambda/proj/pretty_layout.mbt`.
- [x] **JSON pretty-printing** — ✅ Done. `json_to_layout` with string escaping in `lang/json/proj/pretty_layout.mbt`.
- [ ] **Wire into REPL** — Use `render_string` in `cmd/main/` for formatted AST output.
  Exit: REPL displays width-aware formatted expressions.
- [x] **Wire into web editor via ViewNode bridge** — ✅ Done (PR #109). `layout_to_view_tree` in `protocol/` converts `Layout[SyntaxCategory]` → per-line ViewNode tree with token_spans. HTMLAdapter renders syntax-highlighted lines. Property tests validate roundtrip and span coverage.
  Architecture: `docs/architecture/multi-representation-system.md`
  Design: `docs/archive/2026-04-02-pretty-printer-viewnode-bridge-design.md`
- [ ] **Structure-format projections from semantic model** — Rather than generalizing DOT/JSON/S-expr as tree-annotation IRs, build projections that query the semantic model (egglog knowledge base + incr reactive graph). Current DOT rendering needs `Resolution` (a semantic fact about scope), not a tree annotation. The right answer is richer semantics, not a better annotation mechanism.
  Why: the structure-format problem is "how to represent program meaning so projections render from it," not "how to annotate trees." See vision doc.
  Architecture: `docs/architecture/vision-projectional-bridge.md`, `docs/architecture/multi-representation-system.md`
  Research: Trees That Grow (Najd 2017), Cofree comonads, Attributed Grammars, MLIR dialects — each addresses a fragment of this. The semantic model approach (egglog) subsumes them.
  Prerequisite: evaluator Phase 1 (egglog relational evaluation) ✅ Done.
  Exit: at least one structure-format projection (DOT or typed view) queries the semantic model instead of threading ad-hoc data.

### Concrete semantic projection candidates

- [ ] **Scope-colored tree view** — Color variables by binding status (bound/free/shadowed) in the structural tree view. Resolution already exists and is used for DOT; this flows it through the ViewNode protocol instead of an ad-hoc path. First projection that delivers semantic data through the framework.
  Why: lowest effort, proves the semantic-data-through-protocol pattern. If Resolution flows through ViewNode cleanly, types and eval results follow the same path.
  Semantic data: Resolution (available now)
  Exit: tree view shows bound variables colored by binder, free variables highlighted as warnings.
- [x] **Live inline evaluation** — ✅ Done (feature/live-inline-eval branch). Pretty-print view shows `→ 10` / `→ ‹closure›` via Layout post-processing. Structural view has `ViewAnnotation` on nodes. Reactive via `@incr.Memo`. 17 tests.
  Plan: `docs/plans/2026-04-03-live-inline-eval-design.md`, `docs/archive/2026-04-03-live-inline-eval-impl.md`
- [ ] **Eval error/suppression UX** — Eval annotations show semantic errors (e.g., `→ ‹unbound: x›`) in the structure panel while the Error panel stays empty (Incomplete/ParseError are suppressed as "expected during editing"). This is technically correct but confusing: two panels show contradictory information. Consider surfacing eval-level semantic errors in the Error panel, or adding a visual cue that distinguishes "eval stuck" from "no errors."
  Exit: users are not confused by one panel showing errors while another shows none.
- [ ] **Type annotations overlay** — Show inferred types next to bindings and expressions. Egglog typing rules already exist in `loom/egglog/examples/lambda/`.
  Why: types are the canonical "explicit semantics" — they make invisible meaning visible. First projection requiring the egglog semantic model.
  Semantic data: type inference (egglog Phase 1 ✅ Done)
  Prerequisite: evaluator Phase 1 ✅ Done
  Exit: bindings show inferred types (e.g., `double : Int → Int`).
- [ ] **Πe extension** — Add `Choice` constructor and cost-factory resolver for more expressive layout decisions.
  Exit: layout engine supports user-defined cost functions per "A Pretty Expressive Printer" (OOPSLA 2023).

---

## 14. EditorProtocol — Framework-Agnostic Integration Layer

**Impact:** High | **Effort:** High

- [x] Framework-agnostic integration layer to eliminate duplicated TS logic — ✅ Done (Phases 0-6). Protocol types (`ViewPatch`, `ViewNode`, `UserIntent`), ViewUpdater, 3 adapters (HTML, CM6, PM). `examples/web`, `examples/ideal`, `examples/prosemirror`, `examples/demo-react` all migrated.
  Plan: `docs/plans/2026-04-01-editor-protocol-design.md`
- [x] Markdown block editor (Phase 7) — ✅ Done (PRs #115, #117, #121, #123). Three modes (raw/block/preview), 7 edit ops, BlockInput + MarkdownPreview adapters.
  Plan: `docs/archive/2026-04-04-markdown-block-editor-design.md`
- [x] **ZWSP cleanup for empty blocks** — `markdown_export_text()` FFI strips ZWSP at export boundary. `block-input.ts` strips on display/edit/commit. `compute_merge_with_previous` strips on merge. ZWSP remains as internal parser placeholder only. Long-term fix: Container per-block text (§16).
  Known edge: fenced code blocks containing only U+200B on a line would match the strip pattern. Eliminated by Container per-block text migration (§16).
  Exit: No `\u200B` in exported Markdown text.

---

## 15. Lambda Evaluator

**Impact:** Medium | **Effort:** Medium

- [x] **Phase 2: Direct evaluator** — ✅ Done (PR loom#69). Tree-walking `eval` in `loom/examples/lambda/src/eval/`. 31 tests, all Term variants, fuel-limited divergence. Educational comments.
  Plan: `docs/archive/2026-04-02-lambda-evaluator-phase2-impl.md`
- [x] **Phase 0: Egglog API extensions** — ✅ Done (egglog PR #5). Added `Database::scan` and `Database::row_count`. 5 tests.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 0
- [x] **Phase 1: Egglog relational evaluator** — ✅ Done (egglog PR #6). 17 Datalog rules + MoonBit bridge in `loom/egglog/examples/lambda-eval/`. Demand-driven evaluation, partial evaluation (holes), InEnv→TypeEnv rename, composition with typing. 25 tests.
  Plan: `docs/archive/2026-04-02-lambda-evaluator-phase1-impl.md`
- [ ] **Phase 3: Editor integration** — Wire Tier 1 + Tier 2 into incr reactive graph with batch escalation.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 3
  Exit: Memo[EvalResult] per definition, Tier 2 batch escalation for incomplete programs.
- [ ] **Phase 3b: Incremental egglog–incr unification** — Make egglog Database a persistent incr cell with incremental fact insertion/retraction, instead of rebuilding from scratch each Memo recompute. Currently egglog creates a throwaway `@incr.Runtime` per `Saturate` call — no reactive connection between egglog facts and incr Memos. Requires: persistent Database across revisions, fact retraction, delta-driven escalation from Tier 1 Stuck results.
  Why: Phase 3 rebuilds the entire egglog Database on every edit. Fine for small programs but blocks the incremental compiler vision at scale.
  Depends on: Phase 0 + Phase 1 (validates the relational model first).
  Exit: Tier 2 re-derives only affected `Eval` facts when a single `Term` changes, not full re-seed.

---

## 16. Unified Container (CRDT)

**Impact:** High | **Effort:** High

- [x] **Phase 0: Rename** — ✅ Done. TreeDoc→TreeState, TreeDocError→TreeError.
- [x] **Phase 1: Container + tree ops** — ✅ Done. `container/` package with `Document` struct. Block editor switched from `@tree.TreeState` to `@container.Document`. 25 tests.
  Plan: `docs/archive/completed-phases/2026-03-29-container-phase1-tree.md`
- [x] **Phase 2: Per-block text (Path A — shared global LVs)** — ✅ Done (PR #112, event-graph-walker PR #18). `TextBlock` wraps per-block `FugueTree[String]` with shared global LVs. `Document::insert_text/delete_text/replace_text/get_text/text_len`. Block editor migrated from `TextState` map to Document text ops. 20 new tests, `next_version()` refactoring. Codex-reviewed.
  Plan: `docs/archive/completed-phases/2026-04-03-container-phase2-text.md`
- [x] **Internal text pipeline refactoring** — ✅ Done (PR #134, event-graph-walker PR #21). Split Lv (replica-local causal handle) from ItemId (per-block Fugue identity), moved fugue storage to dense ItemId indexing, and cleaned merge/delete bookkeeping to target canonical versions instead of assuming LV=ItemId.
  Plan: `docs/archive/completed-phases/2026-04-06-container-text-sync-refactor.md`
- [x] **Phase 3: Unified sync** — ✅ Done (PR #134, event-graph-walker PR #21). Two peers converge on a block document with document-level sync export/import, causal-parent preservation, out-of-order buffering, incremental diff export, and BlockDoc integration.
  Design: `docs/plans/2026-03-29-container-design.md` §Phase 3
- [x] **Phase 4: Document-level undo** — ✅ Done (canopy PR #187, egw PR #28, 2026-04-17). Model I undo/redo + transactions on Document; undo groups span tree + text edits.
  Design: `docs/plans/2026-03-29-container-design.md` §Phase 4

---

## 17. Incremental Parsing — Convergence Relex

**Impact:** Medium | **Effort:** Low-Medium

- [x] **Convergence relex** — ✅ Done. Mode-aware incremental re-lex with convergence checking in `loom/loom/src/core/mode_lexer.mbt`. Incremental now faster than full parse at all scales (0.85-0.91x). 4 convergence tests in `mode_relex_wbtest.mbt`.
  Plan: `docs/archive/completed-phases/2026-04-02-convergence-relex-impl.md`

---

## 18. Example App Consolidation

**Impact:** Medium | **Effort:** High

- [x] **Archive `examples/rabbita/`** — ✅ Done. Removed from active tree, Cloudflare deploy config removed, doc references updated to point to `examples/ideal/`.
  Exit: `rabbita/` removed from active tree, no broken references.
- [x] **Migrate `demo-react/` E2E coverage to `web/`** — ✅ Done. PR #145 added 28 Playwright tests to `web/` (6 lambda + 10 JSON + 12 markdown). Single-editor tests already covered; collaborative demo tests are not portable (feature doesn't exist in `web/`).
  `demo-react/` stays — its unique value is the per-agent undo/redo collaborative demo (Alice/Bob dual editor with sync, operation logging). Not a duplicate of `web/`.

- [x] **E2E tests in CI** — ✅ Done. Both `web/` (28 tests) and `demo-react/` (25 tests) run in CI as `web-e2e` and `demo-react-e2e` jobs, gated by `All Checks Passed`. Markdown flaky tests fixed (all `waitForTimeout` replaced with auto-waiting assertions).

App inventory:

| App | Purpose |
|-----|---------|
| `web/` | Canonical demo — vanilla JS, lambda + JSON + markdown editors |
| `demo-react/` | Collaborative demo — per-agent undo/redo, Alice/Bob sync |
| `ideal/` | Flagship full-featured editor (Rabbita) |
| `prosemirror/` | Reference integration — PMAdapter proof |
| `canvas/` | Future infinite canvas app |
| `block-editor/` | Block editor demo (pending Phase 7) |
| `relay-server/` | Signaling server infrastructure |

---

## 19. Documentation & Demo Polish

**Impact:** High (first impressions) | **Effort:** Low-High

### Medium effort (no new features needed)

- [x] **Record a GIF of the current editor** — pretty-printer + syntax highlighting + tree update is already visual. Embed at top of README. Imperfect GIF now is better than perfect GIF later.
  Exit: README has a GIF that shows the editor experience in under 5 seconds.
- [ ] **Promote product vision visibility** — add `VISION.md` symlink at repo root pointing to `docs/architecture/product-vision.md`, or expand README "Bigger Picture" section with the cold pitch text.
  Exit: a visitor who reads only the README encounters the product vision, not just the framework description.
- [ ] **Unify voice across architecture docs** — README and product-vision speak product language; projectional-bridge and structure-format-research speak academic language. One editing pass to make them consistent.
  Exit: all architecture docs feel like they were written by the same person for the same audience.

### Requires new features

- [x] **Live inline evaluation display** — makes the GIF compelling ("→ 10" appearing as you type). See §13 concrete projection candidates.
  Exit: demo shows evaluation results inline while typing.
- [x] **Scope-colored compact tree view (Phase 1)** — compact inline layout, full binder coloring, bold defs / regular usages, selection-driven binder↔usage highlighting with dimming.
  Plan: `docs/plans/2026-04-04-scope-colored-tree-view-design.md`
  Exit: compact inline view with binder colors, def/use font weight, selection highlights binder + usages.
- [ ] **Scope-colored tree view — smart tooltip (future)** — small tooltip popup on selection showing scope info (binding site, usage count). Smart positioning to avoid occluding relevant text.
  Depends on: Phase 1 compact view.
  Exit: tooltip appears on selection, never hides related nodes.
- [x] **Deploy updated web demo** — ✅ Done. README links to `canopy-ideal.pages.dev` (full-featured editor). `canopy-lambda-editor.pages.dev` also live for the canonical `web/` demo.
  Exit: live demo link in README shows the current canonical `web/` editor.

---

## 20. Editor Framework Decoupling

**Impact:** Medium | **Effort:** Medium | **Status:** Phase 2 Done

- [x] **Phase 1: Extract lambda standalone functions** — ✅ Done (PR #135). Moved `build_lambda_projection_memos` to `lang/lambda/flat/`, created `lang/lambda/eval/` package with `EvalResult`, `eval_term`, `build_eval_memo`, annotation helpers. Removed `dowdiness/lambda/eval` from editor imports.
- [x] **Phase 2: LanguageCapabilities[T]** — ✅ Done (PR #146). `LanguageCapabilities[T]` closure-based callbacks in editor, `LambdaCompanion` + `new_lambda_editor()` factory in `lang/lambda/companion/`. `editor/moon.pkg` has zero lambda imports; `SyncEditor[T]` has zero lambda-typed fields. `DropPosition` moved to `core/types.mbt`. `apply_span_edits()` public API added.
  Plan: `docs/plans/2026-04-07-language-capabilities-design.md`
- [ ] **Extract ephemeral subsystem** — Move ~9 files / ~1500 lines (EphemeralStore, EphemeralHub, EphemeralValue, presence types, cursor view, encoding) from `editor/` to its own package.
  Why: Zero dependency on editor concepts. Self-contained collaboration primitive with own binary protocol, encoding, and timeout logic.
  Exit: `editor/` imports ephemeral as a dependency; ephemeral has its own test suite.
- [ ] **Unify sync protocol** — `editor/sync_protocol.mbt` and `relay/wire.mbt` independently encode/decode the same binary wire protocol (version 0x02, same message types).
  Why: Duplication risks protocol drift between client and server.
  Exit: Shared protocol definition used by both editor and relay.

---

## 22. Generic Tree Libraries

**Impact:** Medium | **Effort:** Medium | **Status:** Phase 2 Done

- [x] **Phase 1: Rose tree zipper** — ✅ Done (PR #130). `lib/zipper/` standalone module (`dowdiness/zipper`) with `RoseNode[T]`, `RoseCtx[T]`, `RoseZipper[T]`. 36 tests (33 blackbox + 3 @qc properties), full API in `pkg.generated.mbti`.
  Plan: `docs/plans/2026-04-07-rose-tree-zipper-impl.md`
  Design: `docs/superpowers/specs/2026-04-07-rose-tree-zipper-library-design.md`
- [x] **ProjNode integration** — ✅ Done (PR #133). `core/proj_zipper.mbt` provides `navigate_proj[T]` via path arithmetic on ProjNode (no RoseZipper dependency in core/). Old `lang/lambda/zipper/` (Term-level Huet zipper) removed. 24 whitebox + 7 E2E tests.
- ~~**Annotation trait**~~ — Dropped. Annotations are a tree-definition concern, not a zipper concern.
- [x] **Phase 2: Generic B-tree library** — ✅ Done (PR #138). `lib/btree/` standalone module (`dowdiness/btree`). `BTreeNode[T]`, `BTree[T]`, `BTreeElem` super trait over rle's Spanning+Mergeable+Sliceable. High-level API: `mutate_for_insert/delete` with callbacks, `seek`, `view`. 22 whitebox tests. `order-tree` uses `@btree.BTreeElem` bounds.
  Plan: `docs/plans/2026-04-08-generic-btree-library.md`
- [x] **Phase 2b: Full type migration** — ✅ Done (PR #139 + order-tree#5). OrderTree wraps @btree.BTree[T]. insert_at/delete_at delegate via callbacks. -1,304 lines, 5 duplicate files deleted. 79 tests (12 @btree-internal tests moved out).
  Plan: `docs/plans/2026-04-09-btree-type-migration.md`
- [x] **Phase 2c: Range delete extraction** — ✅ Done. Moved 20 functions (493 lines) from order-tree to `lib/btree/walker_range_delete.mbt`. Added `descend_rightmost`, `plan_delete_range` to pub API. 15 tests migrated + 7 test-debt tests added (LeafContext, descent boundary, ensure_min, propagate_node_splice). order-tree walker_range_delete.mbt deleted (-584 lines).
  Plan: `docs/archive/2026-04-09-btree-range-delete-extraction.md`
- [x] **Phase 2d: API narrowing** — ✅ Done (PR #141 + order-tree#7). `BTree::delete_range`, lazy cursor-based `iter`, 15 pub fns + 5 types made private. Fixed underfull propagation, boundary merge, boundary subtree sibling preservation. Fallback rebuild for underfull boundary subtrees. 3 property-based tests.
  Plan: `docs/plans/2026-04-09-btree-api-narrowing.md`
- [x] **Phase 2e: Splice promotion** — ✅ Done (PR #144). O(n) fallback replaced with O(log n) chain repair (`repair_at_boundary` with `BoundaryKind` enum). Fixes: array aliasing (shallow-copy), unary root (insertion-site repair), min_degree > 2 (while loop). `from_sorted` bulk constructor added. Property tests at min_degree 2/3/5. delete_range benchmarks added.
  Spec: `docs/archive/2026-04-11-btree-splice-promotion-design.md`
- [x] **event-graph-walker integration** — ✅ Done (egw PR #23). `impl @btree.BTreeElem for VisibleRun` in `internal/document/visible_run.mbt`.

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
| 11 | Generic tree libraries (`rose-zipper[T]`, `btree[T]`) | Medium | Medium | Rose tree → zipper is the API; B-tree → the tree is the API (cursor internal) |
| 12 | Code cleanup | Medium | Medium | Mostly done |
| 14 | EditorProtocol integration layer | High | High |
| 20 | Editor framework decoupling (LanguageCapabilities[T]) | Medium | Medium | Phase 1 done (PR #135), Phase 2 planned |
