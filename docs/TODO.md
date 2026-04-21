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

- [ ] Remove redundant render-time tree scans (e.g. sidebar selection lookup from the full rendered tree).
  Why: low priority — full frame is <1 ms, but the scans are still wasted work.
  Exit: render path does not scan the full tree for already-known state.

---

## 5. Memory & Scalability

- [ ] Implement lazy loading for 100 k+ operation documents (load causal graph skeleton, hydrate on demand).

- [ ] Add B-tree indexing for FugueTree (O(n) → O(log n) random-access character lookup).

- [ ] Cheaper `FugueTree::lv_to_position`.
  Why: current impl allocates the full visible-items array then linearly scans. Replace with a tree walk that counts visible items and exits early when target LV is found. No allocation, O(n/2) average. ~20 lines in `event-graph-walker/internal/fugue/tree.mbt`. Bottleneck for incremental remote cache updates.

---

## 6. Testing Gaps

- [ ] E2E tests for outline tree panel.
  Why: `examples/ideal` outline tree operations (select, collapse, expand, drag-and-drop) have no E2E coverage. Unit tests in `projection/tree_editor_wbtest.mbt` (67 tests) cover the logic, but no browser-level verification exists for the Rabbita-based outline UI.

---

## 7. Code Cleanup

- [ ] Tighten `ActionRecord` visibility (GitHub #97).
  Exit: `ActionRecord` fields use appropriate visibility modifiers.

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

- [ ] Extract ephemeral subsystem — move ~9 files / ~1500 lines (EphemeralStore, EphemeralHub, EphemeralValue, presence types, cursor view, encoding) from `editor/` to its own package.
  Why: zero dependency on editor concepts. Self-contained collaboration primitive with own binary protocol, encoding, and timeout logic.
  Exit: `editor/` imports ephemeral as a dependency; ephemeral has its own test suite.

- [ ] Unify sync protocol — `editor/sync_protocol.mbt` and `relay/wire.mbt` independently encode/decode the same binary wire protocol (version 0x02, same message types).
  Why: duplication risks protocol drift between client and server.
  Exit: shared protocol definition used by both editor and relay.

---

## Shipped history

Completed items (with PR references and shipping notes) are preserved in
[docs/archive/TODO-snapshot-2026-04-21.md](archive/TODO-snapshot-2026-04-21.md).
When marking work done going forward, move the completed entry into a new
dated snapshot or an existing archive plan doc rather than accumulating it
here.
