# Cut B′ candidate lifetime allocation — research inventory

**Date:** 2026-08-13
**Status:** Research inventory only
**Reader:** Maintainers evaluating #1236 and the Cut B′ production gate
**Decision:** Allocate one candidate lifetime owner and close the conditional
positive-deletion ledger without authorizing implementation
**Keep until:** #1236 is closed or its evidence is incorporated into a durable
implementation decision
**Disposition:** Delete after incorporation; Git history preserves the research
inventory
**Parent:** [#1230](https://github.com/dowdiness/canopy/issues/1230)
**Child investigation of:** [#1236](https://github.com/dowdiness/canopy/issues/1236)
**deps/loom pointer:** `ae3f222f3c3135c55fc574ac418e8a54144af1a2`

## Scope and non-goals

This document records the candidate single-owner resource allocation and
positive deletion ledger for a shell-owned projection publisher (Cut B′). It
does **not** authorize:

- a replacement implementation;
- an Incr Next state layer or current-Incr interoperability;
- parser migration, new Mounts, or removal of production Watches/ProtectedCells;
- performance optimization or baseline measurement;
- an ADR;
- publication of any issue or PR comment.

P1 performance is frozen; this gate does not revisit it. No-op detection
classification is completed in a prior sub-gate and is not reopened here.

## Status vocabulary

```text
SOURCE-CLOSED       Current creation, ownership, close, and retention are
                    explained by source.
ORACLE-NEEDED       Source leaves an actual runtime behavior undecidable.
OUT-OF-CUT          A distinct external owner is identified; the Lambda
                    read-model cut must not close it.
BLOCKER             The current path has no complete close/retention-severance
                    path, or cannot be reused by Cut B′.
CONDITIONAL         Deletable only after a stated migration completes.
```

A row may be SOURCE-CLOSED as a description of current behavior and still be a
BLOCKER for candidate reuse.

## Verdict

```text
PASS WITH CONSTRAINTS — ledger closure only
```

The five-item semantic ownership inventory and the current retention-root
ledger are source-closed. The candidate single-owner allocation is viable as a
contract, but current construction cannot realize it and current lifetime
cannot close it. Cut B′ implementation, migration, and ADR remain unauthorized.

## Constraints from completed gates

Prior sub-gates established:

1. **Projection transition characterization** — PASS; shell-owned reducer
   viability remains; Incr Next state layer requirement not demonstrated.
2. **Trace timing** — sole production consumer
   (`apps/ideal/main/intent_log.mbt::push_patch`) forces projection before
   reading trace; no demand-triggered timing dependency found.
3. **Semantic edit completion funnel** — PASS WITH CONSTRAINTS; batch-eager
   publisher preferred; SyncEditor is the single shell owner candidate for
   semantic batch depth/token and finalization.
4. **No-op identity-evidence classification** — required semantic contracts,
   explicit compatibility contracts, and implementation accidents classified.
5. **Remote causal state vs projection identity** — the former
   pending/history-only question is closed; DocumentVersion and
   ParseSnapshot are separate publication nodes; closed identity-evidence
   semantics (`NoEvidence | Valid | Invalidated`) established.
6. **Five-item ownership ledger** — SOURCE-CLOSED; positive Lambda deletion
   candidate present but conditional; current construction cannot realize it.
7. **Projection/parser consumer and constructor closure** — production consumer
   inventory SOURCE-CLOSED; current Runtime construction-edge closure BLOCKED;
   five runtime/API groups must migrate before no-current-Runtime proof.
8. **Retention-root/lifetime ledger** — SOURCE-CLOSED; current lifetime reuse
   FAIL; no ORACLE-NEEDED rows for in-cut failures.

## Candidate single owner / resource allocation

### Lifetime owner

The candidate assigns one **Lambda shell owner** that exclusively owns:

- parser publication owner (Runtime-free `ImperativeParser` via
  `@loom.new_imperative_parser` — `deps/loom/loom/factories.mbt::new_imperative_parser`);
- projection/read-model children (registry, source map, eval, typecheck,
  analysis, view exports);
- analysis/typecheck/debug subscriptions selected by the target;
- transport/async admission selected by the shell.

The shell owner does **not** own `WorkspaceCellHandle` resources held by
external workspace consumers. Those are OUT-OF-CUT.

### Candidate Store/Region

The candidate read-model Region is **Incr Next evidence** — it is a proposed
target construct, not the current `WorkspaceCellHandle`
(`modules/canopy/workspace/coordinator/workspace_cell_handle.mbt::WorkspaceCellHandle`)
or current `Coordinator`
(`modules/canopy/workspace/coordinator/methods.mbt::Coordinator`). The current
Coordinator remains the workspace dependency/refusal gate and is OUT-OF-CUT for
the Lambda read-model cut. The candidate Region is a contract placeholder for
a future Incr Next Formula/Program owner; it does not exist today.

### ProjectionIdentityTracker

`ProjectionIdentityTracker`
(`deps/loom/loom/projection/projection_identity.mbt::ProjectionIdentityTracker`)
tracks stable semantic leaf identity across source frames. It is **unrelated**
to ParseSnapshot publication identity/provenance. It does not satisfy the
coherence proof required by Cut B′.

### Child resources assigned to the shell owner

| Child resource | Candidate assignment | Current source symbol |
|---|---|---|
| `ProjectionState` | Shell-owned; holds `previous`, `next_node_id` | `modules/canopy/core/projection_memo.mbt::prev_proj_ref`, `counter` |
| Pending identity evidence | Outer `SemanticBatchState` tied to predecessor commit | `modules/canopy/editor/sync_editor.mbt::pending_transforms` |
| `ProjectionCommit` | Immutable; carries projection, trace, snapshot identity, projection input | New contract; no current type |
| Registry/source-map Formula regions | Lazy Formulas keyed by commit ID | Current: `registry_memo`, `source_map_memo` Deriveds |
| Program/Region close | Shell-owned; explicit close before parser publication owner | Current: `LambdaAnalysis::dispose`, `TypecheckAttachment::dispose` |
| Analysis attachment | Child resource; closed before parser publication owner | `deps/loom/examples/lambda/analysis.mbt::attach_lambda_analysis` |
| Protected exported capabilities | Typed exports with lifecycle gate | Current: `LambdaProtectedCells` ten Watches |

### One candidate `ProjectionCommit` Source

The candidate design assigns exactly one `ProjectionCommit` per successful
transition. The commit carries:

```text
ProjectionCommit {
  commit_id
  predecessor_commit_id
  publication         : strong ParserPublication handle
  projection          : owned immutable projection
  trace               : immutable Array[ReconcileTraceEvent]
  projection_input    : exact owned/immutable syntax payload
  next_state          : next ProjectionState
}
```

No second Source, Derived, or live Ref publishes the same projection/trace
under the candidate. The current `LambdaCompanion.trace_ref`
(`modules/canopy/lang/lambda/companion/lambda_editor.mbt::trace_ref`) is the
sole current trace publication point and is a deletion candidate.

### Child Programs/resources close order

The shell owner closes children before the parser publication owner:

```text
1. Stop candidate ingress/publication (mark Closing)
2. Close the analysis owner once; the current `LambdaAnalysis::dispose` closes
   both its own Scope and its child `TypecheckAttachment`
3. Close any replacement typecheck subscription/index not owned by the
   replacement analysis resource
4. Close debug/telemetry subscriptions (e.g., RecomputeTap replacement)
5. Close read-model Region (registry/source-map/eval/typecheck/view exports)
6. Close parser publication owner and release the `ImperativeParser` payload
   (the current engine has no explicit close API)
7. Sever coordinator/host payload reachability
8. Leave only defined metadata/fallback behavior (Closed)
```

## Typed ownership / lifetime graph

### Edge classes

```text
TrackedRead      — consumer reads a value through a tracked/provenance boundary
EagerRead        — consumer reads a value directly without provenance gating
Construction     — edge created at construction time; defines structural ownership
Retention        — edge that keeps a value alive beyond its semantic consumer
Mutation         — edge that modifies owned state
Publication      — edge that delivers a committed value to a consumer
Lifetime         — edge that defines close/dispose ordering
CrossRuntime     — edge where the same semantic value is owned by both current
                   Incr and Incr Next (forbidden in Cut B′)
```

### Graph nodes and edges

```text
Lambda Shell Owner (lifetime owner)
  ├──Construction──▶ ImperativeParser engine (retained, Runtime-free)
  │                    └──Publication──▶ ParserPublication {
  │                                        publication_id
  │                                        source_id
  │                                        owned immutable ParseSnapshot
  │                                      }
  ├──Construction──▶ ProjectionState (semantic owner)
  │                    ├──Mutation──▶ previous : ProjNode
  │                    └──Mutation──▶ next_node_id : Int
  ├──Construction──▶ SemanticBatchState (evidence owner)
  │                    └──Mutation──▶ NoEvidence | Valid(hints) | Invalidated
  ├──Publication───▶ ProjectionCommit (one per successful transition)
  │                    ├──TrackedRead──▶ projection
  │                    ├──TrackedRead──▶ trace
  │                    ├──TrackedRead──▶ parse_snapshot_identity
  │                    └──TrackedRead──▶ projection_input
  ├──Construction──▶ Read-model Region (lazy Formulas)
  │                    ├──TrackedRead──▶ RegistryExport { commit_id, view }
  │                    ├──TrackedRead──▶ SourceMapExport { commit_id, view }
  │                    ├──TrackedRead──▶ EvalExport { publication_id, result }
  │                    └──TrackedRead──▶ TypecheckExport { publication_id, queries }
  ├──Construction──▶ Typed export surface (lifecycle-gated)
  │                    └──TrackedRead──▶ ProjectionExport, ParserPublication exports
  ├──Lifetime──────▶ Child close (analysis-owned typecheck → any separate target subscription → debug → Region → parser)
  └──Lifetime──────▶ Host severance (coordinator payload, raw aliases)

Coordinator (OUT-OF-CUT)
  ├──Retention───▶ EditorRegistration metadata (alive/dead)
  └──Lifetime────▶ Refusal gate (DestroyWhileDependedUpon)

WorkspaceCellHandle (OUT-OF-CUT)
  └──Retention───▶ External workspace consumer dependency edges

Browser Editor Controller (external owner)
  └──Lifetime────▶ Preflight participation; retryable on refusal
```

### CrossRuntime edges

```text
CrossRuntime edge count in candidate: ZERO
```

No edge assigns the same semantic value to both current Incr and Incr Next.
The candidate deletes all current-Incr Lambda producers
(projection/eval/typecheck/analysis Deriveds, Watches, ProtectedCells) and
replaces them with shell-owned or Incr Next Formula/Program owners. Generic
current-Incr producers for non-Lambda languages (JSON, Markdown, JSX) remain
unchanged and are not part of the Cut B′ deletion scope.

## Alive / Closing / Closed state machine

### States

```text
Alive
  refused preflight → Alive with zero lifecycle/resource delta
  authorized preflight → Closing

Closing
  does not execute provider read/compute
  accepts no new action or publication
  releases every resource owned at authorization, unless already closed
  does not repeat any resource release during duplicate/re-entrant close
  rejects late publication
  severs host → heavy provider retention
  never returns to Alive
  → Closed

Closed
  duplicate destroy result is defined
  lookup may return metadata/fallback
  lookup does not invoke provider, root, observe, schedule, or publish
  sibling editors on the shared host are unaffected
```

"Zero delta" refers to editor/lifetime state. The current host gateway prints
the refusal report; this pass does not redefine logging as mutable editor
state.

### Exact close order

```text
Alive → authorized preflight → Closing:
  1. Stop ingress: reject new actions, edits, publications
  2. Close the analysis owner once
     (`deps/loom/examples/lambda/analysis.mbt::LambdaAnalysis::dispose` closes
     both its Scope and its child `TypecheckAttachment`)
  3. Close any replacement typecheck subscription/index that is deliberately
     allocated outside the replacement analysis resource
  4. Close debug/telemetry subscriptions (Ideal RecomputeTap replacement or removal)
  5. Close read-model Region (registry/source-map/eval/typecheck/view Formulas)
  6. Close parser publication owner and release the ImperativeParser payload
     (the current engine has no explicit close API)
  7. Sever coordinator registration payload (EditorRegistration closures)
  8. Remove HostRegistry entry and view state
  9. Release typed export surface
  → Closed

Alive → refused preflight → Alive:
  1. Zero lifecycle/resource delta
  2. Return refusal report
  → Alive (unchanged)
```

### Refusal atomicity

Current source-backed refusal ordering
(`modules/canopy/workspace/coordinator/methods.mbt::Coordinator::destroy_editor`,
`modules/canopy/ffi/host/host.mbt::HostRegistry::destroy`,
`modules/canopy/ffi/lambda/lifecycle.mbt::try_destroy_editor`)
has the required internal boundary. However, end-to-end refusal atomicity is
FAIL: the browser owner tears down UI resources **before** calling
`try_destroy_editor` and discards `false`. A dependency refusal leaves the
MoonBit editor alive but its browser owner torn down and unable to retry.

## Current → candidate positive deletion ledger

### Five ownership items

| # | Current element | Current responsibility | Current source symbol | Candidate replacement owner | Deletable? | Deletion condition | Reason it remains |
|---|---|---|---|---|---:|---|---|
| 1 | `prev_proj_ref` | Previous successful projection | `modules/canopy/core/projection_memo.mbt::prev_proj_ref` | Shell `ProjectionState.previous` | Conditional | Distinct Lambda publisher construction; all consumers moved; no compatibility Derived | Current `SyncEditor::new_with_builder` and `Language` require and Watch the projection trio; generic other-language local retained |
| 2 | Projection counter | NodeId allocation | `modules/canopy/core/projection_memo.mbt::counter` | Shell `ProjectionState.next_node_id` | Conditional | Same construction/consumer closure; uniqueness and required continuity established | Exact counter tests still require contract classification; generic counter retained |
| 3 | `pending_transforms` | Cross-batch identity queue and Opaque taint | `modules/canopy/editor/sync_editor.mbt::pending_transforms` | Batch-local `SemanticBatchState.identity_evidence` tied to predecessor commit | Conditional | One explicit outer batch/finalizer; no Lambda old queue allocated | No outer batch exists; current constructor allocates queue unconditionally; generic Markdown path retained |
| 4 | `IdentityHintConsumer` | Consume-only queue boundary | `modules/canopy/core/identity_hint_consumer.mbt::IdentityHintConsumer` | Deleted from Lambda instance; commit-time owned handoff | Conditional | No Lambda current builder consumer remains | Shared generic type retained while current hint pipeline remains |
| 5 | `trace_ref` | Live reconcile trace publication | `modules/canopy/lang/lambda/companion/lambda_editor.mbt::trace_ref` | Exact `ProjectionCommit.trace` returned with edit token | Conditional | In-repo/exported consumers migrated; old closure/root removed | Exact command→commit handoff and exported API decision remain |

### Additional deletion items

| Current element | Current responsibility | Current source symbol | Candidate replacement | Deletable? | Deletion condition | Reason it remains |
|---|---|---|---|---:|---|---|
| 6 | Parser reactive wrapper | Current-Incr ParseSnapshot publication and Runtime participation | `deps/loom/loom/factories.mbt::new_parser` (via `Parser::new`) | Shell ParserPublication owner over `new_imperative_parser` | Conditional | Eval/typecheck/debug/protected/concrete API blockers closed; distinct constructor omits `new_parser` | Consumer inventory is closed, but no-current-Runtime and old-producer omission proofs are not |
| 7 | Projection trio (projection/registry/source-map Deriveds) | Lambda projection, registry, source map | `modules/canopy/lang/lambda/proj/projection_memo.mbt` (via `build_lambda_projection_memos`) | ProjectionPublisher + lazy Formulas | Conditional | All Lambda consumers use exports; distinct constructor omits old trio | Concrete `SyncEditor` APIs/callers and Derived-based protected surface still active |
| 8 | Three SyncEditor Watches | Editor-lifetime roots | `modules/canopy/editor/sync_editor.mbt::finish_editor` (`projection_anchor`, `registry_anchor`, `source_map_anchor`) | None or one later justified root | Conditional | Lambda constructor never calls `finish_editor`; no old trio exists | Current successful destroy does not dispose them; retention ledger shows they remain active |
| 9 | 10 LambdaProtectedCells Watches | Workspace retention/read preflight | `modules/canopy/ffi/lambda/protected_cells.mbt::LambdaProtectedCells` | Typed exports plus structured lifecycle gate | Conditional | Derived-based protected bundle removed; semantic/preflight callers migrated | Current bundle creates Watches; registry is retention-only but projection/source-map still read |
| 10 | `escalation_memo` / `build_eval_memo` | Evaluation result ownership | `modules/canopy/lang/lambda/eval/eval_memo.mbt::build_eval_memo`, `modules/canopy/lang/lambda/eval/batch_escalation.mbt::build_escalation_memo` | Evaluation Formula/export carrying ParserPublication provenance | Conditional | Eval/escalation producer migrated; no Parser/Runtime callback remains | Current constructors build current Deriveds |
| 11 | Typecheck output | Analysis read model | `deps/loom/examples/lambda/typed_parser.mbt::attach_typecheck` | Typecheck Program/query export carrying ParserPublication provenance | Conditional | Loom/Canopy producer accepts publication port; listener/scope removed and closed | Current attachment requires Parser Runtime; discarded ListenerId prevents cancellation proof |
| 12 | Analysis attachment | Analysis/typecheck diagnostics lifetime | `deps/loom/examples/lambda/analysis.mbt::attach_lambda_analysis` | Program/resource owner combining parser diagnostics + typecheck export | Conditional | Create/destroy path and async subscriptions migrated to one Region owner | Current attachment owns current Scope/Watch and depends on current Parser |
| 13 | Companion memo aliases | Facade access to projection/eval/typecheck/trace | `modules/canopy/lang/lambda/companion/lambda_editor.mbt` (LambdaCompanion) | Lambda shell/read façade and typed exports | Conditional | In-repo/external callers migrated; Derived-returning APIs removed | Public current concrete types would recreate/retain old graph |
| 14 | Projection/snapshot coherence | Implicit same-Runtime Parser Input/Derived graph | Implicit via `deps/loom/loom/pipeline/parser.mbt` snapshot Input | `ParseSnapshotIdentity` plus exact owned `projection_input` in `ProjectionCommit` | Conditional | All Lambda parser-view consumers moved; old wrapper/roots removed; one close owner | Current wrapper has no identity; source map needs payload, not ID alone; parser poison/lifetime unresolved |
| 15 | `cached_proj_node` | Projection root | `modules/canopy/editor/sync_editor.mbt::cached_proj_node` | Opaque ProjectionExport carrying exact commit provenance | Conditional | All Lambda consumers use exports; distinct constructor omits old trio | Concrete `SyncEditor` APIs/callers and Derived-based protected surface still active |
| 16 | `registry_memo` | NodeId registry | `modules/canopy/editor/sync_editor.mbt::registry_memo` | Lazy RegistryExport tagged with commit ID | Conditional | Structural/action and Ideal consumers migrated; old builder omitted | Current Language SPI requires registry Derived; protected registry Watch has no live in-repo semantic reader but is still constructed |
| 17 | `source_map_memo` | Projection/source ranges | `modules/canopy/editor/sync_editor.mbt::source_map_memo` | Lazy SourceMapExport over projection + exact ParserPublication syntax | Conditional | Every paired read checks commit provenance; legacy wire shape preserved; old builder omitted | Current readers and concrete APIs remain; payload identity alone is insufficient without exact syntax |
| 18 | Diagnostic revision | Diagnostic source revision Derived | `modules/canopy/editor/diagnostic_publication_input.mbt::SyncEditor::diagnostic_publication_source_revision` | Pure typed `{SourceId, DocumentVersion}` export | Conditional | No current Derived/Watch in candidate path | Currently retention-only; registered but only unused diagnostic-input builder reads it |
| 19 | Ideal RecomputeTap | Debug derived-event listener on shared current Runtime | `apps/ideal/main/init.mbt::init_model` → `RecomputeTap::attach(editor.parser_runtime())` | Next debug/telemetry stream or explicit product decision | Conditional | No `parser_runtime()` call/current listener in candidate | No production detach call exists; detach only flips `active` |
| 20 | Async pattern ingress | ast-grep request/result publication | `modules/canopy/ffi/lambda/analysis.mbt::apply_ast_grep_results_json` | Shell/provider boundary with versioned request/publication provenance | Conditional | Versioned token captured before dispatch; validated at ingestion; late result after close must not publish | Current ingress stamps with current source snapshot; no request/publication token |
| 21 | Browser refusal | Browser editor controller around `try_destroy_editor` | `apps/web/src/features/lambda/browser/editor.ts::dispose` | External owner must participate in preflight outcome | Conditional | Keep owner usable until preflight authorization or restore retryable owner on refusal | Currently tears down UI before destroy; ignores refusal |
| 22 | File ingress | File open/save host invocation | `modules/canopy/ffi/lambda/file_io.mbt::load_file`, `save_file` | Shell/FFI boundary must gate target validity before host invocation | Conditional | Validate live handle before outbound request/save; late inbound delivery must relookup/admit | `load_file` invokes host without handle lookup; late open dispatch can target raw Ideal model path |
| 23 | Cursor subscription | Internal cursor-store subscription | `modules/canopy/editor/sync_editor.mbt::setup_hub_and_cursor` (returned `EphemeralSubscription` is ignored) | Must be explicitly assigned: Shell-owned or Sync/Presence-owned | Conditional | Assign an owner and unsubscribe, or prove Sync/Presence owns the complete lifetime | Subscription handle is discarded; no explicit owner can sever it |
| 24 | Raw MoonBit aliases | `get_sync_editor` / `get_lambda_companion` bypass | `modules/canopy/ffi/lambda/lifecycle.mbt::get_sync_editor`, `get_lambda_companion` | Migrate to single Lambda shell/read façade; post-close façade must not execute provider | Conditional | Concrete public APIs and Ideal Model migrated; old aliases removed | FFI registry removal cannot revoke copied aliases; aliases can still call parser/projection/analysis methods |
| 25 | Typecheck raw DerivedMap / listener | Typecheck additive on-change listener | `deps/loom/examples/lambda/typecheck/typecheck.mbt::build_typecheck_pipeline_with_index` (ListenerId discarded) | Target typecheck owner must own replacement index lifecycle and subscription | Conditional | No listener on current Runtime; disposal owned by Program/Region | Scope disposal does not register/dispose this map; listener fires on every later Runtime revision |

### Generic framework vs Lambda-instance deletion scope

```text
Lambda instance responsibility deleted:
  - prev_proj_ref instance in Lambda projection stack
  - NodeId counter instance in Lambda projection stack
  - pending_transforms instance + IdentityHintConsumer instance
  - trace_ref + LambdaCompanion getter
  - Lambda reactive Parser wrapper (new_parser call)
  - Lambda projection trio Deriveds
  - Lambda eval/escalation Deriveds
  - Lambda analysis/typecheck current scopes/Watches/listener
  - 10 LambdaProtectedCells Watches
  - Three SyncEditor private Watches (via omitting finish_editor)
  - Lambda companion memo aliases
  - Ideal RecomputeTap current-Runtime attachment
  - Raw SyncEditor/LambdaCompanion public aliases

Generic framework responsibility retained:
  - core prev_proj_ref for JSON/Markdown/JSX projection stacks
  - core counter for other current projection stacks
  - IdentityHintConsumer shared generic type
  - Core trace machinery (shared framework/test infrastructure)
  - Generic Loom Parser for non-Lambda users
  - Generic LanguageCapabilities machinery for non-Lambda languages
  - Generic SyncEditor for JSON/Markdown/current users
  - Coordinator and WorkspaceCellHandle (OUT-OF-CUT)

Shared abstraction deleted globally:
  - None claimed in this cut
```

## Responsibility delta

### Deleted responsibilities

- Long-lived cross-batch identity queue and demand-time drain
- Path-specific pre-taint (operation-start, pending-only, history-only)
- Multiple `Opaque` sentinel accumulation
- Hints retained before `Opaque`
- Live Ref-based trace publication and companion getter
- Current-Incr Parser wrapper with five Derived views on shared Runtime
- Current projection/registry/source-map Deriveds for Lambda
- Current eval/escalation Deriveds for Lambda
- Current analysis/typecheck Scope/Watch/listener for Lambda
- Ten `ProtectedCell::from_derived` Watch roots for Lambda
- Three undisposed SyncEditor private anchor roots
- Dead coordinator registration payload retaining disposed Watch closures
- Raw concrete `SyncEditor[@ast.Term]` / `LambdaCompanion` public aliases
- Ideal `parser_runtime()` tap attachment

### Added responsibilities

- Shell-owned `ProjectionState` (previous, next_node_id)
- Shell-owned `SemanticBatchState` (nesting/finalization token, predecessor commit identity, evidence decision)
- Shell-owned `ParserPublication` (publication_id, source_id, owned immutable snapshot)
- Shell-owned `ProjectionCommit` (commit_id, publication, projection, trace, projection_input, next_state)
- Lazy registry/source-map Formulas keyed by commit ID
- Typed export surface with lifecycle gate
- Explicit child close ordering (analysis-owned typecheck → any separate target subscription → debug → Region → parser)
- Coordinator payload severance on successful close
- Browser preflight participation contract
- File ingress live-handle admission gate
- Async pattern versioned request/publication provenance
- Cursor subscription explicit ownership

### Semantic state owners

```text
Current:  scattered across Derived closures, SyncEditor fields, LambdaCompanion, Coordinator
Candidate: one Lambda shell owner
```

### Cross-runtime synchronization edges

```text
Current:  implicit via shared Runtime (parser, projection, eval, analysis, protected cells, tap)
Candidate: ZERO
```

### Retention roots

```text
Current:  ProtectedCell Watches, SyncEditor private anchors, Coordinator registration payload,
          Runtime disposed memo closures, typecheck listener/map, Ideal tap, raw aliases
Candidate: typed exports with lifecycle gate; no current-Incr roots for Lambda
```

### Lifetime owners

```text
Current:  partial (Coordinator disposes ProtectedCells; no unified close)
Candidate: one Lambda shell owner with explicit close order
```

### Constructor wiring edges

```text
Current:  assemble_lambda_handle → new_lambda_editor → lambda_language.build →
          SyncEditor::new_with_builder → @loom.new_parser → finish_editor →
          LambdaProtectedCells → coordinator registration
Candidate:  Lambda FFI construction shell → imperative shell components →
            new_imperative_parser → ParserPublication owner → ProjectionPublisher →
            SemanticBatchState → read-model Region → typed export surface → Lambda handle
```

Note: responsibility delta is not reported numerically because not every row
maps exactly to a single countable unit. The delta is qualitative: old
scattered ownership → one shell owner with explicit children and close order.

## Remaining conditional blockers

The following must close before Cut B′ can proceed from research to
implementation authorization:

1. **Eval/escalation producer migration** — current `build_eval_memo` /
   `build_escalation_memo` construct current Deriveds; no Formula/Program
   producer exists yet.
2. **Typecheck/analysis producer migration** — `attach_typecheck` /
   `attach_lambda_analysis` require `@loom.Parser`/Runtime; discarded
   `ListenerId` prevents cancellation proof; raw `DerivedMap` is outside Scope
   ownership.
3. **Ideal debug telemetry replacement** — `RecomputeTap::attach(editor.parser_runtime())`
   has no production detach; no replacement debug stream decided.
4. **Public concrete Lambda API migration** — generated interfaces export
   `SyncEditor[Term]`, `LambdaCompanion`, `Derived[...]` return types; external
   MoonBit API compatibility review required.
5. **Typed protected-export/lifecycle construction** — no current replacement
   for `ProtectedCell::from_derived` with provenance-gated reads.
6. **Async pattern provider/client token migration** —
   `apply_ast_grep_results_json` stamps with current source snapshot; no
   request/publication token; web-client migration in progress.
7. **Ideal handle propagation** — Ideal `Model` stores raw `SyncEditor` and
   `LambdaCompanion`; web bootstrap assumes handle 0; distinct construction
   must propagate actual handle or deliberately fix that contract.
8. **Distinct Lambda constructor/lifetime owner** — no publisher-aware
   construction path exists that omits `new_parser`, `finish_editor`,
   `build_lambda_projection_memos`, and the projection trio.
9. **Browser refusal atomicity** — browser tears down before
   `try_destroy_editor`; dependency refusal leaves MoonBit editor alive with
   browser gone.
10. **File ingress gating** — `load_file` invokes host without handle lookup;
    late inbound delivery can bypass live-handle admission.
11. **Cursor subscription ownership** — `EphemeralSubscription` from
    `setup_hub_and_cursor` is discarded; no explicit owner.
12. **Raw alias revocation** — `get_sync_editor` / `get_lambda_companion`
    return uncancellable copies; post-close behavior undefined.
13. **Coordinator payload severance** — dead `EditorRegistration` retains
    disposed Watch/getter/Derived closures; no tombstone or closure release.
14. **Runtime disposed-payload severance** — module-global Runtime retains
    old `MemoData` through append-only dispatch references; no in-process
    release path.

## Hard gates summary

A candidate fails when any of the following remains:

- [x] manual current-Incr-to-Next value copying — **not present**
- [x] a Next Formula callback reading current `Derived` — **not present**
- [ ] duplicate projection/registry/source-map/evaluation/parser-snapshot ownership — **candidate omission proof is incomplete; constructing both paths would fail this gate**
- [ ] current producers retained solely for moved consumers — **BLOCKED: 5 runtime/API groups**
- [ ] capability-specific bridge Sources — **not yet**
- [ ] old and new production paths evaluating the same capability — **not yet**
- [ ] projection/source-map snapshot mismatch — **current has no explicit identity**
- [ ] hint consumption owned by more than one component — **current has single consumer but cross-batch accumulation**
- [ ] trace publication owned by both companion and publisher — **current has companion only**
- [ ] double-rooting through Watch and Mount — **not yet (no Mounts)**
- [ ] two close owners — **current has partial/no unified close**
- [ ] permanent cross-runtime synchronization — **candidate has none by contract, but no-current-Runtime construction is unimplemented**

## Decision criteria application

### PASS conditions

- [x] projection history state one owner — **candidate assigns to ProjectionState**
- [x] parser/projection coherence one explicit identity — **candidate assigns ParseSnapshotIdentity + ProjectionCommit**
- [x] preserves required NodeId, hint, and trace behavior — **candidate preserves semantics**
- [x] keeps registry/source-map laziness — **candidate uses lazy Formulas**
- [ ] deletes all old Lambda projection/evaluation owners — **BLOCKED**
- [x] one explicit lifetime owner and close order — **candidate defines it**
- [x] no cross-runtime synchronization edge — **candidate has zero**
- [ ] positive responsibility/deletion ledger — **CONDITIONAL; ledger complete but deletions conditional**

### Verdict

```text
PASS WITH CONSTRAINTS — ledger closure only
```

Constraints:

1. Current construction cannot realize the candidate; a distinct Lambda
   constructor is required.
2. Current lifetime cannot close the candidate; five runtime/API groups must
   migrate first.
3. Generic framework responsibilities for non-Lambda languages are retained,
   not deleted.
4. Cut B′ implementation, migration, and ADR remain unauthorized.
5. No-op detection is not part of this gate (completed in prior sub-gate).
6. P1 performance is frozen.

## Baseline measurement seams (for after ledger closure)

After the ownership/deletion candidate closes, baseline measurement must
distinguish:

```text
projection only
registry only
source map only
projection + registry
projection + source map
all read-side outputs
```

Measurement seams:

- parser edit/reset to projection availability
- projection reconcile count and time
- registry compute count and time
- source-map compute count and time
- evaluation/escalation recomputation
- view publication latency
- active Watch count
- ProtectedCell retention
- editor create/destroy residual roots
- allocation and retained memory across repeated edits

Do not make baseline measurement or optimization the primary task until the
ownership/deletion candidate is closed.
