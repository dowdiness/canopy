# Incremental Generative UI semantic-core validation

**Status:** ready for bounded validation; product integration gated

## Why

The [Incremental Generative UI document engine](../design/incremental-generative-ui-document-engine.md)
defines authority, transaction, identity, recovery, and trust invariants that
are not implemented. The first implementation must therefore be a falsifiable
semantic-core experiment, not a syntax, DOM, persistence, or JavaScript
integration. It is discardable architecture research: passing it cannot add
semantic candidates or generated behavior to the personal knowledge
environment before that direction's fixed deterministic baseline is accepted,
and it cannot freeze a public renderer-neutral contract.

This plan proves the central claim: an invalid human draft can coexist with one
exactly-once agent commit while source rewriting conflicts, renderer effects
fail or arrive out of order, and restart/replay still reconstructs the same
committed graph and semantic IDs. If that transcript cannot pass through a
small deterministic core and fake shell, the broader document-engine direction
is not justified.

This file is the sole implementation spec for that validation slice. The design
document remains the source of principles and invariants.

## Scope

In:

- `moon.work` — add the renderer- and agent-neutral core module.
- `lib/generative-ui-document/moon.mod` — new standalone module with no Canopy,
  cognition, renderer, DOM, or incremental-runtime dependency; pin
  `moonbitlang/quickcheck` for tests.
- `lib/generative-ui-document/moon.pkg` — core package plus
  `core/quickcheck`, SplitMix, and `@qc` imports scoped to white-box tests.
- `lib/generative-ui-document/types.mbt` — private document, revision,
  identity, request, outcome, sync, and effect data.
- `lib/generative-ui-document/graph.mbt` — private semantic graph invariants
  and semantic equality.
- `lib/generative-ui-document/operation.mbt` — private forward batch
  application, canonical request content, deterministic ID resolution, and
  inverse derivation.
- `lib/generative-ui-document/transition.mbt` — pure document reducer and
  persistence/effect decisions.
- `lib/generative-ui-document/replay.mbt` — pure checkpoint/history recovery.
- `lib/generative-ui-document/reference_model_wbtest.mbt` — deliberately small
  immutable reference model and observation oracle.
- `lib/generative-ui-document/fixed_scenario_wbtest.mbt` — the mandatory
  falsifiable transcript and fake atomic store/source/renderer shell.
- `lib/generative-ui-document/operation_properties_wbtest.mbt` — generated
  graph/batch/identity/inverse properties.
- `lib/generative-ui-document/transition_properties_wbtest.mbt` — generated
  request, draft, outbox, and state-machine traces.
- `lib/generative-ui-document/replay_wbtest.mbt` — checkpoint, corruption, and
  crash-boundary recovery tests.
- `lib/generative-ui-document-proof/` — optional standalone proof module for
  scalar transition rules only, gated by an early proof-compilation spike.
- `.github/workflows/ci.yml` — run the new core package on both JS and native;
  if the proof spike lands, include its paths in change detection and run each
  standalone proof module explicitly.
- `docs/design/incremental-generative-ui-document-engine.md` and
  `docs/TODO.md` — gate link and completion status only.

Out:

- Changes to `lib/cognition/`; its lifecycle and replay code are precedents,
  not dependencies of the semantic core.
- Production JSX adapter changes or new renderer-neutral public APIs.
- Arbitrary JavaScript, `js_engine`, DOM, React, provider, or agent-framework
  integration.
- A real database, filesystem store, or production outbox implementation.
- Final source syntax, parser, or projection-to-source lowering.
- Collaboration, causal history, CRDT merge, or semantic undo integration with
  `event-graph-walker`.
- Schema-migration authoring, action/command execution, approval UI, a second
  renderer, product-value experiments, or PKE semantic/generated views.
- Performance optimization or benchmarks before correctness is established.

## Current state

- [`lib/cognition/generative_ui.mbt`](../../lib/cognition/generative_ui.mbt)
  provides the current request/generation lifecycle, event vocabulary, and
  terminal-state handling. It is a behavioral precedent; the new module must
  not import cognition or its `incr` dependency.
- [`lib/cognition/generative_ui_candidate.mbt`](../../lib/cognition/generative_ui_candidate.mbt)
  demonstrates fail-closed capability validation. Its table/filter-specific
  candidate types remain adapter content and are not generalized into the core.
- [`lib/cognition/generative_ui_replay.mbt`](../../lib/cognition/generative_ui_replay.mbt)
  demonstrates deterministic fixed-event replay with an explicit cursor.
- [`lib/canvas-graph/graph_model/model.mbt`](../../lib/canvas-graph/graph_model/model.mbt)
  and its operation tests demonstrate pure operation replay; they are examples,
  not dependencies.
- [`core/reconcile_properties_wbtest.mbt`](../../core/reconcile_properties_wbtest.mbt)
  demonstrates bounded recursive `Arbitrary` generators, explicit shrinkers,
  and `@qc.quick_check_fn`.
- [`ffi/jsx/render_baseline_wbtest.mbt`](../../ffi/jsx/render_baseline_wbtest.mbt)
  demonstrates folding generated renderer events through a lifecycle and
  checking reachable invariants. Real JSX conformance remains a later plan
  because its baseline and outcomes are adapter-private.
- [`lib/semantic/proof/`](../../lib/semantic/proof/) and
  [Formal Verification](../development/formal-verification.md) define the
  standalone `moon prove` pattern and its Map/Array/state-machine limits.
- [The JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md)
  remains the V1 adapter/session contract. This plan does not change its
  DOM-gated candidate commit semantics.

## Desired state

The slice is complete when a private, deterministic core and test-owned shell
can execute the fixed transcript below and satisfy every core obligation mapped
in this plan.

The functional core owns:

- semantic graph validation and equality;
- ordered, atomic `OperationBatch` application;
- deterministic request-local handle resolution;
- request canonicalization and collision-aware idempotency decisions;
- graph, draft, request-ledger, sync, and outbox transitions;
- replay and fail-closed recovery;
- decisions describing persistence, response, source rewrite, and rendering.

The imperative shell remains test-only in this slice. It owns a fake atomic
store, delivery order, injected failure, response loss, fake draft bytes, and
fake renderer baselines. The reducer may emit a response or post-commit effect
only after the shell reports that the corresponding terminal `RequestRecord`
and, for `Applied`, graph/history/outbox transaction were persisted.

No type from this module is public. `pkg.generated.mbti` should remain empty or
contain only intentionally unavoidable module metadata. A later adapter plan
must re-evaluate and validate any API promotion.

## Decision locks

- The core lives in `lib/generative-ui-document`, not `lib/cognition`, so its
  dependency graph enforces renderer, agent, and reactive-runtime neutrality.
- `UiNodeId` is logically derived from `(DocumentId, RequestId, insertion
  ordinal)`. The core stores canonical request content alongside its digest;
  digest equality alone never proves request equality or semantic identity. A
  test-owned digest function must be injectable so collision handling is
  falsifiable without weakening production canonical-content comparison.
- `RequestRecord` is mandatory for every host-constructed terminal request.
  The initial slice does not compact these records; retention bounds require a
  later equality-preserving tombstone or monotonic request-sequence design.
  Decoder failures before request construction remain boundary diagnostics.
- The persistence protocol has an explicit intent/acknowledgment boundary.
  “Persist before respond” is not modeled as an in-memory ledger mutation.
- Every `SchemaRevision` names one immutable canonical descriptor. Commits and
  checkpoints persist its digest; restore fails closed if either identity or
  digest differs.
- Effects carry base and target graph revisions. Dirty repair takes precedence
  over stale acknowledgment. Clean consumers ignore stale targets, apply only
  from the expected baseline, and rebuild from the latest committed snapshot
  after a gap.
- The plan verifies only the obligations reachable without production adapters.
  Adapter/trust-boundary obligations stay unclaimed and are listed as deferred
  in the evidence matrix.
- `moon prove` is optional and subordinate to executable core evidence. It may
  prove only scalar/enum decision functions that compile under the documented
  prover constraints.

## Reference model and observation oracle

`reference_model_wbtest.mbt` owns a small immutable model that is intentionally
simpler than production code. It uses the same public event meaning but does
not call production transition or apply functions.

Every generated or fixed trace compares this model with the implementation
through one test-only observation containing:

- semantic graph, schema revision, and canonical schema descriptor digest;
- graph revision;
- exact draft bytes, draft revision, and sync status;
- canonical terminal request outcomes;
- applied-history IDs and deterministic new-node mappings;
- pending effect IDs with base/target revisions;
- source and renderer baselines;
- read-only/fail-closed recovery state.

Implementation-only caches, collection iteration order, diagnostic formatting,
and builder scratch state are excluded. A mismatch reports the minimized event
trace and both observations.

## Fixed falsifiable scenario

`fixed_scenario_wbtest.mbt` is the first red test and the final integration gate.
It executes this transcript through the reference model and production reducer:

1. Start with draft bytes `D0 = "valid\n"`, a root-only committed graph `G0`,
   graph revision 0, an immutable schema revision and descriptor digest, and a
   renderer synchronized to revision 0. Retain a
   redeliverable already-acknowledged renderer effect `E0` whose target is 0.
2. Edit the draft to `D1 = "valid\n<unfinished"` and report it invalid; retain
   those exact bytes and keep `G0` as current meaning. The strings are test
   fixtures, not a proposed source grammar.
3. Deliver host-constructed request `Q` at base revision 0. Its valid batch
   declares two new-node handles, inserts both nodes, and sets one property so
   deterministic ordinal IDs and multi-primitive commit are observable.
4. Persist the resulting graph `G1`, request record, history, source/render
   effects, and graph revision 1 atomically, then lose the response. Retry `Q`;
   return the recorded outcome without another revision or history entry.
5. Deliver the source-rewrite effect for target 1. Its draft validity/revision
   precondition fails; preserve `D1` byte-for-byte and enter
   `RewriteConflict`.
6. Deliver renderer effect `E1` for target 1 and force failure. While the
   renderer is dirty at baseline 0, deliver stale `E0`: dirty repair must take
   precedence and rebuild from `G1`, not merely acknowledge `E0`. Duplicate
   `E1` after recovery; it must be acknowledged without regression.
7. Crash before every effect acknowledgment is durable. Recover from
   checkpoint, applied history, request records, and pending outbox, then
   redeliver remaining effects.
8. Assert that recovered graph, schema revision, and schema descriptor digest
   equal `G1`, graph revision is exactly 1, `Q` has one terminal/applied outcome,
   IDs are unchanged, `D1` is unchanged, and the renderer baseline is 1.
   Separate generated traces must create revisions 1 and 2 and deliver target 2
   to baseline 0 to prove gap rebuild.

Separate terminal-outcome fixtures must persist, crash, recover, and retry one
`NoSemanticChange` request and one `Rejected` request. Each returns its recorded
outcome without adding a graph revision, applied-history entry, or outbox entry.
A batch-rejection fixture is required, but it is not a substitute for the full
transcript or these request-ledger recovery fixtures.

## Evidence matrix

| Obligation from the design document | Evidence in this plan |
| --- | --- |
| Only semantic commit advances meaning | Fixed transcript; transition trace property; fake-store acknowledgment test |
| Failed primitive exposes no batch prefix | Batch-rejection unit test; generated batch atomicity property |
| Applied advances once; no-op does not | Request/revision unit tests; generated no-op property |
| No-op and rejected outcomes survive restart/retry | Terminal-outcome crash/recovery fixtures |
| `RemoveProperty` differs from `null` | Focused value/property unit test |
| Duplicate request does not apply twice | Fixed transcript; retry and response-loss fault tests |
| Request-local handles cannot mint/reuse IDs | Deterministic derivation and uniqueness properties |
| Inverse restores when preconditions hold | Valid-batch/inverse property with explicit precondition generator |
| Syntax-only edit preserves meaning | Reducer event test using a fake no-semantic-delta lowering result |
| Invalid/concurrent draft is not overwritten | Fixed transcript; stale draft trace property |
| Renderer failure cannot alter semantic meaning | Fixed transcript; generated renderer-failure traces |
| Replay reconstructs or fails closed | Replay properties; gap/request-digest/schema-descriptor corruption tests |
| Projection/renderer IDs are not durable semantic IDs | Deferred to adapter/API conformance; no such IDs exist in the private core |
| Stale graph/schema/draft revisions reject | Generated stale-revision properties |
| Generated input cannot obtain host/DOM/callback authority | Deferred to decoder and adapter conformance; not claimed by this core slice |
| Host trust boundary is structural | Deferred to host/renderer integration; not claimed by this core slice |
| Terminal request record precedes response | Fake atomic-store acknowledgment and crash-boundary tests |
| Canonical-equivalent requests compare identically | Typed canonical-content and ordering properties; equal-digest/different-content collision fixture; raw transport whitespace/encoding remains deferred to decoder conformance |
| Schema revision change is semantic | Focused semantic-equality unit/property test |
| Duplicate/out-of-order effects converge monotonically | Fixed transcript including dirty-plus-stale precedence; generated effect permutation traces |
| Stale source effect never overwrites draft | Fixed transcript; generated CAS mismatch traces |
| Node identity repeats on retry and separates tuples | Deterministic ID properties and replay assertion |

The plan is complete when every non-deferred row has passing evidence. Deferred
rows remain explicit blockers on the corresponding future safety claim.

## Existing API first — reuse check

Project APIs and patterns reused:

- `GenerativeUiLifecycle::dispatch` supplies the existing event/transition and
  terminal-state precedent. The new core reuses the reducer shape, not the type
  or module dependency.
- `GenerativeUiReplaySource` supplies the fixed replay-log/cursor testing
  precedent. Recovery state remains owned by the new core.
- `@qc.quick_check_fn`, `@quickcheck.Arbitrary`, `@qc.Shrink`, and SplitMix
  random-state splitting follow the patterns in
  `core/reconcile_properties_wbtest.mbt` and
  `ffi/jsx/render_baseline_wbtest.mbt`.
- `@canvas_graph` operation replay is checked as an existing deterministic-log
  precedent but is not reused because its workflow graph and action history
  have different invariants.
- `lib/semantic/proof` is reused as the standalone proof-package and CI pattern,
  not as a dependency.

MoonBit/core candidates to check before new definitions:

- `Map` and `Set` for graph lookup, request records, uniqueness, and pending
  effects; use owning collections privately and do not expose mutable values.
- `Array` and `Iter` for ordered children, ordered batches, trace folds, and
  local result construction.
- `Option` and `Result` for lookup and validation outcomes.
- `String`/`StringView` and `Bytes`/`BytesView` for exact draft observations and
  canonical request input; avoid copies where a view suffices.
- `Buffer`/`StringBuilder` for canonical encoding only if the actual core API is
  preferable to structural canonical content comparison.
- `cmp`/math helpers for revision and bound comparison instead of new numeric
  helpers.
- Core JSON APIs only at a future decoder boundary; the semantic core consumes
  validated typed values.

Checked but not reused:

- `GenerativeUiCandidate::validate` is table/filter-specific. Reuse its
  fail-closed principle, not its candidate types or validator.
- `ProjNode`, `SourceMap`, JSX AST, DOM patches, `incr`, and
  `event-graph-walker` are excluded from this private single-writer core.
- `Map`, `Set`, `Array`, recursive graph functions, canonical encoders, and
  state-machine traces are excluded from `moon prove` under current prover
  limitations.

New definitions are justified only for the semantic graph, operation algebra,
request/identity vocabulary, reducer decisions, replay model, and observation
oracle described above. Each new helper must stay within one of those
responsibility boundaries.

## Steps

### Phase 0 — Package boundary and first red transcript

1. Add `lib/generative-ui-document` to `moon.work`; create its `moon.mod` with
   a pinned `moonbitlang/quickcheck` test dependency and its `moon.pkg` with
   JS/native support plus core QuickCheck/SplitMix/`@qc` imports restricted to
   white-box tests.
2. Run `moon ide doc`/`outline` checks listed under Validation and record any
   better existing API in the Reuse check before defining helpers.
3. Add the observation vocabulary, fake-shell protocol, and full fixed
   transcript as a failing white-box test. The initial failure must be missing
   core behavior, not a parser, renderer, or persistence dependency.

### Phase 1 — Semantic graph and forward batch

4. Implement private typed values, graph state, semantic equality, revision
   wrappers, immutable schema descriptor identity/digest, request-local handles,
   and deterministic ordinal-based IDs.
5. Implement structural precondition validation and ordered application for
   `InsertNode`, `MoveNode`, `SetProperty`, `RemoveProperty`, and subtree
   `RemoveNode` on a private working graph.
6. Commit the working graph only after final graph/schema validation. Add the
   batch-rejection fixture, no-op behavior, `RemoveProperty`/`null` distinction,
   graph invariant tests, and inverse derivation tests.

### Phase 2 — Request and persistence protocol

7. Implement canonical typed request content, collision-aware request lookup,
   and terminal outcomes. Store canonical content as the equality authority;
   use a digest only as an index/check. Provide a white-box-only digest injection
   seam so tests can force equal digests for different canonical requests.
8. Implement reducer decisions for persistence intent, persistence success or
   failure, response emission, and effect release. The reducer must not emit a
   response or effect-delivery command before persisted acknowledgment.
9. Add a fake atomic store that can fail before commit, commit then lose the
   response, restart with committed records, and reject mismatched request
   content under the same ID. Force one equal-digest/different-content case and
   assert that the stored request record, graph, history, and outbox remain
   unchanged. Persist, restart, and retry separate `NoSemanticChange` and
   `Rejected` records without creating applied history or effects.

### Phase 3 — Draft and outbox transitions

10. Implement draft revision/validity/sync transitions and source-rewrite
    compare-and-swap decisions without a real parser or writer.
11. Implement renderer/source effect classification using base/target graph
    revisions, consumer baselines, dirty state, stale acknowledgment, and
    latest-snapshot rebuild decisions. Dirty repair must be evaluated before
    stale-target acknowledgment.
12. Add fake source and renderer consumers that can fail, duplicate, reorder,
    and acknowledge effects. Make the full fixed transcript pass through the
    persistence and restart boundary.

### Phase 4 — Generated traces and shrinking

13. Add separate bounded generators for valid graphs, valid batches, invalid
    batches, request retries/collisions, draft events, and effect-delivery
    permutations. Do not rely on filtering mostly invalid random data.
14. Add shrinkers that shorten event/batch sequences, remove leaf subtrees,
    simplify properties, and replace identity-relative placements with simpler
    valid placements while preserving the failing precondition when required.
15. Compare every generated trace with the reference model observation. Add
    bounded exhaustive traces for the smallest graphs/events before relying on
    randomized larger traces. Include a two-commit trace that delivers target
    revision 2 to renderer baseline 0, then verifies latest-snapshot rebuild and
    stale target-1 suppression.

### Phase 5 — Replay and corruption

16. Implement checkpoint plus contiguous applied-history replay. Validate base
    graph/schema revisions and canonical request content at each step.
17. Inject history gaps, mismatched request content/digests, unavailable schema,
    stale outbox acknowledgments, schema descriptor identity/digest mismatches,
    and crash boundaries. Recovery must reproduce
    the live observation or enter explicit diagnostic read-only state.
18. Complete the non-deferred rows in the evidence matrix and keep deferred
    adapter/security rows visibly unclaimed.

### Phase 6 — Optional scalar formal-proof spike

19. Create `lib/generative-ui-document-proof` as a standalone module outside
    `moon.work`. First prove that one small Int/Bool/enum mirror with an explicit
    `proof_ensure` compiles and terminates.
20. If the spike succeeds, prove only scalar decision laws such as revision
    delta by terminal outcome, effect classification preconditions, and
    non-regressing next-baseline projection. Keep tree equality, batch
    atomicity, inverse correctness, hashing, canonical encoding, and traces in
    unit/property tests.
21. If the spike fails because of documented prover limitations, record the
    reason in this plan, omit unsupported claims, and keep the executable test
    evidence. Formal-proof failure does not weaken or block already passing
    core properties.
22. If the proof module lands, update `.github/workflows/ci.yml` path filters and
    the Formal Verification job to run both standalone proof modules explicitly.

### Phase 7 — Gate decision and cleanup

23. Run all validation commands on both JS and native, inspect the new package
    `.mbti` for accidental exports, and verify no forbidden dependency appears
    in the new module. Add an explicit CI step for both package targets.
24. Record the fixed transcript result and the evidence-matrix status. Do not
    claim adapter, host-trust, or product-value safety from this core gate. Do
    not begin PKE semantic/generated behavior until its fixed baseline is
    independently accepted.
25. If the gate passes, open a separate JSX conformance plan. If it fails,
    revise or reject the document-engine direction before adapter work.
26. On completion, move this plan to `docs/archive/completed-phases/` and mark
    the linked TODO item done in the same change.

## PR split

1. **Core boundary and red gate:** Phase 0 only.
2. **Graph and operation algebra:** Phase 1.
3. **Request/persistence protocol:** Phase 2.
4. **Draft/outbox and fixed transcript:** Phase 3.
5. **Property/reference-model traces:** Phase 4.
6. **Replay/fault recovery:** Phase 5.
7. **Optional formal proof and CI:** Phase 6, only after the spike succeeds.
8. **Gate report and archival:** Phase 7.

Each PR starts with failing evidence for its phase and ends with affected-package
`moon check`/`moon test`; no PR may introduce the next adapter layer early.

## Acceptance criteria

- [ ] `lib/generative-ui-document` is a `moon.work` member with no Canopy,
      cognition, `incr`, JSX, DOM, provider, agent, or `event-graph-walker`
      dependency.
- [ ] The full invalid-draft/duplicate-request/rewrite-conflict/renderer-
      failure/out-of-order/restart transcript passes against both reference and
      production observations.
- [ ] Applied persistence happens once; retry after response loss returns the
      recorded result without another graph revision or history entry.
- [ ] Failed batches expose no prefix; semantic no-ops do not advance revision;
      explicit property removal remains distinct from `null`.
- [ ] Draft bytes survive stale or invalid rewrite attempts exactly.
- [ ] Renderer/source baselines never regress: the fixed transcript covers
      dirty-plus-stale precedence, duplicate and failure delivery, and generated
      two-commit traces cover revision gaps and latest-snapshot rebuild.
- [ ] Persisted `NoSemanticChange` and `Rejected` records survive restart and
      retry without adding graph revisions, applied history, or outbox entries.
- [ ] Replay either reconstructs the exact live observation or fails closed on
      corruption, schema absence, or changed schema descriptor content.
- [ ] Deterministic IDs repeat for the same document/request/ordinal, differ for
      distinct logical tuples, survive replay, and cannot be supplied by the
      generated proposal body.
- [ ] An equal-digest/different-canonical-content request collision is rejected
      without changing the stored record, graph, history, or outbox; raw
      transport equivalence remains deferred to decoder conformance.
- [ ] Every non-deferred evidence-matrix row maps to at least one passing test;
      deferred rows remain explicitly unclaimed.
- [ ] Generated traces have useful shrinking and report a minimized event trace
      on failure.
- [ ] `moon info` shows no accidental public API or trait-bound widening in the
      new core package.
- [ ] If formal proofs land, every claim is attached to a compiling
      `proof_ensure`, the standalone module has no project dependency, and CI
      runs it. No proof is claimed for unsupported collection/stateful laws.
- [ ] No source, JSX, DOM, JavaScript, persistence backend, collaboration, or
      second-renderer implementation is added by this plan.

## Validation

Before adding definitions:

```bash
NEW_MOON_MOD=0 moon ide outline lib/cognition
NEW_MOON_MOD=0 moon ide outline lib/canvas-graph/graph_model
NEW_MOON_MOD=0 moon ide doc "Map::*"
NEW_MOON_MOD=0 moon ide doc "Set::*"
NEW_MOON_MOD=0 moon ide doc "Array::*"
NEW_MOON_MOD=0 moon ide doc "String::*"
NEW_MOON_MOD=0 moon ide doc "Bytes::*"
NEW_MOON_MOD=0 moon ide doc "Buffer::*"
NEW_MOON_MOD=0 moon ide doc "Option::*"
NEW_MOON_MOD=0 moon ide doc "Result::*"
NEW_MOON_MOD=0 moon ide doc "@cmp"
NEW_MOON_MOD=0 moon ide doc "@quickcheck"
```

During each core PR:

```bash
NEW_MOON_MOD=0 moon check --target js lib/generative-ui-document
NEW_MOON_MOD=0 moon check --target native lib/generative-ui-document
NEW_MOON_MOD=0 moon test --target js lib/generative-ui-document
NEW_MOON_MOD=0 moon test --target native lib/generative-ui-document
```

Before merge:

```bash
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git status --short -- '*.mbti'
git diff -- '*.mbti'
git diff --check
```

If the proof spike lands:

```bash
cd lib/generative-ui-document-proof
moon check
moon prove
moon fmt
moon info
```

Also inspect `moon.work` and `.github/workflows/ci.yml`, and open every new or
changed `pkg.generated.mbti`; `git diff` alone does not display an untracked
interface file. Verify that the core interface is empty apart from unavoidable
module metadata and that the optional proof interface exposes nothing
unexpected.

No TypeScript, browser, JS artifact, proof-submodule, or vendored-submodule
command is required locally unless the corresponding out-of-scope boundary
changes. Once this plan edits `.github/workflows/ci.yml`, however, the pull
request must wait for the full workflow-triggered CI fan-out, including proof
and browser jobs selected by that workflow path.

## Risks

- The fake store proves protocol ordering and recovery decisions, not the
  atomicity guarantees of a future production storage technology. Each real
  store will need its own boundary tests.
- A production-looking graph API may invite premature export. Keep all core
  declarations private until a later adapter/public-contract decision.
- Random graph generation can hide behind rejection-heavy samples. Separate
  valid and invalid generators and report their coverage.
- Shrinking a stateful failure can destroy the precondition that triggered it.
  Shrink traces and graph fixtures together and re-check the intended failure
  class.
- Canonical digests are not injective. Persist canonical content and treat a
  digest as an index/check, not as semantic identity.
- The full fixed transcript verifies only the private architecture hypothesis.
  It cannot authorize PKE semantic candidates before the fixed deterministic
  baseline, and product value still requires a later real use case and decision
  gate.
- The optional proof mirror can drift from production behavior. Keep proof
  targets scalar, name the corresponding production decision, and retain the
  production property test as the integration oracle.
- The 21-obligation list may evolve. Update the evidence matrix by obligation
  meaning whenever it changes; the fixed count is only a diagnostic.
- Raw JSON whitespace, key-order, and encoding equivalence cannot be proved by a
  typed core that has no decoder. The core verifies canonical typed content;
  the eventual decoder/adapter gate owns transport equivalence.

## Open questions

- Which private persistent collection representation gives the clearest graph
  equality and replay implementation without exposing mutation? Resolve during
  Phase 1 after the required MoonBit API checks; do not optimize before the
  reference properties pass.
- Should bounded exhaustive trace enumeration be a handwritten small alphabet
  or generated from the same event grammar as QuickCheck? Choose the simpler
  implementation that reports reproducible traces.
- Which scalar transition rule, if any, gives enough value to justify the
  standalone proof module and CI cost? Phase 6 begins with a compilation spike
  precisely to answer this.

## Notes

- `event-graph-walker` remains the sole owner of future causal history, CRDT
  tree semantics, sync, and collaborative undo. This private single-writer log
  must not evolve into a competing causal oplog.
- Real JSX conformance belongs to a follow-up plan under `ffi/jsx`, where the
  adapter-private baseline and outcomes are visible without reversing
  dependencies.
- The design document's gate is satisfied only for the non-deferred core rows.
  It must not be read as proof of adapter isolation, hostile JavaScript safety,
  collaboration, product usefulness, or readiness to bypass the PKE baseline
  and existing Generative UI V1 sequence.
