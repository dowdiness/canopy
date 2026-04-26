# Lambda Typecheck Pipeline Evolution

**Status:** 1/6 shipped (1a only; 1b open)

## Why

The lambda diagnostic pane is wired end-to-end (PR #186 + follow-ups #190/#191/#194), but the pipeline that feeds it has structural debt that blocks every future surface (hover, inline squigglies, inlay hints, type-on-cursor, click-to-jump from diagnostic). The debt isn't bugs — it's missing primitives:

- Diagnostics carry no source `Range`, so nothing downstream can point at code.
- Wire format is ad-hoc JSON, re-stringified per rAF tick, with stringly-typed schema drift.
- JS pulls every input event instead of subscribing to memo changes the runtime already knows about.
- Canopy builds the typecheck pipeline without the index variant, so there's no `NodeId → Type` lookup.
- `ModuleTypeResult` re-runs on any edit; cost model is O(file) where users expect O(edit).
- Two `TypecheckAttachment`-shaped structs exist (loom example + canopy bundle) with no shared abstraction in `@typecheck`.

These are the primitives that, once present, make every UI surface a ~10-line consumer rather than a new pipeline.

## Scope

In:
- `ffi/lambda/{lifecycle,diagnostics}.mbt`
- `lang/lambda/companion/*.mbt` (potentially)
- `loom/examples/lambda/src/typecheck/` (the typecheck module — extending API surface)
- `loom/examples/lambda/src/typed_parser.mbt` (`TypecheckAttachment` — promoted into typecheck module)
- `examples/web/src/editor.ts`
- New: typed wire protocol package (parallel to `ViewPatch`)

Out:
- JSON editor's typecheck (no typecheck pipeline today; not in scope)
- Markdown editor's diagnostics (different shape, separate work)
- Egglog/incremental evaluator integration with type errors (tracked in #13 Lambda Evaluator)
- LSP server export (this work makes one *possible*, but isn't one)

## Current State

- `ffi/lambda/lifecycle.mbt:15` — `priv struct TypecheckBundle { scope, output }`. No `TypecheckIndex`. Built via `build_typecheck_pipeline`, not `_with_index`.
- `ffi/lambda/diagnostics.mbt:36-78` — `get_diagnostics_json` flattens parse + type + eval into an untyped JSON array. Type diagnostics carry `{level, message, def_name?}` only — no range, no severity beyond "error", no related-info, no diagnostic code.
- `examples/web/src/editor.ts:55-69` — polls every input event via rAF, `JSON.parse`s the array, replaces `#error-output` innerHTML each tick.
- `loom/examples/lambda/src/typed_parser.mbt::TypecheckAttachment` — uses `build_typecheck_pipeline_with_index` and `add_observer` for GC anchoring; canopy doesn't use it (example modules aren't workspace members).
- `@typecheck` exports both `build_typecheck_pipeline` and `build_typecheck_pipeline_with_index` already; the index is `NodeId → Type` keyed.
- `ModuleTypeResult.all_diagnostics : Array[TypeDiagnostic { level, message, def_name : Option[String] }]` — `range` is absent at the source.

## Desired State

A layered pipeline where each layer is a pure function of the layer below, and the FFI exposes subscriptions + queries over typed protocols:

```
L0  Runtime + Source Signal
L1  Parse cells (tokens, CST, AST, parse diagnostics)
L2  Per-def TypedDef memos    →  Module result = combine(defs)
L3  Indices (TypecheckIndex, SourceMap, Diagnostics-with-ranges)
L4  FFI: subscribe(kind, cb) + query(kind, args)
L5  Typed wire protocol (versioned, generated bindings)
L6  UI consumers (~10 lines each: pane, squigglies, hover, inlays)
```

Two queries — `nodes_with_diagnostics` and `smallest_enclosing(offset)` — feed every surface. Layer below knows nothing about layer above; typecheck doesn't know about positions, the wire protocol doesn't know about the DOM.

## Approach — why this ordering

The ordering is value-per-disruption, not feature appeal. **Ranges first** because every other improvement assumes them: you can't squiggly without a range, can't write hover that links to errors without ranges, can't scope per-def memos cleanly without per-def ranges. Range is the load-bearing absence; everything else is shape-of-the-house decisions.

After ranges, **typed wire** is cheap once data is structured. Then **TypecheckIndex** unlocks hover with no new infrastructure. **Subscription bridge** retires polling once there are enough surfaces to justify the FFI work. **Per-def memos** is the cost-model fix, deferred until module size demands it. **Hoisting `attach_typecheck`** is last because it's a refactor of working code, not a capability.

## Steps

### 1. Plumb source ranges into type diagnostics

The naive framing ("just thread positions through") collides with reality: `TypedTerm` has no positions (it's `Var(String) | Lam(String, Type?, TypedTerm) | App(TypedTerm, TypedTerm) | …`). The CST has positions; `convert_from_cst` drops them. `infer` runs after convert, so `DiagCtx` can't see CST positions without help. Three design options surfaced:

- **A. `Located<T>` envelope around `TypedTerm`.** Cleanest semantics; ranges first-class on the typed AST. Invasive — every match site rewrites.
- **B. Side-table `Map[NodeId, Range]` keyed by `id : Int` on `TypedTerm`.** Needs a new field on every `TypedTerm` variant. Less invasive than A but still touches every constructor.
- **C. Thread the *enclosing def's* range through `DiagCtx`.** Convert tags each `DefEntry` with its CST range, infer reads it from context on `emit`. Only ~80 lines, single package. Sub-expression precision lost — diagnostics point at the def, not the subterm.

**Decision:** ship C now, plan A later. C unblocks click-to-locate-by-def (already what the existing `def_name` UI implies), and most diagnostics are def-shaped anyway (`unbound variable`, `missing annotation`, `duplicate def`). A is the long-term ideal — preserves sub-expression precision needed for inline squigglies and precise hover errors. When A lands, C's `current_def_range` becomes redundant and is removed.

Split into two commits:

**1a. Structural wedge.** Reuse the existing `@core.Range` from `loom/loom/src/core/range.mbt` (mature API: `contains`, `overlaps`, `merge`, `length`, `Eq`, `Hash`, `Compare`, `Show`). Add `range : @core.Range?` to `TypeDiagnostic`. Add `dowdiness/loom/core @core` to `typecheck/moon.pkg`. Update the 4 construction sites to pass `range: None`. **Do not** introduce a fourth local Range — `@core.Range`, `@text.Range` (egw), and the implicit positions in seam are already 3 too many; the `lib/range` unification (canopy TODO §3) will lift this; depending on `@core` from typecheck is the honest reflection of where Range lives today. **Exit:** `TypeDiagnostic.range` field exists end-to-end; `moon check && moon test` green; web UI unaffected (still ignores the field).

**1b. Populate def-level ranges.** Extend `DefEntry` with `range : Range`. Update `cst_convert` to capture the def's `SyntaxNode` range. Add `current_def_range : Range?` to `DiagCtx`, set per-def in the typecheck pipeline. Update `emit` to read from context.

**Codex-flagged pitfalls (do not skip):**
- **Duplicate-definition diagnostics bypass `emit()`.** They're synthesized inline in `typecheck.mbt`'s `rebuild_chain` (line ~235). `DiagCtx` threading alone won't populate their range — handle them separately by tagging with the offending def's range at the construction site.
- **Nested `Module` nodes reuse the parent `ctx`.** In `infer_impl` (line ~160), block-local `let`s inside a top-level def will inherit the *outer* def's range. Either tighten `current_def_range` on every `Module` recursion (preferred) or document that 1b's granularity is "outermost enclosing def" with nested-def precision deferred to 1c.

**Exit:** every type diagnostic raised inside a named def carries that def's range; duplicate-def diagnostics carry the offending def's range; web UI click on a diag entry scrolls editor to the def.

**Step exit (1 overall):** click-to-locate works at def granularity in the lambda editor. Sub-expression precision is tracked as a separate plan (option A: `Located<T>` envelope) and not in scope here.

### 1c (future, separate plan). `Located<T>` envelope on `TypedTerm`

Wrap every `TypedTerm` recursion site in a `Located[TypedTerm]` carrying a source range. Threading is invasive but the result is principled: ranges are properties of the typed AST, not a side-channel. Inline squigglies and per-subterm hover errors require this. Open as a fresh plan when step 4 (subscription) and step 5 (per-def memos) are done — the cost-benefit shifts once the surrounding pipeline is mature.

**Codex-flagged design risk:** if the wrapper makes range part of `TypedTerm` structural `Eq`, harmless source-position shifts (e.g. an edit earlier in the file shifts every later byte by +1) will invalidate every downstream memo even when term *structure* is unchanged. Fix by either (a) deriving a custom `Eq` that ignores the range, (b) using a `Located<T>` whose `Eq` impl delegates only to `T`, or (c) keeping ranges in a side-table keyed by node identity rather than embedded in the term. Decide before invasive threading begins.

### 2. Lift diagnostic wire format to a typed protocol

Define `Diagnostic { range, severity, message, def_name?, code? }` in a shared protocol package, parallel to `ViewPatch`. Generate JS bindings via the existing `npm_typed`-style flow. Retire `get_diagnostics_json` stringify path; switch FFI to emit typed diagnostics. Web UI consumes typed objects directly.

**Exit:** no `JSON.stringify`/`JSON.parse` in the diagnostic path; renaming a field is a compile error on both sides.

### 3. Add `TypecheckIndex` + hover query

Switch `TypecheckBundle` to `build_typecheck_pipeline_with_index`. Store `index : @typecheck.TypecheckIndex` on the bundle. Add `query_type_at_offset(handle, offset) -> TypeRepr?` FFI: source map gives `offset → SyntaxNode`, index gives `SyntaxNode → Type`, formatter renders. Wire a debounced hover handler in `examples/web/src/editor.ts`.

**Exit:** hovering a token in the lambda editor shows its type in a tooltip; hovering whitespace or unresolved nodes shows nothing without errors.

### 4. Subscription bridge across the FFI

Replace rAF-polling for diagnostics + pretty patches with push-based observer callbacks: JS registers a callback per `kind`; MoonBit's runtime fires it when the corresponding memo changes. Keep `query_*` synchronous-pull for hover (event-driven, not memo-driven). Polling stays as a fallback path for environments that can't bridge callbacks.

**Exit:** typing a character that doesn't change diagnostics produces zero diagnostic-pane re-renders and zero JSON ser/de.

### 5. Per-def typing memos

Replace single `Memo[ModuleTypeResult]` with `Map[DefId, Memo[TypedDef]]` materialized from the AST, combined into the module result. New def → new memo. Removed def → memo disposed. Edit inside one def → only that def's memo invalidates. Requires stable `DefId` (already exists for evaluator memos; reuse).

**Exit:** edit inside def `f` does not recompute typecheck for any def `g ≠ f` (verified via memo recompute counter test).

### 6. Hoist `attach_typecheck` into `@typecheck`

Move the attachment abstraction from `loom/examples/lambda/src/typed_parser.mbt` into the `@typecheck` package, with options for observer mode (anchor vs. not). Both canopy's `TypecheckBundle` and the loom example call the shared abstraction. Remove duplicate scope-management code.

**Exit:** `TypecheckBundle` is a thin wrapper over `@typecheck.attach`; the loom example uses the same call with different options; no scope-management code is duplicated.

## Acceptance Criteria

- [x] Step 1a: `TypeDiagnostic.range : @core.Range?` field exists; all construction sites updated; `moon check && moon test` green in loom (556 tests). Shipped as loom PR #99, merged 2026-04-26 (`36745f8`).
- [ ] Step 1b: every type diagnostic inside a named def carries that def's range; web UI click-to-locate works at def granularity.
- [ ] Step 2: typed diagnostic protocol with generated bindings; no JSON-string round-trip.
- [ ] Step 3: hover shows types in lambda editor; FFI exposes `query_type_at_offset`.
- [ ] Step 4: diagnostic pane updates are subscription-driven; no rAF polling for unchanged data.
- [ ] Step 5: per-def memos verified by recompute-isolation test.
- [ ] Step 6: single shared attachment abstraction; loom example + canopy both consume it.

## Validation

```bash
# After each step
moon check
moon test
cd loom/examples/lambda && moon test

# After steps that touch web:
cd examples/web && npm run build && npx playwright test

# After step 5:
cd lib/semantic && moon test  # if typecheck spans this package
```

## Risks

- **Step 1 (ranges) risk:** `TypeDiagnostic` is a public type; adding a required field breaks downstream. Mitigation: add as `Option[Range]` first, populate everywhere, then tighten in a follow-up.
- **Step 4 (subscriptions) risk:** crossing the FFI with callbacks differs by target (JS vs native). Native build may need a polling fallback indefinitely. Acceptable — JS is the user-facing target.
- **Step 5 (per-def memos) risk:** module-level diagnostics that span defs (e.g., name resolution conflicts) need careful scoping; a per-def memo can't see other defs' types. Mitigation: keep a thin module-level memo for cross-def checks, with per-def memos handling local typing.
- **Ordering risk:** steps 1 and 2 are tempting to bundle ("we're already touching the wire"). Resist — step 1 ships value alone (click-to-locate), step 2 is a wire refactor that can wait one PR cycle.

## Notes

- Related memory: `project_lambda_type_diagnostics_followups.md` — links here as the canonical tracking doc.
- Related TODO: `## 16. Lambda Type System` (this plan's index entry).
- Related plan: `docs/plans/2026-04-02-lambda-evaluator-design.md` — Phase 3b (per-def eval memos) shares the per-def-memo abstraction with step 5; coordinate stable `DefId`.
- Reference: `loom/examples/lambda/src/typed_parser.mbt::TypecheckAttachment` — current best-shape source for step 6.
- Reference: pretty-printer's `ViewPatch` (`@canopy/editor-adapter`) — wire-protocol model for step 2.
