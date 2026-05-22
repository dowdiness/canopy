# Shared `@incr.Runtime` Safety Probe — Decision Record

**Date:** 2026-05-23
**Branch:** `worktree-research-from-main`
**Probe package:** `workspace/probe/gate1_runtime_safety_wbtest.mbt`
**Research basis:** `docs/research/2026-05-22-spec-aware-workspace.md` §3, Appendix B P0a #1, Appendix C #1

---

## Question

Is sharing a single `@incr.Runtime` across editors safe enough to host
cross-editor reactive surfaces (workspace dep-graph `MemoMap`, intent
queue subscribers, etc.)?

The original Appendix B P0a #1 recipe asked the question against the FFI
`destroy_editor` path. The probe widens the question to the underlying
runtime mechanics, since destroy_editor today is mostly a map-removal
operation (`ffi/lambda/lifecycle.mbt:88-101`,
`ffi/markdown/markdown_ffi.mbt:25-28`) — it doesn't actively dismantle
parser/Memo chains, and the editor handle being held vs dropped is
not what determines whether cells stay alive on the runtime.

**Decision-exit options (from the report §3):**

- **(i)** Single shared runtime per workspace with editor-level
  rooting discipline.
- **(ii)** Per-editor runtimes + a workspace bridge signal.

---

## Scope

The probe stays at the **public-API surface**: `@incr.Runtime::new`,
`@incr.Runtime::set_on_change`/`clear_on_change`,
`@incr.Runtime::cell_info`, `@incr.Runtime::gc`, `@incr.Runtime::read`,
`@incr.Memo::new`, `@incr.Memo::id`, `@incr.Memo::observe`,
`Observer::dispose`, `@loom.new_parser(..., runtime=shared)`,
`Parser::source`, `Parser::set_source`. No production-code changes.
Two **JSON** parsers on the shared runtime — same-grammar pair per
Codex finding (b); JSON is already imported in the probe package,
which avoids adding Lambda grammar imports for no informational gain.

**API surface finding (independent of any test verdict):** today the
public editor constructors (`new_lambda_editor`,
`new_markdown_editor`, `new_json_editor`) do **not** expose
`runtime?`. Each builds a `make_parser` closure that calls
`@loom.new_parser(source, grammar)` without forwarding a shared
runtime, so a fresh `@incr.Runtime::new()` is created per editor
(`lang/lambda/companion/lambda_editor.mbt:107-129`,
`lang/markdown/companion/markdown_companion.mbt:11-17`). A
shared-runtime workspace requires either (a) a new
`new_*_editor(..., runtime=shared)` constructor variant, or (b)
direct use of `@editor.SyncEditor::new_generic` with a custom
`make_parser` that forwards the runtime to `@loom.new_parser`
(`editor/sync_editor.mbt:41-77`). The probe demonstrates that path
(b) works mechanically.

---

## Findings

### Verdict table

| Section | What the probe demonstrates                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Implication                                                                                                                                                                                                                                                            |
|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| §A      | `Runtime::set_on_change` is a **single-occupancy slot** (`loom/incr/cells/runtime.mbt:449-460`). Sequential registration `fA` → `fB` silently overwrites `fA`. On a revision bump, only `fB` fires (`count_a = 0`, `count_b = 1`). The control (single-callback case) confirms the slot wires up correctly when uncontended, so the §A verdict attributes specifically to single-occupancy, not to a broken trigger path.                                                                                          | A shared runtime cannot have multiple editors directly subscribing for change notifications. A workspace-level coordinator must multiplex `set_on_change` (one registered fan-out) — or editors must use Observer-driven `Reactive`/`Effect` cells instead.            |
| §B      | Holding a parser handle **does not** pin its Memos. Without any `add_gc_root` / Observer / Effect, `Runtime::gc()` collects every Memo (`gc_role = Interior`, `loom/incr/cells/internal/pull/memo_data.mbt:46-48`). Calling `parser_b.source().observe()` pins parser B's source view across `gc()` while parser A's source view (no observer) is collected. Probe `cell_info(id)` returns `None` for collected IDs and `Some(_)` for the survivor. Control confirms: with **no** observers, both source views are collected. | Editors in a shared runtime **must** explicitly root their reactive surface through `Observer` (or other gc_role=Root cells) to survive any workspace-level `gc()`. Today no editor does this — there's no production-code call to `Memo::observe` in the editor stack. |
| §C      | A cross-editor `Memo::new` whose compute reads both `parser.source()` Memos, when rooted via `cross.observe()`, transitively pins both inputs through `gc_dependencies` BFS (`loom/incr/cells/internal/kernel/gc.mbt:63-87`). After two `gc()` calls (Codex finding (d) — second drains broadcast queue) the cross Memo, both source Memos remain alive, and a subsequent `parser_a.set_source` propagates correctly to the cross Memo. Control: same cross Memo without observer → cross + both inputs collected.       | Workspace-level Memos that join multiple editor surfaces are **self-rooting for their input cone**. The workspace dep-graph pattern from the report §3.3 is mechanically viable under (i) provided the workspace Memo is itself rooted by an Observer or downstream Effect.   |

### Codex pre-implementation review findings (incorporated)

| Finding                                                                                                                                                                                                                                                                                                                          | Reflected in                                                                                                                                                       |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| (a) Use per-cell liveness via `cell_info` — NOT aggregate cell count; disposed slots don't shrink storage arrays.                                                                                                                                                                                                                | §B and §C assert `cell_info(id) is None` / `is Some(_)` per cell, never a count delta.                                                                              |
| (b) Two-of-same-grammar — avoid mixing Lambda+Markdown.                                                                                                                                                                                                                                                                          | Probe uses two JSON parsers throughout.                                                                                                                            |
| (c) Use `parser.source()` (`Memo[String]`) — not `cached_proj_node` — for the cross-editor observable.                                                                                                                                                                                                                           | §C's cross Memo reads `parser_a.source().get().length() + parser_b.source().get().length()`.                                                                       |
| (d) `Runtime::gc()` is synchronous mark+sweep but drains pending broadcast events afterward (`runtime.mbt:564-568`) — call `gc()` twice for steady state.                                                                                                                                                                        | §B and §C call `gc()` twice before reading `cell_info`.                                                                                                            |
| (5) Implicit-pin risk from `gc_role = Root` (Effects). Production canopy creates **zero** push effects in the editor/parser/projection stack (verified grep 2026-05-23). Memos are `gc_role = Interior`, so without explicit roots the "leak" verdict of §B is unambiguous — `gc()` with no roots really collects all Interiors. | §B's negative control (no observers) confirms ALL Memos collected; §B's positive case (one observer) attributes survival cleanly.                                  |

Plus the trigger-discipline detail: §A's revision bump uses
`parser.set_source` from test top-level (no enclosing `rt.batch`).
`set_source` opens exactly one `rt.batch` internally
(`loom/loom/src/pipeline/parser.mbt:108`), so `on_change` fires exactly
once per call — making the verdict attributable.

---

## Recommendation

**Path (i) — single shared runtime with editor-level rooting discipline — is mechanically viable but requires new contracts that don't exist today.**

The probe answers the bare-mechanics question affirmatively:

1. Two parsers on a shared runtime coexist without runtime errors.
2. Cross-editor Memos work and are self-rooting for their input cone.
3. `gc()` is well-defined and respects explicit roots.

But the contracts that today's editor code does not implement:

1. Each editor must observe its **own** outputs (at least the Memos
   that downstream cross-editor surfaces will read). Without this,
   any `gc()` call wipes the editor's reactive cells.
2. The workspace must own a single `on_change` registration and
   fan it out to interested parties, or editors must abandon
   `on_change` in favour of Observer/Reactive/Effect-driven
   notification.
3. The FFI `destroy_editor` path must drop the editor's Observers
   so its reactive surface becomes collectable on the next workspace
   `gc()`. Today destroy_editor only disposes the typecheck Scope
   (`ffi/lambda/lifecycle.mbt:92`); it doesn't touch parser-side Memos
   or any future `Observer` handles.

Whether this is **simpler** than path (ii) (per-editor runtimes + a
workspace bridge signal) is a separate design question. The probe's
contribution is to make the contract list legible so that comparison
can happen on concrete terms rather than vague "shared runtime feels
risky" intuition.

---

## Named follow-ups

In rough priority order, gated on whether the report §3 chooses path
(i):

1. **Workspace-side `on_change` multiplexer.** A single registered
   callback that fan-outs to all interested subscribers (editors,
   panels). Owned by the workspace coordinator, not individual
   editors.

2. **Editor-side observer discipline.** Each `new_*_editor` should
   register `Observer`s for the Memos it externally exposes
   (`get_proj_node`, `source`, `diagnostics`, etc.) when constructed
   on a shared runtime. The Observers must be tied to the editor's
   destroy path so they dispose on `destroy_editor`.

3. **New `new_*_editor(..., runtime=shared)` constructor variants.**
   The §P0b "needed `new_generic_with_runtime` variant" surface.
   Should accept an external runtime and forward it through
   `make_parser` to `@loom.new_parser`.

4. **Codex review of workspace contract.** Before any of (1)–(3)
   land, send the contract list above to Codex for design validation
   — the contract is the load-bearing piece, not the implementation
   of any individual constructor.

5. **Per-editor runtime + bridge signal feasibility study.** If
   path (ii) is chosen instead, the bridge signal pattern needs its
   own probe — what does cross-runtime change notification look like
   when neither runtime can see the other's cells?

---

## Status

- §A — verified single-slot semantics; control passes.
- §B — verified observer-based survival; negative control passes.
- §C — verified cross-editor Memo self-rooting; negative control passes.
- All 6 gate #1 tests pass (`moon test -p dowdiness/canopy/workspace/probe`).
- Total workspace/probe count: 21 → 27.

§P0a is complete: gates #2, #3, #4, #1 all shipped on this branch.
The next slice (§P0b) can begin once the report §3 reflects the
contract list above.
