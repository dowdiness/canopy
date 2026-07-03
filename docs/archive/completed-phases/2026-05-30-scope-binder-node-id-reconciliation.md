# Scope-graph binder identity reconciliation, driven by go-to-definition

**Status:** Design — Codex-reviewed 2026-05-30 (verdict: SOUND-WITH-CHANGES; revisions folded in). Ready for implementation-doc breakdown.
**Date:** 2026-05-30
**Supersedes the open work in:** docs/TODO.md §20 ("reconcile [the node_id divergence] here, or when a consumer first reads a module `node_id` as output").

This is a design document: it states *what* to build and *why this way*. It does not contain implementation code or an ordered task list — those belong in a follow-up implementation doc once the design is validated.

---

## 1. Problem

The scope graph resolves a `Var` reference to a `Decl`. A `Decl` carries a `node_id` whose documented invariant (`lang/lambda/scope/graph.mbt`) is that it **"occupies a projection node."** That invariant holds for lambda binders and is broken for module binders. The breakage has already metastasised into **three incompatible synthetic-id schemes** for the same conceptual thing — "where is `x` bound in `let x = …`":

| Site | Module-binder `node_id` | Real tree node? |
|------|-------------------------|-----------------|
| `lang/lambda/proj/flat_proj.mbt` `to_flat_proj` (production) | fresh positive counter id | **no** — occupies nothing |
| `lang/lambda/proj/flat_proj.mbt` `from_proj_node` (test/oracle) | reuses the def's *init* node id | yes, but it's the **value**, not the binder |
| `examples/ideal/main/scope_annotation.mbt` (binder highlighting) | `NodeId::from_int(-(child.node_id + 1))` — a **negative** id | no — fabricated |

The lambda binder, by contrast, is uniformly `node.id()` of the real `Lam` `ProjNode` (`lang/lambda/scope/builder.mbt:89`), and everything Just Works for lambdas.

### Why this is the high-leverage problem, not the cross-pipeline PBT

The recently-merged cross-pipeline PBT (#401, trimmed in #402) and the #399 contract fixture both **pin this gap as a known gap** — they document the breakage, they do not close it. Meanwhile the gap imposes a concrete, shipped cost:

- **A whole consumer bypasses `@scope`.** `examples/ideal/main/scope_annotation.mbt` does not call `@scope.declaration`/`references` at all. It **re-implements scope resolution from scratch** (`walk_scope`, a second scope-stack walk that duplicates the binding rules already encoded in `lang/lambda/scope/builder.mbt`), specifically because the scope graph's module binder id cannot be mapped to a tree node it can highlight (see its own comment, lines 139–141). It then invents the third synthetic-id scheme above to key its highlight map.
- **Rename/refactor already depend on `@scope`** (`lang/lambda/edits/text_edit_rename.mbt:109`, `text_edit_refactor.mbt:144`) and work only because they re-derive the def site via `find_usages`/`def_index`, never trusting `Decl.node_id` to point anywhere.
- **Go-to-definition cannot be built at all** on top of `Decl.node_id` today: for a module def there is no node to jump to.

So the gap is not academic. It is why one feature was built twice and another can't be built once.

### What the consumer actually needs

Trace it from the feature backward (design principle §1: problem first). Go-to-definition, binder highlighting, and rename all need the same primitive: **"given a reference, where in the source is its binder?"** That is a *source range*, not a node id. The "occupies a `ProjNode`" invariant was only ever a *proxy* for "you can locate the binder." For lambdas the proxy happens to coincide with a real node; for module defs it never did, because the binding occurrence (`x` in `let x = …`) is not currently a `ProjNode` — only its init *value* is.

The cross-pipeline PBT already proved the relevant fact: **source ranges are the pipeline-independent coordinate** (both pipelines derive identical ranges from the same `syntax_to_proj_node`; only node-id *values* differ). The fix should lean on that same fact rather than fabricate node identities that then disagree.

---

## 2. Goal / Non-goals

**Goal.** Make "where is this binder?" answerable uniformly for module defs and lambda params, from a single source of truth (`@scope`), so that (a) go-to-definition can be built, (b) `scope_annotation.mbt` can delete `walk_scope` and consume `@scope`, and (c) the §20/#399 "occupies a node" gap is *resolved*, not pinned.

**Non-goals.**
- Not changing resolution *semantics* (shadowing, cutoff, sequential module scope). Those are correct and covered by `scope_equivalence_wbtest.mbt`.
- Not making the binding occurrence a structurally-editable node unless an option requires it (see Option B). Structural editing *of* a binder (drag/drop, wrap) is out of scope.
- Not touching the `@incr` incremental memo wiring beyond what id/range stability requires.

---

## 3. The crux design question

**What is a module binder's identity, and how does a consumer locate it?**

Four candidate answers (A–D), evaluated against: restores a coherent locate-the-binder contract; lets go-to-definition jump to the **name** (not the value); lets `scope_annotation.mbt` collapse onto `@scope`; survives incremental edits with stable identity; blast radius. **Recommended: Option D.**

### Option A — Reuse the init node id everywhere

Make `to_flat_proj` reuse the def's init node id (what `from_proj_node` already does), so both pipelines agree and `node_id` points at a real node.

- Locate contract: coherent, but the node is the **init value** (`0` in `let x = 0`), not the binder. Go-to-definition would jump to the value expression, not the name. Rename-at-definition cannot target the name token.
- `scope_annotation` collapse: partial — it could key on the init node, but its negative-id hack exists precisely to *avoid* colliding with the init node (which may itself be a `Lam` with its own annotation). So this reintroduces the collision it was avoiding.
- Incremental: init node id is already reconciled across edits (`reconcile_flat_proj` preserves it). OK.
- Blast radius: small. But it cements a semantically wrong target.
- **Verdict: rejected.** Cheapest, but it locks in "the binder is its value," which blocks name-level go-to-def and rename and re-creates the collision.

### Option B — Give the binding occurrence its own `ProjNode`

Insert a dedicated binder node (carrying the name token's span) into the Module `ProjNode`, so `Decl.node_id` points at a first-class binder node in both pipelines.

- Locate contract: ideal — restores "occupies a node" literally, target is the name.
- `scope_annotation` collapse: yes.
- Incremental: needs a new id-stability story for the binder node in `reconcile_flat_proj`.
- Blast radius: **large.** It changes the Module child layout (`children = [init₀…initₙ, body]`), which is assumed by `from_proj_node`, `to_proj_node`/`to_proj_node_with_prev_module_id`, `scope_annotation.walk_scope`, the cross-pipeline PBT's `def_init_ranges`, `find_binding_for_init`, and likely SourceMap/outline rendering. Every "first N children are inits" site breaks.
- **Verdict: viable but heavy.** Justified only if a future need makes the binder a structural citizen (e.g. drag-drop a binding, structural rename UI). Record as the eventual endpoint, not the first step.

### Option C — `Decl` carries a materialised binder source-range field

Add a binder **source range** field to the scope graph's `Decl` (name-token span for module defs; `(x) =>`/`Lam` span for lambda params). Consumers use the range to locate the cursor; `node_id` is demoted to an internal detail.

- Locate contract: replaces the *proxy* invariant ("occupies a node") with the *real* one ("carries the binder's source range"). Go-to-def jumps to the name; rename targets the name span.
- `scope_annotation` collapse: see §5 caveat — not as direct as first assumed (outline rows are keyed by `NodeId`).
- Incremental: see §8 Q3 — store the binder's *identity* (preserved id / `DeclId`), recompute the *range* each parse; ranges legitimately shift with edits ("current-source location," not a stable range).
- Blast radius: **medium.** No Module child-layout change. But it requires `Decl` to gain a field AND the range to be threaded from the parse into `builder`. Codex review found the threading is **unnecessary** — see Option D.
- **Verdict: viable, but D is cheaper.** Keep C only if a stored range field on `Decl` is later wanted for ergonomics.

### Option D — On-demand binder location via the existing `SourceMap` token spans (recommended)

Codex design review (2026-05-30) surfaced that the binder ranges **already exist**: `lang/lambda/proj/populate_token_spans.mbt` already records each `let`-name token span on the Module node via `SourceMap::set_span_from_token` (a test asserts `let x` → `4..5`, `projection/source_map_token_spans_wbtest.mbt:63`). So instead of materialising a range onto `Decl` or threading it through `FlatProj`, expose a **binder-location accessor** on `@scope` that resolves on demand through `SourceMap::get_token_span` (`core/source_map.mbt:309`):

- lambda binder → the `Lam` node's range (already a real node);
- module binder → `(module_node_id, "name:<def_index>")` looked up in the SourceMap token spans.

- Locate contract: same real invariant as C (a source location per binder), with **zero new storage**.
- Feasibility gate (§4): **already satisfied** — the spans are populated today; no loom PR, no `LetDefView::name_range()` needed (though that method is trivially implementable from seam if a cleaner API is wanted — see §4).
- `FlatProj`: **unchanged** — no tuple churn, so the binding-handle consumers of `defs[i].3` (§6) are untouched.
- Blast radius: **small–medium.** Add the accessor + migrate `references` off `node_id` (§6); `Decl.node_id` can stay as-is internally or be deprecated later.
- **Verdict: recommended.** Cheapest path that gives consumers a locatable binder, reuses already-maintained machinery, and avoids both the tree-shape change (B) and the `FlatProj`/loom changes (C).

> Design note (principle §2, question binary framings): the original framing was "make `node_id` a real node (B) vs. leave it synthetic (status quo)." Both C and D widen the frame — the consumer never needed a *node*, it needed a *location*. D goes further: it observes the location is *already recorded* in the SourceMap, so the fix is an accessor, not new data. This is the design neither original option contained.

---

## 4. Feasibility gate — RESOLVED (the binder span already exists)

Codex design review confirmed the gate is **already satisfied**, which is what makes Option D cheap:

- Seam retains absolute UTF-16 offsets through the CST → `SyntaxNode` facade; `SyntaxToken` exposes `start()`/`end()` and `SyntaxNode::find_token` returns positioned tokens (`loom/seam/syntax_node.mbt:15,20,404`). `LetDefView::token_text` is just a text-only wrapper over the same path (`:438`), so `LetDefView::name_range()` is trivially implementable **with no new seam capability** — but D doesn't even need it.
- The decisive fact: lambda projection **already records each `let`-name token span** on the Module node via `SourceMap::set_span_from_token` (`lang/lambda/proj/populate_token_spans.mbt:35,45`), and a test asserts `let x` produces span `4..5` (`projection/source_map_token_spans_wbtest.mbt:63`). The location Option D needs is already maintained on every parse.

Consequence: **no loom PR, no `LetDefView::name_range()` prerequisite, no pointer bump.** (A `name_range()` helper remains an optional ergonomic cleanup, not a blocker.) This removes the original sequencing step 1.

One thing to confirm during implementation: tests that build a `SourceMap` via plain `SourceMap::from_ast` *without* calling `populate_token_spans` would not have the let-name spans — the builder/accessor must either require populated spans or be robust to their absence.

---

## 5. Driving consumer: go-to-definition

Build go-to-definition as the thin end-to-end consumer that *forces* the fix and proves it:

1. Editor receives a "go to definition" request at a cursor position.
2. Map position → reference `NodeId` (existing SourceMap `innermost_node_at` / `nodes_at_position`).
3. `@scope.declaration(graph, ref_id)` → `Decl`.
4. Resolve the binder **location** via the Option-D accessor (lambda → `Lam` range; module → SourceMap token span for `name:<def_index>`) and move the cursor / select it.

**`scope_annotation` cleanup is a *second* step, not free (Codex correction).** The current outline highlight model is `HashSet[NodeId]` and colours rows by `model.scope_map.get(node.id())` (`examples/ideal/main/view_outline.mbt:55,95`). A range/location-based module binder cannot light up an outline *row* without one of: keeping a stable per-binder id as the row key (so the highlight map stays `NodeId`-keyed while *navigation* uses the range), mapping ranges back to rendered rows, or changing the UI model. So go-to-definition is the clean forcing consumer; collapsing `scope_annotation` onto `@scope` follows as a distinct step with an explicit UI-representation decision. The leverage (one resolver, one binder scheme) still lands — just in two moves, not one.

---

## 6. Blast radius (Option D, recommended)

- **`lang/lambda/scope/` (graph.mbt / query.mbt / builder.mbt)** — add a binder-location accessor (e.g. `binder_span(g, decl, source_map) -> Range?`). Resolution itself is untouched: `resolve` matches only `decl.name` + `decl.kind` and `pass3` resolves references from registry node ids, not binder ids (`builder.mbt:146,163,192`). The "occupies a node" doc note in `graph.mbt` is rewritten to "a binder's location is its source span, recovered via `SourceMap` token spans."
- **`references(g, decl_node)` MUST migrate off `node_id` (Codex finding).** Today it searches decls by `d.node_id` (`query.mbt:18`) — the one real consumer of `Decl.node_id` as a key. Re-key it on `DeclId` (or a stable binder key) before/with demoting `node_id`, or it silently preserves the broken "binder is a NodeId" contract.
- **`FlatProj`: UNCHANGED under D.** No tuple change → the binding-*handle* consumers of `defs[i].3` stay intact: `find_binding_for_init` (`lang/lambda/edits/scope.mbt:54`), binding-edit lookup (`text_edit_utils.mbt:39`), action plumbing (`examples/ideal/main/action_model.mbt:27`), binding ops (`text_edit_binding.mbt:2`). (If a future need forces Option C instead, introduce a named `FlatDef` struct rather than growing/replacing the 4-tuple — the 4th element is a *binding handle*, not just scope dedup, so it must be *added to*, never *replaced*.)
- **`examples/ideal/main/scope_annotation.mbt`** — collapses onto `@scope` as the *second* step, with the UI-model decision from §5. Net code removed once landed.
- **Tests that pin the gap** — the #399 module-`node_id`-is-synthetic fixture and the cross-pipeline PBT's `assert_production_node_id_invariants` are *designed* to fail when the gap closes (the failure is the intended signal). Rewrite them to affirm the new contract (binder span present and pipeline-equal) rather than the old gap — don't just delete the coverage.
- **Rename/refactor** (`text_edit_rename.mbt`, `text_edit_refactor.mbt`) — unchanged; optionally simplified later to use the binder span.

`from_proj_node`'s and the PBT's "first N children are inits" assumption is **preserved** under D (no tree-shape change), and verified against the layout: `to_proj_node_with_prev_module_id` emits `[init₀…initₙ, body]` (`flat_proj.mbt:251`), `from_proj_node` reads it back (`:277`), `populate_token_spans` documents the same (`populate_token_spans.mbt:27`). Option B would break all of these.

---

## 7. Test strategy

1. **Go-to-definition behavioral tests** — cursor on a `Var` lands on the right binder name span: module def, shadowed module def (later wins), lambda param, nested-lambda shadowing, free var (no jump). These replace the gap-pinning fixtures with contract-affirming ones.
2. **Incremental ↔ full differential resolution test (high-leverage, currently missing).** Apply a sequence of edits to an editor, then assert that the incrementally-maintained scope graph resolves every reference *identically to a fresh full parse + build of the final text* — including the binder ranges. This is the analog of `loom/examples/lambda/src/imperative_differential_fuzz_test.mbt` and covers the `@incr`/`to_flat_proj_incremental` path the cross-pipeline PBT explicitly excludes. This is where the real, untested staleness bugs live; the binder-range work is the natural moment to add it.
3. **Retain** `scope_equivalence_wbtest.mbt` (the hand-derived semantic oracle) unchanged — it remains the guard against a shared bug in `@scope.build` that any equivalence/differential test is blind to.

---

## 8. Open questions (status after Codex review 2026-05-30)

1. **Feasibility gate — RESOLVED.** The binder spans already exist in the SourceMap; no loom work needed (§4).
2. **Option D vs B — RESOLVED for now: D.** Codex found no current consumer that needs the module binder to be a first-class `ProjNode`; resolution and `pass3` don't key on it, and the only `Decl.node_id`-as-key use is `references` (which migrates to `DeclId`). Revisit B only if structural editing *of* a binder is later required.
3. **Binder dedup identity vs range (Q3, refined).** Frame the binder's stored identity as the preserved id / `DeclId`, and treat the range as a recomputed **"current-source location,"** not a stable value — ranges legitimately shift with edits (correct for navigation). Note an existing limitation Option D does *not* fix: `reconcile_flat_proj` matches defs by **name** (`flat_proj.mbt:178`), so renaming a binder allocates a fresh id. If stable identity across rename is later needed, that's separate work.
4. **Lambda binder span target (still open):** does go-to-def/highlight want to land on the whole `Lam`, the parameter-list head, or the param-name token? Pick for symmetry with the module name-span and for the nicest cursor behaviour.
5. **`references` migration (new, from Codex):** confirm the target key for `references` after `node_id` is demoted — `DeclId` vs a binder-span key — and that no other caller relies on the `NodeId`-keyed form.
6. **Gap-test rewrite:** confirm the #399 fixture + PBT `node_id` invariants are *rewritten* to affirm the new contract, not deleted, so regression coverage survives.

---

## 9. Sequencing (Option D; design validated)

No loom PR — the feasibility gate is already satisfied (§4).

1. Add the `@scope` binder-location accessor (lambda → `Lam` range; module → SourceMap token span for `name:<def_index>`), backed by the already-populated let-name spans. Migrate `references` off `Decl.node_id` to `DeclId` in the same change.
2. Build go-to-definition as the driving consumer; add its behavioral tests (§7.1). **This is the visible payoff and the forcing function.**
3. Add the incremental ↔ full differential resolution test (§7.2) — the genuinely-missing coverage for the `@incr` path.
4. Rewrite the #399 fixture + cross-pipeline PBT `node_id` invariants to affirm the binder-location contract (§6).
5. Collapse `scope_annotation.mbt` onto `@scope` — *after* deciding the outline-highlight UI representation (§5). Net code removed.
6. Mark docs/TODO.md §20 resolved; archive this plan per the docs protocol.

Steps 1–4 are independently reviewable and self-contained; step 5 carries the UI decision and can trail.
