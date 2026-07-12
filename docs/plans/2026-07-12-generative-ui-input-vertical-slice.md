# Generative UI input vertical slice

## Why

Canopy now has a JSX incremental parser, session-owned FFI rendering, and a
direction for Generative UI. The missing implementation boundary is the path
from an asynchronous model-like input stream to a validated candidate UI.

The first implementation must prove that incomplete, duplicated, cancelled,
late, or invalid input cannot corrupt the committed UI. It should establish
this property without depending on a live LLM or a particular provider.

## Scope

In:

- A replayable fixed-chunk input source for the JSX session.
- A request/generation envelope with request identity, base revision, chunk
  sequence, finalization, cancellation, and terminal-state rules.
- Candidate syntax, schema, capability, and base-revision validation.
- Internal dry-run validation using a pure/fake DOM model before commit.
- Commit and recovery behavior for the existing session-owned JSX renderer.
- A read-only JSON/CSV data-exploration vertical slice with table, filter, and
  detail/summary projections.
- Property, focused contract, and browser tests for the input lifecycle.

Out:

- Live Gemini or other provider integration.
- Arbitrary JSX, raw HTML, JavaScript, or model-controlled expressions.
- Network, persistence, navigation, or other generated side effects.
- User-visible approval preview (internal dry-run is required).
- Concurrent semantic editing, cross-session identity, and multi-language
  renderer generalization.
- A general-purpose renderer-neutral API.

## Current State

- The Generative UI direction and guarantees are documented in
  `docs/architecture/generative-ui-direction.md`.
- JSX sessions own parser/projection/DOM state and expose structured render
  results through `ffi/jsx/session.mbt`.
- DOM patch ordering and sibling-index correctness have a regression test in
  `ffi/jsx/session_contract_wbtest.mbt`; broader property coverage is tracked
  by [Issue #888](https://github.com/dowdiness/canopy/issues/888).
- `examples/web/src/genui.js` already replays JSX prefixes through a stateful
  session, but its source is a local fixed string and its stop behavior is not
  yet a generation lifecycle contract.
- `llm/` is a Gemini-specific, whole-response text-edit client. It is not the
  UI candidate protocol and is intentionally not required for this phase.
- `lib/cognition` contains provider-boundary concepts for request identity,
  source revisions, cancellation, stale completion, and typed failures. Reuse
  those semantics rather than duplicating provider lifecycle rules in the JSX
  renderer.

## Desired State

The vertical slice has this observable pipeline:

```text
replayable chunk source
  → request lifecycle
  → candidate assembly
  → syntax/schema/capability validation
  → base-revision check
  → internal dry-run against a fake DOM/model
  → session-owned DOM commit
```

The LLM/provider is replaceable and not trusted. Only a validated candidate
whose base revision is current and whose dry-run succeeds may advance the
committed session revision.

### Input envelope

Each input event carries, at minimum:

```text
generation_id
base_revision
sequence
payload
kind = chunk | final | cancel
```

The request lifecycle owns ordering, duplicate handling, missing-sequence
policy, finalization, cancellation, stale-generation rejection, and
terminal-state idempotency. A late or cancelled generation cannot overwrite a
newer committed generation.

### Candidate and capability boundary

The first candidate language is a constrained JSX-like language or equivalent
allowlisted UI program. It permits only declarative components needed by the
vertical slice: table, column, filter, text, stack/panel, and summary.

Validation rejects unknown components, invalid attributes, disallowed data
access, raw HTML, navigation, URLs controlled by the model, arbitrary code or
expressions, and any side-effecting action. The renderer receives only
validated candidates.

### Commit boundary

Candidate state is not committed when parsing or validation succeeds. Commit
requires successful dry-run and successful DOM application with consistent
session state, registry, mounted IDs, and revision. If application fails, the
existing session recovery/dirty-state contract applies and the candidate is
reported as uncommitted.

## Steps

1. Define the request lifecycle and event envelope as pure domain data. Add
   deterministic transitions for start, chunk, duplicate, gap, final,
   cancel, stale, failed, and resumed states.
2. Add a fixed-chunk replay source and fixtures for complete, incomplete,
   duplicated, out-of-order, late, cancelled, and resumed generations. Do not
   call a network provider.
3. Define the constrained UI candidate schema and validator. Keep the
   allowlist minimal and make rejection diagnostics structured and replayable.
4. Build the internal dry-run model. Compare candidate projection results with
   the expected model, including sibling order, text/element mixtures, nested
   updates, and failed applications. Reuse the existing patch contract rather
   than inventing a second DOM semantics.
5. Connect validated replay candidates to the existing JSX session. Commit only
   after dry-run and DOM success; preserve the last committed UI on rejection
   or failure.
6. Implement the read-only JSON/CSV surface with table, filter, and
   detail/summary updates. Preserve filter and selection state where structure
   permits.
7. Add focused and property-based tests, then browser tests for streaming,
   cancellation, late chunks, state preservation, and recovery.
8. Measure update latency, candidate rejection/repair counts, state-loss
   count, stale-chunk application count, and deterministic replay results.

## Acceptance Criteria

- [ ] A complete replay produces the expected table/filter/detail UI.
- [ ] Incomplete or invalid candidates leave the last committed UI intact.
- [ ] A stale base revision is rejected without advancing the session revision.
- [ ] Duplicate chunks are idempotent; out-of-order chunks follow a defined
      rejection or buffering policy.
- [ ] Cancellation invalidates the generation; late chunks cannot commit.
- [ ] Resumption starts only from an explicitly selected committed revision.
- [ ] Finalization is idempotent and terminal generations cannot accept later
      chunks.
- [ ] Dry-run validation completes before any candidate commit.
- [ ] DOM application failure follows session recovery/dirty-state behavior and
      never reports the rejected candidate as committed.
- [ ] The generated surface cannot perform network mutation, persistence,
      navigation, raw HTML insertion, or arbitrary code execution.
- [ ] Existing filter/selection state is preserved for supported structural
      updates.
- [ ] Property tests cover removal-before-insertion, sibling indexes, nested
      updates, text/expression-span nodes, and session isolation.
- [ ] Browser tests cover the same lifecycle against the real JSX session.
- [ ] The results and measurements are recorded before deciding whether to add
      a live provider or freeze a renderer-neutral contract.

## Validation

During implementation, run the smallest affected checks after each change:

```bash
NEW_MOON_MOD=0 moon check ffi/jsx
moon test ffi/jsx
moon test core
moon test lang/jsx/proj
```

Before the vertical slice is considered complete:

```bash
moon fmt
moon info
moon check
moon test
moon build --target js --release
cd examples/web && npm run build
```

Run the relevant browser suite after the web server and built artifacts are
available. Existing unrelated vendored-browser failures must remain separately
identified rather than hidden by this plan.

## Risks

- A fake DOM model may accidentally diverge from real DOM behavior; retain
  browser tests for the commit path.
- The candidate allowlist may be too broad; begin with the smallest useful
  component set.
- Chunk buffering can create unbounded memory; enforce a generation size and
  sequence limit.
- Recovery may rebuild more UI than ideal; correctness precedes optimization.
- Provider-specific concerns may leak into the lifecycle; keep the replay
  source and provider boundary separate.
- A successful demo may tempt premature semantic merge or multi-renderer
  abstraction; require a second adapter and measured invariants first.

## Notes

- The first live provider should be added only after replay and browser tests
  pass. Adapt `llm/` as a transport/provider implementation; do not make its
  Gemini-specific `EditAction` contract the Generative UI domain model.
- `moon prove` is a later option for pure request/reconciliation invariants. It
  is not a prerequisite for proving the JavaScript/DOM boundary.
- Related direction: `docs/architecture/generative-ui-direction.md`.
- Related correctness work: [Issue #888](https://github.com/dowdiness/canopy/issues/888).
