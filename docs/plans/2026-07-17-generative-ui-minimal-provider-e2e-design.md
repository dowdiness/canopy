# Generative UI minimal provider E2E design

**Status:** Accepted

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
- `buildFeasibilityPrompt` and `GENUI_PROVIDER_SETTINGS.maxCandidateBytes` from
  `examples/web/src/genui-feasibility-provider.js`.
- Existing fixture lookup and normalized capability/dataset JSON from
  `examples/web/src/genui-feasibility-fixtures.js`.
- `runFeasibilityCandidate` from
  `examples/web/src/genui-feasibility-flow.js`.
- The existing browser-loaded MoonBit evaluator and session commit path in
  `examples/web/src/genui.js`.
- The existing Playwright Chromium dependency and the dev-server command pattern
  in `examples/web/playwright.feasibility.config.ts`.

No general provider interface is introduced. A second live provider is required
before a shared provider abstraction can be justified.

## Command contract

The developer command accepts only:

- `--fixture <case-id>`
- `--model <model-slug>`
- `--output-dir <absolute-path-outside-repository>`
- optional `--timeout-ms <positive-integer>`, defaulting to the existing
  `GENUI_PROVIDER_SETTINGS.timeoutMs`

The output directory must not already exist, and its parent must already exist.
The command resolves the parent canonically, rejects parents inside the
repository (including symlink aliases), then creates the directory exclusively
with mode `0700`; retained files use mode `0600`. This prevents private model
output from landing in the checkout accidentally.

Fixture, model, timeout, and output-parent validation happen
before the run directory is created. A failure in that pre-run phase writes one
diagnostic to stderr and creates no artifact. Once the run directory exists,
every terminal outcome writes `result.json`. The process exits `0` only when the
provider succeeds and the existing MoonBit path returns classification
`success`, `rubric.passed == true`, and `session.success == true`.

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

This is not a confidentiality sandbox. Codex `read-only` prevents writes but can
read host files available to an ordinary local Codex invocation, and tool output
can be sent to the configured model provider. The command is limited to trusted
synthetic fixtures and machines where that ordinary Codex access is acceptable.
Stronger host-read isolation would require the deliberately excluded external
sandbox.


The parent process enforces the timeout over the complete provider process tree,
not only the direct `codex` child. It sends a graceful tree termination, waits a
small bounded interval, then force-terminates survivors. Timeout or interruption
records one terminal outcome and never retries. POSIX process groups and the
Windows process-tree facility provide the platform-specific mechanism.

## Data flow

```text
developer command
  -> resolve existing fixture
  -> build existing feasibility prompt
  -> write private request.json and temporary schema
  -> codex exec once in private empty cwd
  -> provider-events.jsonl + candidate.json
  -> reject missing, syntactically invalid, or >64 KiB candidate
  -> local Playwright Chromium page
  -> new minimal DEV-only injected-candidate commit hook
  -> existing MoonBit decode/materialize/rubric/replay/session commit
  -> private result.json
  -> exit 0 or nonzero
```

The Playwright step follows the existing feasibility dev-server command pattern
but uses dedicated local-only wiring. It binds to loopback, uses a strict port,
never reuses an already-running server, disables trace retention, and directs
all temporary Playwright output below the private run directory. A local-only
Playwright entry reads `candidate.json`, calls the DEV-only browser hook, and
writes the returned MoonBit result without reclassifying it. The runner alone
applies the command success contract so MoonBit failure classifications survive.

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

Playwright traces, reports, screenshots, and `test-results` must not be written
inside the repository. Temporary Playwright output is deleted before the final
four-file contract is checked.

No digest graph, manifest, journal, redacted transcript, or aggregate evidence
is required for a single developer-run E2E check.

## Failure classifications

The command needs only boundary-level classifications that change the next
engineering action:

- `configuration_error`: a pre-run invalid CLI input, fixture, or output parent.
  It is reported on stderr because no safe run directory exists yet.
- `provider_timeout`: the sole provider generation process exceeded its deadline.
- `provider_failed`: Codex could not start, rejected its options, was interrupted,
  exited nonzero, or produced no final message.
- `candidate_oversize`: final output exceeded the existing 64 KiB limit.
- `candidate_invalid`: final output was not syntactically valid JSON. The runner
  does not duplicate MoonBit semantic candidate validation.
- `browser_failed`: the dedicated Playwright process could not return one
  parseable MoonBit result.
- `candidate_decode_error`, `capability_decode_error`,
  `candidate_validation_error`, `dataset_decode_error`,
  `materialization_error`, `rubric_failure`, `replay_mismatch`, and
  `commit_failure`: preserved unchanged from the existing MoonBit result.
- `success`: rubric and session commit both succeeded.

There is no global-stop taxonomy because one invocation owns one attempt.

## Required tests

Tests defend only observable behavior needed by the command:

1. CLI parsing rejects missing/invalid fixture, model, or output parent and
   invalid timeout values, non-canonical paths, repository-internal parents,
   and symlink aliases before provider invocation or artifact creation; omitted
   timeout uses the existing default.
2. The sole provider generation process receives the required Codex flags,
   existing prompt, generated schema, and selected model.
3. Timeout terminates an orphan-prone fake provider's complete process tree and
   writes a non-success `result.json` without a retry.
4. Missing, malformed, and oversized final output never reaches the browser;
   syntactically valid schema failures remain owned by MoonBit.
5. A fake provider candidate traverses the real browser/MoonBit path and commits
   successfully.
6. Every existing MoonBit failure classification produces nonzero exit and is
   retained unchanged.
7. The completed run directory contains only the four documented durable files,
   with `candidate.json` absent when no candidate exists and no Playwright output
   retained in the repository.
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

## Implementation structure refinement

The implementation keeps orchestration in the command runner but extracts the
provider child-process lifecycle into one private support module. That module
owns the single spawn, fixed Codex arguments, timeout and interrupt handling,
whole-process-tree termination, and bounded pipe settlement. The runner retains
CLI validation, private artifact ownership, candidate classification, browser
evaluation, and terminal result policy.

This split is organizational, not a provider abstraction. It introduces no
provider interface, scheduler, retry policy, or second execution path. Existing
runner exports remain stable for focused tests and the package command remains
the only user-facing entry point.

The lifecycle module keeps production timing defaults fixed while permitting
tests to shorten grace periods. At least one real descendant-process test must
still exercise operating-system process-tree cleanup rather than a fake child.
The fake-provider browser test continues to pin the unchanged MoonBit
materialization, rubric, replay, and session-commit boundary.

Implementation verification and live feature validation are reported
separately. Deterministic tests may establish that the command and unchanged
pipeline work, but Required test 8 remains unmet until a post-fix credentialed
run ends with classification `success`, a passing rubric, and a successful
session commit. No deterministic substitute may be reported as that evidence.

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
- After safe run-directory creation, a failed boundary writes one private
  `result.json` and exits nonzero without retry. Pre-run validation failures
  create no artifact.
- The private run directory follows the four-file contract and remains outside
  the repository.
- No provider comparison, App Server client, bubblewrap contract, scheduler,
  manifest, journal, finalizer, or aggregate evidence implementation is added.
- No production provider API, CI credential, user-value claim, or `Closes #896`
  relationship is introduced.
