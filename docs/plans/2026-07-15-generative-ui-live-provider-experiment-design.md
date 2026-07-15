# Generative UI live-provider experiment design

- **Date:** 2026-07-15
- **Status:** Proposed, design-only; live provider and network implementation remain unapproved
- **Decision date:** 2026-07-29
- **Decision owner:** Canopy maintainers

## Why

The deterministic Generative UI path now covers request identity, base revisions,
chunk assembly, cancellation, late-event rejection, validation, dry-run, and
session-owned commit. The remaining question is whether a real provider can
produce useful constrained UI candidates often enough, quickly enough, and
cheaply enough to justify retaining a live adapter.

A syntactically valid commit is not evidence of value. A provider could return a
no-op, a trivial panel, or a valid table that does not satisfy the requested task.
The experiment therefore measures fixture-specific task success and blinded
human usefulness in addition to the existing zero-tolerance safety metrics.

The current renderer does not yet meet that value bar. It lowers validated
`table`, `filter`, and `summary` nodes to empty declarative `data-genui-*`
markers. The working JSON/CSV explorer is a separate fixed host UI. Running a
live provider against that split would measure candidate shape, not a generated
UI that anyone can use.

Before the first live request, fixed replay must prove one authoritative,
session-owned functional projection. The validated candidate selects structure;
a trusted host context supplies data and interaction state; the existing session
dry-run, commit, and recovery boundary owns the actual visible explorer.

No provider implementation may land from this document alone. This design must
be reviewed, the experiment issue must be approved, and a separate implementation
plan must be accepted first.

## Value gate

- **Consumer:** maintainers evaluating the read-only JSON/CSV data-exploration
  surface in `examples/web`.
- **Signal:** safety, fixture-specific semantic task success, blinded human
  usefulness, latency, token use, provider cost, retries, and rejection reasons.
- **Lifecycle:** a local-only, removable experiment. It does not establish a
  public library API, production service, or renderer-neutral provider contract.
- **Decision:** record `KEEP` or `DELETE` in the experiment issue by 2026-07-29.
  Missing or incomplete evidence defaults to `DELETE`; the experiment cannot
  remain indefinitely pending.

`KEEP` authorizes a follow-up decision about continued experimentation. It does
not authorize production deployment or freeze a general provider API.

## Alternatives considered

### 1. Session-owned functional projection — selected

Use the local `examples/web` host and existing async lifecycle, but do not retain
two visible representations of the candidate. After validation, the JSX session
adapter renders the actual table, filter, summary, and rows inside its own root.
A private trusted host context supplies synthetic fixture rows and current
filter/selection state. Provider output supplies neither data nor state.

This gives the existing session one DOM owner and one success/failure boundary.
It also makes screenshots and interaction tests evidence about the generated UI
rather than about a separate hand-written explorer.

### 2. Marker projection plus synchronized host explorer — rejected

Updating the session marker tree and a separate functional explorer creates a
distributed DOM transaction. Installing either tree can synchronously trigger
focus, listener, or custom-element effects that a DOM snapshot cannot undo.
Two-phase apply and rollback would therefore overstate atomicity.

### 3. Candidate-program scoring without materialization — rejected

Tree-shape checks can reject malformed and trivial output, but they cannot prove
that a person can use the result. This would preserve the current split and make
the keep/delete decision easy to game.

### 4. Browser-direct Gemini request — rejected

Direct browser access exposes the API key. Moving the key from a query parameter
to a header does not make it secret. Google's current guidance requires a
server-side proxy for web clients.

### 5. General provider interface — rejected

One live adapter cannot establish renderer-neutral invariants. A generic API now
would either encode Gemini assumptions or duplicate lifecycle responsibilities
already owned by `GenerativeUiLifecycle` and the JSX session. A second materially
different adapter is required before freezing a shared contract.

The synchronous `CognitionProvider` and Gemini-specific `EditAction` types are
not candidates for reuse as the async Generative UI domain model.

## Scope

### In

- A provider-neutral, session-owned functional projection for the existing
  read-only order explorer.
- A private trusted host context for fixture rows and host interaction state.
- Fixed, allowlisted host event handling for filter and selection updates.
- Gemini Developer API as the first experimental backend.
- A local-development-only, same-origin server proxy.
- Whole-response structured JSON generation.
- Browser scheduling and cancellation through the existing deterministic async
  driver shell.
- Three fixed read-only fixture tasks, ten runs per fixture.
- Automated semantic scoring, blinded human evaluation, and dated evidence.

### Out

- Production or public deployment of a provider endpoint.
- Browser-visible credentials or an arbitrary prompt relay.
- Provider-controlled data, interaction state, event handlers, DOM access,
  session mutation, identity, revision, capability policy, dry-run, or commit.
- A second DOM owner for the generated explorer.
- Reusing `llm.EditAction` as a UI candidate protocol.
- Replacing deterministic replay or scripted provider tests with network tests.
- Streaming/SSE transport; the deterministic shell already owns chunk lifecycle
  semantics.
- Multi-provider abstraction, renderer-neutral API, semantic edits, undo,
  co-editing, or generated side effects.

## Responsibility map

| Surface | Owns | Must not own |
| --- | --- | --- |
| Local Gemini proxy | Fixed fixture prompts, Gemini request encoding, server-side credential lookup, HTTP transport, response decoding, usage metadata, size limits, safe error mapping | Generation IDs, revisions, DOM/session state, retries, commit decisions, arbitrary prompts |
| Browser provider driver | One active request, timeout, retry pacing, `AbortController`, provider-result correlation, transport outcomes, experiment metrics | API key, candidate validation, host data/state, DOM/session mutation |
| Existing async lifecycle | Generation identity, base revision, cancellation, terminal idempotency, late-result rejection, exact-generation completion | Provider credentials, HTTP, prompts, retries, rendering |
| UI input adapter | Candidate syntax, schema, capability validation, limits, structured rejection | Provider transport, host values, events, DOM mutation |
| Trusted host context | Defensive derived render snapshot from the existing TypeScript order functions: visible rows, selected row, query, summaries, and allowed capabilities | Candidate/provider values, mutable source arrays, callbacks, HTTP, revision or commit policy |
| Session-owned functional adapter | Validate candidate references against the trusted snapshot; render the actual explorer projection; session dry-run, DOM apply, revision, recovery, registry and mounted-ID consistency | Filtering/selection/summary business logic, provider transport, credentials, candidate-owned state or callbacks, a second visible explorer |
| Trusted host interaction shell | Use existing pure TypeScript functions to derive proposed state and a defensive render snapshot for allowlisted filter/selection events; request session refresh with the same committed candidate | Direct generated DOM mutation, arbitrary candidate actions, provider calls |
| Experiment evaluator | Fixture rubric, shuffled artifacts, usefulness score, keep/delete evidence | Changing candidates, repairing output, replacing failed runs |

The provider can generate candidate bytes only. It cannot claim that a candidate
was accepted, materialized, useful, or committed.

## Data flow

```text
fixed fixture id
  → local same-origin proxy
  → Gemini generateContent
  → decoded untrusted candidate JSON
  → browser provider driver
  → existing Promise/Abort generation lifecycle
  → syntax/schema/capability validation
  → bind trusted host context
  → functional explorer projection inside the session-owned tree
  → base-revision check and internal dry-run
  → one session-owned DOM commit/recovery boundary
  → automated rubric + blinded review artifact
```

The provider response carries no session handle, generation ID, base revision,
host data, interaction state, mounted ID, or commit instruction. The browser
driver correlates the response to the exact locally owned generation before
handing candidate bytes to the lifecycle.

## Deterministic functional-projection prerequisite

The current marker-only candidate lowering is not sufficient for a live-provider
experiment. The same validated `GenerativeUiCandidate` must lower to the actual
functional order explorer inside the session root.

A private experiment host context contains a defensive serialized snapshot of:

- visible `orders` rows derived by the existing `deriveOrderView`;
- current query, selected row, and selected-visible state;
- count, total, and average derived by the existing `summarizeOrders`;
- allowlisted binding fields, selection key, filter operators, and aggregations.

The host keeps source rows and mutable query/selection state outside the session.
The snapshot contains no callbacks, DOM handles, credentials, provider fields,
or live mutable containers. The candidate can read neither the source rows nor
the host state.

The candidate selects only declarative structure. A `table` references the
allowlisted binding. `column`, `filter`, and `summary` select allowlisted fields
and operations. The functional adapter validates those references against the
snapshot and renders plain session-owned elements. It does not reimplement
filtering, selection, or aggregation. Candidate text stays inert text. No
candidate value becomes an event handler, expression, URL, raw HTML, or action.

The trusted host shell owns fixed event delegation at the session root. It
accepts only the allowlisted filter-input and row-selection events; focus,
custom, and generated event names are ignored. Before a host-state refresh, it
terminalizes the exact active provider generation as cancelled and then aborts
that generation's provider and transport handles. It never auto-restarts the
request. A later explicit generation starts from the refreshed session revision.

Existing TypeScript functions derive a proposed next state and defensive render
snapshot. The shell calls the session synchronously with the same committed
candidate and proposed snapshot. A successful refresh is a normal session commit
and advances its revision. The shell then installs the proposed host state with
one non-fallible assignment before returning to the event loop. On failure, the
previous host state remains current and the session follows its established
recovery/dirty contract without advancing the revision.

There is no marker tree synchronized with a separate explorer. The session root
is the authoritative visible projection. The existing fixed explorer may remain
as a fixture/input control during implementation, but it is not the generated
result, is not shown in evaluation screenshots, and cannot satisfy a fixture
rubric.

Fixed replay must prove this boundary before the local provider endpoint is
enabled:

- all six rows, selected columns, filter control, and summaries render inside the
  session root;
- filter and selection events use only trusted host handlers;
- host state survives a structural candidate update where supported;
- invalid, stale, no-op, unsupported, or failed-apply candidates advance no
  revision and cannot replace the previous committed functional explorer;
- failed host-state refresh keeps the previous host state and follows the
  session's established recovered-or-dirty DOM contract;
- no provider-specific branch exists in validation, rendering, or interaction.

Until these checks pass, no request may carry a real credential.

## Existing API and reuse boundary

The experiment reuses these project boundaries:

- `GenerativeUiCandidate` and `GenerativeUiCandidateNode` as the only validated
  program input;
- `GenerativeUiLifecycle` and the existing Promise/Abort driver for generation,
  cancellation, terminalization, and stale-result handling;
- the JSX candidate projection, session dry-run, DOM apply, revision, and
  recovery contract;
- `deriveOrderView`, `selectOrder`, and `summarizeOrders` for host-owned data and
  interaction decisions.

The existing TypeScript functions remain the single functional core for
filtering, selection, and summaries. MoonBit receives a defensive derived render
snapshot and must not duplicate that business logic. The implementation plan
must still check MoonBit core `Result`/`Option`, `Array`/`ArrayView`, `Json`, and
`Map`/`Set` APIs before adding validation, storage, or projection traversal.

The synchronous `CognitionProvider`, Gemini-specific `EditAction`, and direct
browser `llm.GeminiConfig` are checked but rejected because their contracts do
not match this boundary. Any host-context or render-snapshot type remains private
to the experiment; no new public container, provider interface, or lifecycle
type is justified.

## Backend and transport contract

### Provider selection

- Backend: Gemini Developer API.
- Endpoint: `POST /v1beta/models/gemini-3.5-flash:generateContent`.
- Model: explicit `gemini-3.5-flash`; do not use a floating `latest` alias during
  the 30-run experiment.
- Mode: non-streaming whole response.
- Output: `application/json` constrained by a provider-side JSON schema matching
  the current candidate tree.
- Authoritative validation: Canopy's existing candidate validator. Provider
  structured output is an early transport guard, not a trust boundary.

`llm/` remains unchanged by default. Its Gemini URL/body/response shapes may
inform or supply provider-specific encoding and decoding only if the
implementation plan proves that reuse does not expose `GeminiConfig.api_key` to
the browser or couple GenUI to `EditAction`. The current `fix_typos` and
`edit_text` APIs are not used.

### Local host surface

The experiment adds one development-only same-origin endpoint:

```text
POST /__canopy_dev/genui/generate
```

The request accepts only:

```json
{ "fixture_id": "json-overview" }
```

Allowed fixture IDs are compiled into the proxy. The proxy chooses the fixed
prompt, fixture data, candidate schema, model settings, and opaque attempt ID.
It rejects unknown fields and fixture IDs. It is not a general prompt or model
proxy.

A successful response has this transport-only envelope:

```json
{
  "attempt_id": "opaque-server-id",
  "model": "gemini-3.5-flash",
  "candidate_json": "{...}",
  "usage": {
    "prompt_tokens": 0,
    "candidate_tokens": 0,
    "total_tokens": 0
  }
}
```

`attempt_id` identifies one proxy call. The browser owns each predetermined
experiment slot and associates its initial call and retries with that slot. The
proxy cannot replace a failed slot.

The proxy maps Gemini `usageMetadata` into numeric counters and rejects missing,
non-finite, or negative values. It limits the decoded HTTP body and candidate to
64 KiB each before returning data to the browser. Existing candidate limits
remain authoritative where stricter.

The production build has no equivalent route. Calling the path outside the local
development host returns 404. No production fallback is permitted.

## Credential boundary

- The proxy reads `GEMINI_API_KEY` from the server process environment.
- The variable must not use a `VITE_` prefix and must never enter
  `import.meta.env`, generated JavaScript, HTML, source maps, fixtures, or test
  snapshots.
- Local credentials belong in an ignored `.env.local` or the invoking shell.
- The proxy adds `x-goog-api-key` only to the outbound Gemini request.
- Startup reports credential presence as a boolean; it never prints a key,
  prefix, suffix, digest, or request header.
- CI and browser tests use a fake proxy transport and require no credential.
- A known-positive leak probe verifies that a synthetic sentinel is absent from
  built assets, logs, error envelopes, and evidence before any live run.

## Scheduling, cancellation, and shutdown

- At most one provider request is active per GenUI session.
- Starting a replacement generation first dispatches cancellation for the exact
  active generation and confirms its terminal transition. The driver then aborts
  its fetch and starts the replacement.
- User cancellation and session disposal use the same order: terminalize the
  exact generation, abort provider and transport handles, then remove registry or
  session ownership.
- This corrects the current test shell: its restart path aborts before calling
  `restart`, and its dispose path removes driver state without dispatching
  lifecycle cancellation. Live-provider work cannot reuse those orderings.
- A response can resolve only the provider handle created for its generation.
  A late response after cancel, restart, or dispose is ignored and cannot reach
  validation or commit.
- A host filter or selection event uses that same cancel-before-abort order
  before its session refresh. The refresh advances the session revision; it
  never lets an in-flight result commit against the pre-interaction revision.
- Each attempt has a 30-second timeout. A complete experiment slot has a
  45-second deadline covering attempts and retry waits, measured by an injected
  monotonic clock.
- Driver shutdown aborts every active request and creates no completion.
- Whole-response transport produces one candidate payload followed by
  finalization; it invents no provider-owned chunk sequence numbers.

## Retry and rate-limit policy

The browser driver, not the proxy, owns retry scheduling so cancellation and
fake-time tests exercise the same policy.

- Retry only HTTP 408, 429, or 5xx transport failures.
- Do not retry authentication, permission, invalid request, schema, decode,
  budget, candidate-validation, stale-completion, timeout, or cancellation.
- Permit at most two retries after the initial attempt.
- Use exponential backoff with full jitter: 500 ms base, doubling per retry,
  capped at 4 seconds.
- Respect valid `Retry-After`, capped at 10 seconds. Waiting remains cancellable.
- Start a retry only when its delay and a new attempt can begin before the
  45-second slot deadline. Reaching the deadline aborts the active attempt and
  terminalizes the slot as `timeout`.
- Never retry after candidate bytes enter the lifecycle.
- Enforce one active request and at least one second between attempt starts.
- Record every attempt, delay, provider status, and terminal classification.

The proxy performs no hidden retry. It returns a redacted classified error and a
bounded `retry_after_ms` hint when available.

## Error and redaction contract

Transport errors map to stable experiment classifications:

- `cancelled`
- `timeout`
- `rate_limited`
- `auth`
- `network`
- `invalid_request`
- `provider_rejected`
- `decode`
- `budget_exceeded`
- `unexpected`

Persisted and browser-visible errors contain the classification, safe HTTP
status, retryability, bounded retry hint, and fixed local message. They exclude
headers, keys, Gemini request bodies, raw response bodies, environment-bearing
stacks, and provider-generated text.

The experiment records a SHA-256 candidate digest and byte length. Raw candidate
JSON remains only in the local evidence bundle required for semantic review; it
is not written to consoles or issue comments. Fixtures contain synthetic order
data and no personal information.

## Fixed experiment fixtures

All runs use fixed repository fixtures and prompts. Prompt text, candidate
schema, model, temperature, output-token limit, capability set, and initial
candidate are hashed into the evidence manifest. Any change invalidates the run
set and requires restarting it.

Before collecting runs, fixed replay must pass the functional-projection
prerequisite for all three task shapes. A materialization failure blocks the
experiment rather than consuming a slot.

### F1: `json-overview`

Input: `examples/web/src/fixtures/orders.json`.

Task: produce a useful order overview with one `orders` table, columns for
`name`, `status`, and `amount`, and a `sum` summary for `amount`.

Automated success requires all named components and attributes, one non-empty
session-owned functional explorer, all six rows, and total amount `6846.50`.
Unsupported or duplicate primary tables fail.

### F2: `csv-status-filter`

Input: `examples/web/src/fixtures/orders.csv` through the existing host parser.

Task: produce one filterable `orders` table with `name`, `status`, and `amount`
columns and a `status` filter using `contains`.

Automated success applies `paid` through the trusted host interaction path and
requires exactly three paid rows inside the session root. The candidate cannot
own or reset the filter value.

### F3: `stateful-enhancement`

Input: the JSON fixture and a committed base candidate containing only the three
order columns. Before generation, the host selects `ord-1002`, focuses that row,
and sets the filter to `pending` through the trusted interaction path.

Task: add the allowlisted status filter and amount sum summary without replacing
the table or losing host state.

Automated success requires a candidate different from the canonical base, the
required filter and summary, preserved selection and query, focus restored when
structurally possible, two pending rows, and total amount `2180.00`. An unchanged
base is a no-op and fails.

## Semantic and human evaluation

A slot is semantically successful only when:

1. provider transport succeeds;
2. the existing lifecycle accepts the exact generation;
3. validation, base-revision check, dry-run, and session commit pass;
4. the fixture-specific functional rubric passes inside the session root; and
5. a blinded human evaluator rates the result task-complete without repair.

Valid syntax or a committed revision alone is insufficient. No-op output, empty
panels, placeholder text, missing fields, duplicate primary surfaces, or
decoration that does not perform the task are failures.

Capture the task statement, final screenshot, accessibility summary, and
interaction trace. Assign shuffled artifact IDs and remove fixture order, run
number, retries, latency, token use, raw candidate, and provider metadata before
human review. Score each slot:

- **1:** no-op, trivial, misleading, broken, or task-incomplete;
- **2:** substantial failure requiring repair;
- **3:** technically complete but unclear or awkward;
- **4:** useful and clear without repair;
- **5:** notably effective within the constrained surface.

A no-op or trivial result is always score 1. A slot with no committed screenshot
because any earlier stage failed is task-incomplete and score 1. The evaluator
records the checklist and one reason before metrics are unblinded. Manual edits,
prompt retries, cherry-picking, and replacement runs are prohibited.

## Metrics and evidence

Record every attempt, including failures:

- fixture ID, predetermined slot ID, and every provider attempt ID;
- prompt/schema/settings manifest digest;
- provider and exact model;
- attempt count, errors, retry delays, and cancellation outcome;
- request, provider, validation, dry-run, DOM apply, and end-to-end latency;
- prompt, candidate, and total tokens;
- price URL and capture date, per-run cost, and total cost;
- candidate digest and byte length;
- lifecycle transitions and terminal state;
- rejection code, base and committed revisions, and commit count;
- functional rubric result and failed clause;
- blinded task result, score, and reason;
- stale, cancelled, invalid, and no-op/trivial commit counters.

Exclude secrets, headers, provider bodies, and console dumps. Keep all 30
predetermined slots. An aborted or failed slot remains a failure.

Every semantic rate and usefulness median uses all ten slots for that fixture.
End-to-end latency is actual monotonic time from the initial attempt to terminal
slot result, including retries and waits. No timeout value is substituted. The
45-second slot deadline bounds it. P95 is the nearest-rank 95th percentile across
all 30 slot latencies. Cost includes every attempt, including failed slots.

## Keep/delete gate

Run each fixture exactly ten times, for 30 predetermined slots. Decide by
2026-07-29.

`KEEP` requires every condition:

- zero stale-generation commits;
- zero cancelled-generation commits;
- zero invalid-candidate commits;
- zero falsely reported failed DOM applies;
- at least 9/10 semantic task successes for each fixture, hence at least 27/30;
- median blinded usefulness at least 4 for each fixture;
- no manual candidate or prompt repair and no replacement runs;
- median end-to-end latency at most 8 seconds and p95 at most 20 seconds;
- total provider cost for all attempts at most USD 5.00;
- complete redacted evidence and a passing secret-leak probe.

Any missing condition produces `DELETE`. Record the decision, metric table,
evidence path, settings digest, and decision author in the issue by the deadline.

`DELETE` removes the live proxy and adapter while retaining provider-neutral
deterministic projection/lifecycle/validation coverage and decision evidence.
`KEEP` permits a separately reviewed continuation plan but leaves the adapter
experimental and private.

## Test contract for a later implementation

Network access and real credentials are never part of CI. A future implementation
plan must preserve these deterministic checks:

- fixed replay renders columns, rows, filter, and summaries inside the session
  root rather than a parallel explorer;
- host context is defensive, provider-free, candidate-read-only, and rejects
  unknown bindings/fields/actions;
- generated controls reach only trusted filter/selection event delegation;
- pure host next-state decisions reuse the existing data functions;
- a host interaction terminalizes and aborts the exact active generation before
  refresh, never auto-restarts it, and rejects late success or rejection;
- successful host-state refresh advances the session revision, then commits host
  state with the functional projection;
- failed refresh retains prior host state and follows session recovery/dirty
  behavior without advancing revision;
- invalid, stale, no-op, unsupported, and failed-apply candidates cannot replace
  the last valid functional explorer;
- active restart/disposal terminalizes the exact generation before abort/removal,
  including late provider success and rejection;
- proxy allowlist rejects arbitrary prompts and unknown fields;
- Gemini success/error decoding uses fixtures;
- a credential sentinel is absent from client artifacts, errors, logs, and
  evidence;
- fake time covers timeout, backoff, `Retry-After`, retry cap, and cancellation;
- response and candidate size limits are enforced;
- rubric known-positive and known-negative controls include a valid no-op that
  fails semantic scoring;
- artifact shuffling removes provider/run metadata;
- existing replay, async driver, candidate validation, session, and browser
  safety suites remain authoritative.

Live runs require an explicit `GEMINI_API_KEY` and cost confirmation. They are
not tests and never run in CI, on page load, or in a production build.

## Approval gates

1. Independent design review against the cognition provider boundary and
   Generative UI direction.
2. Maintainer approval of this design, prompts, rubric, model, cost ceiling, and
   dated keep/delete rule.
3. A separate implementation plan defining file ownership and test-first slices.
4. Deterministic fixed-replay proof of the session-owned functional explorer,
   including state interaction and known-negative controls.
5. Implementation review before the first request carrying a real credential.
6. Keep/delete review of complete 30-slot evidence by 2026-07-29.
7. If kept, a second materially different adapter before any renderer-neutral
   provider contract or conformance suite is frozen.

## References

- [Generative UI direction](../architecture/generative-ui-direction.md)
- [Generative UI input vertical slice](2026-07-12-generative-ui-input-vertical-slice.md)
- [Cognition provider boundary design](2026-05-26-cognition-provider-boundary-design.md)
- [Gemini API overview](https://ai.google.dev/gemini-api/docs/api-overview)
- [Gemini API key security](https://ai.google.dev/gemini-api/docs/generate-content/api-key)
- [Gemini retries](https://ai.google.dev/gemini-api/docs/troubleshooting)
- [Gemini model versions](https://ai.google.dev/gemini-api/docs/models/gemini)
