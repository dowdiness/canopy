# Generative UI provider comparison design

**Date:** 2026-07-15
**Status:** Approved
**Depends on:** PR #902, merged as `1ee60dfd`
**Issue:** #896

## Purpose

The local-LLM feasibility study proved the deterministic candidate preparation,
materialization, rubric, replay, and session-commit path. It did not produce a
candidate: all nine corrected v2 slots ended at `provider_http_error` after
Ollama returned HTTP 500.

The immediate question is causal and technical, not whether Generative UI has
user value. The experiment holds the downstream candidate pipeline fixed while
changing the provider path. It asks:

1. Why did the frozen Ollama request return HTTP 500, and can a working local
   request be established without rewriting the candidate pipeline?
2. Can a Codex App Server path traverse that same pipeline when the Ollama path
   cannot?
3. If both paths are runnable, how reliably and quickly do they produce
   candidates that pass the same MoonBit rubric at one recorded point in time?

This separates an Ollama runtime, request, model-capability, or latency failure
from a shared pipeline failure. The Codex synthetic smoke runs independently of
Ollama qualification. If Ollama remains unavailable, a preregistered Codex-only
cohort still runs against the same frozen fixtures and MoonBit rubric. A matched
reliability and latency comparison runs only when both paths are operational.

The result is an engineering provider benchmark. It does not establish that
Generative UI is useful, that either model is intrinsically better, or that a
hosted model slug identifies immutable weights.

## Prior evidence remains immutable

The following evidence is not rerun, replaced, or reinterpreted:

- `genui-local-llm-v1` selected `NOT_YET_FEASIBLE` because preflight failed.
- `genui-local-llm-v2` selected `NOT_YET_FEASIBLE` after nine Ollama HTTP 500
  responses.
- The v2 raw-artifact retention incident remains recorded separately.

The diagnostic and comparison use new study IDs, manifests, schedules, output
paths, and evidence files. A later success does not alter either prior result.

## Value gate

- **Consumer:** the Canopy maintainer deciding whether provider-backed candidate
  generation merits another technical iteration.
- **Primary signal:** fixture-specific and overall MoonBit rubric pass rate.
- **Secondary signals:** preparation classification, latency, token usage,
  replay equality, identity drift, tool-use violations, and auditability.
- **Lifecycle:** removable engineering experiment.
- **Decision:** qualify zero, one, or both provider paths for further technical
  work. Qualification does not authorize Gate A user research or a product
  provider API.

## Non-goals

This work does not add:

- public or provider-neutral runtime APIs;
- browser credentials or browser-direct model calls;
- arbitrary prompt execution;
- streamed candidate commits;
- retries or replacement slots;
- multi-turn provider sessions;
- user telemetry, participant recruitment, or usability claims;
- a claim of statistical superiority from 30 observations per provider;
- a claim that `gpt-5.6-luna` is weight-frozen or reproducible indefinitely.

## Decision summary

The investigation has four gates:

1. Diagnose the Ollama HTTP 500 outside any scored schedule.
2. Independently prove the Codex adapter and external sandbox with one synthetic
   smoke request, even if Ollama never qualifies for comparison.
3. Freeze one branching manifest. Select the paired branch when Ollama passes
   its development gate; otherwise select the Codex-only branch and mark every
   Ollama slot not run.
4. Execute the frozen Stage 1 cohort, then run the remaining active-provider
   slots only when the branch-specific Stage 1 rule passes.

Every active provider returns untrusted candidate bytes to the existing MoonBit
preparation and rubric path. A provider cannot score its own candidate.

## Responsibility map

The existing boundaries remain authoritative:

- `genui-feasibility-fixtures.js` owns trusted fixture normalization and
  capability construction.
- `genui-feasibility-provider.js` owns the current prompt and Ollama request.
- `generative_ui_feasibility_adapter.mbt` owns candidate decoding, capability
  decoding, candidate validation, materialization, and rubric evaluation.
- `generative_ui_replay_adapter.mbt` and the session path own evaluate-and-commit
  and provider-free replay.
- `run-genui-feasibility-study.mjs` owns frozen-repository checks, validation
  subprocesses, schedule execution, and append-only journal events.
- `finalize-genui-feasibility-study.mjs` owns schedule completeness,
  sanitization, evidence construction, and the decision rule.

The comparison may extract experiment-private provider and schedule boundaries
from those files. It must not introduce a second decoder, validator,
materializer, rubric, replay implementation, or session commit path.

## Shared provider contract

A provider attempt produces exactly one of two outcomes:

- candidate bytes plus provider identity and telemetry; or
- one terminal failure classification plus bounded diagnostics.

The shared runner treats candidate bytes as opaque. It does not parse or
normalize candidate JSON before the MoonBit preparation call. This preserves
byte-level replay and prevents provider-specific acceptance rules.

The provider boundary is private to the benchmark. The first materially
different production adapter, if one is ever justified, must precede any public
provider contract.

## Phase 1: Ollama diagnosis

### Diagnostic sequence

The diagnostic is not part of the comparison sample. It varies one request
property at a time and retains the response body and corresponding server log.
The sequence stops at the first failing prerequisite:

1. Confirm Ollama version, installed model identity, model manifest, template,
   parameters, and available memory.
2. Load `gemma4:e2b` without generation.
3. Run a minimal plain-text generation.
4. Run JSON-object mode without a schema.
5. Run a minimal JSON Schema response unrelated to Canopy.
6. Run the frozen candidate schema with a minimal synthetic prompt.
7. Run the three trusted fixture prompts through the corrected request.

A known-working installed model is used once as a runtime control if
`gemma4:e2b` fails before the Canopy prompt. This distinguishes an Ollama/runtime
failure from a model-specific structured-output failure. The control does not
become a comparison arm.

### Diagnostic evidence

Each probe records:

- canonical request body and digest;
- HTTP status, headers, and body;
- Ollama server-log interval;
- model identity before and after the request;
- load duration, generation duration, token counts, and memory observations
  when available;
- the single request dimension changed from the preceding probe.

The old study discarded the HTTP error body. The diagnostic must retain it.
No probe may mutate the v1 or v2 manifest, journal, or evidence.

### Exit rule

The Ollama diagnostic produces one terminal, reviewable summary. It records every
completed prerequisite, the first failed prerequisite if any, request and
response digests, identity observations, and whether the selected request:

- returns candidate bytes for all three fixtures in a development-only pass;
- preserves the expected model identity before and after every request;
- reaches the existing MoonBit preparation core;
- has fixed request settings and a recorded request digest.

The development pass is not counted in the scored cohort. A safe, complete
diagnostic selects exactly one manifest branch:

- `paired` when all four conditions hold;
- `codex_only` when an Ollama request, runtime, model, timeout, HTTP, candidate,
  or preparation failure prevents qualification.

The `codex_only` branch executes the preregistered 30-attempt Codex cohort against
the same three fixtures and rubric while recording all 30 Ollama slots as not
run with reason `ollama_not_operational`. It can establish standalone Codex
reliability and latency, but not a matched provider difference.

A global safety, credential, budget, isolation, or evidence-integrity failure
creates no manifest and authorizes no scored request.

## Phase 2: Codex app server adapter

### Time-bounded identity

The Codex arm uses:

- `codex-cli 0.144.4`;
- stdio JSONL transport;
- model slug `gpt-5.6-luna`;
- reasoning effort `medium`;
- the existing Codex login;
- one App Server process at a time per run;
- one ephemeral thread per slot.

Before any candidate request, each process calls `account/read` with token
refresh disabled and records only the auth mode. It then calls `model/list`,
selects the exact catalog entry for `gpt-5.6-luna`, stores its canonical bytes
and digest, and verifies that `medium` is supported.

The initialization
handshake sets `capabilities.experimentalApi` to `true`; this negotiation is
required by Codex v0.144.4 before `thread/start` may set the experimental
`allowProviderModelFallback` field to `false`.

Missing negotiation, a rejected
field, a model-reroute notification, auth-mode change, or catalog drift ends the
affected run.

The hosted backend can change behind the slug. Evidence must call this a
**time-bounded provider benchmark**, not a frozen-model comparison. It records
the CLI version, selected catalog entry, slug, effort, auth mode, timestamps,
request/schema digests, and normalized event transcript.

### Protocol lifecycle

Each App Server process performs one initialization handshake with experimental
API negotiation, sends the `initialized` notification, then performs its account
read and model-catalog read. A slot then:

1. creates a unique empty working directory;
2. starts an ephemeral thread with the selected model and no fallback;
3. starts one turn with the shared semantic prompt and candidate output schema;
4. consumes JSON-RPC responses and notifications until terminal turn status;
5. extracts exactly one final agent message when the turn status is `completed`.

The runner ends all threads by terminating the App Server process when the run
finishes or the process fails.

Request IDs are unique within the process. Every notification must match the
active thread and turn. EOF, malformed JSONL, unknown response IDs,
out-of-order lifecycle events, duplicate final messages, missing final messages,
`failed`/`interrupted` turns, and timeouts are terminal failures.

The candidate is the UTF-8 bytes of the final agent message. The adapter checks
only the byte limit before passing those bytes to MoonBit. It does not
`JSON.parse` and reserialize them.

### Permitted and forbidden items

Normal turns may contain only:

- the user message;
- reasoning metadata;
- one final agent message.

The following item types are boundary violations:

- command execution;
- file change;
- MCP or dynamic tool call;
- collaboration or subagent activity;
- web search;
- image view or generation.

Plan, review-mode, sleep, context-compaction, hook-prompt, or unknown items are
protocol failures for this single-turn benchmark. A forbidden item triggers
`turn/interrupt` and terminal classification. Detection is audit evidence, not
the primary isolation mechanism.

### Timeout and process recovery

A timed-out or corrupt App Server process is terminated, and the failed slot is
not retried or replaced. The next frozen slot may use a new process after a new
handshake and catalog check. This recovery cannot improve the failed slot's
outcome.

## External sandbox

### Why App Server read-only mode is insufficient

App Server's `readOnly` sandbox prevents writes but does not define readable
roots. An empty cwd does not hide the repository, host home, or credentials.
Interrupting after a tool event also cannot prevent a read that already began.

The App Server process therefore runs inside a bubblewrap mount namespace and
the turn declares an external sandbox. The repository is not mounted.

### Mount contract

The namespace contains only:

- the statically linked Codex binary;
- TLS and DNS files required for upstream authentication and generation;
- `/proc` and `/dev`;
- a tmpfs `/tmp`;
- an empty `/work` directory;
- an experiment-private Codex home.

It excludes:

- the repository and all worktrees;
- the host home directory;
- SSH, Git, npm, and cloud credentials other than the copied Codex auth state;
- shells, coreutils, Git, Node, and package managers;
- global Codex skills, memories, hooks, MCP servers, apps, and plugins;
- inherited environment secrets.

Bubblewrap unshares namespaces while sharing the network namespace required by
the App Server's upstream connection. The agent receives no executable shell or
filesystem view beyond the minimal namespace.

### Minimal Codex configuration

The private Codex home contains a mode-`0600` copy of the minimum auth state and
a generated configuration with:

- history persistence disabled;
- analytics, feedback, and update checks disabled;
- web search disabled;
- shell, unified execution, patch, JavaScript REPL, search, memory,
  multi-agent, browser, app, MCP-app, and plugin features disabled;
- app and collaboration instruction injection disabled;
- environment and permission context injection disabled;
- no hooks, skills, marketplaces, plugins, or MCP servers;
- no inherited shell environment.

The implementation must validate these keys against the version-matched
`rust-v0.144.4` configuration schema. It may not rely on current-main Codex
configuration documentation.

The turn uses `externalSandbox` with restricted network metadata. This tells
Codex that the host already owns the process boundary; it does not itself create
that boundary.

### Credential handling

The real Codex home is never mounted. Before bubblewrap starts, the runner
creates a mode-`0600` private auth copy and deletes it after the run.

The adapter omits the auth bytes from logs and evidence. Before writing public
evidence, it scans stderr, JSONL events, normalized transcripts, and diagnostics
for injected secret canaries.

No credentialed request occurs until deterministic isolation tests and an
independent review pass.

### Positive controls

A preflight creates known-positive canaries and proves that its detector and
namespace fail closed:

- a host canary path is absent in the namespace;
- the repository path and host home are absent;
- `/bin/sh` and other executable tools are absent;
- `/work` is empty;
- unrelated Codex home state is absent;
- secret/path canaries cause transcript sanitization to fail;
- App Server `initialize`, `account/read`, and `model/list` still succeed.

A clean absence report is invalid unless the corresponding positive detector
fires on an injected canary first.

## Shared prompt and output constraints

The semantic prompt, normalized fixture bytes, capability JSON, candidate
schema, maximum candidate bytes, and 120-second slot timeout are identical
between providers. Only the transport envelope and provider controls differ.

Ollama exposes temperature, seed, context, and prediction limits. App Server
exposes model slug and reasoning effort but no equivalent sampling seed or
provider-side output-token limit. The benchmark records this asymmetry and does
not describe the arms as parameter-matched.

The comparison freezes the study-private Ollama seed vector
`[1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710]`. Each repeated-slot
index maps to one seed, and only the Ollama half of that pair uses it. The first
three values preserve the merged v2 study.

The existing three-slot `GENUI_PROVIDER_SETTINGS.slotSeeds` and `callOllamaSlot`
contracts remain unchanged; comparison execution uses an explicit-seed attempt
core extracted from `callOllamaSlot`.

The candidate schema constrains the final answer. It is not treated as a
replacement for MoonBit decoding, semantic validation, materialization, or the
fixture rubric.

## Comparison schedule

### Frozen branches

The manifest always contains 60 terminal slot positions: three fixtures, ten
repeated slots per fixture, and two provider labels. The diagnostic freezes one
execution branch:

- `paired`: all 60 slots are active;
- `codex_only`: the 30 Codex slots are active and the 30 Ollama slots are
  terminally not run with reason `ollama_not_operational`.

No execution result can change the branch.

### Stage 1

Stage 1 contains the first three repeated slots per fixture. It therefore has:

- 18 active attempts in `paired`;
- nine active attempts and nine terminal Ollama not-run records in `codex_only`.

In `paired`, the Ollama and Codex attempts at each fixture and repeated-slot
index form a pair. A fixed randomization seed balances which provider runs first
within each pair.

Paired attempts are adjacent and sequential; providers do not run concurrently.
In `codex_only`, the Codex attempt keeps its exact frozen slot identity and order
without consuming an Ollama request.

Stage 1 continues after ordinary active-slot failures and reaches a terminal
record for every Stage 1 slot without retry or replacement. A global safety,
identity, credential, budget, isolation, or evidence-integrity failure stops the
run and classifies all remaining active slots as not run.

### Stage 1 eligibility

Stage 2 is eligible only when every active provider:

- produces at least one candidate per fixture that passes MoonBit preparation;
- has zero tool-use, state-mutation, and credential-leakage violations;
- has zero provider identity or catalog drift;
- has zero replay mismatch;
- passes manifest, schedule, evidence, and retention checks.

In `paired`, both providers must pass. In `codex_only`, Codex must pass and the
preclassified Ollama not-run records are not qualification failures. If an
active provider is ineligible, Stage 2 does not run and Stage 1 is the recorded
outcome.

### Stage 2

The initial manifest contains the complete 60-slot schedule before Stage 1.
Stage 2 executes:

- the remaining 42 active attempts in `paired`;
- the remaining 21 active Codex attempts in `codex_only`.

Provider order and slot identity use the same frozen rules. No Stage 1 outcome
may add, remove, reorder, activate, or replace a Stage 2 slot.

## Qualification rule

Each active provider path qualifies for further technical work only when all
conditions hold:

- at least 24 of 30 attempts pass the fixture rubric;
- at least 7 of 10 attempts pass for each fixture;
- zero safety violations;
- zero replay mismatch;
- zero provider identity drift.

The final engineering outcome is one of:

- neither active provider qualifies;
- Ollama only qualifies;
- Codex only qualifies;
- both providers qualify.

In `codex_only`, Ollama has status `unavailable` and contributes no scored
failure. The only possible qualification outcomes are Codex or neither.

When both active providers qualify in `paired`, both remain candidates. The
study does not force a winner.

It reports overall and fixture-specific pass rates, Wilson intervals, p50/p95
latency, token usage, and failure-class counts. Thirty observations per active
provider do not support a statistical-superiority claim.

## Failure taxonomy

Provider-independent terminal classes include:

- request rejected before provider access;
- provider unavailable, timeout, transport error, or HTTP error;
- provider identity or catalog mismatch;
- provider protocol error;
- forbidden provider tool use;
- candidate oversize or invalid UTF-8;
- candidate decode failure;
- capability decode failure;
- semantic validation failure;
- materialization failure;
- rubric failure;
- replay mismatch;
- session commit failure;
- global safety or budget stop;
- not run because Stage 1 was ineligible.

Provider diagnostics may add bounded detail, but they do not create
provider-specific success semantics. Every scheduled slot ends in exactly one
terminal class.

## Evidence and retention

### Immutable manifest

The comparison manifest freezes:

- study ID, claim scope, selected branch, and diagnostic-summary digest;
- complete 60-slot schedule, active/not-run classification, and balancing seed;
- fixtures, prompt, schema, capability, preparation-core, and rubric digests;
- decision and branch-specific Stage 1 rules;
- Ollama identity, request settings, ten-seed vector, and each slot's exact seed;
- Codex CLI version, selected catalog entry, slug, effort, and auth mode;
- bubblewrap and minimal-config contracts;
- byte, active-request, token, and wall-time limits;
- validation commands and artifact paths.

The manifest freezes the benchmark procedure. It does not freeze the hosted
Codex backend.

### Private raw artifact

Raw App Server JSONL, stderr, Ollama response bodies, and server logs are written
with exclusive creation under:

`$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/`

The directory is mode `0700`; files are mode `0600`. It is outside Playwright,
Vite, build, and test cleanup paths. The aggregate evidence records each raw
artifact digest and whether the artifact remains available.

### Normalized audit transcript

A reviewable transcript replaces request, thread, and turn IDs with stable
opaque IDs and removes absolute paths and account metadata. It preserves:

- ordered request/response methods and terminal statuses;
- selected model identity observations;
- item types and boundary violations;
- usage and timing fields;
- candidate digest, byte length, and private raw-artifact digest;
- every redaction performed.

The committed transcript contains neither prompt nor candidate bytes. Exact
bytes remain private under the run root.

Fixtures are synthetic and fixed. The provider receives no held-out, user,
repository, or host data. A transcript containing a secret/path canary cannot be
published.

### Aggregate evidence

The committed evidence verifies schedule completeness and includes:

- one terminal event per scheduled slot;
- no duplicate, replacement, or retried slots;
- Stage 1 eligibility and Stage 2 execution status;
- rubric, replay, safety, and identity results;
- provider-specific reproducibility limits;
- manifest, raw-artifact, transcript, and source digests;
- an auditability flag that changes if raw artifacts are missing.

Missing raw artifacts do not silently preserve full-audit claims. They set the
flag to unavailable and limit the stated conclusion.

## Test strategy

### Protocol tests

Deterministic JSONL fixtures cover:

- initialization, account-read, and model-catalog success;
- experimental fallback-field rejection without negotiation and acceptance
  only after `experimentalApi` opt-in;
- missing model, changed catalog entry, auth-mode drift, and model reroute;
- malformed JSONL, unknown response ID, wrong thread/turn ID, and out-of-order
  notifications;
- EOF, failed/interrupted turn, timeout, and process restart;
- missing or duplicate final agent messages;
- approval requests and every forbidden item type;
- exact candidate-byte preservation.

### Isolation tests

Deterministic bubblewrap tests cover every positive control in the external
sandbox section. They verify both sides of the boundary: prohibited host paths
are unavailable, while initialization, account read, and catalog access remain
functional.

### Runner and finalizer tests

Tests cover:

- paired and Codex-only branch generation;
- 18-terminal-slot Stage 1 completeness with 18 or nine active attempts;
- branch-specific Stage 1 eligibility for every failed predicate;
- no retry or replacement after process failure;
- fixed 60-slot schedule with 42 or 21 active Stage 2 attempts;
- overall and fixture-specific qualification thresholds;
- global-stop and unavailable-provider classification;
- provider-specific identity representation;
- raw-artifact loss and auditability downgrade;
- normalized transcript redaction and canary rejection.

### Existing-path verification

The existing focused Node, MoonBit, TypeScript, recorded-candidate browser, and
production preview checks remain preflight requirements. Any UI assertion change
must describe an actual product-contract change; the provider comparison is not
a reason to weaken the recorded-candidate UI tests.

## Execution gates

The implementation proceeds in this order:

1. Write failing protocol, sandbox, schedule, and evidence tests.
2. Implement deterministic boundaries until focused tests pass.
3. Run affected Node, MoonBit, TypeScript, and browser verification.
4. Complete an independent, different-model review.
5. Run one credentialed Codex request against a synthetic fixture.
6. Apply the preregistered conservative token-budget rule and freeze every
   numeric request, token, wall-time, and byte limit.
7. Complete the seven-step Ollama diagnostic and three-fixture development gate.
8. Freeze the branching comparison manifest and review it independently.
9. Run the selected branch's Stage 1 exactly once.
10. Run the selected branch's Stage 2 only if its frozen eligibility rule passes.
11. Validate and commit normalized transcript and aggregate evidence.
12. Complete final independent review before any provider recommendation.

The existing Codex login may not expose exact monetary cost. The hard budget is
therefore enforced by request count, total observed tokens, wall time, and
candidate bytes. The 60-request schedule is an absolute maximum.

The smoke is an availability and integration check, not a representative token
sample.

The per-request observed-token ceiling is the greater of 16,000 tokens and four
times the smoke total-token count rounded up to the next 1,000. If that
value exceeds 32,000, the comparison stops before manifest creation rather than
silently expanding its budget.

The run ceiling is the accepted per-request ceiling multiplied by the branch's
active-request count: 60 for `paired` or 30 for `codex_only`. No accepted
manifest can authorize more than 1,920,000 or 960,000 observed tokens,
respectively.

## Expected implementation surface

The App Server client, external sandbox, Ollama qualification harness, immutable
manifest, comparison runner, finalizer, and focused tests are expected to add or
change roughly 1,500–2,500 lines across 12–15 files. The work should remain under
`examples/web` except for the design, manifest, and evidence records.

This range is deliberately wider than the earlier 500–780-line estimate: the comparable
existing provider, manifest, runner, finalizer, and focused-test modules already
total about 1,700 lines, before the new protocol and sandbox boundaries.

The MoonBit preparation and commit implementation should remain unchanged unless
a failing regression proves an existing defect.

The implementation plan separates these independently reviewable slices:

- experiment-private App Server JSONL protocol and lifecycle;
- external-sandbox launcher and isolation preflight;
- pure comparison schedule, qualification, and evidence policy;
- immutable manifest construction;
- comparison runner and credentialed smoke entry point;
- byte-equivalent Ollama request-core extraction;
- seven-step Ollama diagnostic and three-fixture qualification gate;
- deterministic cross-stack verification and pre-credential review;
- versioned manifests, execution, and evidence artifacts.

Exact file changes belong in the implementation plan after repository-level
reuse and reference checks. This design does not preselect new public types or
APIs.

## Rejected approaches

### `codex exec` wrapper

This would reduce implementation size but hide thread, turn, item, interrupt,
and token-usage events needed for a fail-closed audit.

### Direct Responses API

This would provide a cleaner generator-only boundary but requires separate API
credentials and would not test the selected App Server path or existing Codex
login.

### Prompt-only tool prohibition

A prompt is not an isolation boundary. It cannot hide the repository or
credentials and cannot prevent a tool from starting before an interrupt.

### App Server `readOnly` sandbox without bubblewrap

Read-only prevents writes, not reads. It does not satisfy the approved
repository and host-home isolation requirement.

### Immediate 60-request execution

This spends local and hosted capacity before the active provider boundaries are
known to work. The branch-specific Stage 1 preserves the complete frozen
schedule while limiting the first scored cohort to 18 paired requests or nine
Codex-only requests.

## References

- [Codex App Server README](https://github.com/openai/codex/blob/rust-v0.144.4/codex-rs/app-server/README.md)
- [Codex v0.144.4 configuration schema](https://github.com/openai/codex/blob/rust-v0.144.4/codex-rs/core/config.schema.json)
- `codex app-server generate-json-schema --experimental`
- `docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility.md`
- `docs/plans/2026-07-15-generative-ui-live-provider-experiment-design.md`
- `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json`
- `docs/evidence/2026-07-16-generative-ui-local-llm-feasibility-v2-retention-incident.json`
