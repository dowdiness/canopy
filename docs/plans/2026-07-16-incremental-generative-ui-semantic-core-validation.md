# Incremental Generative UI semantic-core validation

**Status:** ready for bounded validation; product integration gated

## Purpose

The [document-engine design](../design/incremental-generative-ui-document-engine.md)
defines unimplemented authority, identity, transaction, and recovery rules.
This plan tests them in a private deterministic core before syntax, DOM,
storage, or JavaScript integration.

The gate is intentionally falsifiable: if an invalid human draft, exactly-once
semantic commit, failed renderer, conflicting rewrite, and restart cannot
coexist in a small core and fake shell, revise or reject the design.

Passing does not authorize PKE semantic candidates before its fixed baseline,
change the Generative UI V1 sequence, or establish a public renderer-neutral
contract.

## Scope

Create one private module:

| Area | Planned files |
| --- | --- |
| Workspace/module | `moon.work`, `lib/generative-ui-document/moon.mod`, `moon.pkg` |
| Core | `types.mbt`, `graph.mbt`, `operation.mbt`, `transition.mbt`, `replay.mbt` |
| Test model | `reference_model_wbtest.mbt`, `fixed_scenario_wbtest.mbt` |
| Properties | `operation_properties_wbtest.mbt`, `transition_properties_wbtest.mbt`, `replay_wbtest.mbt` |
| Optional proof | standalone `lib/generative-ui-document-proof/` for scalar decisions only |
| CI/docs | `.github/workflows/ci.yml`, design gate link, TODO completion |

The module supports JS and native and pins `moonbitlang/quickcheck` for
white-box tests. It imports no Canopy, cognition, renderer, DOM, provider,
agent framework, `incr`, or `event-graph-walker` package. No type is public;
`pkg.generated.mbti` should contain no accidental API.

Out of scope:

- production JSX, source, renderer, storage, or outbox adapters;
- public renderer-neutral APIs;
- arbitrary JavaScript, `js_engine`, DOM, React, or provider integration;
- collaboration, CRDT merge, causal history, and collaborative undo;
- schema migration, commands, approval UI, second renderer, PKE generated
  views, and product-value experiments;
- optimization or benchmarks before correctness.

## Existing evidence

| Existing code | Use in this plan |
| --- | --- |
| `lib/cognition/generative_ui.mbt` | Reducer lifecycle and terminal-state precedent; no dependency. |
| `generative_ui_candidate.mbt` | Fail-closed capability validation precedent; candidate types stay adapter-specific. |
| `generative_ui_replay.mbt` | Fixed replay-log and cursor precedent. |
| `lib/canvas-graph/graph_model/model.mbt` | Pure operation replay example; different domain invariants. |
| `core/reconcile_properties_wbtest.mbt` | Bounded generators and explicit shrinkers. |
| `ffi/jsx/render_baseline_wbtest.mbt` | Generated lifecycle traces and reachable invariants. |
| `lib/semantic/proof/` | Standalone proof layout and documented collection/state limits. |
| JSX DOM patch contract | Existing V1 session contract; unchanged by this plan. |

## Core and shell boundary

The functional core owns graph validation/equality, ordered batch apply,
deterministic ID resolution, request canonicalization, idempotency decisions,
draft/sync/outbox transitions, inverse derivation, and replay. It returns next
state plus persistence, response, source, or renderer decisions.

The test-only imperative shell owns the fake atomic store, draft bytes,
renderer baselines, delivery order, failure injection, response loss, and
restart. It releases no response or effect until the terminal request record
(and, for `Applied`, graph/history/outbox transaction) is persisted.

Core results do not expose mutable internal collections. Use immutable views or
defensive copies at adapter boundaries; local builder mutation is acceptable
only when it cannot escape.

## Decision locks

- `UiNodeId` derives from `(DocumentId, RequestId, insertion ordinal)`.
- Canonical request content is equality authority; its digest is only an
  index/integrity check. Tests can inject a colliding digest.
- Every host-constructed terminal request has a durable `RequestRecord`.
  Decoder failures before construction remain boundary diagnostics.
- The initial slice does not compact request records. Retention requires a
  separate equality-preserving tombstone or monotonic sequence design.
- Each `SchemaRevision` names one immutable descriptor. Commits and checkpoints
  persist its digest; restore rejects identity/content disagreement.
- Persistence intent and acknowledgment are separate reducer events.
- Dirty renderer repair precedes stale acknowledgment. Clean renderers apply
  only from the expected baseline and rebuild the latest snapshot after gaps.
- The core makes no adapter, host-trust, accessibility, collaboration, or
  product-value claim.
- `moon prove` is optional and subordinate to executable evidence.

## Reference model and observation

`reference_model_wbtest.mbt` implements a small model without calling production
apply or transition functions. Every fixed or generated trace compares this
model with the implementation using one test-only observation:

- graph, schema revision/digest, and graph revision;
- exact draft bytes/revision and sync state;
- canonical terminal request outcomes and handle mappings;
- applied history and pending effects with base/target revisions, snapshot
  references, and draft preconditions;
- renderer/source baselines and dirty/conflict state;
- explicit diagnostic read-only recovery state.

Exclude caches, iteration order, diagnostic prose, and builder scratch state.
On mismatch, report the minimized event trace and both observations.

## Fixed transcript

`fixed_scenario_wbtest.mbt` is the first red test and final integration gate:

1. Start with valid draft `D0`, root-only graph `G0` at revision 0, immutable
   schema identity/digest, renderer baseline 0, and acknowledged effect `E0`.
2. Change the draft to exact invalid bytes `D1 = "valid\n<unfinished"`; retain
   `G0` as meaning. These bytes are fixtures, not proposed syntax.
3. Submit host-built request `Q` at base 0. Its batch inserts two handles and
   sets a property, making ordinal IDs and multi-step atomicity observable.
4. Atomically persist `G1`, revision 1, request record, history, and source/render
   effects, then lose the response. Retry `Q`; return its record without a
   second revision or history entry.
5. Deliver the source effect. Its draft precondition fails, so preserve `D1`
   byte-for-byte and enter `RewriteConflict`.
6. Fail renderer effect `E1`. While dirty at baseline 0, deliver stale `E0`;
   dirty repair must rebuild `G1` rather than merely acknowledge `E0`. Duplicate
   `E1` after recovery without regression.
7. Crash before each possible effect acknowledgment becomes durable. Recover
   from checkpoint, history, request records, and outbox, then redeliver.
8. Assert graph `G1`, schema identity/digest, revision 1, one terminal/applied
   outcome for `Q`, stable IDs, unchanged `D1`, and renderer baseline 1.

Additional mandatory fixtures:

- persist, restart, and retry one `NoSemanticChange` and one `Rejected` request;
  neither creates graph revision, applied history, or outbox work;
- deliver revision 2 to renderer baseline 0 and rebuild the latest snapshot;
- force equal digests for different canonical requests and preserve all state;
- reject failed batch prefixes and distinguish `RemoveProperty` from `null`.

## Evidence matrix

| Claim | Required evidence |
| --- | --- |
| Only semantic commit advances meaning | Fixed transcript and transition traces. |
| Batch is atomic; no-op does not advance | Rejection/no-op units and generated batches. |
| Request retry applies at most once | Response-loss transcript and crash fixtures. |
| Non-applied outcomes survive restart | No-op/rejected recovery fixtures. |
| Canonical content defeats ID reuse/collision | Ordering properties and injected collision. |
| Handles cannot mint/reuse IDs | Derivation, uniqueness, retry, and replay properties. |
| Inverse restores under preconditions | Valid-batch/inverse property. |
| No-delta lowering preserves meaning | Reducer fixture: synchronized draft; no request, revision, history, or outbox. |
| Invalid or stale draft is preserved | Fixed transcript and generated CAS mismatch. |
| Renderer state never regresses | Dirty-plus-stale transcript and delivery permutations. |
| Replay reconstructs or fails closed | Gap, request, digest, schema, and checkpoint corruption. |
| Stale graph/schema/draft rejects | Generated revision properties. |
| Schema change is semantic and immutable | Equality and descriptor mismatch properties. |
| Transport canonicalization agrees | Typed canonical-content tests; raw decoder equivalence deferred. |
| Agent lacks host/DOM authority | Deferred to decoder/adapter conformance. |
| Host isolation is structural | Deferred to host/renderer integration. |

Every non-deferred row must pass. Deferred rows block only their corresponding
future safety claim.

## Reuse check

Project precedents reused:

- `GenerativeUiLifecycle::dispatch` for reducer shape, not as a dependency;
- `GenerativeUiReplaySource` for replay-log/cursor structure;
- `@qc.quick_check_fn`, `@quickcheck.Arbitrary`, `@qc.Shrink`, and SplitMix
  patterns from existing property tests;
- the standalone proof-module pattern from `lib/semantic/proof`.

Checked but not reused:

- `@canvas_graph` replay: workflow graph and action-history invariants differ;
- `@egwalker`: owns future causal history, not this private single-writer log;
- JSX renderer baseline types: adapter-private and would reverse dependencies;
- SDEG identity: useful precedent, but its projection mapping has a different
  lifetime and authority boundary.

MoonBit/core candidates to inspect before definitions:

- `Map`/`Set` for graph, ledger, uniqueness, and pending effects;
- `Array`/`Iter` for ordered children, batches, folds, and trace generation;
- `String`/`StringView` and `Bytes`/`BytesView` for bounded canonical inputs;
- `Buffer`/`StringBuilder` for canonical encoding only if existing encoders do
  not fit;
- `Option`/`Result` for lookups and pure validation;
- `cmp`/math helpers for revision and bounds checks;
- QuickCheck `Arbitrary`, `Shrink`, combinators, and SplitMix.

Do not introduce a helper until `moon ide doc`, `outline`, `peek-def`, and
`find-references` establish that these APIs do not cover its responsibility.

## Implementation phases

Each phase is a separate PR. It begins with failing evidence and ends with
package checks/tests; no PR starts the next adapter layer.

### Phase 0 — Boundary and red gate

- Add the module to `moon.work`, with pinned `moonbitlang/quickcheck`, JS/native
  support, and `core/quickcheck`, SplitMix, and `@qc` imports restricted to
  white-box tests.
- Record the Existing API First results.
- Add observation types, fake-shell protocol, and the complete failing fixed
  transcript. Its first failure must demonstrate missing core behavior while
  the package remains free of adapter dependencies.

### Phase 1 — Graph and operations

- Add private values, graph, revisions, schema descriptor identity/digest,
  request-local handles, and deterministic IDs.
- Apply all five operations to a private working graph, checking each
  primitive's structural preconditions as it runs and final graph/schema
  invariants at the batch boundary.
- Cover atomic rejection, no-op, property deletion versus `null`, graph
  invariants, limits, and inverse derivation.

### Phase 2 — Requests and persistence

- Add typed canonical content, collision-aware lookup, and terminal outcomes.
- Model persistence intent, success/failure, response release, and effect
  release as reducer events.
- Add fake-store failures before commit, response loss after commit, restart,
  request-ID misuse, forced digest collision, and no-op/rejected recovery.

### Phase 3 — Draft and outbox

- Add draft validity/revision and source rewrite CAS without a real parser.
- Classify renderer/source effects with dirty precedence, stale acknowledgment,
  expected baseline, and latest-snapshot rebuild.
- Make the fixed transcript pass through restart with duplicate, reordered, and
  failed delivery.

### Phase 4 — Generated traces

- Build separate bounded generators for valid/invalid graphs and batches,
  request retries/collisions, draft events, and effect permutations.
- Shrink sequences, leaf subtrees, properties, and placements while preserving
  the failure precondition.
- Compare all traces to the reference model. Include small exhaustive traces
  and the revision-2-to-baseline-0 gap case.

### Phase 5 — Replay and corruption

- Replay checkpoint plus contiguous applied history.
- Inject history gaps, request/digest mismatches, schema identity/digest changes,
  stale acknowledgments, and crash boundaries.
- Match the live observation or enter explicit diagnostic read-only state.

### Phase 6 — Optional scalar proof

- Create `lib/generative-ui-document-proof` outside `moon.work` only after one
  explicit `proof_ensure` compilation spike succeeds.
- Limit proofs to scalar terminal-outcome or effect-classification decisions.
  Keep trees, maps, arrays, canonical encoding, inverse laws, and stateful traces
  in executable tests.
- If it lands, add CI path detection and run every standalone proof module. If
  it fails, record why and retain executable evidence without weaker claims.

### Phase 7 — Gate decision

- Run JS/native validation, inspect `.mbti` and dependency edges, and add CI
  steps that check and test `lib/generative-ui-document` explicitly on both
  targets.
- Record the transcript and evidence-matrix result without claiming adapter,
  host-trust, or product safety.
- On pass, create a separate JSX conformance plan. On failure, revise or reject
  the engine before adapter work.
- Archive this plan and close its TODO only when all non-deferred rows pass.

## Acceptance gate

- The private module has no forbidden dependency or accidental public API.
- Fixed and generated traces match the reference model on JS and native.
- Applied, no-op, rejected, response-loss, and collision outcomes satisfy their
  persistence and retry contracts.
- Syntax-only lowering synchronizes the draft without a request, graph revision,
  history, or outbox work.
- Draft bytes and semantic meaning survive all tested conflict/failure paths.
- Renderer/source baselines never regress, including dirty-plus-stale and gaps.
- Replay reconstructs exactly or fails closed on every injected corruption.
- Generated failures shrink to reproducible minimal traces.
- Optional proofs claim only compiled scalar properties and run in CI.
- No source, renderer, JavaScript, storage backend, collaboration, or product
  integration enters this validation slice.

## Validation

Before definitions:

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

Open every new or changed `pkg.generated.mbti`; `git diff` omits untracked
files. If the proof spike lands, run `moon check`, `moon prove`, `moon fmt`, and
`moon info` from its standalone module.

No local browser or TypeScript command is required unless those boundaries
change. Editing `.github/workflows/ci.yml` still triggers the full selected CI
fan-out, so the PR must wait for those proof/browser jobs.

## Risks and deferred evidence

- The fake store validates protocol decisions, not a production store's
  atomicity; each real adapter needs boundary tests.
- Canonical digests are not injective; canonical content must remain the
  equality authority.
- Typed-core tests cannot prove raw JSON encoding equivalence; the eventual
  decoder owns that conformance gate.
- Random generators and shrinkers can hide or destroy preconditions; use
  separate valid/invalid generators, small exhaustive traces, and re-check the
  intended failure class.
- A proof mirror can drift; pair every scalar proof with a production property
  test.
- This gate proves no adapter isolation, hostile JavaScript safety,
  collaboration, accessibility, or product usefulness.
