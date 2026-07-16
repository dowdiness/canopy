# Generative UI local-LLM technical feasibility

- **Date:** 2026-07-15
- **Status:** Proposed
- **Decision:** `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE`
- **Scope owner:** Canopy maintainers

## Purpose

Determine whether Canopy can accept an untrusted candidate from a local LLM,
validate it fail-closed, materialize it through host-owned capabilities, and
update the committed UI without corrupting existing state.

This is an engineering feasibility study. It does not evaluate what Generative
UI product should be built, whether a generated interface is useful to people,
or whether it improves on a fixed interface. Product discovery and value
evaluation are separate later work.

## Existing foundation

The deterministic input vertical slice already establishes the request,
validation, dry-run, commit, cancellation, replay, and recovery boundaries. See
[Generative UI input vertical slice](2026-07-12-generative-ui-input-vertical-slice.md).

The architectural ownership rules remain canonical in
[Generative UI direction](../architecture/generative-ui-direction.md).

Spike 0 adds a development-only local Ollama request for one fixed pending-orders
case. Its strict recipe proves that one model response can cross the local
transport and validation boundary.

Because that recipe predetermines the filter, columns, and aggregation required
by the answer, it does not yet establish a reusable local-LLM candidate boundary.

## Feasibility question

Can the existing deterministic shell accept local-LLM candidates across
structurally different fixtures without adding model-controlled code, data,
effects, or commit authority?

A positive result requires the same candidate contract and materialization path
to work for both development-only live generation and production-safe recorded
replay. It does not require a cloud provider or a human study.

## Scope

### In

- Development-only whole-response generation through local Ollama.
- A bounded declarative recipe for read-only JSON/CSV surfaces.
- Structurally different fixtures that exercise the bounded contract without
  sharing one answer-specific recipe.
- Fail-closed syntax, schema, capability, field, and authority validation.
- A frozen fixture-specific outcome rubric evaluated after materialization.
- Host-owned filtering, projection, aggregation, query, and selection behavior.
- Candidate materialization through the existing session-owned commit boundary.
- Preservation of committed UI and host interaction state on rejection or
  failed application.
- Recorded production-demo candidates that traverse the same validator and
  materialization path without network access.
- Deterministic evidence for valid, invalid, unsupported, stale, and failed
  candidates.

### Out

- Target-user recruitment, telemetry, feedback collection, or usability claims.
- Comparison with the fixed explorer, hand-authored oracle, or deterministic
  rules.
- Gate A, Gate B, Gate C, statistical power, or preregistration.
- Gemini, another cloud provider, browser credentials, or a production proxy.
- Streaming provider output, retry policy, or provider-neutral transport.
- Arbitrary JSX, raw HTML, JavaScript, model-controlled expressions, or effects.
- Concurrent semantic editing, cross-session identity, or CRDT integration.
- A public provider API, renderer-neutral candidate contract, or second adapter.

## Responsibility boundaries

### Local provider adapter

The adapter owns only the development request, whole-response decoding, limits,
and transport failure classification. It cannot validate UI semantics, access
the DOM, mutate host state, or advance a session revision.

Each request contains only the frozen synthetic fixture rows, the fixture task,
and the candidate schema and instructions. It contains no live user or project
data. The feasibility result makes no broader privacy claim about a future
product data path.

### Candidate contract

The contract describes only allowlisted presentation and references to
host-owned capabilities. It cannot contain source data, executable expressions,
network targets, persistence commands, navigation, or arbitrary event handlers.

The schema and runtime validator must have one authoritative definition or a
complete conformance check that proves they accept and reject the same values.
The shared schema cannot encode a fixture's expected filter, columns,
aggregation, answer, or outcome rubric.

### Host capability layer

Trusted host code owns data, filtering, projection, aggregation, query, and
selection. A candidate may select an allowlisted capability and validated
parameters; host code performs the operation and owns its mutable state.

### Session projection

Only a validated candidate may reach dry-run and the existing session commit
boundary. Rejection or application failure leaves the last valid UI, host state,
and committed revision intact. Provider code cannot bypass this boundary.

### Public recorded demo

The production build contains recorded candidates and the shared deterministic
candidate path. It omits the local-provider endpoint, credential path, telemetry,
and external requests. Recorded replay executes the shared validator and
projection, and its visible result comes from that path.

## Required fixture breadth

The evidence set must contain multiple structurally different JSON/CSV shapes
and exercise distinct combinations of the bounded capabilities. Their sole
purpose is falsifying contract overfitting across technical shapes.

Validation of product use cases belongs to later product discovery. The set must
include known-negative candidates for every generic authority boundary.

Each valid fixture also has a separate frozen outcome rubric. Apply that rubric
after materialization to check whether the candidate produced the requested
technical structure and behavior. Keep the rubric outside the shared candidate
schema, prompt, and generic validator so it cannot predetermine the model output.

Fixture content, expected materialized structure, state-preservation invariants,
generic rejection outcomes, and fixture-specific rubric are fixed before judging
feasibility. A failed fixture is not replaced with an easier one.

## Local model attempt protocol

Before the first live attempt, freeze the valid fixture set, local model ID and
version, prompt digest, generation settings, limits, and exactly three attempt
slots per valid fixture.

Execute every slot once. Transport errors, malformed responses, generic
validation rejection, materialization failure, fixture-rubric failure, and
missing results remain failed slots. Do not retry, replace, edit the prompt, or
rerun a preferred result.

At least one of the three predetermined slots for each valid fixture must pass
the generic validator, materialization path, and fixture-specific outcome rubric.
Retain and report all slot classifications and the success rate.

This threshold establishes only that the frozen local model can cross the
technical boundary for each fixture. It does not establish reliability or model
quality. Changing any frozen input starts a new feasibility run.

## Acceptance criteria

Select `TECHNICALLY_FEASIBLE` only when all of the following are observed:

1. At least one of the three predetermined local Ollama slots for every frozen
   valid fixture passes generic validation, materialization, and the separate
   frozen fixture rubric through the real development adapter.
2. Every successful candidate uses only the bounded recipe and host-owned
   capabilities; no arbitrary code or generated side effect is reachable.
3. The generic validator rejects every frozen syntax, schema, capability, field,
   and authority-boundary negative fixture before commit.
4. The separate frozen fixture rubric classifies each materialized valid
   candidate without influencing the prompt, candidate schema, or generic
   validator.
5. Rejection, stale base revision, dry-run failure, and DOM application failure
   preserve the last valid UI and follow the existing dirty-state and recovery
   contracts without falsely advancing the committed revision.
6. Replaying the same successful candidate from the same base state produces the
   same modeled and visible result.
7. Frozen interaction state survives regeneration whenever the resulting
   structure still supports that state.
8. Production recorded replay traverses the shared validator and projection,
   works without network access, and exposes no provider endpoint or credential
   path.
9. Every predetermined local model slot has a terminal classification, and
   deterministic replay reproduces each returned candidate's validation,
   materialization, and fixture-rubric result.

Any missing criterion selects `NOT_YET_FEASIBLE`. A negative result identifies a
technical boundary to redesign; it does not imply that Generative UI is or is
not useful.

## Evidence and non-claims

Retain fixture digests, rubric digests, prompt digest, frozen model identity and
version, generation settings, slot IDs, every terminal classification, candidate
digests, validation and rubric results, state and revision assertions, browser
results, and end-to-end local latency. Do not collect participant data or public
telemetry.

A successful result supports only this claim:

> A local LLM can drive Canopy's bounded Generative UI candidate path across the
> frozen synthetic fixtures. Fixture data stays host-owned, and the model and
> its candidate receive no effect, DOM, mutable-state, or commit authority.

It does not support claims about usability, usefulness, adoption, task
performance, model superiority, production readiness, or a general provider or
renderer abstraction.

## Later product-discovery boundary

After technical feasibility is decided, start a separate design discussion. Ask
which Generative UI application would help which user with which job, and why a
fixed interface is insufficient.

The later discussion chooses its own evidence. It may decide that no human
experiment is needed, that one or two formative sessions are sufficient, or that
a comparative evaluation is worth the cost. This feasibility work does not
preselect that application or evaluation method.
