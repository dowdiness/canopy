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

- [x] Add `npx tsc --noEmit` CI job for `examples/{web,prosemirror,demo-react}`.
  Shipped: `typecheck-ts-examples` matrix job in `.github/workflows/ci.yml`; builds MoonBit JS artifacts, installs deps, runs `npx tsc --noEmit` per example, gated by `all-checks-passed`. Drift it caught on the way in: `examples/demo-react/tsconfig.json` had a deprecated `"baseUrl": "."` (TS 6.0 TS5101 deprecation; redundant under `moduleResolution: "bundler"` since `paths` already resolves relative to the tsconfig); dropped in the same change.

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

- [x] Replace Markdown ordered-list `SourceMap` side channel with explicit list payloads.
  Done: Loom PR #429 exposed `OrderedList` / `UnorderedListItem` / `OrderedListItem` payloads with ordered marker metadata; Canopy PR #730 removed `ORDERED_LIST_KIND_ROLE` and reads list kind from Loom payloads.
  Plan: `docs/archive/completed-phases/2026-06-20-markdown-list-payloads.md`
  Exit: `ORDERED_LIST_KIND_ROLE` is removed, ordered-list projection/view/FFI/block-mode regressions pass, and Canopy reads list kind from explicit Loom Markdown list payloads.

- [ ] `SyntaxNode::find[K : ToRawKind]` generic method (low priority).
  Why: 16 `find_token(...to_raw())` callsites remain, but views pattern + `token_text()` already reduce the ergonomic pain. Nice-to-have polish.
  Exit: `pub fn[K : ToRawKind] SyntaxNode::find(self, kind : K) -> SyntaxToken?` in seam.

- [x] Reassess shared `lib/range` primitive for range/span units.
  Why: issue #415 found repeated range-shaped values across SourceMap, protocol, editor text edits, Loom/seam syntax offsets, and eg-walker item-space positions. `moonbitlang/core/range` was also checked, but it is iteration-only today (`iter` + sealed `Step`) and has no span value type. A single `Range[Int]` would erase the unit distinctions pinned by #216 and PR #555.
  Decision: do **not** introduce a shared `lib/range` primitive now. Keep `@loomcore.Range` for SourceMap/projection UTF-16 source spans, keep `@text.Pos` / `@text.Range` for eg-walker item-space, keep protocol fields as JSON numbers with explicit unit docs, and add unit-specific wrappers only at concrete risky boundaries.
  Exit: accepted decision in `docs/decisions/2026-06-13-range-span-unit-boundaries.md`; public/cross-package range docs list units explicitly.

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

- [x] E2E tests for outline tree panel.
  Shipped 2026-06-07. Audit: the original gap was stale/broad.
  Already covered: click selection, keyboard navigation, and scroll-to-selection (`examples/ideal/web/e2e/outline-navigation.spec.ts`); tree roles, selection, active-descendant, and collapse ARIA (`examples/ideal/web/e2e/outline-aria.spec.ts`); resize-handle behavior while `.tree-rows` scrolls (`examples/ideal/web/e2e/outline-resizable.spec.ts`).
  Closed here: collapse/expand descendant visibility plus collapsed badges; light-DOM outline row drag/drop in `examples/ideal/web/e2e/outline-drag-drop.spec.ts`, verifying CRDT/CodeMirror text sync plus outline reorder. Shadow structure-mode drag/drop remains covered separately by `examples/ideal/web/e2e/drag-drop.spec.ts`.

---

## 7. Code Cleanup

- [x] Resolve the forked Rabbita patch provenance/adoption path.
  Shipped 2026-06-05: Canopy now points `rabbita` at `5f828eb` on `dowdiness/rabbita:update-0.12.4-patched`, pinned by tag `canopy-rabbita-v0.12.4-patched-2026-06-05`. This adopts upstream `rabbita-v0.12.4` plus Canopy's fork-only `diff_subs/update_tagger` patch, and the in-repo Rabbita path-dep pins now say `0.12.4`. If the patch lands upstream later, repoint to the upstream release; Warren remains separate.

- [x] Upstream Rabbita native-dialog `closedby` attribute support.
  Shipped upstream in Rabbita PR #118 and release `rabbita-v0.12.4`, then adopted by Canopy through the patched fork gitlink above. Scope remains intentionally narrow: `Attrs::closedby` and `dialog(closedby?)` emit the limited-support attribute only; they do not polyfill light-dismiss behavior or guarantee non-Baseline browser support.

- [ ] Upstream Rabbita fractional `MouseEvent` coordinates.
  Why: browser `MouseEvent.clientX/clientY` are JS numbers, but Rabbita currently exposes `get_client_x()` / `get_client_y()` as `Int`, forcing Canopy's context-menu primitive to use a private raw-JS workaround to preserve fractional anchors.
  Plan: upstream Rabbita issue/PR; decide with maintainers whether the canonical accessors can be corrected to `Double` directly or need a compatibility migration path.
  Exit: Rabbita exposes fractional client coordinates through its public `MouseEvent` API; Canopy removes the private `lib/context-menu` JS accessors and consumes the upstream API.

- [ ] Report/fix Warren dangling-symlink discovery failure.
  Why: `warren build` can abort while walking Canopy's workspace root when it hits a dangling symlink such as `loom/target -> _build` before `loom/_build` exists: `OSError(@fs.kind(): ".../loom/target": No such file or directory)`.
  Upstream: PR moonbit-community/rabbita#120 merged, but released rabbita-v0.12.4 predates it. Apply by bumping rabbita submodule to a post-v0.12.4 upstream commit once available.

- [x] Upgrade `rle` consumers to `dowdiness/rle` 0.2.1 and constructor-style APIs.
  Shipped: all consumers (`event-graph-walker@0.2.3`, `lib/btree@0.2.2`) already use constructor-style APIs (`Rle()`, `PrefixSums()`). No `Rle::new()` or `PrefixSums::new()` calls remain. Stale — the TODO itself was the only remaining artifact.

- [x] Extend the aggregator-trim audit from `lang/{lambda,json}` (PR #265) to the rest of the canopy module.
  Shipped across four PRs (2026-05-16):
  - PR #272 (`core/`): 3 Show stubs + 3 SourceMap query methods kept with TODO refs; ordering contract bug on `nodes_at_position` flagged.
  - PR #273 (`projection/` + `protocol/`): single 5-line annotation on `TreeEditorState::has_node`; ~22 flags resolved to workspace blind-spot (examples/ideal) or JSON/FFI cross-boundary readers.
  - PR #274 (`editor/`): one visibility narrow (`apply_text_edit_internal`); 11 collab Show stubs annotated for the new Collaboration panel; §14 "Canopy library API audit" TODO added recording the aspirational-library framing decision.
  - PR #275 (`relay/`, server-side, internal-tool framing): one visibility narrow (`RelayRoom::send_to`); 2 wire encoders kept per README's documented Public API; stale doc comment about `crdt_relay.mbt FFI` corrected.
  Net across 4 PRs: 0 deletions, 2 visibility narrows, ~9 annotation comments, 5 new TODOs (Inspector traceability workstream + library API audit). Methodology recorded in [[feedback-section7-audit-methodology]].

- [x] DRY seam's three `build_tree` variants (`seam/event.mbt`).
  Shipped: loom PR #494 (merged `454b460`), adopted by canopy via PR #796. `build_tree_buffered_with` parameterized by 5 callbacks; three `_buffered` wrappers are ~15 lines each. Net -167 lines.

- [x] Hoist ProjNode id-allocation boilerplate into `@core` (`core/proj_node.mbt`). (finding B from PR #383)
  Shipped (#437): `@core` exposes `ProjNode::leaf[T](kind, node : @seam.SyntaxNode, counter)` and `ProjNode::branch[T](kind, start, end, children, counter)`. Lambda/JSON/Markdown projection builders now use the shared helpers for fresh syntax leaves/branches; ID-preserving sites keep raw `ProjNode`. `.mbti` change is limited to the two new `@core` exports.

- [x] Add an `EditContext` node-resolution helper (`lang/lambda/edits/text_edit.mbt`). (finding C from PR #383)
  Why: nearly every `compute_*` handler opens with the same pair of guards keyed on one `node_id` — `registry.get(id)` then `source_map.get_range(id)`, both erroring "Node not found" — made visible by the PR #383 guard sweep. `EditContext` already holds both maps.
  Shipped: `EditContext::resolve[T](self, node_id) -> (ProjNode[T], @loomcore.Range) raise ResolveError` added to `text_edit.mbt`; 13 handler prologues across 6 files (commit, delete, drop, structural×3, wrap×4, refactor×2) collapsed to single `resolve()` call; error messages standardised to "Node not found: {id}"; body-level redundant `registry.get` fallbacks in `compute_delete` eliminated. Note: `ResolveError` is a zero-info bridge type (tracked in #667 for cleanup alongside finding D).

- [x] Evaluate moving the edit layer from `Result[_, String]` to a `raise EditError` model (`lang/lambda/edits`). (finding D from PR #383, #667)
  Shipped: `EditError` suberror in `core/edit_error.mbt` with 12 semantic variants (`NodeNotFound`, `NodeNotInSourceMap`, `InvalidTarget`, etc.) and legacy-compatible `message()` method. Lambda, JSON, and Markdown compute-edit handlers all migrated to `raise EditError`. `LanguageSpec` closures (`compute_edit`, `on_no_edit`) updated. `apply_edit` boundary catches `EditError` → `Result[Unit, String]` for FFI stability. All 3682 native + 70 native tests pass.

- [x] Uniform syntax→projection dispatch + projection-walk helper decision (loom `@seam` / `lang/*/proj`). (finding E from PR #383)
  Shipped: #439 extracted Lambda App/Binary token-span left-spine walking into a private iterative helper; loom PR #207 adds Lambda `BlockExprView` / `HoleLiteralView`, and this branch switches Lambda projection dispatch to the uniform typed `View::cast(node) is Some(v)` ladder. Decision: no new public loom-level projection-walk API for now — existing `@seam.SyntaxNode` direct-child helpers plus the private left-spine helper cover the current duplicated/fragile cases without adding an under-evidenced core abstraction.

---

## 8. Handler Chain Follow-ups

- [ ] AST transform pipeline.
  Why: the `EditMiddleware` trait is ready for composable AST-to-AST transforms (constant folding, dead code elimination, simplification). Each pass becomes a middleware impl that intercepts before `core_dispatch`.

- [ ] Cache navigation path between keystrokes to avoid O(n) DFS per keystroke (GitHub #91).
  Exit: path or zipper is cached in editor state and reused across consecutive keystrokes.

---

## 9. Ideal Editor

- [ ] Migrate Ideal to Tailwind v4 incrementally.
  Why: PR #532 proved Tailwind v4 can scan `.mbt` class strings and that shadow CSS delivery is solved; product decision is to adopt Tailwind for design-system maintainability while avoiding broad all-at-once churn.
  Plan: docs/plans/2026-06-06-ideal-tailwind-v4-migration.md; style rules: docs/development/ideal-tailwind-style-management.md; GitHub issue #533
  Status: first slice shipped in PR #534 — Tailwind v4 wired for Ideal only, action overlay/name prompt migrated, semantic hooks preserved, validation green, and rollback criteria documented. Second slice shipped in PR #539 — Ideal-local button recipes migrated toolbar/action-button chrome with explicit source scanning and computed-style coverage. Third slice shipped in PR #541 — bottom tab strip chrome now uses the Ideal-local button recipe layer plus a narrow bottom-strip class bundle; legacy `.bottom-tabs` declarations were removed and computed-style coverage includes desktop, hover, and mobile touch targets. Fourth slice shipped in PR #542 — light-DOM panel header/label/section chrome moved to a private `view_panel_classes.mbt` bundle, semantic hooks were preserved, legacy panel section/header CSS declarations were removed, and computed-style coverage now includes desktop plus mobile drawer states. Fifth slice shipped in PR #543 — light-DOM inspector detail chrome moved to a private `view_inspector_classes.mbt` bundle, semantic hooks were preserved, legacy inspector-detail CSS declarations were removed, and computed-style coverage now includes rows/source-preview/token spans. Sixth slice shipped in PR #544 — light-DOM outline resize-handle chrome (`panel-resize-handle`, `outline-resize-handle`) moved to a private `view_outline_classes.mbt` bundle with narrow Tailwind source scanning, legacy resize-handle CSS removal, and computed-style coverage for base geometry, pseudo-element line, hover/focus-visible states, and mobile hidden state. Seventh slice shipped in PR #684 — toolbar and bottom-panel tab chrome moved into value-derived `main/ui/tabs.mbt` helpers, preserving toolbar button semantics and bottom-panel `@tabs.Model` behavior while avoiding Rabbita handle storage in `Model`.
  Next exit: select the next non-deferred light-DOM Tailwind slice only after confirming a single live CSS owner and a narrow `@source`; continue deferring full panel drawer/scrim/visibility transitions, bottom-panel content/history/incr raw HTML fragments, shadow-owned structure styles, and broad Tailwind scanning.

- [ ] Structure mode — test and polish PM block editor, verify lazy-loading works.
  Note: completion state is unclear; decision pending in `docs/decisions-needed.md`.

- [x] Add safe imperative boundary helpers for Rabbita DOM interop.
  Why: Rabbita has no React-style ref API; current widget and browser-API escape hatches use ad-hoc `after_render` commands, stable ids, and hidden trigger clicks. A tiny helper layer would keep DOM access lifecycle-safe without storing raw elements in app state.
  Exit: shared helpers cover common id-based `after_render` actions such as focus, click, scroll, and typed custom-event subscriptions; ideal-editor bridges use them where practical.
  Done: added `lib/dom-boundary` with typed throwing DOM helpers, a local Ideal Rabbita adapter, and migrated focus/scroll call sites off direct JS DOM externs (2026-05-21).

- [ ] Graphviz SVG theming — SVG uses hardcoded `Arial` from submodule; needs `pub(all) struct SvgConfig` to customize.

- [ ] Grammar: interleaved let/expr.
  Why: `Module` AST supports `ModuleItem` in parser already, but the projection/editor representation still assumes contiguous definition rows plus a body.
  Alternative: design an interleaved `ProjNode`/`DefinitionIndex` view over module items. Decision pending in `docs/decisions-needed.md`.

- [x] Inspector — Intent panel. *Part of Inspector traceability workstream.* Shipped in PR #293 (2026-05-17).
  Op Log tab in `view_bottom.mbt` renders `Model.intent_log : Array[String]` (cap 50), pushed from all four structural-edit dispatch sites after `apply_lambda_tree_edit` succeeds. Two row formats coexist:
  - `TreeEditOp.to_generic().to_string()` for direct-apply paths (`apply_structural_edit_request`, `execute_action`, `OutlineStructuralEdit`)
  - `"{op}(node={id})"` ad-hoc label for the TS-applied `EditorStructuralEdit` path (the typed `TreeEditOp` is already consumed by `handle_structural_intent` FFI before MoonBit sees the message; reconstruction would duplicate the op-string→TreeEditOp dispatch from `apply_structural_edit_request`).

- [x] Inspector — Patch panel. *Part of Inspector traceability workstream.* Shipped in PR #323 (2026-05-22, commit `0c093ac`).
  Scrollable log of recent `SpanEdit`s with back-reference to producing `GenericTreeOp` (each row uses `edit.to_string()`), rendered by `view_patch_log` in `view_bottom.mbt`.

- [ ] Structure-aware diff display from reconciliation trace (#830).
  Why: the Patch panel shows character-level `SpanEdit`s even for structural edits like Wrap; the reconciler already knows "this was a Wrap" but discards it after reconciliation.
  Plan: `docs/plans/2026-07-02-structure-aware-diff-display.md`
  Exit: `core/reconcile.mbt` emits an opt-in `ReconcileTraceEvent` trace; Patch panel renders filtered `StructuredChange` events (e.g. "Wrapped #42 in Lambda") alongside the existing SpanEdit log.

- [ ] IdentityTransform hints in undo/redo for identity-preserving undo (#831).
  Why: `WrapInLambda` → Undo currently falls back to Level 0 LCS (fresh IDs, lost cursor position, lost collapse state) because the forward edit's hint is discarded after one reconciliation pass; the inverse hint must instead be derived at undo time from a stored `UndoOp` description plus the current tree.
  Plan: `docs/plans/2026-07-02-undo-redo-identity-hints.md`
  Exit: Wrap → Immediate Undo preserves cursor position and the inner expression's NodeId (first slice; Unwrap/Rename undo are explicit follow-ups).

- [x] Inspector — unify Op Log label format across direct-apply and FFI paths. *Part of Inspector traceability workstream.* Shipped in PR #327 (2026-05-23, commit `336b29b`).
  Extracted `structural_edit_op_to_tree_edit` helper (handles `WrapInLambda` / `Delete`); reused in both `apply_structural_edit_request` and the `StructureStructuralEdit` FFI arm so the latter rebuilds a typed `TreeEditOp` and routes through `push_intent`. `push_intent_label` remains as fallback for ops whose payload isn't recoverable from `(op, node_id)` alone (currently only `"Drop"`). Two unit tests in `main_wbtest.mbt` pin the unified shape (`StructuralEditKeepSelected(#42)` / `Delete(#42)`).

- [x] Inspector — guard `view_op_log` / `view_patch_log` allocation when bottom panel collapsed. Shipped in PR #324 (2026-05-23).
  PR #293 gated the heavy DOT/SVG pipeline (`render_history_html` / `render_graphviz_html`) on `model.workspace.bottom_visible`, but `view_op_log` (up to 50 row nodes) and the new `view_patch_log` from PR #323 (header + N `SpanEdit` rows per entry, capped at MAX_PATCH_LOG=50) still allocated on every render while the panel was hidden via CSS. Both now early-return an empty `<div>` with the appropriate `bottom_panel_attrs(tab)` when the panel is collapsed.

- [ ] Inspector — Collaboration panel. *Part of Inspector traceability workstream.*
  Why: in a collaborative projectional editor, the connected-peers list, sync status, ephemeral broadcasts (drag state, presence updates), and sync errors are invisible from the main editor surface. Debugging "peer A and peer B disagree on text," "why didn't my drag preview show," or "sync stalled" requires a panel surfacing the collab-layer state. Stub `Show` impls already exist on the relevant types (`PeerCursor`, `PeerPresence`, `PresenceStatus`, `SyncStatus`, `SyncMessage`, `SyncErrorReason`, `DragState`, `EditModeState`, `EphemeralNamespace`, `EphemeralValue`, `EphemeralEventTrigger`) but currently delegate to `@debug.to_string` (verbose dump, not user-facing labels).
  Exit:
  - Connected-peers list: renders `PeerPresence` entries (each row uses `peer.to_string()` for a short label like `"alice (online, editing)"`).
  - Sync status indicator: renders `SyncStatus` + recent `SyncErrorReason` via their `Show` impls.
  - Recent ephemeral events stream: renders `EphemeralStoreEvent`s via `event.to_string()`.
  - Lives in `view_bottom` or new tab alongside outline/inspector/history/intent/patch.

- [x] Enforce `SourceMap::nodes_at_position` ordering contract. *Part of Inspector traceability workstream.*
  Why: the doc-comment promised "outermost to innermost" but the body returned `Map.keys().to_array()` — no ordering guarantee. Latent contract bug if any consumer ever depended on nesting order. The earlier framing ("wire into editor click-path") was stale: `examples/ideal/main/view_editor.mbt` is 25 lines of DOM mount only; the position→node lookup already routes through `SyncEditor::node_at_position` (which uses `innermost_node_at`). The "selection-extend command consumes `nodes_in_range`" sub-bullet had no committed consumer either.
  Shipped: `SourceMap::nodes_at_position` now sorts by range length descending (outermost first, innermost last — matches `innermost_node_at`'s `minimum_by_length` semantics). Property test in `core/source_map_properties_wbtest.mbt` pins the contract — for any two consecutive returned nodes, the earlier's range contains (or equals) the later's. `SourceMap::rebuild` remains annotated in source as recovery API; no UI consumer committed, not bundled into this entry.

---

## 10. Editor Drag-and-Drop Follow-ups

- [x] First-class LetDef ProjNodes for binding-level structural edits (#127).
  Merged: canopy#448 (336d7e1, 2026-06-01); cleanup PRs #664, #668–#671 (2026-06-15).
  All acceptance criteria verified 2026-06-15: Module children are [LetDef..., body];
  scope builder uses LetDef child ids for Decl.node_id; convert.ts/reconciler.ts map
  actual LetDef ProjNodes to let_def; drag/drop E2E moves whole binding rows; binding
  actions pass real LetDef ids; scope annotation uses real LetDef ids; binder_span /
  go_to_definition remain source-span based; canvas unchanged.
  Post-#677 follow-up cleanup removed the remaining binding-id compatibility
  fallbacks; action-context plumbing now uses real LetDef ids instead of init ids.

- [x] Prepare drag-and-drop foundations for `examples/block-editor`.
  Why: `move_block` only appends as last child; needs `move_before`/`move_after` for sibling reorder. Markdown list/list-item move provenance (issue #724) is resolved: #730 added explicit ordered/unordered list payloads, and PR #731 landed tight same-list item reorder with parse-shape, identity, ambiguity, marker-renumbering, separator, and unsupported-container regressions. #724 is closed with a proof-backed rejection for the cases the sibling-level reconciler cannot preserve identity across (see `docs/design/sdeg-invariant-review.md` "Decision: Markdown move-provenance scope"). Cross-container / list-container legality and loose-list separator preservation remain narrow follow-ups carried here.
  Plan: `docs/plans/2026-03-30-editor-drag-drop-foundation.md` (steps 2-3); cross-container/list-container move provenance follow-up (was issue #724, now documented-rejected).
  Exit: `block-editor` exposes positioned block moves plus structural render metadata.
  Completed: `get_render_state()` with depth/parent_id/child_count (PR #800);
  three-zone drop positions (Before/Inside/After) with CSS indicators;
  depth-based nested block indentation via `--depth` CSS var;
  `validateDropTarget` wired into dragover/drop handlers;
  text-content span isolation for editable text.

- [x] Spike Markdown block move provenance for future block UI.
  Why: SDEG Phase 1 documents pure source reorder as position-stable; future block moves need explicit provenance so identity follows the moved block.
  Plan: `docs/archive/2026-06-20-markdown-block-move-provenance-spike.md`
  Exit: accepted `MarkdownEditOp::MoveBlock(source, target, position)` contract with tests showing only explicit provenance moves heading identity.

- [ ] Convergence tests for concurrent drag-drop.
  Why: concurrent relocations across CRDT peers need convergence guarantees.
  Exit: property tests covering concurrent drop, undo grouping after relocation, and reconciliation.

---

## 11. Multi-Language Support

- [ ] JSON member-projection optimization — 1000-member objects at 28 ms exceed 16 ms budget. Add incremental per-member derivation when needed.

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

- [ ] Canopy library API audit and documentation.
  Plan: boundary declared in [docs/decisions/2026-06-11-library-api-boundary.md](decisions/2026-06-11-library-api-boundary.md) (Accepted 2026-06-11; S0 of [docs/plans/2026-06-11-architecture-redesign-proposal.md](plans/2026-06-11-architecture-redesign-proposal.md)) — three tiers, `*_internal` convention, audit defaults. Remaining here: the per-symbol audit sweep (§7 aggregator-trim item, now executable against the boundary) and the optional release milestone.
  Why: canopy is currently used as an internal monorepo, but the aspirational direction is to publish it as a general projectional editor library consumable by external MoonBit modules. The audit framing — what's "unused" vs "library API surface" — depends on which direction is committed. Many `pub` symbols in `editor/`, `core/`, `projection/`, and `protocol/` are canonical library API (constructor methods, structural-edit operations, error accessors, query primitives, wire-protocol encoders) that look "unused" under an internal-tool lens because no in-tree consumer exercises them, but are exactly what external library users would call. Without a documented decision, every audit re-relitigates the framing.
  Exit:
  - Document the intended library boundary: which packages are public API for external consumers (`core`, `editor`, `projection`, `protocol`) vs internal implementation (`ffi/*`, `editor/*_internal` symbols, etc.).
  - Establish convention: methods named `*_internal` (e.g. `apply_text_edit_internal`) are implementation-detail regardless of `pub`; library API gets explicit pub visibility, implementation gets private.
  - Future `moon ide analyze` audits default to KEEP for canonical library API surface; "unused by in-tree consumers" stops being a deletion trigger for these packages.
  - Optional: a release plan / milestone for first published canopy library version.

---

## 15. Editor Framework Decoupling

- [x] Route inspector kind-labels through `Show`. *Part of Inspector traceability workstream.* Shipped 2026-05-17 (PRs #277, #278).
  Why: `examples/ideal/main/view_outline.mbt::kind_of()` and `view_inspector.mbt` each implement their own kind→label classifier, hardcoding lambda-specific syntax ("(x) =>" label, "App", "let", "if") in framework views. Adding a new language requires editing per-view classifiers. Existing `Show` impls on `core/proj_node.mbt::ProjNode[T]`, `core/types.mbt::GenericTreeOp`, and `core/types.mbt::SpanEdit` are stubs delegating to `@debug.to_string` (verbose dump, not a short label) with no consumers.
  Exit (as originally drafted):
  - Tree-row labels in `view_outline` use `node.to_string()` — consumes real `Show for ProjNode[T]` producing e.g. `"#9 App [25..47]"`.
  - Kind chips in `view_inspector` use `node.kind.to_string()` — consumes existing `Show for Term`/`JsonValue` (already real, no stubs) producing e.g. `"App"`.
  - `view_outline::kind_of()` and any duplicate per-view classifier deleted.
  - Adding a new language touches only the language's `Show for Kind` impl, not framework views.

  As shipped (see `docs/plans/2026-05-16-show-unification.md` for the trace):
  - Real `Show` impls landed for `SpanEdit`/`GenericTreeOp`/`ProjNode[T]`/`InteractiveTreeNode[T]` (PR #277), but `view_outline` tree-row body keeps `node.label` — the `"#9 App [25..47]"` form is debug output for inspectors/logs, not the navigation tree.
  - Inspector chip uses `@loomcore.Renderable::kind_tag(node.kind)` (typed kind tag) rather than `node.kind.to_string()` (PR #278); same end-state for the kind→label classifier collapse, different mechanism.
  - `view_outline::kind_of()` deleted; CSS class derives from `term_css_class(node.kind)` in `lang/lambda/proj/`.
  - Adding a new language requires a `Renderable` impl (already required) plus an optional language-specific `term_css_class` for accent colors — framework views unchanged.

- [x] Extract ephemeral subsystem — move ~9 files / ~1500 lines (EphemeralStore, EphemeralHub, EphemeralValue, presence types, cursor view, encoding) from `editor/` to its own package.
  Closed 2026-06-11 (stale entry — already shipped): the top-level `ephemeral/` package owns the subsystem with its own test suite; `editor/` imports it and re-exports via `editor/ephemeral_facade.mbt`. Confirmed during architecture S0 ([docs/plans/2026-06-11-architecture-redesign-proposal.md](plans/2026-06-11-architecture-redesign-proposal.md)).

- [x] Unify sync protocol — `editor/sync_protocol.mbt` and `relay/wire.mbt` independently encode/decode the same binary wire protocol (version 0x02, same message types).
  Resolved: the duplication was resolved — `editor/sync_protocol.mbt` became a `#deprecated` re-export shim over `@wire` (`protocol/wire`), and this branch deletes the shim; `relay/wire.mbt` is a distinct concern (peer-control frames), not a duplicate.

- [ ] Extract reusable orchestration out of `examples/ideal/main` (god-package: ~5.4k src lines).
  Why: structural-edit reconstruction, scope annotation, action domain logic, and log-entry construction are library-grade logic trapped in the Rabbita example, contradicting the accepted library boundary (docs/decisions/2026-06-11-library-api-boundary.md).
  Plan: `docs/plans/2026-07-02-ideal-orchestration-extraction.md`
  Exit: example retains only Rabbita Model/view/command wiring; extracted logic lives in lang/lambda/{companion,scope,edits} with tests moved to owning packages.

---

## 16. Unicode Text Correctness

GitHub issue: [#216](https://github.com/dowdiness/canopy/issues/216).
Steps 1, 3, 4 shipped (#239, #241, #242). **Step 2 shipped** in
[#251](https://github.com/dowdiness/canopy/pull/251) — the moji
library (`loom/moji/`, [#250](https://github.com/dowdiness/canopy/issues/250))
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

- [x] Make `text_diff::find_common_prefix` / `find_common_suffix_after_prefix` grapheme-safe (`editor/text_diff.mbt`). Fix lives in `loom/text-change/text_change.mbt::compute_text_change` so canopy + loom both path-dep on the same leaf.
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

- [ ] (perf, P3) `editor/sync_editor_text.mbt::utf16_offset_to_item_pos` is O(n) per call and runs on every mutation path; `gcb_of` does up to 13 binary searches per codepoint; `next/prev_grapheme_boundary` rebuild the boundary array each call (O(n²) for tight loops). Acceptable for canopy's short strings today; documented in `loom/moji/grapheme.mbt` and `loom/moji/README.md`. Concrete fixes when a hot-path actually needs them: ASCII fast path in `gcb_of` (only CR/LF/Control populate `< 0x80`), drop `ch.to_string().length()` allocation in `utf16_offset_to_item_pos` (use `if ch.to_int() >= 0x10000 { 2 } else { 1 }`), and a materialise-once boundary cache for hot callers.
  Status: not blocking; cosmetic perf debt.

- [x] Disambiguate cursor intent offsets — replaced generic `UserIntent.SetCursor.position` with `SetPmCursor(pm_tree_position)` and `SetDocCursor(doc_code_unit_offset)`. Naming cleanup only; no unit conversion.
  Status: completed 2026-06-07.

- [x] Tighten `examples/ideal/web/src/bridge.ts::applySpliceChanges` partial-batch semantics.
  Shipped 2026-06-07: implemented option (a). If splice K in a multi-change batch fails `handle_text_intent_checked` after splices 0..K-1 were applied, the bridge now calls `afterLocalEdit()` before reconciling so peers receive the valid prefix immediately. Playwright coverage in `examples/ideal/web/e2e/bridge-partial-batch.spec.ts` pins both prefix-broadcast and first-splice-failure/no-broadcast behavior.

---

## 17. Lambda Type System

- [ ] Evolve the lambda typecheck pipeline so it produces ranged diagnostics + queryable types via subscription, not stringly-typed JSON snapshots.
  Why: the diagnostic pane shipped (PR #186 + follow-ups), but the pipeline below it lacks the primitives every future surface needs — source ranges on diagnostics, a typed wire protocol, `TypecheckIndex`, push-based subscription, per-def memos, and a shared `attach_typecheck` abstraction. Once these land, hover / inline squigglies / inlay hints / click-to-locate become ~10-line consumers each.
  Plan: `docs/plans/2026-04-26-lambda-typecheck-pipeline-evolution.md`
  Exit: 6/6 plan steps shipped — type diagnostics carry ranges, wire is typed (no JSON round-trip), `query_type_at_offset` exposed and consumed by hover, diagnostic updates are subscription-driven, per-def memo isolation verified by test, and `@typecheck.attach` is the single shared attachment abstraction used by both canopy and the loom example.

## 18. Shared-Runtime Workspace (§P0b prep)

- [ ] Resume §P0b design with grounded substrate.
  Why: §P0a research shipped (PR #326); the tracked observer-discipline contract now pins the editor-side rooting obligations. 2026-05-24 PR-shape brainstorm paused after 5 Codex rounds + 17 substantive findings without convergence — root cause: jumped to coordinator-API design without grounding in actual call flow.
  Grounding: `docs/research/2026-05-24-shared-runtime-call-flow-grounding.md` (this branch, 2026-05-24) — maps the new-editor construction call flow, full cell construction inventory (10-cell protected surface; only 1 persistent Observer today on `TypecheckBundle.output`), scope ownership graph, destroy flow, five atomic-boundary candidates with tradeoffs, ten constraints the coordinator must respect.
  Contract: `docs/research/2026-05-23-observer-discipline-contract.md`.
  Next: open a fresh brainstorm session using the grounding doc as substrate. Pick an atomic-boundary candidate (§5) before sketching coordinator API.

## 19. Cognition Runtime

- [ ] Plan a real provider-client integration before adding LLM/network calls.
  Why: PR #379 shipped the engine-agnostic provider-boundary contract with request planning, explicit completion, typed status/errors, deterministic scripted driver tests, and internal `@incr` planning/status cells. The next risk is accidentally putting credentials, HTTP clients, timers, retry loops, or provider-specific transport into `CognitionStore` instead of a separate driver/client layer.
  Plan: `docs/plans/2026-05-26-cognition-provider-boundary-design.md`
  Exit: a provider-client plan names the backend, driver clock/scheduling model, credential boundary, retry/redaction policy, and host integration surface. No real network/LLM code lands without that plan.

## 20. Scope-Graph Fidelity

- [x] Reconcile the module-binder `node_id` divergence (Option D, driven by go-to-definition).
  Plan: docs/plans/2026-05-30-scope-binder-node-id-reconciliation.md (Codex-reviewed;
  Option D: an on-demand `@scope` binder-location accessor over the
  already-populated SourceMap token spans).
  Shipped: `@scope.binder_span` + `@scope.go_to_definition` accessors
  (`lang/lambda/scope/query.mbt`); `references` migrated off `Decl.node_id` to
  `DeclId`; §7.1 go-to-def behavioral tests (`go_to_definition_wbtest.mbt`);
  live memo-stack vs fresh-rebuild scope differential coverage
  (`scope_memo_stack_differential_wbtest.mbt`); and Ideal outline scope
  annotation collapsed onto @scope with the NodeId-keyed UI model retained via
  stable module-binder UI keys. The old cross-pipeline flat-module fidelity
  tests were removed with the flat compatibility layer.
  Remaining: gated query-indexing is the only open scope follow-up here; the
  binder-location plan itself is complete.

- [x] Block-local **rename** soundness (§20 exit criterion).
  Shipped: `rename_from_var` / `rename_binding_by_id` / `rename_module_binding`
  in `text_edit_rename.mbt` no longer round-trip the block-aware `Decl` back into
  a root-relative `def_index`. They thread the resolved `Decl` + graph straight
  through, deriving references via `@scope.references(g, decl.id)`, the binder
  span directly off the decl's own `LetDef` node (no root `module_node_id`
  fallback for nested decls), and the dup-name guard off the decl's own scope
  siblings. Block-local var-rename AND binder-click rename are now sound; the
  capture guard stays conservative (over-rejects when `new_name` is bound in an
  ancestor the renamed binder would shadow — sound, never mis-renames). wbtests:
  `Rename block-local binding leaves root binding intact`, `Rename block-local
  binding by binder id`, `Rename block reference to outer binding renames root`.

- [x] Teach `edits/` **inline** ops about nested-block scopes.
  Shipped: `compute_inline_definition` / `compute_inline_all_usages`
  (`text_edit_refactor.mbt`) thread the block-aware `Decl` straight through —
  `module_def_decl_for_binding(g, id)` → `edit_binding_for_decl(ctx, decl)` for
  the def view, `@scope.references(g, decl.id)` for usages, and the node-relative
  `free_names_would_rebind_at_node` for the capture guard. No root-relative
  `def_index` round-trip. wbtests: `InlineDefinition nested block uses resolved
  declaration`, `InlineAllUsages nested block uses binding declaration`
  (#636 / #655).

- [x] Teach `edits/` **binding** ops (delete / duplicate / move) about
  nested-block scopes.
  Shipped: `compute_delete_binding` / `compute_duplicate_binding` /
  `compute_move_binding_{up,down}` (`text_edit_binding.mbt`) dropped the
  root-only `edit_module_view` + `find_def_index` + `module_view.defs[i]` path
  for the same decl-threaded shape as inline. The move ops find their swap
  neighbour with `sibling_module_def_decl(g, decl.scope, def_index ± 1)` —
  `def_index` is scope-local (the builder assigns it per scope, root and nested
  block alike), so adjacent indices in the same scope are the move neighbours;
  the first/last guards became `def_index == 0` (up) / `sibling is None` (down).
  The name-based `free_vars` move guard is unchanged. wbtests assert SOUNDNESS by
  reparsing the result (`DeleteBinding removes block-local binding`,
  `MoveBinding{Up,Down} swaps block-local bindings`,
  `MoveBindingUp rejects first block-local binding`). Follow-up PR #688 added
  adversarial coverage for block-local scoping-violation moves, deleting a
  still-referenced block binding, and root/block same-name shadowing.

- [x] Teach `edits/` **extract** op about nested-block scopes.
  Shipped: PR #674 (`f0cf3cf`, 2026-06-16) makes `compute_extract_to_let`
  find the innermost enclosing `Module` through the scope graph and insert the
  new `let` inside that block instead of hoisting to the root. wbtests cover
  block-body insertion, block-def insertion, lambda-in-block ancestry,
  empty-def blocks, and capture/rebind refusals. Verified via scope-graph wbtests
  that block-body insertion preserves resolution of block-local free vars even when
  shadowing outer bindings. The block-body path inserts after all defs so block-local
  visibility is maintained — no scope_is_within guard needed (unlike block-def path).
  Closes #659.

## 21. Analysis Query Layer

- [ ] Decide whether diagnostics join the analysis projection aggregator (#710).
  Why: Phase 2 shipped the lambda-local decoration/annotation aggregation seam in PR #706 and PR #708, but parse/type/eval diagnostics still use existing FFI/protocol paths. That is intentional until a larger diagnostic fact shape is justified.
  Plan: `docs/archive/completed-phases/2026-06-18-analysis-query-phase2-aggregator.md`
  Exit: diagnostics are either explicitly kept out of the aggregator with a stable rationale, or routed through a typed diagnostic fact shape without adding public protocol variants.

- [x] Implement Phase 1 ast-grep range-only analysis overlay (#692).
  Shipped: PR #699 added `lib/analysis/` and `analysis_bridge/`; PR #704 completed host FFI and lambda editor decoration wiring.

- [x] Add provider range normalization tests for analysis facts (#693).
  Shipped: PR #699 covered core byte→UTF-16 conversion; PR #704 added FFI-level non-ASCII coverage.

- [x] Reject stale analysis provider results by source snapshot (#694).
  Shipped: PR #699 added `SourceSnapshot::matches`; PR #704 clears stale lambda pattern facts before view patches are computed.

- [x] Add structural-search match list projection (#695).
  Shipped: PR #699 — `facts_to_match_list` supplies `from`/`to`/`pattern_id` for future host list/jump rendering. Host-side list UI remains a follow-up.

- [ ] Consolidate Lambda name resolution on `lang/lambda/scope` (#129).
  Why: edit free-variable guards and module-end lookup still carry local name-resolution walks that can drift from the canonical scope graph.
  Plan: `docs/plans/2026-07-02-lambda-name-resolution-consolidation.md`
  Exit: production edit guards, alpha lowering, and free-variable diagnostics all read scope-graph facts; duplicate edit-layer resolvers are removed or test-only; #652's module-end cutoff drift is closed.

## 22. SDEG Lifecycle

- [x] Distinguish delete from malformed transient absence (#748).
  Why: The lifecycle `Missing` state conflates a committed delete with a transient parse failure. Both produce zero current observations, but delete should progress toward retirement while a transient absence should recover when the observation reappears.
  Shipped: the Markdown projection pipeline now attaches a private heading side-table memo to the returned source-map memo. It derives snapshot validity from parser diagnostics plus recovered projection `Error` nodes before calling `advance`, so valid deletes advance absence counters while malformed snapshots mark live/ambiguous rows unavailable without advancing the absence ladder.
  Evidence: `lang/markdown/proj/sdeg_heading_side_table_wbtest.mbt` covers valid delete advancement and malformed snapshot unavailable-state behavior through the production memo path. No public SDEG or `.mbti` surface was added.

## Shipped history

Completed items (with PR references and shipping notes) are preserved in
[docs/archive/TODO-snapshot-2026-04-21.md](archive/TODO-snapshot-2026-04-21.md).
When marking work done going forward, move the completed entry into a new
dated snapshot or an existing archive plan doc rather than accumulating it
here.
