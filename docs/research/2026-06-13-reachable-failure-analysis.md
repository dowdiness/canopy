# Reachable Failure Analysis — Method-Ray → Incorrectness Logic → Canopy (research note, 2026-06-13)

**Status:** research/proposal note. Per [design-principles §8] this records *what
was analysed and verified, and what it suggests building* — it is not an accepted
decision record and not an execution spec. Method-Ray facts are verified against a
clone of `dak2/method-ray`; Canopy facts are code-verified against the tree at this
date with `file:line` citations; the Incorrectness Logic correspondence is
explicitly flagged **aspirational, not realized**.

**Source system:** [dak2/method-ray](https://github.com/dak2/method-ray) — a Rust
static "callable method checker" for Ruby (TypeProf-2 lineage).
**Theoretical lens:** Incorrectness Logic (O'Hearn, POPL 2020, [DOI 10.1145/3371078]).
**Reviewed by:** Codex (3× SOUND-WITH-CAVEATS; two corrections folded in below, both
re-verified against code).

**Tracking:** #616 (sub-issues #617 Step 1, #618 Step 2).
**Related Canopy issues:** #568 (extract a language-agnostic scope graph — the
generalization step / Step 4, gated on a second scoping consumer), #567 (converge
lambda binder identity onto loom `ProjectionIdentityTracker` — bears on the
diff-identity risk). **Related code:** `lang/lambda/scope/`,
`lang/lambda/semantic/semantic_projection.mbt`, `lang/lambda/edits/`.

---

## 1. What Method-Ray actually computes

A **flow-insensitive type-flow graph** with reactive constraint nodes:

- **Source / Vertex** nodes; edges = "flows-into". A `Vertex` accumulates a *set* of
  types, stored as `HashMap<Type, HashSet<VertexId>>` — type → the set of source
  vertices that contributed it (provenance). Propagation is monotone set-union and
  forwards only newly-added types — a worklist fixpoint
  (`core/src/graph/vertex.rs:51`).
- Control flow merges **every** `if`/`case` arm into one result vertex → a union; no
  path conditions (`core/src/analyzer/conditionals.rs:29,35,42`).
- **`MethodCallBox`** reads the receiver vertex's accumulated type set and, for each
  type, resolves the method against RBS/builtins or user methods; an unresolved type
  records a located `TypeError` (`core/src/graph/box.rs:212`, `report_type_error`).
- Output: undefined-method diagnostics (`file:line:col`). The CLI rebuilds a fresh
  `GlobalEnv` **per file** (`core/src/checker.rs`) — the reactive machinery is
  *designed* for incrementality but edge retraction (`EdgeUpdate::Remove`) is a TODO.

**Bug class:** a single class — `NoMethodError` (undefined method on receiver),
which subsumes nil-dereference (`x.length` where `x` can be `nil` →
`undefined method 'length' for nil`, asserted in `test/defined_test.rb:60`).

**What it ignores:** path feasibility, assignment order, value-level facts; and it
**declines to flag the unknown** — an empty/`Bot` receiver is dropped after bounded
rescheduling (`core/src/graph/box.rs:91,202,207`) and unresolved `Singleton`
(class-method) calls are skipped (`core/src/graph/box.rs:145`).

## 2. Incorrectness Logic mapping — aspirational, not realized

Incorrectness Logic is the *under-approximate* dual of Hoare logic: a reported state
is **reachable** with a witness, giving no false positives (Pulse/Infer).

**Verdict: Method-Ray is not a faithful IL analysis.**

- Its type domain is **over-approximate** (0-CFA-style may-union). The reporting rule
  is *existential over that over-approximation* — `∃ T ∈ recv.types . resolve(T,m)
  fails`, iterating all accumulated types (`box.rs:212`) over branch-merged unions
  (`conditionals.rs`). Existential-over-an-over-approximation is **still
  over-approximate**: `x = cond ? "s" : 1; x.upcase` flags the `Integer` arm with no
  proof `Integer` reaches at runtime. (Confirmed by Codex; the test suite never
  exercises this mixed-union case — it uses homogeneous or fully-offending unions.)
- The "fire only on a witnessed type, skip `Bot`/`Singleton`" behaviour is
  **incompleteness** (false negatives — declining to flag ⊤), *not*
  under-approximation. So Method-Ray is **neither sound nor complete** — a pragmatic
  may-analysis with a false-positive-reduction heuristic.
- The `HashSet<VertexId>` provenance is *structurally* an IL witness, but it
  witnesses a **dataflow route**, not an **executable path**. That gap is exactly
  what separates it from Pulse.

The IL reading is therefore **prescriptive**: it tells Canopy *what to add*
(executable / edit-grounded witnesses) to turn "*possible* failure" into genuine
"*reachable* failure."

## 3. The reusable essence

Strip Ruby, methods, classes, syntax. What remains is domain-agnostic:

> A directed graph of **fact-carrying** nodes over which facts propagate
> monotonically to a fixpoint; certain nodes are **obligations** that watch their
> inputs and emit a **located, witnessed failure** when a fact violates a contract;
> each fact retains the **provenance** of the nodes that produced it; recomputation
> is **incremental** (only obligations downstream of a change re-fire).

Instantiate the fact domain (types → reference targets / semantic kinds / schema
constraints) and the same kernel answers *"what can break, where, and why."*

## 4. Canopy already built this graph — for lambda

`lang/lambda/scope/` is Method-Ray's vertex/box graph specialised to **name
resolution**:

| Method-Ray | `lang/lambda/scope/` (verified) |
|---|---|
| `Vertex` accumulating types | `Ref` with a `Resolution` (`graph.mbt`) |
| bad state: `resolve(T,m)` fails | **`Resolution.decl == None`** — "a NEGATIVE OBSERVATION (unresolved/free)" (`graph.mbt:61`) |
| `HashSet<VertexId>` provenance (witness) | **`Resolution.visited_scopes`** — scopes checked, name absent; reserved "for a future incremental layer" (`graph.mbt`) |
| `SourceLocation` on the box | `binder_span` / `SourceMap` token spans (`query.mbt`) |
| reverse provenance | `references(g, decl) -> Array[NodeId]` (`query.mbt`) |

**The decisive difference (Codex-confirmed):** unlike Method-Ray's type domain,
lambda name resolution is **exact** for the current language — resolution walks
parent scopes and returns `decl: None` only after exhausting the chain
(`builder.mbt:143,152,164,175`); `ModuleDef` is a deterministic sequential cutoff,
not open/dynamic binding. A free variable *is* free. So the false-positive caveat
that dooms a naive type-domain port **does not bite in the scope domain** — this is
where Canopy can earn the name "ReachableFailure" on solid ground.

Caveat to track: the exactness claim holds *for today's lexical lambda language*. If
lambda gains open/extensible modules or dynamic binding, scope resolution becomes
approximate and the genuine-reachable property weakens.

## 5. What exists vs. what's missing (Codex corrections folded in)

- **Free-variable diagnostics already exist** — but via the *older semantic
  projection*, not the scope graph: `lang/lambda/semantic/semantic_projection.mbt:224`
  pushes `Diagnostic(severity=SevWarning, message="Free variable 'x'")` plus a
  `semantic-free` decoration. So the user-visible squiggle is **not** the gap.
- The scope graph today is consumed **defensively** by `lang/lambda/edits/` (rename
  capture-avoidance, binding-reorder safety), **not** to surface failures.
- **Missing:** (a) failures surfaced *with the `visited_scopes` witness* and the
  `references` reverse-impact query; (b) a before/after failure-set **diff** for
  agent review; (c) incremental maintenance (the graph is rebuilt O(N) per
  `builder.mbt`, not `incr`-wired).

> Naming discipline: `incr`'s `ReachableDerived` (HybridMemo) is about cell
> *liveness* / GC-anchoring, **unrelated** to the `ReachableFailure` proposed here
> despite the shared word. Do not conflate them in any doc or API.

## 6. Staged adoption plan

**Step 1 — Reground free-variable diagnostics on the scope graph (days; do first).**
Add a derived view `failures(g, sm) -> Array[ReachableFailure]` collecting
`resolution.decl is None` refs with `{ location: ref span, name, witness:
visited_scopes }`, and have it *supersede* the `semantic_projection.mbt:224`
warning. **Value is witness-enrichment + impact-query feed, not new diagnostics** —
the squiggle exists; the explanation machinery does not. No `incr` work, no new
graph.

**Step 2 — Agent-review diff (the headline capability).** Snapshot `failures()`
before an agent's `UserIntent`/`GenericTreeOp` edit, recompute after, report
`{ newly_reachable, resolved }` — "what failures did this edit make reachable, and
why." **Key the diff on pipeline-independent semantic identity (module: `def_index`;
lambda: binder *name* + *range*), NOT on `DeclId`/`NodeId`.** `DeclId` is explicitly
"NOT persistent identity" (`graph.mbt:2`) and `NodeId` is only best-effort across
reconciled edits; the existing cross-pipeline test already keys on semantic identity
and never reads `node_id` for this reason
(`lang/lambda/edits/scope_cross_pipeline_pbt_wbtest.mbt`). See #567.

**Step 3 — Incrementalise ONLY when measured.** `visited_scopes` is the dependency
footprint of a negative observation (re-resolve a ref only if an edit touched one of
its visited scopes or added a decl with its name) — this is the "executable witness"
upgrade the IL reading demands. **Per the project's benchmark-first rule, do not do
this until the O(N) rebuild is shown to be a real bottleneck on editor-sized
documents.** No issue filed until reproduced.

**Step 4 — Generalise across languages.** This is **#568** (`Decl[K]` loom lift,
gated on a second real scoping consumer). ReachableFailure on lambda is a *consumer
of resolution results*, not a second scoping *language*, so it does not by itself
meet #568's gate — track there, do not duplicate.

## 7. Verdict

**Important Extension — not a Core Primitive, not a mere experiment.** `ReachableFailure`
is a **derived view** composed from existing primitives (`incr` Input/Derived, the
projection dependency graph, the lambda scope graph), maintained incrementally by
`incr`, surfaced as a projection, consumed by agents. It is not foundational (the
engine and graph already exist), and it is too aligned with Canopy's stated north
star (impact analysis, change propagation, *explanation of why things break*, agent
review) to be a side probe.

**The condition that is the whole point:** the name "Reachable**Failure**" promises
under-approximation. The easy implementation (copy Method-Ray) delivers "*possible*
failure" and inherits its false positives. Adopt it **starting in the scope graph**,
where the failure is genuinely reachable and the witness is exact — earn the name on
solid ground before considering the approximate type/eval domain
(`lang/lambda/eval/`), which is precisely where a naive port would ship false
positives.
