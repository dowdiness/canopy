# Cognition Provider Boundary Design

## Why

PR #359 added deterministic synchronous `CognitionProvider` and `ContextRanker`
seams for mock summary generation and context ranking. Those seams are useful
for tests and deterministic policy injection, but they are not a safe boundary
for real LLM or network calls: real providers are asynchronous, fallible,
cancellable, credential-bearing, rate-limited, and may complete after workspace
inputs have changed.

Design the provider boundary before implementation so future work does not
smuggle network effects into `CognitionStore` recomputation or into the current
plain callback seams.

## Status

Design shipped in PR #363 (`07d4039`). The first provider-boundary
implementation shipped in PR #379 (`e4a25fa`), adding request planning,
explicit completion, typed provider status/error handling, internal
`@incr`-assisted planning/status cells, and deterministic scripted driver tests.
Keep real provider clients, credentials, and network transport out of scope
until a separate provider-client plan names the backend and driver boundary.

## Scope

In:
- `docs/architecture/cognition-runtime.md`
- `lib/cognition/types.mbt`
- `lib/cognition/provider.mbt`
- `lib/cognition/ranker.mbt`
- `lib/cognition/store.mbt`
- `lib/cognition/reactive.mbt`
- `lib/cognition/*_test.mbt`
- `lib/cognition/README.mbt.md`

Out:
- real LLM calls
- API keys, credential storage, or provider-specific HTTP clients
- vector database integration
- frontend UI or VSCode/Cursor integration
- CRDT, parser, projection, or rendering changes
- moving the existing file/repo/context recomputation graph wholesale into
  `@incr` artifact cells
- path canonicalization or rename semantics
- performance optimization without fresh measurement

## Current State

- `CognitionStore` owns artifact values, revisions, dependencies, dirty state,
  recompute counts, workspace-file lifetime, and metadata snapshots.
- `CognitionProvider` is a deterministic synchronous policy struct with
  `file_summary` and `repo_summary` callbacks. It produces values only and does
  not own graph state.
- `ContextRanker` is a deterministic synchronous policy struct for scores and
  inclusion reasons.
- Packed context is stored as `ContextItems` artifacts with source keys,
  source revisions, payloads, and inclusion reasons.
- The graph is manually dynamic, not purely static: recomputation replaces a
  key's dependency set, file removal drops deleted-file edges, and packed
  context dependencies can change when ranking or budgets select a different
  file-summary set. The store does not yet keep dependency-edge operations as a
  durable history, and artifact recomputation is not `@incr` cell-driven.
- PR #360 made context packing reuse clean cached `ContextItems` and made
  `pack_context_with_stats` derive telemetry from the stored artifact instead
  of rerunning selection.
- Architecture docs explicitly say no real LLM, network, vector DB, frontend, or
  agent framework exists yet.

## Desired State

A future implementation should have a boundary that separates deterministic graph
ownership from effectful provider execution:

1. `CognitionStore` remains synchronous and deterministic. It may plan provider
   work, store provider results, and validate source revisions, but it must not
   execute network calls during recomputation.
2. Provider calls are modeled as external effects with graph-visible inputs and
   completion artifacts. The request and result are part of the cognition graph;
   the network call itself is not.
3. Every provider request carries enough provenance to reject stale completions:
   target artifact, selected context items, source revisions, model/options, and
   a stable request id or idempotency key.
4. Async execution, retries, cancellation, credential access, and rate limiting
   live in a provider driver outside `CognitionStore`.
5. Tests use deterministic scripted providers, fake cancellation, and fake time;
   no test performs network I/O.

## Dynamic Dependency Discipline

Provider requests must snapshot the dependency set observed at planning time, not
just the source revisions. A completion is stale if any planned dependency is
removed, any source revision changes, or recomputation would select a different
set of context inputs for the same target. This matters for packed context, where
the selected `FileSummary` dependencies are query/ranker/budget-dependent.

For this provider-boundary step, keep dependency-edge changes as explicit store
state updates. Do not introduce a durable operation log for dependency edits or
migrate artifacts into `@incr` cells unless a separate plan owns that lifecycle
and test matrix. If dependency operations become first-class later, model edge
add/remove/invalidate operations as data and replay them through the same stale
completion checks.

A future durable dependency-history plan should specify operation variants,
idempotency, replay order, compaction/discard rules, and deletion tombstone
semantics before implementation. Provider completion should validate against the
materialized graph state, not against an unbounded historical log.

## Migration Hooks

Leave migration room without committing to a new recomputation engine:

- keep provider request descriptors independent of the current `Map`-backed edge
  storage so an `@incr` artifact-cell spike can preserve the request/completion
  contract;
- keep all dependency mutation behind store APIs rather than exposing maps or
  reverse-edge internals;
- require lifecycle tests for request cancellation, deleted files, stale queries,
  and pending completions before moving provider artifacts into `@incr` cells;
- require fresh measurement before changing recomputation strategy for
  performance reasons.

Do not add public `@incr`-specific types or placeholder hooks to this boundary
just to reserve space. The stable seam should be request planning, explicit
completion, and source/dependency validation.

## What Belongs to `@incr` vs. the Provider Boundary

Some of the hard pieces should be implemented with `@incr`, or eventually live
in an effect layer built on top of `@incr`. They should not be hidden inside
provider callbacks or treated as provider-client behavior.

| Concern | `@incr` role | Provider-boundary role |
| --- | --- | --- |
| Request identity | Can derive stable request descriptors from graph inputs and options. | Defines domain idempotency: target key, task kind, provider/model/options fingerprint, and context provenance. |
| Source revision / dependency snapshot | Can discover dependencies inside tracked request-planning computations and can invalidate derived descriptors when inputs change. | Persists the source revisions and dependency-set fingerprint needed to reject late completions without depending on private `@incr` internals. |
| Cancellation | Can model cancellation intent as an input/status cell and invalidate dependent planning state. | Cancels in-flight external work, records cancelled/stale status, and preserves the last clean accepted artifact. |
| Retry / error classification | Can cache and propagate typed status values once represented as data. | Owns provider-specific retry policy, redaction, rate-limit interpretation, and transport error mapping. |

So the decision is not "avoid `@incr`". The decision is: do not make real
provider execution an `@incr.Derived` body, and do not require callers to know
`@incr` internals to validate provider completions.

An `@incr`-first artifact graph would add lifecycle work that must be designed
explicitly:

- one keyed cell family per file, query, packed context, and provider request;
- disposal semantics for removed files, abandoned queries, and cancelled
  requests;
- persistent `Watch`/scope ownership for any long-lived request-planning cells;
- translation back to the domain dependency edges exposed by `CognitionStore`;
- a hard rule that no network call runs inside a `Derived` closure.

Decision for this plan: the first provider-boundary implementation should use
`@incr` internally for pure request planning and status derivation, while keeping
the request/completion contract engine-agnostic and keeping effect execution
outside the reactive graph.

## Recommended V1: `@incr`-Assisted Planning and Status

Use `@incr` where it is strongest: deriving stable data from changing graph
inputs. Keep the public boundary and completion validation as ordinary domain
values.

Internal shape:

- Inputs: prompt/task request, provider/model/options fingerprint,
  cancellation intent, completion/error records, and fake time for tests.
- Derived values: planned provider request descriptor, dependency-set
  fingerprint, visible request status, retry classification, and next driver
  action.
- Anchors: long-lived planning/status cells owned by a `Scope` and held through
  `Watch` values so `Runtime::gc()` cannot sweep request-planning state.
- Store APIs: explicit plan/read, cancel, and complete operations. Completion
  remains a store operation that validates the request id, option fingerprint,
  source revisions, and dependency-set fingerprint.
- Driver: reads watched request/status values outside the graph and starts,
  cancels, retries, or completes external work. The driver never runs provider
  transport inside a `Derived` closure.
- Read discipline: pure planning/status `Derived` bodies read `Input` cells with
  `.get()` and upstream `Derived` cells with `.get_or_abort()` unless they
  intentionally handle cycle results; driver, store APIs, and tests read from
  outside the graph through persistent `Watch` handles.

This gives cancellation and retry state a reactive representation without making
network I/O part of recomputation. It also lets a later artifact-cell migration
preserve the same request/completion tests.

## Responsibility Map

Before adding types, verify the existing store responsibilities and classify each
provider-related value as one of three categories:

| Surface | Owns | Must not own |
| --- | --- | --- |
| `CognitionStore` | request descriptors, pending/done/error status, accepted or stale completion records, source-revision checks, dependency edges, last clean artifact values | HTTP clients, credentials, timers, retry loops, background tasks |
| Provider driver | async scheduling, cancellation tokens, timeout/retry policy, rate-limit handling, credential lookup and redaction, fake time in tests | direct graph mutation outside explicit store APIs, dependency policy |
| Provider client | provider-specific transport, request encoding, response decoding | `CognitionStore` internals, workspace graph state |
| Tests | scripted responses, fake cancellation, fake retry timing, stale-completion scenarios | real network I/O or real credentials |

The store may record that work is pending or failed, but the driver decides when
to execute, retry, cancel, or abandon a request.

## Boundary Shape

### Request planning

Add a graph-facing request descriptor before any real client:

- request id / idempotency key,
- target cognition key,
- prompt or task kind,
- packed context items with source revisions,
- provider id plus model/options that are safe to store,
- dependency keys observed when the request was planned.

Planning is synchronous and deterministic. Re-planning the same clean request
should reuse the existing request descriptor unless an input revision, prompt,
model option, or budget changes.

### Provider options schema

Separate provider-agnostic fields from provider-specific options. Stable shared
fields may include task kind, model id, output budget, and context budget only if
their meaning is consistent across providers. Provider-specific options should be
wrapped under a provider id and stored only when they are safe, deterministic,
and redacted. Secrets, tokens, and endpoint credentials are driver state, never
request-descriptor state.

Changing any stored option that can affect the response must change request
identity. If an option cannot be safely stored, store a stable redacted label or
digest for provenance and keep the secret value in the driver.

### Effect execution

A separate provider driver consumes request descriptors and performs the effect.
The driver owns:

- async scheduling,
- cancellation tokens,
- timeout and retry policy,
- credentials and redaction,
- provider-specific transport and response decoding.

Do not put credentials or HTTP clients inside `CognitionStore`, `CognitionKey`,
or stored `CognitionValue` payloads.

### Completion

Provider completion should be an explicit store operation, not a callback that
mutates graph state from inside recomputation. Completion validates:

- request id exists and is still pending,
- source revisions still match the planned request,
- target key is still live,
- response is within configured size/budget limits,
- provider errors are typed and safe to persist.

If source revisions no longer match, reject or record the completion as stale;
do not overwrite a newer artifact.

## Async Semantics

- Store methods stay synchronous.
- Effect drivers may be `async fn` or host-callback based, depending on target
  backend, but the async surface must be outside the store.
- Cancellation is request-scoped. Cancelling a request must not delete the last
  clean successful artifact for the same target.
- Shutdown cancellation should leave pending requests observable but not
  completed.
- A dirty dependency should make in-flight requests stale unless the design
  explicitly supports revision-rebased completion.

## Error Semantics

Use typed provider errors before adding transport code. Candidate categories:

- `Cancelled`
- `Timeout`
- `RateLimited(retry_after?)`
- `Auth`
- `Network`
- `InvalidRequest`
- `ProviderRejected`
- `Decode`
- `BudgetExceeded`
- `StaleCompletion`

Each error should carry an explicit retry/availability classification rather than
forcing callers to infer behavior from variant names or display text:

- retryable later: timeout, network, rate limit;
- terminal until configuration changes: auth, invalid request, unsupported model;
- terminal for this request but not for future requests: provider rejected,
  budget exceeded, decode failure;
- caller-initiated: cancelled;
- graph-consistency rejection: stale completion.

Errors must not include secrets. Retries belong to the driver, not to store
recomputation. The store may persist a redacted error status for provenance and
UI/debugging, but it must not schedule retries itself.

## Deterministic Tests

Before real provider clients exist, add test doubles that can prove the boundary:

- scripted success/error responses keyed by request id,
- fake cancellation before and during completion,
- stale completion after a file edit is rejected,
- repeated clean reads do not re-plan or re-run requests,
- retry decisions are deterministic under fake time,
- errors are stored or surfaced without credentials,
- provider result completion preserves dependency edges and source revisions.

Start with a deterministic sequence matrix: plan request, edit file, remove file,
change budget/ranker selection, cancel request, complete stale request, complete
fresh request. Property-based add/edit/remove/plan/complete sequences can follow
once the deterministic matrix is stable. If generators are added, they must crash
on invalid generated states rather than silently skip them.

## Candidate Type Sketch

Names are illustrative; the first implementation should refine them before
landing public API:

```mbt nocheck
struct ProviderSourceSnapshot {
  key : CognitionKey
  revision : Revision
}

struct ProviderRequest {
  id : ProviderRequestId
  target : CognitionKey
  task_kind : String
  provider_id : String
  model_id : String
  options_fingerprint : String
  context : Array[ContextItem]
  source_revisions : Array[ProviderSourceSnapshot]
  dependencies : Array[CognitionKey]
  dependency_fingerprint : String
}

suberror ProviderError {
  Cancelled
  Timeout
  RateLimited(retry_after_ms? : Int)
  Auth
  Network(String)
  InvalidRequest(String)
  ProviderRejected(String)
  Decode(String)
  BudgetExceeded
  StaleCompletion
}
```

Do not treat this sketch as final syntax or final public API. Its purpose is to
force the design to name request identity, option provenance, context revisions,
and typed failures before transport code exists.

## Implementation Steps

Recommended PR slicing:

1. Retarget the active TODO from design drafting to boundary implementation.
2. Add pure domain types for request descriptors, result descriptors,
   cancellation handles, option provenance, dependency fingerprints, typed
   provider errors, and retry/status classification. Keep this PR free of driver
   scheduling and network code.
3. Add request planning, cancellation, and explicit completion APIs. Completion
   must validate request id, option fingerprint, source revisions, and
   dependency-set fingerprint.
4. Add stale-completion tests for file edits, file removal, context budget/ranker
   selection changes, user cancellation, and driver shutdown semantics.
5. Add deterministic data types plus an internal `@incr` planning/status graph:
   inputs for request intent, cancellation, completion/error records, and fake
   time; derived cells for request descriptors, dependency fingerprints, status,
   retry classification, and next driver action.
6. Add `Scope`/`Watch` lifecycle tests for long-lived keyed request-planning
   cells before exposing any driver surface.
7. Add a scripted provider driver test harness with no HTTP client.
8. Update architecture and README examples to show the boundary and reiterate
   that current synchronous provider/ranker callbacks remain deterministic
   policy seams.
9. Only after the boundary tests pass, open a separate provider-client plan for a
   specific backend/provider.

## Acceptance Criteria

- [ ] A design/implementation plan specifies whether each provider-related value
      is a graph artifact, an external effect, or transient driver state.
- [ ] The plan includes a responsibility map for store, driver, provider client,
      and tests.
- [ ] Provider options are split into provider-agnostic stored fields,
      provider-specific redacted fields, and driver-only secret state.
- [ ] Async shape is explicit and keeps `CognitionStore` synchronous.
- [ ] Cancellation behavior covers user cancel, dependency dirtying, and driver
      shutdown.
- [ ] Provider errors are typed, retry classification is explicit, and secret
      redaction is part of the contract.
- [ ] Stale completion behavior is specified with source-revision and dependency
      set checks.
- [ ] Durable dependency-history and `@incr` artifact migration are explicitly
      either out of scope or owned by separate plans with replay/lifecycle tests.
- [ ] Public request/completion APIs remain ordinary domain values; no `@incr`
      handle types leak into the provider-boundary contract.
- [ ] Internal `@incr` request-planning/status cells keep provider execution
      outside `Derived` closures and include `Scope`/`Watch` lifecycle tests for
      keyed request cells.
- [ ] Deterministic test doubles and a sequence matrix are specified before any
      network client.
- [ ] Current `CognitionProvider` / `ContextRanker` synchronous seams are not
      repurposed for network calls.
- [ ] No real LLM, network, vector DB, frontend, CRDT, parser, projection, or
      rendering scope enters this step.

## Validation

For the design-only PR:

```bash
git diff --check
```

For the first implementation PR that changes `lib/cognition`:

```bash
moon -C lib/cognition check --deny-warn
moon -C lib/cognition test
moon check
moon test
moon info
```

## Risks

- Treating provider calls as ordinary recomputation would make cache reads
  perform network I/O and make cancellation ambiguous.
- Storing credentials or raw provider responses in graph artifacts can leak
  secrets through debug output or tests.
- Completing stale requests without source-revision validation can overwrite a
  newer artifact with obsolete context.
- Over-designing provider-specific HTTP behavior before the boundary is pinned
  can couple the runtime to one vendor.

## Notes

Related shipped work:

- PR #358 (`4c5e0bb`) cleaned deleted-file dependency edges and pinned graph
  invariants.
- PR #359 (`83d6e8a`) added deterministic provider/ranker seams and
  provenance-packed context.
- PR #360 (`9f228fa`) made packed-context reads reuse cached clean artifacts.
- PR #361 (`5468c9c`) archived the recompute cleanup plan and made this design
  the active cognition TODO.
