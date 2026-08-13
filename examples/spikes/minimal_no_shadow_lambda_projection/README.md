# Minimal no-shadow Lambda projection P0

**Status:** Throwaway feasibility prototype. Keep it on the prototype branches;
do not merge it into production.

- P0 projection result: **PASS WITH CONSTRAINTS** at `667aaf63`.
- P1 annotation extension: **PASS WITH CONSTRAINTS**; see [P1.md](P1.md).
- P1.1 query counters: lazy and cross-consumer sharing pass; see
  [P1_QUERY_METRICS.md](P1_QUERY_METRICS.md).
- P1.2 Term Eq cutoff: a whitespace commit recomputes the selector but makes
  Evaluation verify green without recomputing; see
  [P1_2_EVAL_GREEN_PATH.md](P1_2_EVAL_GREEN_PATH.md).
- P1.3 cutoff benchmark: native release measurements are positive for all
  measured let chains; JS repeats are positive at the large size while the
  small/medium crossover remains unstable; see
  [P1_3_CUTOFF_BENCHMARK.md](P1_3_CUTOFF_BENCHMARK.md).
- P1.4 mixed workload: one changing path has stable Eq overhead; large remains
  positive at a 50% equivalent-edit mix on native and JS in this run, while
  medium and threshold estimates remain noisy; see
  [P1_4_CUTOFF_MIXED_WORKLOAD.md](P1_4_CUTOFF_MIXED_WORKLOAD.md).
- P1.5 test-derived trace replay: demand cadence suppresses intermediate lazy
  work and SourceMap-only demand leaves Term/Evaluation undemanded; all
  whole-session timing ranges cross zero, and no captured user trace exists;
  see [P1_5_TEST_DERIVED_TRACE_REPLAY.md](P1_5_TEST_DERIVED_TRACE_REPLAY.md).
- P2a Runtime-free typecheck: exact snapshot syntax feeds lazy `TypedTerm` and
  whole-module `ModuleTypeResult` Queries without current reactive objects;
  production diagnostics, per-definition reuse, and stable index remain open;
  see [P2A_RTFREE_TYPECHECK.md](P2A_RTFREE_TYPECHECK.md).

## Question

Can one application shell use the production Lambda `ImperativeParser`,
projection conversion, reconciliation, registry, source-map, evaluation, and
annotation algorithms with the issue #464 incremental provider, while
constructing no current-Incr runtime objects or bridge, keep ownership visibly
small, and stop one semantic propagation path after a whitespace-only edit?

This is an architecture feasibility gate, not production migration evidence.
Issue #1236 remains the production authorization ledger.

## Run

From the Canopy repository root:

```bash
./scripts/run-minimal-no-shadow-lambda-projection.sh
./scripts/run-minimal-no-shadow-lambda-cutoff-benchmark.sh
./scripts/run-minimal-no-shadow-lambda-cutoff-mixed-benchmark.sh
./scripts/run-minimal-no-shadow-lambda-trace-replay.sh
./scripts/run-minimal-no-shadow-lambda-typecheck.sh
```

On the current P1.2 branch, the command verifies the materialized #464 provider
hash, checks the affected packages, runs the native executable, prints every
relevant state transition and all five Query debug records, checks the prototype
allowlist, and prints the virtual deletion ledger. P1.2 preserves the P0/P1
assertions and adds one whitespace-edit green-path assertion.

## Scope

P1.2 runs these operations in order:

```text
initial
raw-edit
structural-batch
demand-annotations
demand-registry
demand-source-map
evaluation-edit
whitespace-green-path
close
duplicate-close
post-close-read
```

The structural fixture renames a nested Lambda binder/reference with two parser
updates. The fixture deliberately stays below Lambda's private module-key
reconcile hook, so both the production path and P0 use the public production
`reconcile_hinted` engine. `RenameLeaf` is evidence carried to this transition,
but generic reconciliation does not give it special matching semantics; P0
proves batch-local ownership and exactly-once handoff, not wrap/unwrap identity
semantics. No production adapter is copied or widened.

The source-range consumer resolves the production `reference:name` token span
for a projected `Var("z")` and checks that the exact committed parse snapshot
contains `"z"` at that range.

## Owner graph

```text
MinimalLambdaProjectionShell
├─ ImperativeParser
├─ SemanticBatchState
├─ ProjectionState
└─ issue #464 Store
   └─ Region
      ├─ Source[ProjectionCommit]
      ├─ Query[Unit, Registry]
      ├─ Query[Unit, SourceMap]
      ├─ Query[Unit, Term] with Eq cutoff
      ├─ Query[Unit, Array[EvalResult]]
      └─ Query[Unit, AnnotationMap]
         ├─ exact ProjectionCommit
         ├─ evaluation Query
         └─ source-map Query
```

The split is intentional:

```text
Shell      owns history-sensitive projection transitions.
#464       owns lazy derivation and typed cutoff from one committed value.
```

`ProjectionCommit` owns the exact `ParseSnapshot`, projection, and trace.
Source-map computation therefore cannot combine a new projection with an old
snapshot. P1.2 selects `commit.projection.kind` through a typed Eq-cutoff
Query, then passes the selected Term to production `eval_term`; it does not stage a copied
evaluation Source. The annotation Query reads that evaluation, the same commit,
and its source-map Query in one evaluation context. A trailing-whitespace commit
backdates the equal Term and makes Evaluation verify green. This does not supply
current production's unchanged-definition prefix cache.

## Complexity budget

```text
application owner              1
Store                          1
Region                         1
canonical Source               1
lazy Query                     5
Mount                          0
Watch                          0
Program / Port / Manifest      0
current Runtime objects        0
cross-runtime synchronization  0
async resources                0
```

Canopy's current `core`, Lambda projection, Lambda eval, and companion packages
still have transitive compile dependencies on current Incr because pure
functions share packages with production memo builders. P0/P1 do not call those
builders or construct any current-Incr value. P1 adds one prototype-only public
visibility adapter around the existing package-private annotation conversion;
its generated `.mbti` delta is one function. A production package split or API
deepening remains separate work.

## #462/#464 evidence reuse

P0/P1 materialized the #462 provider under
`evidence/incr_next_incremental_parity/provider/`. P1.2 uses
`evidence/incr_next_cutoff_backdating/provider/`, resolved from #464 commit:

```text
c640f65124b2a0eb362f3f08a1b6220e6647b6b7
```

#464's documented symlinks to #462/#463 files are resolved to their exact source
at that commit. `provider.sha256` guards every materialized provider source. The
adjacent `moon.mod` and minimal `moon.pkg` are prototype-local packaging
adapters. Provider source is not modified and contains no Canopy-specific type.

This makes the result **PASS WITH CONSTRAINTS** if all behavioral and complexity
checks pass. The constraints are:

- prototype-local packaging of the unchanged, resolved #464 package;
- a nested-Lambda fixture using the public generic reconciler, not Lambda's
  private root-module key policy;
- a prototype-only annotation visibility adapter because production conversion
  remains package-private;
- Tier-1 direct evaluation only, not Tier-2 egglog escalation or unchanged-def
  prefix reuse;
- cutoff/backdating is proven only for one Eq-stable Term selector and trailing
  whitespace workload; SourceMap and AnnotationMap still recompute;
- mutable memo result safety, atomic shell-state publication, nested batches,
  and whole-consumer publication coherence remain unproven;
- owner/wiring feasibility only, not production consumer or lifetime closure.

## Reuse check

Reused project APIs:

- Loom `new_imperative_parser`, `ImperativeParser::parse/edit/current`;
- Lambda's real grammar through `new_imperative_parser`;
- Canopy Lambda `to_proj_node` and `populate_token_spans`;
- Canopy core `reconcile_hinted`, `collect_registry`,
  `SourceMap::from_ast`, and `ProjNode::walk_preorder`;
- Lambda eval `eval_term`;
- companion-private `build_eval_annotations` and `AnalysisProjection::annotations`
  through the evidence-only visibility adapter;
- semantic `build_semantic_projection`;
- protocol `proj_to_view_node` as the actual annotation consumer;
- issue #464 `Store`, `Region`, `Source`, `Query`, `query_eq`,
  `query_always_changed`, opaque `View`, `EvalCtx`, `Transaction`,
  cutoff/backdating, debug counters, and close semantics.

MoonBit core APIs checked and reused:

- `Map` for typed registry and batch hint evidence;
- `Option` and `Result` for lifecycle/read boundaries;
- `String`/`StringView` slicing for fixed ASCII fixture edits and range checks;
- `Array` for trace snapshots.

Checked but not used:

- `Iter`: `ProjNode::walk_preorder` already owns traversal;
- `StringBuilder`: fixed two-fragment fixture replacement is clearer with
  `StringView::to_owned`;
- current `build_projection_memos` / `build_lambda_projection_memos`: they own
  the graph being excluded;
- type-owned custom cutoff, eviction, Mount, Program, Port, and Manifest APIs:
  outside P1.2.

New helper boundaries are prototype-local: semantic batch finalization, one
ASCII fixture replacement, state rendering, finding one `Var` through the
existing preorder traversal, recursively checking the resulting protocol
`ViewNode`, and generating fixed-size benchmark let chains. The evidence adapter delegates to existing annotation functions; it
does not copy them. No new kernel or generic collection loop is added.

## Non-goals

```text
decorations, diagnostics, pretty annotation injection
Tier-2 escalation, incremental eval prefix cache, typecheck
remote sync, undo/redo, diagnostic fix
file I/O, browser lifecycle, FFI, coordinator
ProtectedCell replacement, Mount, RecomputeTap
shared host, production constructor, ADR
```
