# Lambda Scope Graph — Binding-Logic Consolidation (Design)

**Date:** 2026-05-30
**Status:** Design approved, pending spec review
**Scope:** canopy-side only (`lang/lambda/`); the `loom` submodule is not touched.

## Motivation

Name-resolution / binding logic for the lambda language is duplicated and ad-hoc
across ~5 sites:

- `lang/lambda/edits/scope.mbt` (167 lines) — `resolve_binder`,
  `find_enclosing_lam_binder`, `find_usages`, `collect_lam_env`,
  `find_binding_for_init`.
- `lang/lambda/edits/free_vars.mbt` (31 lines) — capture analysis `FV(term, env)`.
- `lang/lambda/semantic/semantic_projection.mbt` (265 lines) — walks the AST
  threading an environment array, classifies each `Var` as bound/free.

Two concrete problems:

1. **O(N²) parent search.** `find_enclosing_lam_binder` and `collect_lam_env`
   full-scan `registry: Map[NodeId, ProjNode[Term]]` to find a node's parent —
   O(N) per step, O(N²) overall.
2. **No single source of truth.** Each site re-derives scoping, so a fix in one
   place (e.g. a shadowing edge case) does not propagate. There is no queryable
   "where is this name declared / referenced" facility, which blocks
   go-to-definition / find-references / capture-safe rename from sharing one
   correct implementation.

This design introduces a single **NodeId-keyed binding index** that the binding
sites migrate onto, drawing on:

- *A Theory of Name Resolution* (Néron, Tolmach, Visser, Wachsmuth, 2015) — the
  Scope / Declaration / Reference graph model and resolution-by-path-search.
- *Incremental Type-Checking for Free* (Zwaan, van Antwerpen, Visser, OOPSLA
  2022) — query-confirmation + environment-diffing for incrementality. **Not
  built in v1**; its data shape is *reserved* (see §"Reserved extension points").

A small MoonBit reference implementation of the 2015 theory exists
(`caimeox/scope_graph`). We do **not** depend on it. It is BATCH
(non-incremental), uses position-dependent `Int` indices, and is hardcoded to
its own AST `LmProgram`. We use it only as a **correctness oracle** in
differential tests.

### Framing: what v1 actually is, and what it is not

**v1 is a NodeId-keyed binding index, not a scope-graph engine.** The lambda
language has no imports, no type-dependent resolution, and is a single
compilation unit. Under those conditions almost all of scope-graph theory's
machinery degenerates: there are no `I` (import) edges, no `critical edges` /
Statix scheduling, no file-incremental boundary, and the only path regex that
ever applies is `P*` (walk the parent chain). What remains — a parent chain plus
a sequential-module cutoff — is **structurally a symbol table**.

The concrete v1 wins (kill the O(N²) parent scan, identity-based `references()`,
reserved negative-observation fields) come from making the binding facts an
**explicit, NodeId-keyed, queryable index**, NOT from scope-graph theory per se.
We adopt the Scope/Decl/Ref *vocabulary and data shape* deliberately, as the
minimum-cost stepping stone toward two reserved futures (incremental rebuild;
loom generalization). That bet on future value is **explicitly provisional**:
its payoff is re-evaluated after v1 ships and the migrated consumers are
measured (see §Alternatives and §"Reserved extension points"). If the futures do
not materialize, what we are left with is a clean symbol table that cost the same
to build — so the downside is bounded. This framing is a direct response to an
independent design review that (correctly) flagged the original "scope graph"
framing as larger than the problem warrants.

## Non-goals (v1)

- **Incremental rebuild.** v1 rebuilds the whole graph each time, but correctly.
  Incrementality is a reserved extension point, not v1 work.
- **Migrating all consumers.** v1 rewires exactly ONE call: `rename`'s use of
  `resolve_binder` → `declaration()`, proven equivalent. **rename's OTHER
  dependencies stay on the old logic in v1** (Codex finding 3): its capture
  checks via `free_vars`, its usage-edit enumeration via `find_usages`, and its
  in-scope-name collection via `collect_lam_env` are NOT migrated in v1. Only
  the binder-resolution step is swapped. `free_vars` / `find_usages` /
  `collect_lam_env` / `semantic_projection` / `actions` migrate in later PRs.
  This keeps the v1 equivalence test (Layer 3) scoped to a single, checkable
  behavioral substitution.
- **loom generalization.** The language-agnostic core lives in its own file so a
  future loom sibling package can lift it, but v1 does not extract it.
- **Touching the loom submodule.** canopy `lang/lambda` already shares loom's
  AST type `@ast.Term`; the graph consumes it. No submodule PR.

## Architecture

New package `lang/lambda/scope/`, split into three files by responsibility:

### `graph.mbt` — data model (language-agnostic core, one lambda-specific seam)

```
ScopeGraph { scopes: Array[Scope], decls: Array[Decl], refs: Array[Ref] }
Scope { id: ScopeId, parent: ScopeId?, decl_ids: Array[DeclId], ref_ids: Array[RefId] }
Decl  { node_id: NodeId, name: String, scope: ScopeId, kind: DeclKind }
Ref   { node_id: NodeId, name: String, scope: ScopeId, resolution: Resolution }
Resolution { decl: DeclId?, visited_scopes: Array[ScopeId] }
DeclKind { LamParam(lam_id: NodeId) | ModuleDef(def_index: Int) }
```

**`DeclKind` (Codex finding 1).** `Decl` must carry enough to reconstruct the
current `BindingSite` returned by `resolve_binder`
(`lang/lambda/edits/scope.mbt:3`): `LamBinder(lam_id)` and
`ModuleBinder(binding_node_id, def_index)`. A bare `{ node_id, name, scope }`
cannot reproduce `ModuleBinder.def_index` or distinguish the two binder kinds, so
`DeclKind` records `LamParam(lam_id)` / `ModuleDef(def_index)`. The migrated
`declaration()` maps `Decl{kind, node_id} -> BindingSite` losslessly.

**`DeclKind` is the one lambda-specific type in `graph.mbt` (review point).**
`Scope` / `Decl` / `Ref` / `Resolution` are language-agnostic, but `DeclKind`'s
variants (`LamParam` / `ModuleDef`) are lambda-specific, so strictly the file is
*almost* agnostic. This is a deliberate v1 simplification (single language → a
concrete enum is simpler than premature generics). It has one consequence for the
loom-generalization reserve (§Reserved 2): lifting `graph.mbt` into loom is NOT a
pure move — `Decl` must be made generic over its kind (`Decl[K]`, with `K`
supplied per language) at that point. v1 keeps `K` concrete as `DeclKind`. The
cost of that later generalization is small (one type parameter threaded through
`graph.mbt`), and noting it now keeps the reserve honest rather than implying a
clean cut-and-paste.

Everything is keyed by `core.NodeId` (stable across edits) rather than the
position-dependent `Int` indices that caimeox uses. `ScopeId`/`DeclId`/`RefId`
are internal compact indices into the graph's own arrays (graph-local, not
persistent identity — `NodeId` carries persistent identity).

`Resolution.decl: None` is a **negative observation** (an unresolved /
free reference). `visited_scopes` records the scopes that were checked and found
NOT to contain the name during resolution. Both are populated in v1 but only
`decl` is read by v1 queries. They exist so that incrementality (which depends on
negative observations) can later be layered on without a breaking change to
`Resolution`.

**Is populating `visited_scopes` in v1 actually free? (review point)** §7 says
reserve the *place* (the field), not necessarily do the *work* of filling it. We
populate it in v1 anyway, justified as a genuine by-product: resolution already
walks the scope chain upward (via the Pass-1 parent map) to find a binding, so
`visited_scopes` is just an `Array[ScopeId]` (`ScopeId` = `Int`) that records the
scopes that walk *already visits* — **zero extra traversal, only the allocation**.
The cost is one small array per ref per full rebuild. If profiling later shows
this allocation is hot on large programs, the reserved fallback is to leave
`visited_scopes` empty in v1 and populate it lazily when the incremental layer
first needs it — the field stays, only the fill moves. (v1 chooses eager fill so
the differential/equivalence tests can assert the negative observations are
correct from day one, rather than discovering fill bugs when incrementality is
built.)

### `builder.mbt` — lambda-specific construction

`build(flat_proj, registry, source_map) -> ScopeGraph`, run once per rebuild:

- **Pass 1:** build a `NodeId -> parent NodeId` map from `registry` in a single
  scan. This removes the O(N²) full-scan that `find_enclosing_lam_binder` /
  `collect_lam_env` perform today.
- **Pass 2:** create scopes and decls encoding the binding rules below.
- **Pass 3:** resolve each ref, storing its `Resolution` (decl + visited_scopes).

Binding rules of the lambda language (must be faithfully encoded):

1. `Lam(param, body)` opens a new lexical scope binding `param`; an inner `Lam`
   shadows an outer one.
2. `Module` defs are **sequential**: def `i` is in scope for defs `i+1..n` AND
   the body. A later def with the same name shadows an earlier one.
3. A `Var` resolves to the innermost enclosing `Lam` param matching the name,
   else the latest *preceding* `Module` def, else free/unbound.

**Sequential-scope encoding (Codex Q1).** A single module scope is used, but each
ref carries a **cutoff** (the def index it appears within, or a body sentinel),
and resolution only considers decls whose def-index is *strictly before* the
cutoff. Consequences that MUST hold:

- `def x = x` alone → the inner `x` is **unbound** (a def is not visible in its
  own init).
- `def x = 1; def x = x` → the second init's `x` binds to the **first** `x`.
- A def referencing a *later* def → unbound.

Per-def child-scope chaining (caimeox's `seqb` approach) is an equivalent
alternative but unnecessary; the cutoff index achieves the same visibility with
one module scope.

### `query.mbt` — query API

- `declaration(ref_node: NodeId) -> Decl?` — the binding site a reference
  resolves to (replaces `resolve_binder`).
- `references(decl_node: NodeId) -> Array[NodeId]` — **identity-based**: returns
  refs whose `resolution.decl` points at this decl, NOT a name match. (Codex Q2:
  a name-based `find_usages` over-renames when shadowing is present.) *(Reserved
  API surface; consumer migration — `find_usages` callers — deferred per
  §Non-goals.)*
- `enclosing_env(node: NodeId) -> @immut/hashset.HashSet[String]` — bound names
  in scope at a node (replaces `collect_lam_env`). **Set semantics** (Codex
  finding 6): the current `collect_lam_env` returns a `HashSet[String]` and its
  consumer (`text_edit_refactor.mbt` capture check) needs membership, not order;
  the query mirrors that to avoid an impedance mismatch. *(Reserved API surface;
  consumer migration deferred per §Non-goals. Of the three query methods, only
  `declaration()` is wired to a consumer in v1.)*

**Token-span lookup is via the Module node, not the binding NodeId (Codex
finding 2).** Module binding name spans are stored on the *Module* ProjNode under
the role `"name:<def_index>"` (`lang/lambda/proj/populate_token_spans.mbt`,
consumed by `lang/lambda/edits/text_edit_rename.mbt`), NOT on the FlatProj
binding `NodeId` that `Decl.node_id` holds. Any go-to-definition / rename built
on `declaration()` must therefore resolve a `ModuleDef` decl's edit span as
`source_map.get_token_span(module_node_id, "name:" + def_index)`, using
`DeclKind::ModuleDef(def_index)`. The graph stores `def_index` precisely so this
lookup remains possible; the spec does NOT change where spans live.

Dependency direction: `scope` depends on `core` (NodeId/SourceMap/ProjNode) and
`lang/lambda/proj` (FlatProj/Term). `edits` / `semantic` / `rename` will depend
on `scope` (no back-edge).

## Data flow (v1, non-incremental)

```
edit → projection rebuild (existing) → FlatProj + registry + SourceMap (existing)
     → ScopeGraph::build(...)              [new, once]
        ├─ pass 1: NodeId → parent map     (single registry scan)
        ├─ pass 2: scopes + decls          (Lam param scopes + sequential module scope)
        └─ pass 3: resolve refs            (store Resolution per ref)
     → query (declaration / references / enclosing_env) ← consumers
```

**v1 full-rebuild cost (review point).** `build()` runs over the projection on
*every* rebuild, and a projectional editor rebuilds on every edit. This is the
accepted non-incremental cost. The §Framing "downside is bounded" argument is
about *code* (worst case = a symbol table), and that bound does NOT extend to
*runtime* — so it must be stated separately here.

Per-pass cost (be precise, since a decision is gated on it):

- **Pass 1** (build `NodeId -> parent` map): O(N), one walk of the projection of
  size N.
- **Pass 2** (scopes + decls): O(N), one walk emitting a scope/decl per relevant
  node.
- **Pass 3** (resolve refs): **O(R · d)**, NOT O(N) — each of R refs walks the
  parent chain upward; the parent *lookup* is O(1) (Pass-1 map) but the *walk
  length* is the nesting depth d. This still strictly improves on today's
  `find_enclosing_lam_binder`, which is O(N · d) per ref because it re-scans the
  whole registry at each step (`scope.mbt:62`); the Pass-1 map turns the
  per-step O(N) into O(1). The v1 win is "kill the per-step O(N) rescan," NOT
  "make resolution linear."
- **Worst case and why it is not reachable.** Pathologically left-nested lambdas
  (`\a.\b.\c. ...`) make d ≈ N, so Pass 3 degenerates to O(N²) — the very shape
  v1 set out to kill. The original O(N²) sin was also "only pathological," so
  this must be argued, not waved: realistic lambda programs keep d (lexical
  lambda-nesting plus the single module level) small and roughly constant
  relative to N — N grows by adding *defs and terms* (breadth), not by deepening
  nesting hundreds deep. So in practice Pass 3 is ≈ O(R) ≈ O(N). If a real
  program ever drives d large, that surfaces as rebuild latency, which is exactly
  the trigger-metric condition below — and the response is the reserved
  incremental path, not a v1 change.

**Not yet measured for this layer, but the budget is known.** The project's
established interactive budget is the **16 ms frame (60 fps)**; the existing
keystroke pipeline sits at ~2.3 ms / 15% of budget at 80 defs
(`docs/performance/2026-03-21-full-pipeline-benchmarks.md`). The scope build must
fit *within* that same 16 ms keystroke budget alongside parse + projection + tree
refresh. The metric that flips the non-incremental decision is made explicit in
§Reserved: **scope-build's contribution to p95 keystroke latency against the
16 ms frame budget**. Until measured and shown to threaten that budget,
incrementality stays reserved (cf. the project rule: measure the bottleneck
before optimizing).

## Error handling

- The builder ALWAYS returns a graph, even on partial / broken ASTs. A
  projectional editor is mid-edit constantly, so resolution never `raise`s on
  unresolved names.
- **`Var` vs `Unbound` (Codex finding 4).** `Var(name)` and `Unbound(name)` are
  BOTH emitted as a `Ref`, and an unresolvable one gets
  `Resolution{ decl: None, .. }` (a normal negative observation). This is
  deliberate: `semantic_projection` already treats `Unbound` as reference-like
  for its free-variable diagnostics (`semantic_projection.mbt:67`), so excluding
  it would drop a diagnostic the migrated consumer must keep. (`free_vars`
  ignores `Unbound`; that asymmetry is a free_vars concern, not a graph concern —
  the graph models both uniformly and each consumer filters as it needs.)
- **`Error` / `Hole` nodes** carry no name and produce neither a `Decl` nor a
  `Ref`; they are inert in the graph.
- The only invariant violation is a **parent-chain cycle**. This cannot arise
  from a mid-edit / broken AST, because the `NodeId -> parent` map (Pass 1) is
  derived by `core.collect_registry` walking the `ProjNode` tree
  (`core/proj_node.mbt:58`): each node appears in exactly one parent's `children`
  array, so the parent map is **acyclic by construction**, independent of edit
  state — a broken AST yields a broken *tree*, never a cyclic graph. The builder
  still asserts acyclicity via `fail()` (Codex Q5), but this is a genuine
  **defect guard** (a violation means `collect_registry` or the tree itself is
  bugged), NOT a runtime error path — so it does not contradict the never-raise
  contract above, which governs *unresolved names* (those become
  `Resolution{decl: None}`, not failures). `fail()` rather than catch because a
  cyclic parent map signals a corrupted invariant where catching would risk
  silently-wrong results (cf. memory `feedback_no_safe_recovery_abort_ok`).

## Testing strategy (three layers)

### Layer 1 — hand-written expected-value tests (primary safety net)

Pin the Codex Q1/Q2 edge cases by name, with values **derived by hand** (not by
re-running a formula; cf. memory `feedback_algorithm_process`):

- `def x = x` → unbound.
- `def x = 1; def x = x` → second init binds to first `x`.
- innermost `Lam` shadowing; `Module` def shadowing.
- body sentinel; "not visible in own init / preceding defs".

### Layer 2 — differential tests (caimeox oracle)

`source fixture → independent Term→LmProgram adapter → caimeox resolution →
compare via a NodeId side-table`.

- **Non-circularity (Codex Q3):** the adapter is an INDEPENDENT transform that
  does NOT route through the new builder/query code.
- **Fidelity (Codex Q3):** caimeox's AST lacks Canopy's `If` / `Unit` / `Hole` /
  `Error` / `Unbound` and has extra `Fix` / imports. Compare only the shared
  subset (Var / Lam / App / Module / let-equivalent); excluded constructs are
  covered by Layer 1.
- **Adjudication rule (Codex finding 5):** caimeox is an oracle, NOT the spec of
  record. The sequential-module semantics are defined by Canopy's cutoff-index
  rule (§"Sequential-scope encoding") and by Layer 1's hand-derived expectations.
  caimeox encodes `let` via `seqb` child-scope chaining; if that disagrees with
  the cutoff encoding on some edge case, **Layer 1 + current-Canopy equivalence
  (Layer 3) win, and the caimeox fixture is removed from the differential set**
  (documented, not silently dropped — cf. "no silent caps"). caimeox earns trust
  on the agreed subset; it does not override Canopy's own binding contract.
- **Agreement is necessary, not sufficient (review point).** Layer 2 catches the
  case where the new builder disagrees with an independent oracle. It does NOT
  catch the case where caimeox and the new builder *agree* but both diverge from
  the intended semantics — there, Layer 1's hand-derived expectations are the
  backstop, by design. So Layer 2 passing is evidence, not proof; Layer 1 is the
  authority on what "correct" means.
- This is the operational form of design principle §6 ("make the discovered
  structure predict").

### Layer 3 — equivalence tests (migration safety net)

For the migrated `rename` consumer, pin that the new `declaration()` and the
current `resolve_binder()` return the SAME `BindingSite` across all fixtures.

- **Non-circularity (memory `feedback_drift_detector_non_circular`):** keep the
  old `resolve_binder` live and run BOTH during the test, comparing outputs.
  Delete the old implementation only after migration is proven, in the same PR.
- **Layer 3 preserves current behavior, bugs included — correctness is Layer 1's
  job (review point).** Problem #2 in §Motivation notes the ~5 binding sites can
  currently disagree, which means `resolve_binder` may carry latent bugs. Layer 3
  deliberately pins *equivalence to current `resolve_binder`*, so it proves the
  migration is **behavior-preserving** — including reproducing any existing bug.
  This is intentional sequencing: a behavior-preserving migration is verifiable
  on its own, and fixing a binding bug is a *separate, later* step (where Layer 1
  is extended with the corrected expectation and the fix lands as its own change,
  not smuggled into the migration). Layer 1 (hand-derived) is the authority on
  correctness; Layer 3 is only the migration-safety net. Where Layer 1 and
  current `resolve_binder` disagree, that disagreement is a *found bug* to file,
  not a Layer 3 failure to paper over.

This is the pass condition for the "structure + 1 consumer" PoC.

## Alternatives considered

An independent design review pressed the question: *the lambda language is single,
lexical-scope-centric, with no imports or type-dependent resolution — does it
warrant scope-graph vocabulary at all, or would a plain symbol table / Datalog
encoding be a better fit?* The three candidates, and why this design picks the
binding-index shape:

### Alt 1 — Classic symbol table + visitor resolution

Fold the CST with a catamorphism, threading an environment; resolve names against
the live environment. This is the lowest-ceremony option and is what
`semantic_projection.mbt` already does ad-hoc today.

- **Pro:** smallest code; no new data model; familiar.
- **Con:** does not by itself give an *identity-keyed, queryable* index. The two
  v1 wins — O(1) parent lookup (kills the O(N²) scan) and identity-based
  `references()` — require materializing decl/ref facts keyed by `NodeId`
  anyway. A symbol table that materializes those facts *is* the proposed index
  under a different name; one that does not, leaves problem #2 (no single source
  of truth) unsolved. So "plain symbol table" either converges on this design or
  fails the requirements.

### Alt 2 — Datalog encoding on loom's fixpoint substrate

Express binding as Datalog rules (`decl(scope, name, node)`, `parent(s, s')`,
`resolves(ref, decl)`) and run them on `loom/incr`'s `Relation` + fixpoint
(cf. Pacak, Erdweg, Szabó, *A Systematic Approach to Deriving Incremental Type
Checkers*, OOPSLA 2020, which compiles type rules to Datalog; and rust-analyzer's
Salsa + `DefMap` as the non-scope-graph incremental baseline).

- **Pro:** incrementality comes from the substrate; directly reuses an asset
  canopy already has (`loom/incr` ships `Relation` + `Runtime::new_rule` +
  `fixpoint` + `MemoMap` — both the demand-driven memo layer AND a Datalog layer
  coexist by design; cf. memory `project_incr_datalog_substrate`); strong
  precedent for incremental name resolution.
- **Con:** wrong altitude for v1. v1 is explicitly *non-incremental* (the user
  chose "verify-first: lock correctness before incrementality"). Introducing the
  Datalog substrate now couples the correctness milestone to the fixpoint
  engine and the memo-cycle hazard (Codex Q5) before there is a passing
  correctness baseline to protect. Datalog is the natural **substrate for the
  reserved incremental future**, not for the v1 correctness layer. Deferring it
  keeps v1 debuggable as a plain batch computation.
- **Subtlety to remember when this future is pursued:** a fixpoint engine is not
  the same as incremental maintenance. Semi-naive evaluation speeds up computing
  a fixpoint *from scratch*; incremental view maintenance (DRed / DRedL) updates
  a result *when inputs change*. Having `fixpoint` does NOT by itself give
  edit-incremental resolution. There is also an impedance question between the
  two incremental models — the memo layer is demand-driven / pull / top-down
  (Salsa-style verifying traces), while the Datalog layer is bottom-up / push.
  These do not conflict in v1 (it uses neither incrementally), and `incr` already
  reconciles them; the intended shape when we do go incremental is the
  coarse-grained one in §Reserved (memo outside, fixpoint inside, unit
  granularity), NOT a hand-rolled fusion of both.

### Alt 3 — NodeId-keyed binding index with scope-graph vocabulary (chosen)

The materialized Scope/Decl/Ref index described above.

- **Pro:** delivers both v1 wins; the Scope/Decl/Ref *shape* is the minimum-cost
  stepping stone to the two reserved futures (incremental via query-confirmation;
  loom generalization), because the negative-observation fields and the
  language-agnostic core file are already in place; admits a batch correctness
  oracle (caimeox) sharing the same conceptual model.
- **Con:** carries vocabulary (`Scope`, `ScopeId`, regex-able resolution) whose
  full power lambda never exercises in v1 — accepted deliberately as the reserved
  bet, with the §Framing escape hatch that the worst case is "a clean symbol
  table that cost the same."

**Decision.** Alt 3. The implementation cost over Alt 1 is marginal (parent chain
+ cutoff is the same code volume whether or not it is framed as a graph), and the
reserved affordances (negative observations, agnostic core) are nearly free when
built in now versus a breaking change later (design principle §7). Alt 2 is
adopted *later*, as the incremental substrate, not as the v1 correctness layer.
The provisional nature of the future bet is recorded in §Framing: re-evaluate
after v1 ships and consumers are measured; name resolution is reported at 35–40%
of type-checker runtime (Zwaan, *Specializing Scope Graph Resolution Queries*,
SLE 2022), so the incremental payoff — if pursued — is material.

## Reserved extension points (NOT built in v1)

Per design principle §7 (reserving an extension point costs far less than a later
breaking change):

1. **Incremental rebuild** via query-confirmation + environment-diffing
   (OOPSLA 2022). The paper's hardest machinery is UNNEEDED here:
   - §7 scope-graph diffing (for non-deterministic scope identity) — unneeded
     because canopy has STABLE `NodeId`.
   - §6 multi-unit actor / deadlock detection — unneeded because canopy is
     currently a SINGLE compilation unit.
   What remains is query-confirmation over negative observations, which is why
   `Resolution` already carries `decl: DeclId?` + `visited_scopes` in v1.
   - **Start at unit granularity, not fine-grained.** When incrementality is
     built, begin with the coarse shape: the `incr` memo decides whether a
     file/module unit must be recomputed, and the resolution runs as a batch
     fixpoint *inside* that unit. Avoid jumping straight to within-unit
     fine-grained incremental (e.g. function-body-level DRedL). Reason: Zwaan
     et al.'s query-confirmation stayed at compilation-unit granularity because
     that was already sound and practical, whereas fine-grained DRedL is a
     higher-cost solution that depends on the special structure of incremental
     replacement of lattice values. Coarse-grained is enough; fine-grained is a
     structure-dependent optimization to reach for only if measurement demands
     it. This shape also keeps the cycle trap below easy to avoid.
   - **Trigger metric:** pursue incrementality when the scope-build's
     contribution to **p95 keystroke latency threatens the project's 16 ms frame
     (60 fps) budget** on a realistic program — the same budget the existing
     pipeline is measured against
     (`docs/performance/2026-03-21-full-pipeline-benchmarks.md`; today ~2.3 ms /
     15% at 80 defs). Two things can drive it there: program size N (Pass 1/2 are
     O(N)) or pathological lambda-nesting depth d (Pass 3 is O(R·d); see §"v1
     full-rebuild cost"). Until the measurement shows the budget threatened, the
     full rebuild is accepted; the field reservations (`visited_scopes`, agnostic
     core) keep the pivot cheap when the metric demands it.
   - **Cycle trap (Codex Q5):** if later layered on canopy's `loom/incr` Datalog
     substrate (`Relation` + `MemoMap`), a transitive-closure `MemoMap` compute
     fn MUST walk the base parent/def edges directly (iterative BFS or Datalog
     fixpoint), NOT recurse through the closure `MemoMap` itself — that creates a
     memo cycle the runtime aborts (cf. memory `project_incr_impact_bfs_cycle_trap`).
2. **loom generalization:** the language-agnostic `graph.mbt` core can be lifted
   into a loom sibling package; per-language builders supply rules. v1 keeps the
   core in its own file to make this *mostly* a move. The one non-move is
   `DeclKind`: it is lambda-specific, so the lift makes `Decl` generic over its
   kind (`Decl[K]`) and each language supplies its own kind enum (see the
   `graph.mbt` §"DeclKind is the one lambda-specific type" note). A small,
   bounded generalization — not a rewrite.

## Open questions

None blocking. Migration order for the remaining consumers
(`free_vars` / `semantic_projection` / `actions`) is decided per follow-up PR.

## References

- Néron, Tolmach, Visser, Wachsmuth. *A Theory of Name Resolution.* ESOP 2015.
- Zwaan, van Antwerpen, Visser. *Incremental Type-Checking for Free: Using Scope
  Graphs to Derive Incremental Type-Checkers.* OOPSLA 2022.
  <https://aronzwaan.github.io/assets/oopsla22.pdf>
- `caimeox/scope_graph` (MoonBit reference impl of the 2015 theory) — oracle only.
- Pacak, Erdweg, Szabó. *A Systematic Approach to Deriving Incremental Type
  Checkers.* OOPSLA 2020. (Datalog encoding — Alt 2 lineage.)
- Zwaan. *Specializing Scope Graph Resolution Queries.* SLE 2022. (Name
  resolution = 35–40% of type-checker runtime.)
- rust-analyzer (Salsa + `DefMap` + `ItemTree`) — non-scope-graph incremental
  baseline cited in §Alternatives.
