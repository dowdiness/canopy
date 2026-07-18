# Structured-data bounded-provider experiment design

- **Date:** 2026-07-15
- **Status:** Deferred before campaign freeze; no manifest was frozen and no gate was executed
- **Former decision date:** 2026-07-29; not active while this proposal is deferred
- **Decision owner:** Canopy maintainers

## Status

This document preserves a proposed product-value experiment for possible later
product discovery. It is not the active Generative UI workstream, does not
authorize participant recruitment or provider implementation, and has produced
no `FIXED`, `RULES`, or `GENERATE` campaign decision.

The active engineering question is defined separately in
[Generative UI local-LLM technical feasibility](2026-07-15-generative-ui-local-llm-technical-feasibility.md).
That work tests implementation feasibility only. It neither depends on this
value protocol nor supplies evidence for its gates.

## Experiment-local claim

This is one confirmatory experiment in the **Information understanding** job
family: answering specified questions about unfamiliar, read-only JSON/CSV
data. It tests one required value source from the opportunity taxonomy:
**composing known controls around a new intent**.

The experiment asks whether a task-specific composition of the bounded table,
filter, and summary capabilities improves task completion over the fixed
explorer. It compares the existing fixed explorer, a task-specific hand-authored
oracle, deterministic rules, and an eligible model-generated candidate on the
same capability-bounded Declarative/Projectional surface.

It does not compare Static, Declarative, Open-Ended, Dynamic, Projectional, and
Hybrid generation as general approaches, nor does it compare their possible
lifecycles. It cannot show that this job is Canopy's best Generative UI
opportunity, that bounded declarative output is the preferred representation
elsewhere, or that generated code and open-ended documents lack value. Its
`FIXED`, `RULES`, and `GENERATE` labels are experiment-local retention decisions
for this job and apparatus, not architecture-wide verdicts.

Arbitrary model-generated HTML, JavaScript, network calls, calculations, and
effects remain outside this experiment. A later opportunity hypothesis that
needs Dynamic or Open-Ended generation requires its own execution boundary,
comparator, evidence contract, and review.

## Why

The deterministic Generative UI path covers request identity, base revisions,
chunk assembly, cancellation, late-event rejection, validation, dry-run, and
session-owned commit. This establishes a safe experiment boundary, not a reason
to add candidate generation.

The useful JSON/CSV explorer is already a fixed host UI. The current provider
tasks ask for tables, filters, and summaries that this explorer can provide.
Measuring only whether Gemini reproduces those features would show adapter
reliability, not that candidate generation improves a concrete user job or
justifies another runtime boundary.

The value question therefore precedes provider work: for which structured-data
job does a task-specific UI beat the fixed explorer, how much of that advantage
can deterministic rules recover, and does a model recover enough additional
value to justify its latency, cost, failure modes, and lifecycle complexity?

No provider implementation may land from this document alone. Gate A uses the
existing explorer and a hand-authored standalone oracle without a candidate
projection. If Gate A passes, Gate B may add only the minimum synchronous local
evaluation harness needed to materialize oracle and rules candidates. The
provider proxy, credentials, async lifecycle integration, and live adapter
remain prohibited until the rules-capture gate makes Gemini eligible.

## Value gate

- **Target-user hypothesis:** a developer or analyst answering a specified
  question over an unfamiliar read-only JSON/CSV schema. This is a hypothesis
  to test, not an established Canopy consumer.
- **Required value source:** composing known controls around a new intent.
- **Primary signal:** the preregistered difference in correct task-completion
  rate within a fixed time limit on held-out schema-by-question cases. Gate A
  measures whether task-specific composition improves on the fixed explorer;
  Gate B measures whether the capability-bounded surface preserves that uplift;
  Gate C, when eligible, measures whether a model recovers additional uplift.
- **Evidence:** each decisive observation binds the question, frozen capability
  composition, answer correctness, completion time, interaction trace, and
  reported useful moment. Aggregate success is attributed to this value source
  only through the frozen arm comparisons.
- **Secondary signals:** interaction count, blinded usefulness, safety, latency,
  token use, provider cost, retries, and rejection reasons.
- **Comparators:** the existing fixed explorer, a task-specific hand-authored
  oracle, deterministic rules, and Gemini only if the earlier gates pass.
- **Lifecycle:** a removable experiment. It does not establish a public library
  API, production service, generator-neutral runtime, or provider contract.
- **Decision:** record `FIXED`, `RULES`, or `GENERATE` by the decision date.
  Missing or incomplete evidence defaults to `FIXED`.

Before the custodian opens the held-out set, the initial manifest freezes the
job, set digests, answer keys, primary metric, time limit, participant protocol,
sample counts, four win margins, statistical analysis plan, role/access matrix,
fixed-explorer version, development rules, prompt, candidate schema,
model-selection protocol, candidate eligibility, development benchmark,
settings envelope, tie-breaks, and cost and safety limits. Gate B separately
freezes the later harness and projection commit. Only after Gemini eligibility
may the preregistered development-only bake-off select a model; Gate C then
freezes the exact provider, model ID and version, settings, and provider
integration before its held-out set is opened.
Changing a field after its stage freeze invalidates the campaign.

`GENERATE` authorizes only a separately reviewed continuation of the private
experiment. It does not authorize production deployment or freeze a general
provider or renderer-neutral API.

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
the final decision easy to game.

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


### 6. Cloudflare Agents SDK as the experiment control plane — deferred

Cloudflare can host a later evaluation control plane, but the current experiment
does not require the Agents SDK. Durable Objects and SQLite, Workers AI or other
model bindings, Workflows, and platform observability are Cloudflare platform
primitives rather than evidence for adopting an agent abstraction.

If the value gates justify a live campaign, evaluate a narrow Worker plus
Workflow first, with a regular Durable Object only if per-campaign coordination
requires it. The Agents SDK adds agent-specific chat, tool orchestration, client
state synchronization, and autonomous-loop concepts that this design excludes.
Reconsider it only if bidirectional agent sessions or connection recovery become
explicit experiment requirements.

Durable storage is not immutable evidence. Any Cloudflare-backed evaluator must
use an append-only event schema, freeze manifest and output digests, and preserve
the finalized evidence outside the mutable runtime when independent retention is
required. Adopting any deployed Cloudflare control plane requires a separate
review because this experiment is currently local-only.

## Scope

### In

- A preregistered fixed/oracle/rules value comparison with separate development
  and held-out schema-by-question sets.
- Objective answer keys, one primary completion metric, frozen win margins,
  blinded secondary evaluation, and dated `FIXED | RULES | GENERATE` evidence.
- Gate A: the existing fixed explorer and a hand-authored standalone oracle,
  with no candidate projection or generation runtime.
- Conditional on Gate A passing: a minimum synchronous local evaluation harness
  and projection shared by oracle and deterministic-rules candidates under the
  same capability surface.
- Conditional on Gemini eligibility: a session-owned functional projection,
  private trusted host context, fixed host events, Gemini Developer API, local
  same-origin proxy, whole-response JSON, and browser-owned async scheduling.
- Conditional on Gemini eligibility: three fixed reliability fixtures, ten live
  runs per fixture, with automated semantic scoring and complete evidence.

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
- A deployed Cloudflare control plane or the Cloudflare Agents SDK; either needs
  a separate decision after the value prerequisite.

## Responsibility map

| Surface | Owns | Must not own |
| --- | --- | --- |
| Local Gemini proxy | Compiled reliability fixtures and a custodian-frozen opaque held-out-task allowlist, Gemini request encoding, server-side credential lookup, HTTP transport, response decoding, usage metadata, size limits, safe error mapping | Generation IDs, revisions, DOM/session state, retries, commit decisions, arbitrary prompts |
| Browser provider driver | One active request, timeout, retry pacing, `AbortController`, provider-result correlation, transport outcomes, experiment metrics | API key, candidate validation, host data/state, DOM/session mutation |
| Existing async lifecycle | Generation identity, base revision, cancellation, terminal idempotency, late-result rejection, exact-generation completion | Provider credentials, HTTP, prompts, retries, rendering |
| UI input adapter | Candidate syntax, schema, capability validation, limits, structured rejection | Provider transport, host values, events, DOM mutation |
| Trusted host context | Defensive derived render snapshot from the existing TypeScript order functions: visible rows, selected row, query, summaries, and allowed capabilities | Candidate/provider values, mutable source arrays, callbacks, HTTP, revision or commit policy |
| Session-owned functional adapter | Validate candidate references against the trusted snapshot; render the actual explorer projection; session dry-run, DOM apply, revision, recovery, registry and mounted-ID consistency | Filtering/selection/summary business logic, provider transport, credentials, candidate-owned state or callbacks, a second visible explorer |
| Trusted host interaction shell | Use existing pure TypeScript functions to derive proposed state and a defensive render snapshot for allowlisted filter/selection events; request session refresh with the same committed candidate | Direct generated DOM mutation, arbitrary candidate actions, provider calls |
| Experiment evaluator | Preregistered manifest, held-out custody and reveal, arm blinding, objective and human scoring, append-only evidence, final decision | Tuning after reveal, changing candidates, repairing output, replacing failed cases or runs |

The provider can generate candidate bytes only. It cannot claim that a candidate
was accepted, materialized, useful, or committed.

## Data flow

```text
compiled reliability fixture ID or opaque held-out task ID
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

### Spike 0 evidence boundary

Spike 0 connected the development-only host to local Ollama
`gemma4:e2b` and produced one valid bounded recipe for the fixed pending-orders
case. The run demonstrated the provider-to-schema-to-renderer path. It did not
establish model value because the schema already fixed the `pending` filter,
`amount` sum, and answer-required fields.

Observed end-to-end latency ranged from 5.8 to 57.6 seconds. These
diagnostic runs enter no `S_*`, uplift, power, viability, or model-selection
calculation, and no result may be generalized from `gemma4:e2b` to stronger
models or LLMs as a class.

### Development-only model selection

The initial manifest freezes the selection procedure rather than naming a
winner. Candidate eligibility requires a stable versioned model ID, Gemini
Developer API structured JSON output, the frozen candidate schema, and the
preregistered latency, cost, and safety ceilings. The manifest also freezes the
development cases, repeat count, prompt, temperature, output-token limit,
timeout, no-replacement failure treatment, primary selection metric, and
tie-break order.

Only after Gate B establishes Gemini eligibility may provider authors run the
frozen bake-off on development cases. Select the eligible model with the highest
task-complete valid-candidate rate. Break a tie by lower median end-to-end
latency, then lower total cost. A timeout, provider error, invalid candidate,
task-incomplete candidate, or missing slot scores as failure and is not
replaced. Record every candidate model and setting, predetermined slot, raw
metric, exclusion, and the deterministic selection result before the Gate C
custodian opens held-out cases.

Gate C evaluates one selected model. Trying multiple models on held-out cases
and reporting only the best is prohibited. A multi-model held-out comparison
requires a new preregistered campaign, separately powered arms, and multiplicity
control. Changing the winner, model version, prompt, schema, or settings after
Gate C freeze invalidates the campaign.

### Provider selection

- Backend: Gemini Developer API.
- Endpoint: `POST /v1beta/models/{frozen-model-id}:generateContent`.
- Model: the explicit versioned winner of the frozen development-only selection
  procedure; never use a floating `latest` alias.
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

The request accepts exactly one selector. Reliability runs use:

```json
{ "fixture_id": "json-overview" }
```

Gate C held-out runs use:

```json
{ "task_id": "opaque-held-out-task-id" }
```

Allowed fixture IDs are compiled into the proxy. Before Gate C, the custodian
supplies a frozen server-side allowlist whose non-semantic task IDs bind the
held-out case, question and prompt construction, fixture-data digest, candidate
schema, capability manifest, model settings, and campaign-manifest digest. The
allowlist remains outside source control and client assets; implementation
authors cannot access it, and only the custodian-run host may load it after the
provider-integration freeze. The browser sends only the opaque task ID.

The proxy chooses all bound inputs and the opaque attempt ID. It rejects unknown
IDs, extra fields, both selectors, or neither selector. Requests cannot carry a
prompt, case data, schema, capabilities, or model settings, so this is not a
general prompt or model proxy.

A successful response has this transport-only envelope:

```json
{
  "attempt_id": "opaque-server-id",
  "model": "frozen-versioned-model-id",
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

## Preregistered value prerequisite

### Development and held-out boundary

The development set is visible to oracle-pattern, rules, prompt, candidate-schema,
harness, and projection authors. They may use it to choose task families, tune
deterministic rules, revise the prompt, and implement generic materialization.
Development results are diagnostic only and never enter the final decision.

One independent custodian controls the materially different held-out
schema-by-question cases. The custodian may also author the held-out oracle, but
may not be a rules, prompt, harness, projection, or provider-integration author
in the same campaign. Held-out cases and case-level artifacts remain unavailable
to those authors until the final decision is recorded.

| Role | Development set | Held-out access before final decision | May change frozen implementation |
| --- | --- | --- | --- |
| Custodian/oracle | Yes | Full, after initial manifest freeze | No |
| Rules/prompt/harness/projection/provider authors | Yes | No; aggregate gate result only | No |
| Blinded human evaluator | No requirement | Shuffled task artifacts only | No |
| Decision maintainer | Manifest and development summary | Aggregate scores and audit status only | No |

Gate A is executed by the custodian. It returns only the aggregate oracle uplift
and pass/fail decision to implementation authors. If Gate A passes, harness and
projection authors work from the development set only. Before the custodian runs
Gate B, the campaign freezes the harness and projection code commit, candidate
schema and capability manifest, fixed-explorer version, rules and prompt digests,
metrics, margins, and sample counts. Gate B contains no provider or model arm.

The custodian executes each gate's frozen arms against that gate's held-out
questions, source data, capability surface, time limit, answer keys, and
evaluation procedure. Only after Gate B establishes Gemini eligibility do
provider authors run the frozen development-only model-selection procedure.
Before Gate C, the campaign freezes its incumbent, selected model and settings,
provider integration, repeat count, and opaque held-out-task allowlist. Failed
or timed-out slots remain failures and are not replaced. Arm labels and provider
metadata remain hidden during human review.

The manifest records set digests, author-role assignments, access events, freeze
time, reveal time, all frozen implementation digests, blinding, and cost and
safety limits. Any forbidden role overlap, early case-level disclosure, post-
freeze implementation change, or replacement case invalidates the campaign.
Held-out contents are revealed only after the outcome and evidence digests are
recorded.

The existing F1–F3 fixtures below are lifecycle and materialization controls.
They cannot satisfy this value prerequisite and do not enter its comparative
scores.

### Participant and experimental-unit procedure

A final `RULES` or `GENERATE` outcome requires every observation used in a
decisive gate (Gate A and Gate B, plus Gate C when run) to come from
preregistered eligible participants in the named target-user population.
Non-author proxy participants may be used only for
pilot or continuation decisions. Their observations remain separately labelled,
do not enter final `S_*` values, and cannot satisfy an uplift, viability, capture,
or model threshold. If the target-user population is missing or any gate has
insufficient eligible target-user observations, the final decision is `FIXED`
even when proxy-only results pass the same thresholds.

A proxy may be a Canopy maintainer only when they have no custodian, oracle,
implementation, or decision role in this campaign and have not seen its held-out
cases. There is no role-overlap or target-user-evidence waiver.

One experimental observation is one participant attempting one held-out
schema-by-question case through one arm. Gates A, B, and C use disjoint
participant pools; each participant belongs to exactly one gate. Within a gate,
every arm receives the same number of observations per case. For Gemini, each
frozen generated candidate is assigned to one participant; deterministic arms
use distinct participants for their matching observations.

Assignment within a gate is blocked by case and balanced across arms. A
participant never sees the same schema or answer in more than one arm, receives
no correctness feedback until the campaign ends, and encounters arms in a
counterbalanced order. The manifest freezes participant eligibility, recruitment
or proxy status, gate/pool membership, counts, case-to-arm assignment, order
schedule, and exclusion rules before held-out execution.

The task clock starts when the participant receives the question and initiates
the assigned arm, so generation and materialization waits count. It stops on
answer submission or the frozen timeout. Answers are captured in a separate
arm-neutral form and scored against the objective key without provider metadata.
Every assigned timeout, abort, invalid output, infrastructure failure, or missing
answer remains an incorrect observation and is not replaced.

For each arm:

```text
S_arm = correct assigned observations / all assigned observations
```

Completion time and post-task usefulness are secondary measures. Each
participant receives a random, non-semantic, non-reversible study ID that cannot
be derived from a name, contact address, account, or stable project identifier.
The evidence store records only that study ID, case and arm assignment, order
position, start and stop times, answer digest, correctness, timeout/failure
classification, and artifact digest. These records are pseudonymized, not
anonymous: timing and assignment data may remain linkable.

Any recruitment or re-identification mapping stays in a separate access-
controlled store, is never copied or joined into the evidence store or review
artifacts, and is accessible only to the custodian with logged access. The
custodian alone may read pseudonymized evidence. The decision maintainer receives
only aggregate scores and audit status; implementation and provider authors
receive only aggregate results and redacted artifacts. The initial manifest
freezes named access roles and deletion dates. Destroy the re-identification
mapping within 30 days after the final decision. Delete or irreversibly
aggregate pseudonymized participant evidence within 12 months after that
decision.

### Staged materialization boundary

For Gate A, the custodian compares the existing explorer with a purpose-built,
hand-authored standalone oracle. The oracle may be interactive, but it is not a
candidate program and needs no generic projection, provider, network, credential,
or generation lifecycle.

Only after Gate A passes may implementation authors build a minimum synchronous
local evaluation harness from development cases. Before held-out execution, its
code, projection, candidate schema, capabilities, and rules are frozen. The
custodian, not those authors, uses the frozen harness to materialize held-out
oracle and rules candidates. A held-out incompatibility is a failed case; fixing
it requires a new manifest and campaign.

The harness may reuse pure host data functions and candidate validation. It must
not contain Gemini code, a proxy, credentials, provider transport, retries,
`Promise`/`Abort` generation control, or live-session lifecycle integration.

The harness and projection are experiment apparatus, not an accepted runtime.
A `FIXED` outcome deletes them unless another accepted use exists. A `RULES`
outcome retains only the projection required by the accepted deterministic
behavior. Only Gemini eligibility permits the frozen development-only model
selection and separately reviewed provider integration. Both use development
cases only, must preserve the frozen candidate semantics, and cannot reveal
held-out cases before the final campaign ends.

### Decision math

Gate A and Gate B use different oracle surfaces and therefore different scores.
Let `S_fixed_A` and `S_oracle_A` be Gate A completion rates for the existing
explorer and standalone oracle. Let `S_fixed_B`, `S_oracle_B`, and `S_rules_B`
be Gate B rates on the capability-bounded evaluation surface. Let
`S_incumbent_C` and `S_gemini_C` be contemporaneous Gate C rates in the disjoint
Gate C participant pool. The incumbent arm is deterministic rules when Gate B
established `rules_viable`; otherwise it is the fixed explorer.

The manifest freezes four minimum practical uplifts from development-set
calibration: `delta_oracle_A`, `delta_oracle_B`, `delta_rules`, and
`delta_model`. Each is an absolute completion-rate difference, not an arbitrary
positive epsilon. The two oracle margins must each be at least 0.15; the rules
and model margins must each be at least 0.10.

The manifest freezes four confirmatory one-sided randomization tests: Gate A
oracle versus fixed, Gate B oracle versus fixed, Gate B rules versus fixed, and
Gate C Gemini versus its frozen incumbent. Each uses the absolute completion-rate
difference

```text
T_X = S_treatment_X - S_control_X
```

as its test statistic. A Bonferroni allocation fixes `alpha_X = 0.0125` for each
test, controlling the four-test family at `0.05`; alpha is neither recycled nor
reassigned. `rules_capture` is a deterministic decision threshold, not a fifth
hypothesis test.

Within each gate and eligibility stratum, the frozen randomization procedure
reassigns complete balanced schedules among participants. All observations from
one participant move as a cluster; case identities, order positions, and
preassignment exclusion outcomes remain fixed. Ties count as at least as extreme.
The manifest freezes exact enumeration or a Monte Carlo permutation count. Exact
enumeration uses the proportion of valid assignments with `T_perm >= T_obs`;
Monte Carlo uses `(1 + count(T_perm >= T_obs)) / (1 + N_perm)` with its frozen
seed and permutation count.

Only preregistered preassignment ineligibility may exclude an observation. Every
post-assignment missing answer, timeout, abort, invalid output, infrastructure
failure, or withdrawal from the task remains in the denominator with correctness
zero; there is no imputation, replacement, or outcome-based exclusion.

Development-only simulation must replay the complete frozen gate/pool assignment,
schedule, exclusion, failure, test-statistic, tie, permutation, and multiplicity
procedure and show at least 80% power at `alpha_X = 0.0125` to detect every
corresponding frozen margin. Before Gate A, freeze and digest the analysis script,
data-cleaning rules, assignment and simulation seeds, enumeration or permutation
counts, and all procedure inputs. A primary comparison passes only when its
observed uplift meets the margin and its frozen test passes. Insufficient eligible
target-user observations make the evidence incomplete and select `FIXED`.

1. Gate A passes only when:

   ```text
   S_oracle_A - S_fixed_A >= delta_oracle_A
   ```

   and `p_A <= 0.0125` under the frozen procedure on preregistered eligible
   target-user observations. A proxy-only pass may authorize another private
   campaign but selects `FIXED` in this campaign. Otherwise select `FIXED`.
2. Gate B first verifies that the constrained projection preserved a worthwhile
   adaptive advantage:

   ```text
   S_oracle_B - S_fixed_B >= delta_oracle_B
   ```

   The Gate B test must satisfy `p_B <= 0.0125` under the same frozen procedure
   on eligible target-user observations. If either condition fails, select
   `FIXED` for the current campaign. A projection redesign requires a new
   manifest and campaign; it cannot repair the exposed held-out run.
3. Only after that check compute rules gain and capture on the same Gate B
   surface:

   ```text
   rules_gain = S_rules_B - S_fixed_B
   rules_capture =
     rules_gain / (S_oracle_B - S_fixed_B)
   rules_viable =
     rules_gain >= delta_rules and p_rules <= 0.0125
   ```

   The frozen procedure computes `p_rules` from eligible target-user
   observations; only those observations enter `rules_gain` and `rules_capture`.
   If `rules_capture >= 0.80` and `rules_viable`, select `RULES`.
   If capture is at least 0.80 but rules are not viable, select `FIXED`.
4. Only when `rules_capture < 0.80` may the live Gemini campaign begin. After
   Gate B, freeze the Gate C incumbent as deterministic rules when
   `rules_viable`, otherwise as the fixed explorer. Gate C randomizes its own
   participant pool between that incumbent and Gemini. Select `GENERATE` only if
   `S_gemini_C - S_incumbent_C >= delta_model`, `p_C <= 0.0125` under the frozen
   procedure on eligible target-user observations, and every live-provider
   safety, reliability, latency, cost, and evidence condition passes. If Gate C
   fails, select `RULES` only when target-user Gate B evidence established
   `rules_viable`; otherwise select `FIXED`.

Secondary usefulness, completion-time, and interaction-count results explain the
primary result but cannot override a failed primary or zero-tolerance safety
gate. Incomplete evidence selects `FIXED`.

A proxy-only campaign always records `FIXED`. It may authorize a new,
preregistered target-user campaign, but it cannot retain rules or a live provider
as a validated outcome.

`FIXED` retains the existing explorer and removes any experiment-only local
harness or projection; the proxy and live adapter remain absent or are removed.
`RULES` retains only the task-specific deterministic behavior and minimum
projection justified by held-out evidence, with no live provider path.
`GENERATE` keeps the provider-capable session projection and Gemini path private
and experimental pending a separate continuation review.

## Live-provider reliability fixtures

These fixed `orders` cases test materialization and lifecycle reliability after
the value prerequisite permits a live campaign. They do not compare product
value against the existing explorer or deterministic rules.

All runs use fixed repository fixtures and prompts. Prompt text, candidate
schema, model, temperature, output-token limit, capability set, and initial
candidate are hashed into the evidence manifest. Any change invalidates the run
set and requires restarting it.

Before collecting runs, fixed replay must materialize all three task shapes.
If any shape fails materialization, the experiment does not start.

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

## Live-provider semantic and human evaluation

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

## Live-provider metrics and evidence

Record every attempt, including failures:

- reliability fixture ID or opaque held-out task ID, predetermined slot ID, and
  every provider attempt ID;
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

## Final decision gate

The preregistered value prerequisite first selects `FIXED`, `RULES`, or
eligibility for the live Gemini campaign. An eligible campaign freezes the Gate C
incumbent from Gate B, then runs balanced, contemporaneous incumbent and Gemini
arms in its own participant pool. It also runs each reliability fixture exactly
ten times, for 30 predetermined lifecycle slots. The final decision remains due
on 2026-07-29.

Only preregistered eligible target-user observations may select `RULES` or
`GENERATE`. Proxy-only comparisons are continuation evidence and always produce
a final `FIXED` outcome, regardless of their measured uplift.

`GENERATE` requires the preregistered model uplift over the frozen incumbent and
every condition below:

- zero stale-generation commits;
- zero cancelled-generation commits;
- zero invalid-candidate commits;
- zero falsely reported failed DOM applies;
- at least 9/10 semantic task successes for each reliability fixture, hence at
  least 27/30;
- median blinded usefulness at least 4 for each reliability fixture;
- no manual candidate or prompt repair and no replacement cases or runs;
- median end-to-end latency at most 8 seconds and p95 at most 20 seconds;
- total provider cost within the preregistered campaign ceiling and no more than
  USD 5.00 for the 30 reliability slots;
- complete redacted evidence and a passing secret-leak probe.

At any gate, missing or insufficient target-user evidence selects `FIXED`. With
complete target-user evidence, failure of a Gate C value or live-provider
condition selects `RULES` only when Gate B established `rules_viable`; otherwise
it selects `FIXED`.
Record the incumbent identity, participant-population status, outcome,
comparative scores, rules gain and capture, statistical results, metric tables,
evidence path, manifest digest, and decision author in the issue by the deadline.

`FIXED` retains the existing explorer and removes any experiment-only projection,
proxy, adapter, or runtime scaffolding that lacks another accepted use.
`RULES` retains only deterministic task behavior and its required projection;
the live proxy and adapter are absent or removed. `GENERATE` permits a separately
reviewed continuation plan but leaves the adapter experimental and private.

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
- proxy selector allowlisting accepts one known reliability fixture or opaque
  held-out task, and rejects unknown IDs, both or neither selector, extra fields,
  prompts, and case data;
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

1. Independent review of this amended design against the cognition provider
   boundary and Generative UI direction.
2. Approve the target-user hypothesis, named target-user population, recruitment
   and eligibility rules, job, primary metric, decision math, development/held-
   out construction, custodian, and non-overlapping author-role access matrix.
3. Calibrate the standalone oracle pattern, deterministic rules, candidate
   schema, prompt, sample counts, win margins, model-selection procedure,
   candidate eligibility, development benchmark, settings envelope, and
   tie-breaks on development cases only.
4. Freeze and approve the initial manifest, complete statistical procedure and
   script digest, study-ID access and retention controls, model-selection
   protocol, cost ceiling, author roles, access log, and held-out set digest
   before custodian-only reveal.
5. The custodian runs Gate A. Only eligible target-user observations can satisfy
   the final oracle-uplift gate; a proxy-only pass may authorize a new target-user
   campaign but the current campaign records `FIXED`.
6. After Gate A passes, approve and implement a test-first plan for only the
   synchronous local evaluation harness and capability-bounded projection, using
   development cases only.
7. Review and freeze the harness/projection code commit, fixed-explorer version,
   rules, prompt, candidate schema, capabilities, metrics, margins, and sample
   counts before the custodian runs Gate B.
8. The custodian runs Gate B without case-level disclosure. Stop with `RULES`
   only when eligible target-user evidence establishes `rules_capture >= 0.80`
   and `rules_viable`.
9. Only after Gemini eligibility, review the frozen development-only selection
   runner and its credential controls before its first request. Execute every
   predetermined candidate slot, record failures without replacement, apply the
   frozen metric and tie-breaks, and freeze the selected versioned model and
   settings before any Gate C held-out access.
10. Freeze the Gate C incumbent identity and custodian-controlled opaque
    held-out-task allowlist digest, then approve a separate test-first plan for
    provider integration. Do not change frozen candidate semantics or use
    held-out cases during implementation.
11. Prove the provider-capable session projection with deterministic fixed
    replay, state interaction, and known-negative controls.
12. Complete implementation review and freeze the provider-integration commit,
    selected model/settings, prompt/schema digests, repeat count, cost and safety
    limits, and allowlist before the first Gate C credentialed request.
13. The custodian runs the frozen held-out Gate C incumbent and selected-model
    arms with eligible target-user participants, plus all 30 reliability slots,
    without replacement.
14. Record `FIXED`, `RULES`, or `GENERATE` and evidence digests before revealing
    held-out contents, no later than 2026-07-29.
15. If `GENERATE`, require a materially different second adapter before freezing
    any renderer-neutral provider contract or conformance suite.

## References

- [Generative UI direction](../architecture/generative-ui-direction.md)
- [Generative UI input vertical slice](2026-07-12-generative-ui-input-vertical-slice.md)
- [Cognition provider boundary design](2026-05-26-cognition-provider-boundary-design.md)
- [Gemini API overview](https://ai.google.dev/gemini-api/docs/api-overview)
- [Gemini API key security](https://ai.google.dev/gemini-api/docs/generate-content/api-key)
- [Gemini retries](https://ai.google.dev/gemini-api/docs/troubleshooting)
- [Gemini model versions](https://ai.google.dev/gemini-api/docs/models/gemini)
- [Cloudflare Agents overview](https://developers.cloudflare.com/agents/)
- [Cloudflare Workflows](https://developers.cloudflare.com/workflows/)
