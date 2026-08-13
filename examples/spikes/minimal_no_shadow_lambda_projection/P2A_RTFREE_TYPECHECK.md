# P2a — Runtime-free whole-module typecheck feasibility

**Question:** Can the no-shadow graph lazily produce a whole-module
`ModuleTypeResult` from the exact parser publication while constructing no
current `Runtime`, `Scope`, `Derived`, `Watch`, `DerivedMap`, `Accumulator`, or
on-change listener?

**Verdict:** **OWNER GRAPH PASS WITH CONSTRAINTS; PRODUCTION TYPECHECK PRODUCER
PARITY NOT YET.**

Run the one-command evidence gate:

```bash
./scripts/run-minimal-no-shadow-lambda-typecheck.sh
```

P2a extends the P1.5 evidence branch only. It does not alter production Lambda
construction, current typecheck packages, the Incr Next provider, or public
interfaces.

## Graph

P2a preserves the one coherent Source. It does not copy the parser snapshot
into a second Source.

```text
ProjectionCommit Source
  owns exact ParseSnapshot syntax
        ↓
TypedTerm Query
  convert_from_cst(commit.parse_snapshot.syntax)
        ↓
ModuleTypeResult Query
  resolve_typed
  sequential TypeEnv::bind + infer
```

The `ProjectionCommit` is the prototype's parser-publication envelope: its
`commit_id` identifies the publication and it owns the exact `ParseSnapshot`
used by projection. `TypedTerm` reads `parse_snapshot.syntax`, not
`projection.kind`, because production CST conversion observes syntax structure
and annotations that the projected `Term` does not carry.

```text
application owner           1
Store / Region              1 / 1
canonical Source            1
current Runtime             0
Scope / Derived / Watch     0 / 0 / 0
DerivedMap / Accumulator    0 / 0
on-change listener          0
cross-runtime bridge        0
```

The imported production typecheck package still contains its current reactive
pipeline definitions and depends on `dowdiness/incr`. P2a does not call those
constructors. The no-current-object claim applies to the selected execution
path, not to transitive package source or linkage.

## Existing API First

### Production APIs reused

| API | Responsibility | Reused? |
|---|---|---:|
| `convert_from_cst` | exact `SyntaxNode` to `TypedTerm` conversion | yes |
| `resolve_typed` | sequential module name resolution | yes |
| `infer` | production bidirectional inference core | yes |
| `TypeEnv::bind` | extend the type environment after each definition | yes |
| `ModuleTypeResult` / `TypeResult` | existing result shapes | yes |

### APIs checked but not used

| API | Why not used |
|---|---|
| `build_typecheck_pipeline` | requires current `Runtime`, `Scope`, and `Derived` |
| `build_typecheck_pipeline_with_index` | additionally creates `DerivedMap` and an on-change listener |
| `TypecheckIndex` | P2c question; stable definition identity is out of P2a scope |
| `ProjectionIdentityTracker` | unrelated to typecheck definition identity and parser publication |

MoonBit core candidates checked for the data shape:

- `Array` is reused as a local builder for ordered definition results;
- `Option` is reused through existing type annotations and diagnostic shapes;
- `Result` is reused at the Query read boundary;
- `Map`/`Set` are unnecessary for whole-module sequencing;
- `String`/`StringView` and `Bytes`/`BytesView` are unnecessary because
  `convert_from_cst` owns syntax traversal;
- `StringBuilder`/`Buffer` and `cmp`/`math` do not fit this transformation.

The only new helper, `p2a_whole_module_typecheck`, owns whole-module sequential
orchestration. Its local mutation builds a returned value and has no observable
external effect.

## Behavioral evidence

Native and JS run the same assertions.

```text
initial
  TypedTerm compute             0
  ModuleTypeResult compute      0

first demand
  TypedTerm compute             1
  ModuleTypeResult compute      1
  direct trace lengths          1 / 1

repeated read
  compute counts unchanged

body-only edit before demand
  compute counts unchanged

after body demand
  TypedTerm compute             2
  ModuleTypeResult compute      2
  definitions                   2

structural definition insertion before demand
  compute counts unchanged

after structural demand
  TypedTerm compute             3
  ModuleTypeResult compute      3
  definitions                   3

close
  both memo tables/traces cleared
  duplicate close              AlreadyClosed
  post-close read              ClosedRegion
  provider compute delta       0
```

The body-only and structural edits both publish exact new commits but perform no
typecheck work until demand. This preserves the operation/publication/demand
separation established by P1.5.

## Constraint: diagnostics are not production-equivalent

Production detailed diagnostics are emitted by private `infer_impl` through a
current-Incr `Accumulator`. The public pure `infer` entry point intentionally
uses `DiagCtx::empty()` and drops diagnostic messages. P2a therefore returns:

```text
all_diagnostics = []
```

for clean fixtures only. It also does not reproduce duplicate-definition
diagnostics from the current pipeline. Consequently P2a proves that the
conversion, resolution, inference, and whole-module result owner graph can be
Runtime-free. It does **not** close the production typecheck producer blocker.
A pure diagnostic-producing core or another non-current-Incr diagnostic return
path is still required.

## What remains

```text
P2b  unchanged-definition and prefix work reuse
P2c  stable DefId / TypecheckIndex
open pure diagnostic production and duplicate-name diagnostics
open error/failure parity
open typed diagnostic ranges
open production constructor and lifecycle integration
open immutable/defensive result publication review
```

P2a does not authorize a typecheck package refactor, production migration,
current pipeline deletion, P2b/P2c, ADR, or Cut B′ implementation.
