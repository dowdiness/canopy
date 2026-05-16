# Project TODO

Active backlog for Canopy — the incremental projectional editor with CRDT
collaboration. Only currently-open items are listed. Completed work is kept
for historical context in the snapshot linked at the bottom.

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

- [ ] If wasm support is added later, add a dedicated wasm implementation and CI job.
  Why: current supported targets are native and JS only.
  Exit: wasm build runs in CI and is documented as supported.

- [ ] Add `npx tsc --noEmit` CI job for `examples/{web,prosemirror,demo-react}`.
  Why: no CI job currently type-checks the examples, so regressions in the `@canopy/editor-adapter` package or example sources go unnoticed until a human runs tsc locally (cf. the 28 errors that silently accumulated between the Stage 5 adapter move and PR #211).
  Exit: a CI job runs `tsc --noEmit` per example and blocks merge on failure.

- [ ] Reduce CRDT JS bundle size for `index.html` / `memo.html` (lambda bundle is 546 kB, 46 kB over 500 kB threshold).
  Why: large bundle impacts initial page load for web editors.
  Plan: `docs/plans/2026-04-18-crdt-bundle-split.md`
  Status: Per-entry split landed (PRs #195 / #196). Measured sizes: json 277 kB, markdown 246 kB, lambda 546 kB.
  Follow-ups per plan §7: dynamic import of LLM (−19 kB), lazy egglog Tier-2, lazy lambda typecheck, or revise the budget based on real per-page data.
  Exit: `index.html` / `memo.html` bundle under 500 kB ungzipped.

---

## 2. Collaboration Features

- [ ] Complete WebSocket client integration.
  Why: the wire protocol exists, but the supported browser-side integration path is not yet treated as a finished, documented workflow.
  Plan: `docs/plans/2026-03-29-websocket-client-integration.md`
  Exit: one canonical client flow is implemented, documented, and validated.

- [ ] Implement `SyncRequest`/`SyncResponse` recovery so malformed/incompatible `CrdtOps` do not leave peers diverged silently.
  Why: now unblocked — container Phase 3 (unified sync) shipped via egw#21, so retry/buffering/failure semantics can be aligned against the Document-level sync boundary.
  Plan: `docs/plans/2026-03-29-sync-recovery-followup.md`
  Exit: malformed/incompatible ops trigger defined recovery (retry, buffering, or surfaced failure) against the Document sync boundary rather than silent divergence.

---

## 3. Incremental Parsing Optimization

- [ ] Flat edits on tiny nodes — JSON 20-member flat edit is 2× batch.
  Why: per-node reuse overhead exceeds parse cost for 3-token members. Grammar-level tradeoff, not a framework bug.
  Options: (a) accept for tiny structures, (b) batch-reparse fallback when reuse count is zero, (c) amortized threshold that learns from reuse hit rate. Needs a decision (tracked in `docs/decisions-needed.md`).

- [ ] Markdown Token payload removal.
  Why: `HeadingMarker(Int)`, `CodeFenceOpen(Int, String)`, `Text(String)`, `CodeText(String)` still carry payloads. Some are semantic (heading level, info string), not just raw text — needs design thought on how to derive from source.
  Exit: markdown Token is payload-free where possible, semantic info extracted at point-of-use.

- [ ] `SyntaxNode::find[K : ToRawKind]` generic method (low priority).
  Why: 16 `find_token(...to_raw())` callsites remain, but views pattern + `token_text()` already reduce the ergonomic pain. Nice-to-have polish.
  Exit: `pub fn[K : ToRawKind] SyntaxNode::find(self, kind : K) -> SyntaxToken?` in seam.

- [ ] `lib/range` foundational package.
  Why: Range (`{ start: Int, end: Int }`) is defined twice (loom/core, event-graph-walker/text) and represented implicitly in seam. A shared `lib/range` package at the bottom of the dependency graph would: (a) unify the duplicate definitions, (b) enable `SyntaxToken::range()` / `SyntaxNode::range()` in seam, (c) retire rle's `FromRange` trait.
  Touches: lib/range (new), seam, loom/core, rle, canopy/core, event-graph-walker/text. Cross-submodule refactoring.
  Exit: one Range type used by all layers.

- [ ] Unify Token and SyntaxKind into a single enum (rowan style).
  Why: Token and SyntaxKind overlap — every Token variant has a corresponding SyntaxKind variant. Two independent `to_raw()` impls with hardcoded integers can desynchronize.
  Prerequisite: payload-free Token enums (done). Practical trigger: loomgen, which can generate the single enum from a grammar definition.
  Exit: `ParserContext[SyntaxKind, SyntaxKind]` — one type for both T and K.

---

## 4. Rabbita Projection Editor Performance

- [ ] Split and optimize the `handle_text_intent` browser edit path.
  Why: the 2026-05-14 real browser phase benchmark shows the large edit path is dominated by `handleTextIntent` (`p95` 14.7 ms on a 7,284-char example). Rabbita `refreshTotal` is only `p95` 1.6 ms, `TreeEditorState::refresh` is `p95` 0.4 ms, and `buildScopeMap` is `p95` 0.2 ms, so projection refresh is not the first bottleneck.
  Exit: browser-level phase timings split `handle_text_intent` into edit translation, sync-editor mutation, and state publication, and the large-edit text-change `p95` is comfortably below the single-frame compute budget.

- [ ] Remove redundant render-time tree scans (e.g. sidebar selection lookup from the full rendered tree).
  Why: low priority — full frame is <1 ms, but the scans are still wasted work.
  Exit: render path does not scan the full tree for already-known state.

---

## 5. Memory & Scalability

- [ ] Implement lazy loading for 100 k+ operation documents (load causal graph skeleton, hydrate on demand).

- [ ] Benchmark `FugueTree` whole-list traversal after the early-exit `lv_to_position` change.
  Why: event-graph-walker#38 removes `lv_to_position`'s full `get_visible_items()` allocation by sharing an early-exit traversal helper, but full-list callers such as `get_visible_items()` / `to_text()` may have different constant-factor tradeoffs.
  Exit: release benchmarks cover `get_visible_items()` and `to_text()` on representative trees; keep the shared traversal helper only if whole-list callers do not regress materially, otherwise restore a direct collection path while preserving early exit for point lookup.

- [ ] Consider a public allocation-free `FugueTree` visible traversal API.
  Why: `get_visible_items()` must materialize the full visible sequence by contract. A visitor/iterator-style API would let callers that only need a point query, fold, or early-exit search reuse canonical tree order without allocating an array.
  Exit: either expose a documented `visit_visible` / `find_visible` style API and migrate suitable internal callers, or document why the private traversal helper is sufficient for now.

- [ ] Add visible-order indexing for FugueTree / Document LV-position queries.
  Why: early-exit traversal avoids allocation but remains O(n) worst-case. A maintained visible-order index, B-tree, or reverse LV→position map could make `position_to_lv` and `lv_to_position` near O(log n), but must stay coherent across insert/delete/undelete, merge, and retreat paths.
  Exit: benchmarked design/prototype with clear mutation invariants, or a written decision that the complexity is not justified by measured workloads.

---

## 6. Testing Gaps

- [ ] E2E tests for outline tree panel.
  Why: `examples/ideal` outline tree operations (select, collapse, expand, drag-and-drop) have no E2E coverage. Unit tests in `projection/tree_editor_wbtest.mbt` (67 tests) cover the logic, but no browser-level verification exists for the Rabbita-based outline UI.

---

## 7. Code Cleanup

- [ ] Upgrade `rle` consumers to `dowdiness/rle` 0.2.1 and constructor-style APIs.
  Why: the stale `feature/container-phase3-blockdoc-sync` branch only bumped the `rle` submodule pointer to v0.2.1. The actual consumer modules still pin `dowdiness/rle` 0.2.0, and rle 0.2.1 deprecates `Rle::new()` / `PrefixSums::new()`.
  Exit: `lib/btree`, `event-graph-walker`, and `order-tree` resolve the intended `dowdiness/rle` version, downstream code uses custom constructors such as `Rle()` / `PrefixSums()`, and CI passes.

- [ ] Extend the aggregator-trim audit from `lang/{lambda,json}` (PR #265) to the rest of the canopy module.
  Why: `moon ide analyze` flagged ~55 truly-unused `pub` fns across `core/`, `protocol/`, `projection/`, and `editor/` — the same drift pattern PR #265 fixed for the language facades. Higher caller-miss risk than #265 because these packages have many more dependents.
  Exit: each candidate verified via cross-grep over `examples/{ideal,canvas,block-editor}/`, `ffi/*/moon.pkg`, and every in-repo importer (the example subprojects are separate `moon.mod.json` modules and are NOT visible to workspace-scoped `moon ide`). Either trimmed with rationale in commit message, or kept with a note explaining why it must remain public. `moon test` + every per-module test in `.github/workflows/ci.yml` still pass.

- [ ] DRY seam's three `build_tree` variants (`seam/event.mbt`).
  Why: `build_tree`, `build_tree_interned`, `build_tree_fully_interned` are ~80 lines each of near-identical stack-based tree construction, differing only in token creation and node wrapping. Discovered during error handling audit (loom PR #75).
  Exit: shared core function parameterized by token/node creation callbacks; three variants are thin wrappers.

---

## 8. Handler Chain Follow-ups

- [ ] AST transform pipeline.
  Why: the `EditMiddleware` trait is ready for composable AST-to-AST transforms (constant folding, dead code elimination, simplification). Each pass becomes a middleware impl that intercepts before `core_dispatch`.

- [ ] Cache navigation path between keystrokes to avoid O(n) DFS per keystroke (GitHub #91).
  Exit: path or zipper is cached in editor state and reused across consecutive keystrokes.

---

## 9. Ideal Editor

- [ ] Structure mode — test and polish PM block editor, verify lazy-loading works.
  Note: completion state is unclear; decision pending in `docs/decisions-needed.md`.

- [ ] Graphviz SVG theming — SVG uses hardcoded `Arial` from submodule; needs `pub(all) struct SvgConfig` to customize.

- [ ] Grammar: interleaved let/expr.
  Why: `Module` AST supports `ModuleItem` in parser already, but `FlatProj` storage change caused 2× regression from MoonBit enum boxing.
  Alternative: add helper methods on existing `FlatProj` for interleaved views. Decision pending in `docs/decisions-needed.md`.

- [ ] Inspector — Intent + Patch panels. *Part of Inspector traceability workstream.*
  Why: existing inspector shows the State layer (ProjNode tree, via `view_outline` + `view_inspector`) and the CRDT-op layer (Lamport-version causal graph, via `view_history`). The layers between them — user actions (`GenericTreeOp`) and text patches (`SpanEdit`) — are invisible. These are exactly what's needed for debugging "why did this edit produce that text," teaching the projection→patch translation when bringing up a new language, and reproducing collaborative bugs from clean traces. Should consume §15's `Show`-unification work when both are implemented (TODO 2 can ship first with ad-hoc rendering, but that deepens the debt §15 removes).
  Exit:
  - Intent panel: scrollable log of recent `GenericTreeOp`s, each row uses `op.to_string()` (verb-first label like `"Drop(#11→#12 After)"`).
  - Patch panel: scrollable log of recent `SpanEdit`s with back-reference to producing `GenericTreeOp`, each row uses `edit.to_string()` (e.g. `"@25 -3 +«add 3 5»"`).
  - Both panels live in `view_bottom.mbt` (new tab) or a new view file alongside outline/inspector/history.

- [ ] Wire `SourceMap` query API into editor click-path + fix ordering contract. *Part of Inspector traceability workstream.*
  Why: `core/source_map.mbt::SourceMap::nodes_at_position` and `SourceMap::nodes_in_range` are property-tested (`core/source_map_properties_wbtest.mbt`) but unconsumed by production code. Click-path in `examples/ideal/main/view_editor.mbt` reimplements similar text-position→node logic inline. Additionally, `nodes_at_position` documents "outermost to innermost" ordering but returns `Map.keys().to_array()` — ordering is not guaranteed, latent contract bug if any consumer ever depends on nesting order.
  Exit:
  - `SourceMap::nodes_at_position` returns guaranteed outermost→innermost order (sort by `(end - start)` descending) with a property test pinning the contract.
  - Click-path in `view_editor.mbt` consumes `nodes_at_position`.
  - Selection-extend command consumes `nodes_in_range`.
  - `SourceMap::rebuild` annotated as recovery API (see comment in source); not bundled into this TODO's exit since no UI consumer is currently committed.

---

## 10. Editor Drag-and-Drop Follow-ups

- [ ] Prepare drag-and-drop foundations for `examples/block-editor`.
  Why: `move_block` only appends as last child; needs `move_before`/`move_after` for sibling reorder.
  Plan: `docs/plans/2026-03-30-editor-drag-drop-foundation.md` (steps 2-3)
  Exit: `block-editor` exposes positioned block moves plus structural render metadata.

- [ ] Convergence tests for concurrent drag-drop.
  Why: concurrent relocations across CRDT peers need convergence guarantees.
  Exit: property tests covering concurrent drop, undo grouping after relocation, and reconciliation.

---

## 11. Multi-Language Support

- [ ] JSON FlatProj optimization — 1000-member objects at 28 ms exceed 16 ms budget. Add incremental per-member derivation when needed.

- [ ] loomgen design update.
  Why: update `docs/design/07-loomgen-design.md` with learnings from lambda + JSON + markdown. Three real examples now inform the generator.

---

## 12. Pretty-Printer Engine

- [ ] Wire into REPL — use `render_string` in `cmd/main/` for formatted AST output.
  Exit: REPL displays width-aware formatted expressions.

- [ ] Structure-format projections from semantic model.
  Why: the structure-format problem is "how to represent program meaning so projections render from it," not "how to annotate trees."
  Architecture: `docs/architecture/vision-projectional-bridge.md`, `docs/architecture/multi-representation-system.md`
  Prerequisite: evaluator Phase 1 (egglog relational evaluation) ✅ Done.
  Exit: at least one structure-format projection (DOT or typed view) queries the semantic model instead of threading ad-hoc data.

- [ ] Scope-colored tree view — color variables by binding status (bound/free/shadowed).
  Why: lowest effort, proves the semantic-data-through-protocol pattern. If Resolution flows through ViewNode cleanly, types and eval results follow the same path.
  Semantic data: Resolution (available now).
  Exit: tree view shows bound variables colored by binder, free variables highlighted as warnings.

- [ ] Scope-colored tree view — smart tooltip (future).
  Why: small tooltip popup on selection showing scope info (binding site, usage count) with smart positioning.
  Depends on: Phase 1 compact view (shipped).
  Exit: tooltip appears on selection, never hides related nodes.

- [ ] Eval error/suppression UX.
  Why: eval annotations show semantic errors (e.g., `→ ‹unbound: x›`) in the structure panel while the Error panel stays empty. Two panels show contradictory information.
  Exit: users are not confused by one panel showing errors while another shows none.

- [ ] Type annotations overlay — show inferred types next to bindings and expressions.
  Why: types are the canonical "explicit semantics." First projection requiring the egglog semantic model.
  Semantic data: type inference (egglog Phase 1 ✅ Done).
  Exit: bindings show inferred types (e.g., `double : Int → Int`).

- [ ] Πe extension — add `Choice` constructor and cost-factory resolver for more expressive layout decisions.
  Exit: layout engine supports user-defined cost functions per "A Pretty Expressive Printer" (OOPSLA 2023).

---

## 13. Lambda Evaluator

- [ ] Phase 3: Editor integration — wire Tier 1 + Tier 2 into incr reactive graph with batch escalation.
  Plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` §Phase 3
  Exit: Memo[EvalResult] per definition, Tier 2 batch escalation for incomplete programs.

- [ ] Phase 3b: Incremental egglog–incr unification — make egglog Database a persistent incr cell with incremental fact insertion/retraction, instead of rebuilding from scratch each Memo recompute.
  Why: Phase 3 rebuilds the entire egglog Database on every edit. Fine for small programs but blocks the incremental compiler vision at scale.
  Depends on: Phase 0 + Phase 1.
  Exit: Tier 2 re-derives only affected `Eval` facts when a single `Term` changes, not full re-seed.

---

## 14. Documentation & Demo Polish

- [ ] Promote product vision visibility — add `VISION.md` symlink at repo root pointing to `docs/architecture/product-vision.md`, or expand README "Bigger Picture" with the cold pitch text.
  Exit: a visitor who reads only the README encounters the product vision, not just the framework description.

- [ ] Unify voice across architecture docs.
  Why: README and product-vision speak product language; projectional-bridge and structure-format-research speak academic language. One editing pass to make them consistent.
  Exit: all architecture docs feel like they were written by the same person for the same audience.

---

## 15. Editor Framework Decoupling

- [ ] Route inspector kind-labels through `Show`. *Part of Inspector traceability workstream.*
  Why: `examples/ideal/main/view_outline.mbt::kind_of()` and `view_inspector.mbt` each implement their own kind→label classifier, hardcoding lambda-specific syntax ("λ" prefix, "App", "let", "if") in framework views. Adding a new language requires editing per-view classifiers. Existing `Show` impls on `core/proj_node.mbt::ProjNode[T]`, `core/types.mbt::GenericTreeOp`, and `core/types.mbt::SpanEdit` are stubs delegating to `@debug.to_string` (verbose dump, not a short label) with no consumers.
  Exit:
  - Tree-row labels in `view_outline` use `node.to_string()` — consumes real `Show for ProjNode[T]` producing e.g. `"#9 App [25..47]"`.
  - Kind chips in `view_inspector` use `node.kind.to_string()` — consumes existing `Show for Term`/`JsonValue` (already real, no stubs) producing e.g. `"App"`.
  - `view_outline::kind_of()` and any duplicate per-view classifier deleted.
  - Adding a new language touches only the language's `Show for Kind` impl, not framework views.

- [ ] Extract ephemeral subsystem — move ~9 files / ~1500 lines (EphemeralStore, EphemeralHub, EphemeralValue, presence types, cursor view, encoding) from `editor/` to its own package.
  Why: zero dependency on editor concepts. Self-contained collaboration primitive with own binary protocol, encoding, and timeout logic.
  Exit: `editor/` imports ephemeral as a dependency; ephemeral has its own test suite.

- [ ] Unify sync protocol — `editor/sync_protocol.mbt` and `relay/wire.mbt` independently encode/decode the same binary wire protocol (version 0x02, same message types).
  Why: duplication risks protocol drift between client and server.
  Exit: shared protocol definition used by both editor and relay.

---

## 16. Unicode Text Correctness

GitHub issue: [#216](https://github.com/dowdiness/canopy/issues/216).
Steps 1, 3, 4 shipped (#239, #241, #242). **Step 2 shipped** in
[#251](https://github.com/dowdiness/canopy/pull/251) — the moji
library (`lib/moji/`, [#250](https://github.com/dowdiness/canopy/issues/250))
landed Phases 1-3 (UCD 15.1: 1187/1187 GraphemeBreakTest +
1826/1826 WordBreakTest pass) and was wired into the editor's diff
layer + cursor invariant + arrow-key API + FFI variants.
The [moji API spec](plans/2026-05-10-moji-api-spec.md) is now
"implemented in #251."

- [x] Migrate `examples/ideal/web/src/bridge.ts` per-char `insert_at`/`delete_at` loop onto `handle_text_intent`.
  Shipped: bridge now calls `handle_text_intent_checked` (Bool-returning FFI added in `ffi/lambda/intent.mbt`) once per CM6 change with cumulative-delta bookkeeping; partial-batch + drift-detection semantics preserved from the prior `applyCharChanges` loop.

- [x] Enforce the **cursor-on-boundary invariant** across `SyncEditor` — `move_cursor`, `insert`, `delete`, `backspace`, `_and_record` family, and both branches of `apply_text_edit_internal`.
  Shipped (#251): all per-character methods use spec §1.2-§1.4 strict-step formulas (`prev_grapheme_boundary(cursor - 1)` / `next_grapheme_boundary(cursor + 1)`); `apply_text_edit_internal` cursor-stays branch post-snaps with `next` per spec §0.5; `_and_record` mutations got the same treatment in `editor/sync_editor_undo.mbt`.

- [x] **Unconditional cursor post-snap** in both `apply_text_edit_internal` branches (cursor-to-edit-end and cursor-stays). Cluster-fusing inserts (RIs, ZWJ, virama, VS-16) shift downstream boundaries even when the splice itself was boundary-aligned in the old text.
  Shipped (#251 + follow-up): private `SplicePolicy` enum gates Snap vs Exact paths; both branches post-snap unconditionally per spec §0.5. BMP and non-BMP cluster-fusing tests are pinned in `editor/sync_editor_text_wbtest.mbt`.

- [x] Make `text_diff::find_common_prefix` / `find_common_suffix_after_prefix` grapheme-safe (`editor/text_diff.mbt`). Fix lives in `lib/text-change/text_change.mbt::compute_text_change` so canopy + valtio + loom (all path-dep on the leaf) get the fix in one move.
  Shipped (#251): both walks now use `@moji.grapheme_boundaries`. 3 `#216 xfail/panic` tests in `editor/text_diff_test.mbt` flipped to passing inspect assertions.

- [x] Add `move_cursor_left_grapheme` / `_right_grapheme` (and word variants per UAX #29) on `SyncEditor`.
  Shipped (#251): four new methods in `editor/sync_editor_text.mbt` per spec §1.6, exported in `editor/pkg.generated.mbti`. Word-navigation policy (whitespace-skipping, punctuation handling) is a separate concern layered on raw UAX boundaries — not yet implemented.

- [x] **§1.1 splice policy split** in `apply_text_edit_internal` — pure insertion (`deleted_len == 0`) snaps `start` to a single boundary; replacement/deletion expands both endpoints.
  Shipped (#251): `apply_text_edit_with_policy` branches on `SnapToGrapheme` policy — pure-insert snaps `start` with `prev` only; replace/delete snaps `start` with `prev` AND `end` with `next`.

- [x] **FFI variant naming**: document `handle_text_intent_checked` as "exact splice" (rejects non-boundary) and `handle_text_intent` as "snap splice" (applies §1.1 policy) in their doc-comments.
  Shipped (#251): `handle_text_intent_checked` now routes to a new `apply_text_edit_exact` (returns `Bool`, rejects non-boundary endpoints) per spec §1.11. Doc-comments updated.

- [x] (canopy-side, integration-time) Decide cursor unit-storage (UTF-16 vs item-space vs grapheme-ordinal).
  Resolved (#251): chose UTF-16 (smallest blast radius). UTF-16 ↔ item-space conversion (`utf16_offset_to_item_pos`) lives at the editor boundary per spec §0.

- [x] Add a one-line docstring to `lang/markdown/edits/compute_markdown_edit.mbt:211 compute_split_block` noting `offset` is a code-unit offset inside the text span.

- [x] **Fix parser/undo non-BMP `String::sub` mid-surrogate aborts.**
  Resolved (follow-up): `Document::insert` was already codepoint-safe; the unresolved abort surfaces were Loom parser recovery slicing token text with validated substring syntax and `event-graph-walker/text::TextState::insert_and_record` slicing inserted text one UTF-16 code unit at a time. Loom now uses raw `StringView` token spans and keeps recovered invalid-token spans on scalar boundaries; `insert_and_record` now iterates inserted text by `Char` and records full-codepoint undo content. The four `panic #216` tests are now inspect-style behavior tests.

- [x] **Restore non-BMP §4.3 cluster-fusing-cursor tests.**
  Resolved (follow-up): `editor/sync_editor_text_wbtest.mbt` now pins `"🇯🇵🇺🇸" + apply_text_edit(4, 0, "🇮") → cursor 8` and `"👩💻" + insert_at(2, "\u{200D}") → cursor 5`.

- [ ] **Word-navigation policy on top of moji's raw UAX boundaries.** moji exposes spec-correct UAX #29 word boundaries (every transition between word/whitespace/punctuation). Editor word-navigation typically wants different semantics — skip whitespace, treat punctuation as part of the word in some contexts, optionally split camelCase/snake_case. Plan: define the policy as a wrapper around `move_cursor_left_word` / `_right_word` in `editor/sync_editor_text.mbt`. Spec §6.3 deliberately deferred this; pick a default policy (Sublime/VS Code-style is a reasonable starting point) and ship behind a config flag if needed.
  Status: not blocked; standalone canopy-side work.

- [ ] (perf, P3) `editor/sync_editor_text.mbt::utf16_offset_to_item_pos` is O(n) per call and runs on every mutation path; `gcb_of` does up to 13 binary searches per codepoint; `next/prev_grapheme_boundary` rebuild the boundary array each call (O(n²) for tight loops). Acceptable for canopy's short strings today; documented in `lib/moji/grapheme.mbt` and `lib/moji/README.md`. Concrete fixes when a hot-path actually needs them: ASCII fast path in `gcb_of` (only CR/LF/Control populate `< 0x80`), drop `ch.to_string().length()` allocation in `utf16_offset_to_item_pos` (use `if ch.to_int() >= 0x10000 { 2 } else { 1 }`), and a materialise-once boundary cache for hot callers.
  Status: not blocking; cosmetic perf debt.

- [ ] Disambiguate `UserIntent.SetCursor.position` — same `number` carries PM-tree positions (PMAdapter) and CM-doc code-unit offsets (CM6Adapter). Naming cleanup, not unit conversion.
  Status: not blocked on moji.

- [ ] Tighten `examples/ideal/web/src/bridge.ts::applySpliceChanges` partial-batch semantics. Today: if splice K in a multi-change batch fails the `handle_text_intent_checked` bounds check, splices 0..K-1 stay applied to the CRDT but skip the immediate `afterLocalEdit()` broadcast — they ride the next successful edit's `export_since_json` delta. Pre-existing behavior preserved by #246, flagged by Codex on that PR. Options: (a) call `afterLocalEdit()` if anything was applied, broadcasting the valid prefix immediately; (b) make batches atomic with a snapshot/rollback API; (c) leave as-is and document. Prefer (a) — minimal change, removes the cross-replica gap.
  Status: not blocked on moji.

---

## 17. Lambda Type System

- [ ] Evolve the lambda typecheck pipeline so it produces ranged diagnostics + queryable types via subscription, not stringly-typed JSON snapshots.
  Why: the diagnostic pane shipped (PR #186 + follow-ups), but the pipeline below it lacks the primitives every future surface needs — source ranges on diagnostics, a typed wire protocol, `TypecheckIndex`, push-based subscription, per-def memos, and a shared `attach_typecheck` abstraction. Once these land, hover / inline squigglies / inlay hints / click-to-locate become ~10-line consumers each.
  Plan: `docs/plans/2026-04-26-lambda-typecheck-pipeline-evolution.md`
  Exit: 6/6 plan steps shipped — type diagnostics carry ranges, wire is typed (no JSON round-trip), `query_type_at_offset` exposed and consumed by hover, diagnostic updates are subscription-driven, per-def memo isolation verified by test, and `@typecheck.attach` is the single shared attachment abstraction used by both canopy and the loom example.

---

## Shipped history

Completed items (with PR references and shipping notes) are preserved in
[docs/archive/TODO-snapshot-2026-04-21.md](archive/TODO-snapshot-2026-04-21.md).
When marking work done going forward, move the completed entry into a new
dated snapshot or an existing archive plan doc rather than accumulating it
here.
