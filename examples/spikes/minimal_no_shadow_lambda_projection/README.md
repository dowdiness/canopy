# Minimal no-shadow Lambda projection P0

**Status:** Throwaway feasibility prototype. Keep it on the prototype branch; do
not merge it into production.

## Question

Can one application shell use the production Lambda `ImperativeParser`,
projection conversion, reconciliation, registry, and source-map algorithms with
the issue #462 incremental provider, while constructing no current-Incr runtime
objects or bridge, and make ownership visibly smaller than the current reactive
path?

This is an architecture feasibility gate, not production migration evidence.
Issue #1236 remains the production authorization ledger.

## Run

From the Canopy repository root:

```bash
./scripts/run-minimal-no-shadow-lambda-projection.sh
```

The command verifies the materialized provider hash, checks the two packages,
runs the native executable, prints every relevant state transition, checks the
prototype allowlist, and prints the virtual deletion ledger.

## Scope

P0 runs these operations in order:

```text
initial
raw-edit
structural-batch
demand-registry
demand-source-map
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
└─ issue #462 Store
   └─ Region
      ├─ Source[ProjectionCommit]
      ├─ Query[Unit, Registry]
      └─ Query[Unit, SourceMap]
```

The split is intentional:

```text
Shell      owns history-sensitive projection transitions.
#462       owns lazy derivation from one committed value.
```

`ProjectionCommit` owns the exact `ParseSnapshot`, projection, and trace.
Source-map computation therefore cannot combine a new projection with an old
snapshot.

## Complexity budget

```text
application owner              1
Store                          1
Region                         1
canonical Source               1
lazy Query                     2
Mount                          0
Watch                          0
Program / Port / Manifest      0
current Runtime objects        0
cross-runtime synchronization  0
async resources                0
```

Canopy's current `core` and Lambda projection packages still have a transitive
compile dependency on current Incr because their production memo builders share
those packages. P0 does not call those builders or construct any current-Incr
value. Splitting those production packages is explicitly not part of P0.

## #462 evidence reuse

The directory
`evidence/incr_next_incremental_parity/provider/` is copied byte-for-byte from
commit:

```text
d54e78087d3837eccee0c55247adb90c07625869
```

`provider.sha256` guards every provider file. The adjacent `moon.mod` is only a
prototype-local packaging adapter. The provider files are not modified and do
not contain Canopy-specific types.

This makes the result **PASS WITH CONSTRAINTS** if all behavioral and complexity
checks pass. The constraints are:

- prototype-local packaging of the unchanged #462 package;
- a nested-Lambda fixture using the public generic reconciler, not Lambda's
  private root-module key policy;
- owner/wiring feasibility only, not production consumer or lifetime closure.

## Reuse check

Reused project APIs:

- Loom `new_imperative_parser`, `ImperativeParser::parse/edit/current`;
- Lambda's real grammar through `new_imperative_parser`;
- Canopy Lambda `to_proj_node` and `populate_token_spans`;
- Canopy core `reconcile_hinted`, `collect_registry`,
  `SourceMap::from_ast`, and `ProjNode::walk_preorder`;
- issue #462 `Store`, `Region`, `Source`, `Query`, opaque `View`, `EvalCtx`,
  `Transaction`, and close semantics.

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
- later Incr Next cutoff, eviction, Mount, Program, Port, and Manifest APIs:
  outside P0.

New helper boundaries are prototype-local: semantic batch finalization, one
ASCII fixture replacement, state rendering, and finding one `Var` through the
existing preorder traversal. No new kernel or generic collection loop is added.

## Non-goals

```text
annotations, decorations, diagnostics
evaluation, escalation, typecheck
remote sync, undo/redo, diagnostic fix
file I/O, browser lifecycle, FFI, coordinator
ProtectedCell replacement, Mount, RecomputeTap
shared host, production constructor, ADR
```
