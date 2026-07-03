# Lambda thinning/lifting egraph evaluation

**Status:** Evaluation + prototype evidence
**Date:** 2026-06-18
**Issue:** #681
**Decision:** Prefer a Canopy-side context/thinning wrapper prototype over making `Lift(thin, id)` a first-class production e-node. Keep upstream `dowdiness/egraph` as the underlying engine.

## Context verified

- PR #705 (`47b2ead`) added `alpha_key(AlphaTerm) -> AlphaKey`.
- PR #707 (`9fed6c7`) added `lang/lambda/alpha_egraph_adapter` on top of the shared `dowdiness/egraph` engine.
- `lang/lambda/alpha_egraph_adapter/README.mbt.md` makes the adapter explicitly Canopy-side because it depends on `AlphaTerm`, `BinderId`, `ScopeGraph`, `ProjNode[@ast.Term]`, and the named Lambda AST boundary.
- The alpha-safe boundary ADR still keeps named `@ast.Term` plus `ScopeGraph` as the source/display boundary, and warns that the existing string/name-based lambda egraph examples are not safe for substitution.
- Current alpha egraph guardrails already cover the canonical capture case, skip beta on incomplete arguments, and avoid untyped arithmetic identity rewrites.

## Existing API First

Reuse:

- `@egraph.EGraph` / `@egraph.AnalyzedEGraph` as the only egraph engine.
- `EGraph::add`, `union`, `rebuild`, `search`, `apply_rewrite`, and `extract` for ordinary equality saturation.
- `AnalyzedEGraph` analysis hooks for beta/substitution and constant folding, matching the current alpha adapter.
- `@alpha.AlphaTerm`, `AlphaRef`, `BinderId`, `alpha_key`, `lower_root`, and `reify` for Lambda binder safety.
- `@scope.ScopeGraph` for named-source binding resolution before egraph work.

Checked but not sufficient:

- `alpha_key` is excellent for whole-term alpha equivalence, but open subterms only become comparable when interpreted under a binder context. That is the gap thinning/lifting would address.
- `loom/egraph/examples/lambda-opt` is useful API reference, but its string variables and free-variable guards are not a safe substrate for Canopy Lambda substitution.

## Approach A: explicit `Lift(thin, id)` e-nodes

Sketch:

```moonbit
// Conceptual only.
ALift(Thin, @egraph.Id)
```

The regular egraph would store lifted terms as ordinary nodes. Rewrites would include identities and distribution laws such as:

- `Lift(id, ?x) => ?x`
- `Lift(t2, Lift(t1, ?x)) => Lift(compose(t2, t1), ?x)`
- `Lift(t, App(f, a)) => App(Lift(t, f), Lift(t, a))`
- binder-specific rules that extend the thinning under `Lam` / `LetDef` / `Module`

### Pros

- Requires no upstream `EGraph::union` signature change.
- Can be prototyped inside `AlphaLang` with the current egraph APIs.
- Makes lifting visible to ordinary extraction and debugging.

### Problems

- It pollutes the Lambda e-node language with administrative nodes that should not survive to the named `@ast.Term` boundary.
- The current pattern language binds variables to `Id`, not to `(Thin, Id)`, and payloads are strings, not typed thinning variables. Searching over unknown thinnings would require either many generated concrete patterns or a custom matcher.
- Lift distribution rules can explode: every constructor gains lift-push/pull variants, and composition creates many administrative alternatives.
- `union(id_a, id_b)` remains globally meaningful only when both ids already denote terms in the same context. Accidentally unioning a raw id with a lifted id would assert a stronger equality than intended.
- Extraction would need a custom normalizer/cost function to prevent `Lift` nodes from reifying as source terms or from hiding capture hazards.

### Verdict

Good for a tiny smoke test, but not the production direction. It is too easy to turn context metadata into ordinary equality and too hard to make e-matching infer thinnings without explosion.

## Approach B: context/thinning wrapper around `EGraph`

Sketch:

```moonbit
// Conceptual only; Canopy-side, not a new engine.
struct LambdaContext(Array[@alpha.Binder])
struct Thin(...) // finite embedding/renaming between LambdaContext values
struct ContextualId { ctx : LambdaContext; id : @egraph.Id }
struct ThinEGraph { eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState] }
```

The wrapper exposes context-aware operations while delegating storage, congruence, analysis, and extraction to `AnalyzedEGraph`:

- `add_at(ctx, term) -> ContextualId`
- `lift(to_ctx, cid) -> ContextualId`
- `union_at(ctx, left, right)`
- `search_at(ctx, pattern)` with finite thinning candidates derived from existing contexts, not generated blindly
- `extract_at(cid) -> AlphaTerm`, then `@alpha.reify(..., policy)`

### Union semantics

The upstream API should stay `union(Id, Id)`. The wrapper should not ask upstream to understand binders. Instead:

1. Convert both contextual ids to a common target context using explicit thinnings.
2. Add any required administrative representation privately.
3. Call `eg.union(id_left_in_target, id_right_in_target)` only after both ids denote terms in the same target context.

If no finite/common context is available, the wrapper must refuse the union rather than weakening raw equality.

### E-matching without thinning explosion

The wrapper should enumerate only thinnings that are already justified by the finite Lambda contexts in the egraph:

- exact same context first;
- prefix weakenings introduced by descending under binders;
- alpha-renamings between contexts with the same binder shape;
- optionally, support-set-driven thinnings from the free/bound references observed in an eclass.

Do not search all injections between contexts. Keep match budgets from the existing saturation loop, and add prototype counters for candidate thinnings considered per match.

### Extraction and capture

Extraction must be context-aware:

1. Extract a `RecExpr[AlphaLang]` from the underlying egraph.
2. Interpret it at the requested `LambdaContext`, applying the contextual thinning metadata.
3. Produce an `AlphaTerm`, not a named term.
4. Reify through `@alpha.reify`, which already freshens binders and preserves the `Display` / `Source` boundary policy.

This keeps the canonical capture case safe:

```text
((x) => (y) => x) y  ==>  (y1) => y
```

The named output is produced only after alpha-safe extraction, so a free `y` cannot be captured by the result binder.

### Verdict

This is the better prototype direction. It keeps context as semantic metadata instead of ordinary equality, and it can be built around the existing `AnalyzedEGraph` without introducing a second engine.

## Example that proves value beyond `alpha_key`

Whole closed terms such as `(x) => x` and `(y) => y` are already handled by `alpha_key`. The useful thinning/lifting test must involve open subterms where a binder context is required.

Prototype fixture:

```text
let id1 = (x) => x
let id2 = (y) => y
(id1 1) + (id2 1)
```

The lambda bodies are open subterms:

- body of `id1`: `Bound(x)` under context `[x]`
- body of `id2`: `Bound(y)` under context `[y]`

Without context, raw `BinderId`s differ and the current egraph does not share those bodies. Whole-lambda `alpha_key` can say the two lambdas are alpha-equivalent, but it does not give the egraph a way to share or rewrite the open bodies under their binders. A thinning wrapper should be able to compare both bodies in a one-binder abstract context and then let the enclosing lambdas share the same optimized body class.

A second alpha-heavy fixture should include the capture case twice under different binder names:

```text
((x) => (y) => x) y
((a) => (b) => a) y
```

Both should extract to alpha-equivalent `(fresh) => y` terms, and neither result may capture the free `y`.

## Placement

Belongs in Canopy first:

- `LambdaContext`, `Thin`, contextual add/union/search/extract, and all capture fixtures depend on Lambda `AlphaTerm`, `BinderId`, `ScopeGraph`, and named `@ast.Term` reification.
- Keep the prototype inside or beside `lang/lambda/alpha_egraph_adapter`; do not move Lambda binder policy into `dowdiness/egraph`.

Possible upstream follow-ups only after the Canopy prototype proves value:

- an analyzed runner for `AnalyzedEGraph` so adapters do not hand-roll saturation loops;
- budgeted/public search hooks if contextual matching needs them;
- generic helper APIs only if they can be expressed without Lambda binders, `ScopeGraph`, or named AST policy.

## Prototype evidence

The first prototype is private and test-only. Its job is to prove that context metadata adds value beyond whole-term `alpha_key`, not to ship a production optimizer expansion.

### Files

Implemented as a white-box prototype beside the existing adapter:

- `lang/lambda/alpha_egraph_adapter/thin_context_proto_wbtest.mbt`

The prototype is compiled only for white-box tests and adds no public API. `moon info lang/lambda/alpha_egraph_adapter` produced no intended `.mbti` widening.

### Prototype data model

Conceptual private shape:

```moonbit
priv struct LambdaContext {
  binders : Array[@alpha.BinderId]
}

priv struct Thin {
  // `map[i]` is the source-context binder position used for target position i.
  // `None` means the target position is a weakening-only binder not referenced
  // by the source term.
  map : Array[Int?]
}

priv struct ContextualId {
  ctx : LambdaContext
  id : @egraph.Id
}

priv struct ThinEGraph {
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState]
  entries : Array[ContextualId]
}

priv struct ContextSearchResult {
  candidates : Int
  matches : Array[ContextualId]
}
```

Invariants:

- `LambdaContext` stores binder identity order from outermost to innermost.
- `Thin.map.length() == target.binders.length()`.
- Every `Some(i)` is in bounds for the source context.
- Non-`None` entries are injective; one source binder cannot be duplicated into two target binders.
- Same-length positional alpha-renaming and prefix weakening are enough for the first slice. Do not implement arbitrary injections until a test requires them.
- `ContextualId.id` is never unioned with another id unless both have first been interpreted in the same `LambdaContext`.

### Implemented operations

Minimal private operations:

```moonbit
fn add_at(self : ThinEGraph, ctx : LambdaContext, term : @alpha.AlphaTerm) -> ContextualId
fn lift_to(self : ThinEGraph, target : LambdaContext, value : ContextualId, thin : Thin) -> ContextualId?
fn union_at(self : ThinEGraph, target : LambdaContext, left : ContextualId, right : ContextualId) -> Bool
fn extract_at(self : ThinEGraph, value : ContextualId) -> @alpha.AlphaTerm
fn search_at(self : ThinEGraph, target : LambdaContext, pattern : @alpha.AlphaTerm) -> ContextSearchResult
```

Implementation constraints:

- `add_at` should delegate to the existing `alpha_term_add` path after normalizing binder references relative to `ctx`.
- `lift_to` may initially support only identity and prefix weakening. Returning `None` is better than guessing.
- `union_at` should return `false` when it cannot put both ids in `target`; it must not call raw `eg.union` across mismatched contexts.
- `extract_at` must return `AlphaTerm`; named `@ast.Term` appears only at the final `@alpha.reify` assertion in tests.
- `search_at` should enumerate only context-compatible tracked entries and report the candidate count so the prototype can detect thinning-search blowups.

### Tests

Implemented two tests that fail to demonstrate value if context is ignored:

1. **Open-body alpha sharing**

   ```text
   let id1 = (x) => x
   let id2 = (y) => y
   (id1 1) + (id2 1)
   ```

   Test at the alpha layer, not the parser boundary if that is simpler: create two one-binder contexts with different `BinderId`s, add each body `Var(Bound(...))`, lift both into a canonical one-binder context, and assert `union_at` succeeds. Also assert that raw ids from the original contexts are not directly unioned.

2. **Capture fixture under renamed binders**

   ```text
   ((x) => (y) => x) y
   ((a) => (b) => a) y
   ```

   Lower both through `ScopeGraph`, optimize or contextually union the relevant alpha bodies, extract as `AlphaTerm`, and reify with `Source`. Both results must be alpha-equivalent to `(fresh) => y`, and neither result may bind the free `y`.

3. **Bounded contextual search**

   Add two alpha-equivalent one-binder bodies, one same-depth non-match, and one deeper-context non-candidate. `search_at` for the one-binder identity body reports four tracked entries, three compatible thinning candidates, and two matches. This demonstrates contextual search over a finite, counted candidate set rather than all possible injections.

### Current prototype limits

- `Thin` supports only positional same-length alpha-renaming and prefix weakening.
- `lift_to` does not rewrite arbitrary extracted egraph ids; it only accepts a validated thinning and otherwise returns `None`.
- The prototype demonstrates context-gated union, canonical open-body sharing, and counted contextual search. It does not attempt general pattern e-matching over arbitrary thinning variables yet.

### Non-goals for the prototype

- No public API.
- No editor action, FFI export, or source-edit integration.
- No arbitrary thinning search.
- No changes to `dowdiness/egraph`.
- No new rewrite rules beyond what is needed to expose the contextual equality question.
- No migration of `loom/egraph/examples/lambda-opt`.

### Validation

Run:

```bash
moon check lang/lambda/alpha_egraph_adapter --deny-warn
moon test lang/lambda/alpha_egraph_adapter --release
moon fmt lang/lambda/alpha_egraph_adapter
moon info lang/lambda/alpha_egraph_adapter
```

Observed result: adapter tests increased from 7 to 10 and pass. A repository-wide `moon fmt && moon info` is currently blocked by the workspace/local-dependency configuration error, so validation used the package-scoped commands above.

## Recommendation

Do not implement production thinning/lifting yet. The Canopy-side prototype evidence above supports continuing with a context/thinning wrapper over `AnalyzedEGraph` rather than production `Lift` e-nodes. Treat explicit `Lift` e-nodes as an implementation detail or smoke-test baseline, not as the chosen user-facing representation. Upstream `dowdiness/egraph` should remain a generic equality engine until a binder-independent API need is demonstrated.
