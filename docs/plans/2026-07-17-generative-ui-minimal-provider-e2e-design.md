# Generative UI minimal provider E2E design

**Status:** Proposed

**Issue:** #896

## Purpose

Provide one reusable local developer command that asks one configured provider
to generate one Generative UI candidate, sends that candidate through the
existing MoonBit materialization, rubric, replay, and session-commit path, and
retains enough private evidence to diagnose the run.

The command answers one technical question:

> Can this provider produce a candidate that the existing Canopy pipeline
> accepts and commits for this fixture?

It does not compare providers, establish reliability rates, or measure user
value.

## Value gate

- **Consumer:** a Canopy maintainer deciding whether a provider can traverse the
  existing candidate pipeline at all.
- **Success signal:** one invocation ends with a MoonBit result classified as
  `success`, a passing rubric, and a successful session commit.
- **Lifecycle:** a reusable, local-only developer command. It is not a CI gate,
  production API, or permanent provider abstraction.
- **Decision:** a successful run permits another technical iteration. A failed
  run identifies the first provider, decode, materialization, rubric, replay, or
  commit boundary that rejected the candidate. Neither outcome establishes
  Generative UI usefulness.

## Scope

### In

- Codex as the first provider, invoked through the supported non-interactive
  `codex exec` command.
- One existing synthetic feasibility fixture per invocation.
- Configurable model.
- Exactly one `codex exec` turn per invocation; the runner performs no retry. A
  developer may start a new run explicitly.
- Existing prompt construction, candidate schema, fixture data, MoonBit
  materialization, rubric, replay, and session commit.
- A private run directory containing the request, provider event stream,
  candidate when produced, and final result.
- A bounded provider timeout and process termination.

### Out

- Codex App Server protocol implementation or thread reuse.
- Ollama diagnosis or any second provider.
- Provider comparison, randomized schedules, repeated slots, Stage 1/2, or
  aggregate statistics.
- Immutable manifests, journals, finalizers, qualification thresholds, or
  recommendation generation.
- Exact CLI display-version or model-catalog identity freezing.
- Bubblewrap or a benchmark-specific external sandbox.
- Automatic retry, replacement request, or resume.
- Production/public provider endpoints, browser credentials, CI credentials, or
  deployment.
- Target-user recruitment, fixed-UI comparison, or product-value claims.

## Existing boundaries reused

The minimal command reuses rather than duplicates:

- `GENUI_CANDIDATE_SCHEMA` from
  `examples/web/src/genui-candidate-schema.js`.
- `buildFeasibilityPrompt`, `GENUI_PROVIDER_SETTINGS.maxCandidateBytes`, and
  canonical JSON utilities from
  `examples/web/src/genui-feasibility-provider.js`.
- Existing fixture lookup and normalized capability/dataset JSON from
  `examples/web/src/genui-feasibility-fixtures.js`.
- `runFeasibilityCandidate` from
  `examples/web/src/genui-feasibility-flow.js`.
- The existing browser-loaded MoonBit evaluator and session commit path in
  `examples/web/src/genui.js`.
- The existing Playwright web-server configuration and Chromium dependency.

No general provider interface is introduced. A second live provider is required
before a shared provider abstraction can be justified.

## Command contract

The developer command accepts only:

- `--fixture <case-id>`
- `--model <model-slug>`
- `--output-dir <absolute-path-outside-repository>`
- `--timeout-ms <positive-integer>` with a conservative default

The output directory must not already exist. The command creates it with mode
`0700`; retained files use mode `0600`. The command rejects paths inside the
repository so private model output cannot be committed accidentally.

The process exits `0` only when the provider succeeds and the existing MoonBit
path returns classification `success`, `rubric.passed == true`, and
`session.success == true`. Every other terminal outcome exits nonzero after
writing `result.json`.

## Provider invocation

Use the supported `codex exec` surface instead of implementing App Server JSONL:

- `--ephemeral` avoids persisted Codex session files.
- `--ignore-user-config` and `--ignore-rules` remove mutable execution policy
  from the experiment. Authentication remains available through `CODEX_HOME`.
- `--skip-git-repo-check` allows execution in an isolated empty working
  directory.
- `--sandbox read-only` prevents model-generated commands from writing.
- `--model` selects the requested model.
- `--output-schema` points to a temporary JSON file generated from the existing
  `GENUI_CANDIDATE_SCHEMA`; no duplicate schema is committed.
- `--output-last-message` writes the final candidate JSON.
- `--json` emits the provider event stream for private diagnosis.

`codex exec` is headless and therefore uses no interactive approval prompts. The
runner supplies the complete feasibility prompt on stdin and starts Codex in an
empty directory below the private run directory. The prompt contains the fixture
question, capabilities, and normalized dataset but no rubric or expected answer.

At startup the command verifies that the installed `codex exec --help` exposes
the required flags. It does not compare display strings such as
`codex-cli 0.144.4` with semantic versions such as `0.144.4`.

The parent process enforces the timeout. Timeout or interruption terminates the
single child and records the terminal outcome; it never retries.

## Data flow

```text
developer command
  -> resolve existing fixture
  -> build existing feasibility prompt
  -> write private request.json and temporary schema
  -> codex exec once in private empty cwd
  -> provider-events.jsonl + candidate.json
  -> reject missing, invalid, or >64 KiB candidate
  -> local Playwright Chromium page
  -> existing DEV-only commitCandidate hook
  -> existing MoonBit decode/materialize/rubric/replay/session commit
  -> private result.json
  -> exit 0 or nonzero
```

The Playwright step uses the existing web-server lifecycle rather than adding a
custom Vite readiness loop or browser process manager. A local-only Playwright
entry reads `candidate.json`, calls the DEV-only browser hook, writes the returned
MoonBit result, and asserts the command success contract.

## Private run directory

A completed or failed run retains at most these durable files:

- `request.json`: fixture ID, model, timeout, invocation timestamp, and the
  exact prompt. It contains no credential or environment dump.
- `provider-events.jsonl`: exact stdout events emitted by `codex exec --json`.
- `candidate.json`: the final message, only when Codex produced one.
- `result.json`: duration, provider exit/signal, terminal classification, and the
  returned MoonBit evaluation/commit result when reached.

The temporary output-schema file and empty Codex working directory are deleted
at the end of the run. Stderr may be included in `result.json` only after a
small fixed byte cap; inherited environment variables and credential paths are
never serialized.

No digest graph, manifest, journal, redacted transcript, or aggregate evidence
is required for a single developer-run E2E check.

## Failure classifications

The command needs only boundary-level classifications that change the next
engineering action:

- `configuration_error`: invalid CLI input, fixture, output path, or unsupported
  Codex CLI surface.
- `provider_timeout`: the one provider process exceeded its deadline.
- `provider_failed`: Codex exited nonzero or without a final message.
- `candidate_oversize`: final output exceeded the existing 64 KiB limit.
- `candidate_invalid`: final output was not a JSON value accepted by the
  candidate boundary.
- `materialization_error`, `rubric_failure`, `replay_mismatch`, and
  `commit_failure`: preserved unchanged from the existing MoonBit result.
- `success`: rubric and session commit both succeeded.

There is no global-stop taxonomy because one invocation owns one attempt.

## Required tests

Tests defend only observable behavior needed by the command:

1. CLI parsing rejects missing/invalid fixture, model, timeout, and unsafe
   output paths before provider invocation.
2. Provider arguments use the required supported Codex flags, existing prompt,
   generated schema, selected model, and exactly one process invocation.
3. Timeout terminates the child and writes a non-success `result.json` without a
   retry.
4. Missing, malformed, and oversized final output never reaches the browser.
5. A fake provider candidate traverses the real browser/MoonBit path and commits
   successfully.
6. Each existing MoonBit failure classification produces nonzero exit and is
   retained unchanged.
7. The run directory contains only the four documented durable files, with
   `candidate.json` absent when no candidate exists.
8. A local opt-in smoke proves one real `codex exec` invocation can produce and
   commit a candidate. It is never part of CI.

Existing MoonBit package tests, TypeScript checks, development browser tests, and
production build remain the verification gates for the unchanged product path.

## Expected implementation surface

The design should require approximately four to six changed files:

- one minimal CLI runner;
- one focused runner test;
- one local-only Playwright E2E entry or extension;
- the smallest DEV-only browser hook needed to commit an injected candidate;
- optional package script/config wiring;
- this design and its later implementation plan.

The target is roughly 250–450 production lines and 200–350 test lines. This is a
planning constraint, not a reason to omit a required failure path. If the design
requires a protocol client, scheduler, manifest builder, or finalizer, stop and
re-evaluate the boundary instead of recreating PR #906.

## Preservation and migration

PR #906 is closed without merge. Its complete implementation remains on remote
branch `feat/genui-provider-comparison-implementation` at
`fb28b9812385e5a999e3a688b96f86d93a177916` as historical reference.

The minimal implementation starts from `main`. It may copy a small reviewed
function only when the same responsibility is required by this design; it does
not cherry-pick comparison commits wholesale. The remote historical branch is
not a runtime dependency and may not be imported or vendored.

## Acceptance criteria

- One documented local command performs exactly one Codex request for one
  existing fixture.
- A successful provider output reaches the real MoonBit materialization, rubric,
  replay, and session-commit path.
- The command exits zero only for a passing rubric and successful commit.
- A failed boundary writes one private `result.json` and exits nonzero without
  retry.
- The private run directory follows the four-file contract and remains outside
  the repository.
- No provider comparison, App Server client, bubblewrap contract, scheduler,
  manifest, journal, finalizer, or aggregate evidence implementation is added.
- No production provider API, CI credential, user-value claim, or `Closes #896`
  relationship is introduced.
