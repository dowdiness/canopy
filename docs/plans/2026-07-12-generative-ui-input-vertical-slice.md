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
- The Phase 3 DOM patch semantics and dry-run/DOM boundary are fixed in the
  [JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md).
- DOM patch ordering, sibling-index correctness, and duplicate identity
  preservation are covered by merged Canopy PR #892
  (`core/reconcile_properties_wbtest.mbt`,
  `lang/jsx/proj/reconcile_wbtest.mbt`, and
  `lang/jsx/proj/patch_properties_wbtest.mbt`). Issue #888 is closed.
- `examples/web/src/genui.js` now replays validated candidates through the
  session-owned JSX boundary. Its DEV-only `window.__canopyGenUiTest` surface
  is a thin browser-test call-through, not lifecycle or commit policy.
- Browser evidence now covers invalid candidates, stale bases, DOM apply
  failure, dirty-root repair, host-state preservation, and deterministic fresh
  replay. Candidate replay remains synchronous whole-replay; cancellation and
  late candidate chunks remain cognition-only evidence.
- `llm/` is a Gemini-specific, whole-response text-edit client. It is not the
  UI candidate protocol and is intentionally not required for this phase.
- `lib/cognition` contains provider-boundary concepts for request identity,
  source revisions, cancellation, stale completion, and typed failures. Reuse
  those semantics rather than duplicating provider lifecycle rules in the JSX
  renderer.

## Work Ownership

- **Request lifecycle:** pure request/generation state and transition tests;
  reuse provider-boundary semantics, but keep the first implementation
  provider-independent.
- **UI input adapter:** constrained candidate schema, capability validator, and
  structured rejection diagnostics.
- **Dry-run model:** patch/model comparison and generated-tree invariants; it
  must not become a second production DOM implementation.
- **JSX session adapter:** candidate-to-session wiring and the existing commit,
  recovery, registry, and revision contract.
- **Web example:** replay controls, generation status, and the JSON/CSV
  vertical-slice surface. It does not own revision or commit policy.
- **Host interaction state:** trusted data bindings, filter values, selection,
  and allowlisted aggregation parameters remain host-owned. The candidate may
  reference these capabilities declaratively but cannot execute code or own
  their mutable state.

The first implementation should prefer existing project APIs in each owner
package. Any new public type or helper must state its responsibility boundary
and have a focused test before callers are migrated.

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

### Phase 0 transition contract

The following transitions are fixed before implementation begins:

| Current state | Event | Next state | Required effect |
| --- | --- | --- | --- |
| `Idle` | `Start(base_revision)` | `Receiving` | allocate generation identity |
| `Receiving` | next expected `Chunk` | `Receiving` | append exactly once |
| `Receiving` | duplicate `Chunk` | `Receiving` | no state or candidate change |
| `Receiving` | gap `Chunk` | `Receiving` or `Rejected` | follow the explicit gap policy |
| `Receiving` | `Final` | `Validating` | freeze input; reject later chunks |
| `Receiving` | `Cancel` | `Cancelled` | invalidate generation |
| `Validating` | `Cancel` | `Cancelled` | invalidate before dry-run |
| `Validating` | valid candidate | `DryRunning` | check base revision |
| `Validating` | invalid/stale candidate | `Rejected` | preserve committed UI |
| `DryRunning` | `Cancel` | `Cancelled` | invalidate before applying |
| `DryRunning` | success | `Applying` | no committed revision change yet |
| `DryRunning` | failure | `Rejected` | preserve or repair per session contract |
| `Applying` | `Cancel` | `Applying` | cancellation is too late; linearize apply |
| `Applying` | DOM/session success | `Committed` | advance revision once |
| `Applying` | DOM/session failure | `Failed` | candidate remains uncommitted |
| terminal state | any late event | same terminal state | idempotent no-op or typed rejection |

Phase 0 must also decide whether a missing sequence is buffered or rejected,
whether `Final` is a separate event or a flagged chunk, and which terminal
state wins when cancellation races with finalization. Cancellation is checked at
each asynchronous boundary. Once DOM application begins, it is synchronous for
the purpose of this contract: cancellation cannot interrupt or roll it back,
and the apply result determines whether the candidate commits.

### Candidate and capability boundary

The first candidate language is a constrained JSX-like language or equivalent
allowlisted UI program. It permits only declarative components needed by the
vertical slice: table, column, filter, text, stack/panel, and summary. Data
bindings are opaque host-owned references; filter fields/operators, selection
keys, and summary aggregations come from allowlisted host capabilities.

Validation rejects unknown components, invalid attributes, disallowed data
access, raw HTML, navigation, URLs controlled by the model, arbitrary code or
expressions, and any side-effecting action. The renderer receives only
validated candidates.

### Commit boundary

Candidate state is not committed when parsing or validation succeeds. Commit
requires successful dry-run and successful DOM application with consistent
session state, registry, mounted IDs, and revision. If application fails, the
existing session recovery/dirty-state contract applies: committed source and
revision remain unchanged, the session is marked dirty, and the candidate is
reported as uncommitted. V1 permits the DOM to be temporarily dirty after a
partial failure; the next successful render must remount/repair the dirty root
before committing a new candidate. Immediate rollback is a separate follow-up
if the product requires it.

## Steps

1. **Phase 0–4 implementation:** completed by merged PR #890. This includes
   the pure lifecycle, fixed replay source, candidate schema/validator,
   candidate lowering, dry-run model, session commit/recovery contract, and
   JSON/CSV data-exploration surface.
2. **Patch-ordering correctness:** completed by merged PR #892. The generic
   exact-key LCS reconstruction now preserves duplicate sibling identities;
   focused core/JSX regressions and generated patch properties are landed.
3. **Browser boundary evidence:** completed in
   `examples/web/tests/genui.spec.ts` for invalid and stale candidates, DOM
   apply failure, dirty-root repair, host-owned state preservation, and
   deterministic fresh replay. No second lifecycle controller was added;
   cancellation and late candidate chunks remain pure cognition coverage
   because the exported candidate replay is synchronous.
4. **Measurements:** completed with a fixed-count browser measurement test.
   Raw latency samples, rejection counts/rate, repair count, state-loss count,
   deterministic replay mismatches, and heap availability are recorded below.

## Acceptance Criteria

- [x] **AC-01:** A complete replay produces the expected fixture table.
      `examples/web/tests/genui.spec.ts` and the existing candidate browser
      test cover the JSON fixture table.
- [x] **AC-02:** A filter and selection update preserve supported user state.
      The existing browser interaction tests cover filter, selection, detail,
      and focus preservation.
- [x] **AC-03:** Incomplete or invalid candidates leave committed source and
      revision unchanged; invalid candidates do not reach the renderer.
      `lib/cognition/generative_ui_test.mbt` and the browser invalid-candidate
      test cover this boundary.
- [x] **AC-04:** A stale base revision is rejected without advancing the
      session revision. Covered by cognition/session tests and the browser
      stale-base test.
- [x] **AC-05:** Duplicate chunks are idempotent; out-of-order chunks follow a
      defined rejection policy. Covered by
      `lib/cognition/generative_ui_test.mbt` and replay tests.
- [x] **AC-06:** Cancellation invalidates generations before `Applying`; late
      chunks cannot commit, while cancellation after applying is too late.
      Covered by deterministic cognition lifecycle tests. The browser candidate
      API is synchronous and does not claim a browser interleaving test.
- [x] **AC-07:** Resumption starts only from an explicitly selected committed
      revision. Covered by the lifecycle tests.
- [x] **AC-08:** Finalization is idempotent and terminal generations cannot
      accept later chunks. Covered by the lifecycle tests.
- [x] **AC-09:** Dry-run validation completes before any candidate commit.
      Covered by `ffi/jsx/session_contract_wbtest.mbt` and lifecycle tests;
      the browser suite verifies the subsequent real DOM boundary.
- [x] **AC-10:** DOM application failure preserves committed source and
      revision, marks the session dirty, never reports the candidate committed,
      and the next successful render repairs the dirty root. Covered by
      `ffi/jsx/render_baseline_wbtest.mbt`, session tests, and the browser
      failure/recovery test.
- [x] **AC-11:** The generated surface cannot perform network mutation,
      persistence, navigation, raw HTML insertion, or arbitrary code execution.
      Covered by candidate validator/projection tests and the invalid browser
      candidate test.
- [ ] **AC-12:** Property tests cover removal-before-insertion, sibling
      indexes, nested updates, text/expression-span nodes, and session
      isolation. The generated patch property suite covers patch/model
      equivalence and the known-positive corruption detector; fixed session
      contract tests cover isolation, but a dedicated session-isolation
      property is not yet present.
- [x] **AC-13:** Host-owned data bindings, filter/selection state, and
      allowlisted aggregations lower into the candidate without arbitrary
      expressions or candidate-owned mutable state. Covered by candidate,
      projection, data-explorer, and browser state tests.
- [ ] **AC-14:** Browser tests cover the same lifecycle against the real JSX
      session. Browser coverage now proves invalid/stale rejection, DOM failure
      and recovery, state preservation, and deterministic replay. Cancellation,
      late candidate chunks, and internal dry-run failure remain cognition/
      MoonBit evidence because the public candidate replay call is synchronous
      and does not expose internal dry-run state.
- [x] **AC-15:** Results and measurements are recorded before deciding whether
      to add a live provider or freeze a renderer-neutral contract. See the
      dated evidence and metric table below; the live-provider gate remains
      closed while AC-14 is incomplete.

Required zero-count safety metrics are recorded separately by source:

- cognition lifecycle: cancelled-generation commits `0`; stale/late-generation
  chunk commits or terminal-event acceptances `0`; deterministic replay
  mismatches `0` (covered by the cancellation, stale-generation, and terminal
  event tests in `lib/cognition/generative_ui_test.mbt`);
- browser session: stale-base candidate commits `0`; host state loss `0`;
  falsely committed failed DOM applies `0`; deterministic fresh-replay
  mismatches `0`.

Browser measurement run (`npx playwright test tests/genui.spec.ts --grep
"safety measurements"`, Chromium, 2026-07-13): five valid replay latency
samples were `340.50, 1.80, 1.80, 1.60, 1.70 ms` (min `1.60`, median `1.80`,
mean `69.48`, max `340.50`); three invalid and three stale-base candidates
were rejected (`6/6`, rejection rate `1.0`); one forced DOM failure was
followed by one successful repair; deterministic fresh-replay mismatch count
was `0`; Chromium reported heap measurement available with `17,100,000` used
and `20,500,000` total bytes in the captured sample. The attached raw JSON
also contains matching before/after host-state snapshots and failed/repaired
DOM result summaries; fixed denominators and every latency sample are retained.

## Test Matrix

| Acceptance criteria | Pure lifecycle/model | MoonBit package tests | Browser/E2E |
| --- | --- | --- | --- |
| AC-01–AC-02 | candidate/model fixtures | JSX session contract | JSON/CSV surface |
| AC-03–AC-05 | transition + property tests | session recovery | invalid/stale candidate tests |
| AC-06–AC-08 | cancellation/terminal tests | generation adapter | cognition-only for candidate cancellation |
| AC-09–AC-11 | validator + dry-run tests | DOM error contract | real DOM commit and apply-failure recovery |
| AC-12–AC-13 | patch/model + binding properties | `ffi/jsx` tests | interaction/state-preservation cases |
| AC-14–AC-15 | replay/measurement harness | package totals | partial lifecycle browser report + attached metrics |

## Exit Gates

- **Gate 0:** **passed** — transition policies and deterministic lifecycle
  tests are landed in `lib/cognition`.
- **Gate 1:** **passed** — fixed replay covers duplicate, stale, cancellation,
  late, and finalization cases without network access.
- **Gate 2:** **passed** — invalid candidates are rejected before lowering;
  validator, dry-run, DOM error, and capability tests cover AC-09–AC-11.
- **Gate 3:** **partially passed** — model and browser tests cover the JSON/CSV
  surface, host state, candidate rejection, DOM failure, and recovery. Browser
  cancellation/late-candidate interleaving and internal dry-run fault
  injection are intentionally not claimed.
- **Gate 4:** **not yet passed** — all recorded browser safety counts are zero,
  but AC-14 remains open for the explicitly bounded browser lifecycle gap.
  Do not add a live provider or renderer-neutral contract until that gate is
  closed by an approved evidence decision.

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

- The first live provider must remain deferred until the remaining browser
  lifecycle evidence decision is closed and the recorded metrics are reviewed.
  Adapt `llm/` only as a transport/provider implementation; do not make its
  Gemini-specific `EditAction` contract the Generative UI domain model.
- `moon prove` is a later option for pure request/reconciliation invariants. It
  is not a prerequisite for proving the JavaScript/DOM boundary.
- Related direction: `docs/architecture/generative-ui-direction.md`.
- Related correctness work: merged PR #892, “fix(reconcile): preserve duplicate
  sibling identities.”
