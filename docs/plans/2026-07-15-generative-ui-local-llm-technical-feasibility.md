# Generative UI local-LLM technical feasibility

- **Date:** 2026-07-15
- **Status:** Executed
- **Decision:** `NOT_YET_FEASIBLE`
- **Scope owner:** Canopy maintainers

## Purpose

Determine whether Canopy can accept an untrusted candidate from a frozen local
LLM, interpret it once inside MoonBit, materialize it through host-owned
capabilities, and update the committed UI without corrupting existing state.

This is an engineering feasibility study. It does not evaluate what Generative
UI product should be built, whether a generated interface is useful to people,
or whether it improves on a fixed interface. Product discovery and value
evaluation are separate later work.

## Result

- **v2 decision:** The corrected frozen study at commit `e93c5cc7` selected
  `NOT_YET_FEASIBLE`.
- **v2 preflight:** Seven deterministic validation commands and the frozen
  model-identity check passed after validation-child environment isolation.
- **v2 provider boundary:** All nine scheduled attempts terminated as
  `provider_http_error` after Ollama returned HTTP 500. No candidate reached
  MoonBit preparation, no slot was retried, and no candidate bytes were
  retained in the final evidence.
- **v2 interpretation:** The harness correction succeeded, but the selected
  local model and frozen request settings did not produce any candidate. The
  study therefore establishes neither end-to-end technical feasibility nor
  candidate quality, usability, or product value.
- **v2 retained evidence:** The frozen manifest and aggregate evidence remain
  immutable and must not be rerun, replaced, or overwritten. The ignored
  journal and raw-slot archive were validated after execution but were later
  deleted when Playwright cleaned `examples/web/test-results`. They were not
  reconstructed. The retention incident is recorded in
  `docs/evidence/2026-07-16-generative-ui-local-llm-feasibility-v2-retention-incident.json`.
  The aggregate evidence supports the conservative decision, but v2 is no
  longer independently auditable from raw execution artifacts.
- **Preserved v1 result:** The frozen v1 study at commit `3263c714` also
  selected `NOT_YET_FEASIBLE`. Four deterministic checks passed, but the
  development E2E check failed because its Vite process inherited study mode
  before an ephemeral run capability existed. No v1 provider request occurred;
  all nine v1 slots were classified as `not_run_preflight_failure`.
- **v1 interpretation:** The v1 result identifies the corrected live-harness
  environment-isolation defect and provides no evidence about `gemma4:e2b`
  candidate quality or local-model feasibility. Its manifest, journal, and
  evidence remain immutable.

## Approved v2 harness correction

The v2 runner isolates each validation child from ambient study state. It
constructs the child environment in this order:

1. Copy the parent environment.
2. Remove every inherited key whose name starts with
   `GENUI_FEASIBILITY_`.
3. Overlay the validation command's explicit manifest environment.

The final overlay is authoritative. A manifest may deliberately set a reserved
study key, and that value must reach the child process. This ordering prevents
an inherited live-study flag from changing deterministic preflight behavior
without silently defeating explicit manifest configuration.

The runner receives regression contracts before implementation. Two pure tests
prove that inherited reserved keys are absent, unrelated parent keys remain
available, and an explicitly declared reserved key survives with its manifest
value. A wiring test invokes `runDeterministicPreflight` with an injected plain
parent environment and a real Node child. The child must observe explicit
`GENUI_FEASIBILITY_LIVE=0`, no inherited run capability, and the unrelated
parent key. Production defaults the injected parent environment to
`process.env`; tests never mutate that global object.

The v1 manifest, journal, and evidence remain immutable. After the correction
passes focused and workspace verification, execution uses a new v2 manifest,
journal, raw-output path, evidence path, and frozen implementation commit. The
v2 manifest records environment isolation as its changed-input reason. The
frozen v2 run remains one-shot and retains the original acceptance rule: any
missing criterion selects `NOT_YET_FEASIBLE`.

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
effects, interpretation, or commit authority?

A positive result requires the same MoonBit candidate interpretation and
materialization core to serve development-only live generation and
production-safe recorded replay. It does not require a cloud provider, generated
interaction state, or a human study.

## Scope

### In

- Development-only whole-response generation through local Ollama.
- A bounded declarative recipe for read-only JSON/CSV surfaces.
- Structurally different fixtures that exercise the bounded contract without
  sharing one answer-specific recipe.
- Trusted fixture-specific normalization into one bounded dataset format.
- Fail-closed syntax, schema, capability, field, and authority validation.
- A single MoonBit interpretation of every candidate-selected binding, field,
  operator, aggregation, and presentation node.
- MoonBit-owned filtering, projection, aggregation, safe-output construction,
  and generic evidence production.
- A frozen fixture-specific outcome rubric evaluated after materialization.
- Candidate commit through the existing session-owned dry-run, DOM, and revision
  boundary.
- Preservation of the last valid committed UI and unrelated host interaction
  state on rejection or failed application.
- Recorded production-demo candidates that traverse the same validation,
  materialization, rubric, and commit path without network access.
- Deterministic evidence for valid, invalid, unsupported, stale, interrupted,
  drifted, and failed candidates.

### Out

- Generated query state, generated selection state, or interaction-state
  migration between successful generated outputs.
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

### Trusted fixture ingestion

Fixture-specific trusted host adapters parse the frozen JSON array, nested JSON,
and restricted CSV inputs.

They normalize those sources into the exact
`schema_version: 1` dataset object with these fields, in this order:
`schema_version`, `case_id`, `source_format`, `binding`, `selection_key`,
`fields`, `rows`, and `task_value`. `source_format` is exactly `json-array`,
`json-nested-items`, or `restricted-csv`.

`fields` is an ordered array of unique field names, including `selection_key`.
Each row is `{ stable_key, values }`.

`stable_key` is a non-empty string, and `values` is an ordered array of
two-element `[field, scalar]` pairs containing every declared field exactly once
and in `fields` order.

The row value for `selection_key` must be a string
exactly equal to `stable_key`. This pair-array representation keeps duplicate
row fields observable at the MoonBit boundary.

A scalar uses its native JSON string, finite number, boolean, or null variant.
Number lexical spelling is not identity: MoonBit decodes numbers to finite
`Double` values and deterministically re-encodes them without retaining the
input token spelling.

The trusted adapter and MoonBit decoder reject missing or extra fields,
duplicate field names or stable keys, and empty stable keys.

They also reject a missing or non-string `selection_key` value, disagreement
between that value and `stable_key`, non-finite numbers, unsupported nested
values, and row or field order disagreement.

Capabilities must expose exactly one binding. Its field and selection key
allowlists must equal the dataset declarations.

The trusted adapter does not parse,
inspect, validate, or act on the provider candidate. CSV syntax remains an
ingestion concern rather than a new candidate-interpreter concern.

### Local provider adapter

The adapter owns only the development request, whole-response envelope, limits,
model-identity checks, and transport failure classification. It cannot validate
UI semantics, interpret candidate fields or operations, access the DOM, mutate
host state, or advance a session revision.

Each request contains only the frozen synthetic fixture rows, fixture task,
candidate schema, and instructions. It contains no live user or project data.
The feasibility result makes no broader privacy claim about a future product
data path.

Normal development and production builds expose recorded controls only. The live
provider endpoint exists only in an explicit study mode and accepts requests
from the frozen runner through an ephemeral run capability.

### Candidate trust boundary

The provider contract describes only allowlisted presentation and references to
host-owned capabilities. It cannot grant network, persistence, navigation,
arbitrary event, DOM, expression, or commit authority.

MoonBit is the sole candidate parser, validator, and semantic interpreter. Raw
provider JSON crosses into one MoonBit validate-and-materialize operation. No
JavaScript stage reparses the candidate or independently selects a binding,
field, operator, aggregation, or presentation meaning.

The provider JSON Schema is only a generation aid and may be narrower than the
MoonBit validator, which rejects any disagreement at runtime. The schema and
prompt must not encode a fixture's expected filter, columns, aggregation,
answer, matched keys, or outcome rubric.

The runtime validator rejects duplicate attribute names on every raw component
before interpreting any `data`, `selection`, `field`, `operator`, `aggregation`,
`label`, or `value` attribute. A duplicated allowlisted attribute is invalid,
not a first-value or last-value override.

### MoonBit materialization core

After validation, a pure MoonBit core consumes the opaque validated candidate,
host capabilities, normalized dataset, and host-owned task value. It performs
the candidate-selected filter, projection, and aggregation exactly once.

The only materializable provider topology is a root `Stack` with exactly two
direct children in order: one `Text` title and one `Table`.

No provider `Panel` or nested `Stack` is accepted. The `Table` has exactly two to four unique direct
`Column` children followed by exactly one direct `Filter` and exactly one
direct `Summary`. Any missing, duplicated, reordered, nested, or extra node is a
generic materialization failure.

The core returns an internal prepared value containing generic evidence and an
opaque validated safe-output candidate. It does not read the DOM, session,
revision, provider, clock, filesystem, or rubric expectations.

The safe output contains a root `Stack`, the provider title as its first typed
`Text`, one `Panel` per matched row in source order, and one final summary
`Text`. Each panel contains one `Text` per projected column in candidate order,
formatted as `label: scalar`, where `label` is the candidate label or field
name.

The summary is formatted as `aggregation field: scalar`, using the canonical
`count`, `sum`, `average`, `minimum`, or `maximum` name.

Scalar text
is the original string, `Double::to_string`, lowercase boolean, or `null`.
Every numeric aggregate is checked after evaluation; a non-finite result is a
generic materialization failure before evidence or safe-output construction.
Only an empty numeric input set produces a null summary value.

Model text and host data remain typed text values. The core synthesizes no HTML,
expression, URL, event handler, query state, or selection state.

The safe-output projection JSON is the compact object tree
`{ "type": "stack", "children": [...] }`; text nodes contain exactly `type` and
`value`, and panel nodes contain exactly `type` and `children`, in that field
order.

Its child order is the safe-output order above.

The safe-output digest is the lowercase SHA-256 hex digest of that compact
JSON's UTF-8 bytes.

The same
in-memory safe tree produces both this JSON and the raw Stack/Panel/Text tree
that is revalidated with empty capabilities, so hashing cannot describe a
different output.

Generic evidence uses `schema_version: 1` and records fields in this order:
`schema_version`, `case_id`, `source_format`, `binding`, `filter`,
`projected_fields`, `matched_stable_keys`, `summary`, and
`safe_output_sha256`.

`filter` contains `field`, canonical `operator`, and the
native JSON scalar task `value`; `projected_fields` preserves candidate order;
`matched_stable_keys` preserves source order; and `summary` contains `field`,
canonical `aggregation`, and a native JSON scalar or null `value`. It contains
no expected rows, expected aggregate, or fixture-specific pass/fail judgment.

### Fixture rubric

Each frozen case owns a separate pure rubric. The rubric consumes generic
evidence only and returns pass/fail reasons. It cannot alter evidence, construct
a candidate, invoke a provider, access source rows, or commit a session.

Only a rubric-passing prepared value may reach dry-run and commit. A task-wrong
candidate may pass generic validation and materialization, but it must fail at
this separate boundary.

### Session shell

The existing session shell remains the only owner of dry-run, DOM application,
recovery, and committed revision changes. The recorded replay path and
feasibility path share the same private operation that accepts an already
validated candidate and performs the session transaction.

Evaluate-only feasibility execution creates no session and advances no revision.
Evaluate-and-commit uses the same pure preparation core, then passes the internal
safe-output candidate directly to the existing transaction. It never
serializes the raw provider candidate for another interpreter.

Generic rejection, materialization failure, rubric failure, stale revision,
dry-run failure, or DOM application failure leaves the last valid UI, unrelated
host state, and committed revision intact.

### Public recorded demo

The production build contains recorded control candidates, frozen fixture
normalizers, and the shared deterministic MoonBit path. It omits the live
provider endpoint, study capability, model setting, prompt transport, telemetry
collector, and external requests.

Recorded replay executes the shared validation, materialization, rubric, and
session transaction. Its visible result must come from that path rather than
from embedded expected output.

## Required fixture breadth

The evidence set contains multiple structurally different JSON/CSV shapes and
exercises distinct combinations of the bounded capabilities. Their sole purpose
is falsifying contract overfitting across technical shapes.

Validation of product use cases belongs to later product discovery. The set
includes known-negative candidates for every generic authority boundary.

Each valid fixture has a separate frozen outcome rubric. The rubric runs after
materialization to check whether the candidate produced the requested technical
structure and result. It remains outside the shared candidate schema, prompt,
validator, normalized dataset, and generic materializer.

Fixture content, normalized dataset shape, capabilities, task values, expected
materialized structure, generic rejection outcomes, and fixture-specific rubric
are fixed before judging feasibility. A failed fixture is not replaced with an
easier one.

## Frozen study manifest

Before the first generation request, a versioned manifest freezes:

- the valid fixture set and ordered three-slot schedule per fixture;
- fixture, normalization-contract, candidate-schema, prompt, and rubric digests;
- the mutable lookup tag, model-manifest SHA-256 digest, and canonical digest of
  the complete relevant `/api/show` identity payload;
- the Ollama version and separate digests of effective model template and
  parameters;
- every explicit generation setting, seed, timeout, and size limit;
- terminal classifications, replay comparison, and final decision rules.

Model discovery and identity checks do not generate candidates. The runner binds
the committed manifest digest to a clean implementation Git revision in the run
evidence, avoiding a self-referential commit field inside the manifest.

Any change to the implementation, fixture, normalizer, capability manifest,
prompt, schema, rubric, model content, Ollama version, effective model
parameters, generation settings, schedule, or decision rule creates a new
versioned study. It does not amend or resume the frozen run.

## Local model attempt protocol

The study runner uses a fresh development server, one browser worker, no test
retry, and an ephemeral run capability. The live endpoint rejects an invalid
capability, unknown study, unknown case, unknown slot, or duplicate slot before
provider access.

Before each provider call, the runner appends a `started` entry for that slot to
a local study journal. The slot then receives exactly one provider request.
Transport errors, timeouts, aborts, malformed responses, validation rejection,
materialization failure, rubric failure, commit failure, and missing results
remain failed terminal slots.

After a process interruption, a separate provider-disabled finalizer reopens the
journal.

It classifies a trailing `started` slot as `interrupted` and every
later unstarted slot as `not_run_interrupted`, then emits complete terminal
evidence and a `NOT_YET_FEASIBLE` decision. The finalizer has no endpoint or run
capability and cannot contact the provider.

The runner does not retry interrupted or unstarted slots. Existing journal or
evidence for the same study ID prevents another execution. A new attempt
requires a new versioned manifest and an explicit changed-input reason.

For every returned candidate, the runner retains the raw response in an ignored
local artifact, records its digest, and performs the real evaluate-and-commit
path once. It then resets to the same baseline and performs provider-free
evaluate-only replay from the exact saved candidate bytes.

The preparation classification covers candidate decode, validation,
materialization, and rubric outcome. Both executions must agree on it, generic
evidence, rubric result, and safe-output digest.

The evaluate-and-commit session outcome is recorded separately and is not part
of replay equality. A preparation mismatch becomes `replay_mismatch`; the
provider is not called again.

The runner verifies the model-manifest and `/api/show` identity digests, Ollama
version, effective template, and effective parameters before the first slot,
immediately before and after every request, and after the final slot.

The tag is
lookup metadata, not identity. Drift rejects any in-flight result and terminates
the remaining schedule as failed without further provider access.

For each valid fixture, at least one of the three predetermined slots must pass
the generic validator, MoonBit materialization core, fixture-specific rubric,
session transaction, and offline replay comparison. The evidence reports every
slot classification and the resulting success rate.

This threshold establishes only that the frozen local model can cross the
technical boundary for each fixture. It does not establish reliability or model
quality.

## Acceptance criteria

Select `TECHNICALLY_FEASIBLE` only when all of the following are observed:

1. At least one of the three predetermined local Ollama slots for every frozen
   valid fixture passes MoonBit validation, materialization, the separate frozen
   rubric, session commit, and offline replay through the real development
   adapter.
2. MoonBit is the only interpreter of raw provider candidates. Trusted host
   ingestion normalizes fixture data but never parses or acts on candidate
   semantics.
3. Every successful candidate uses only the bounded recipe and host-owned
   capabilities; no arbitrary code or generated side effect is reachable.
4. The generic validator rejects every frozen syntax, schema, capability, field,
   and authority-boundary negative before materialization or commit.
5. The generic materializer performs filter, projection, aggregation, and safe
   output construction without consulting case-specific expected results.
6. The separate frozen fixture rubric classifies generic evidence without
   influencing the prompt, provider schema, validator, normalized dataset, or
   materializer.
7. Rejection, stale base revision, dry-run failure, and DOM application failure
   preserve the last valid UI and unrelated fixed-explorer/source-editor state
   without falsely advancing the committed revision.
8. Evaluate-only and evaluate-and-commit use the same pure preparation core and
   produce the same preparation classification, generic evidence, rubric result,
   and safe-output digest from the same candidate bytes. Stale-revision,
   dry-run, DOM, and commit outcomes remain separate session results.
9. Production recorded replay traverses the shared validation, materialization,
   rubric, and session path, works without network access, and exposes no live
   endpoint, run capability, model setting, or provider marker.
10. Every predetermined slot has one terminal classification, no slot is retried
    or replaced, and a started but incomplete slot remains an interrupted
    failure.
11. The model-manifest and `/api/show` identity digests, Ollama version,
    effective model template and parameters, generation settings, frozen
    manifest, and implementation revision remain unchanged across the run.

Any missing criterion selects `NOT_YET_FEASIBLE`. A negative result identifies a
technical boundary to redesign; it does not imply that Generative UI is or is
not useful.

## Evidence and non-claims

Retain:

- Frozen manifest and implementation digests.
- Fixture, normalizer, schema, prompt, and rubric digests.
- Model lookup tag, model-manifest digest, `/api/show` identity digest, Ollama
  version, and effective model-configuration digests.
- Generation settings, slot IDs, and every terminal classification.
- Candidate, generic-evidence, rubric-result, and safe-output digests.
- Preparation classifications, replay comparisons, session outcomes, and state,
  revision, browser, and end-to-end latency results.

Raw candidate responses and fixture rows remain in ignored local study artifacts
and are not committed as evidence. Do not collect participant data, public
telemetry, credentials, environment dumps, or private user data.

A successful result supports only this claim:

> A frozen local LLM can drive Canopy's bounded Generative UI candidate path
> across the frozen synthetic fixtures. MoonBit alone interprets each untrusted
> candidate, host-owned data operations produce an inert output, and the model
> and candidate receive no effect, DOM, mutable-state, or commit authority.

It does not support claims about generated query or selection state, interaction
state migration, usability, usefulness, adoption, task performance, model
superiority, production readiness, or a general provider or renderer
abstraction.

## Later product-discovery boundary

After technical feasibility is decided, start a separate design discussion. Ask
which Generative UI application would help which user with which job, and why a
fixed interface is insufficient.

The later discussion chooses its own evidence. It may decide that no human
experiment is needed, that one or two formative sessions are sufficient, or that
a comparative evaluation is worth the cost. This feasibility work does not
preselect that application or evaluation method.
