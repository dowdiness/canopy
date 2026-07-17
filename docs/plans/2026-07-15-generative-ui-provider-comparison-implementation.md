# Generative UI provider comparison implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `subagent-driven-development` or `executing-plans` to execute this plan.
>
> Track every step with its checkbox. Protocol and scheduler algorithms remain in
> the main context; delegate only mechanical fixtures, exact-path migrations, and
> independent reviews.

**Goal:** Determine whether the prior failure is specific to the Ollama
runtime, request, model capability, or latency rather than the fixed candidate
pipeline. First build and prove an independent Codex App Server `gpt-5.6-luna`
path through the existing MoonBit preparation, materialization, rubric, replay,
and session-commit flow. Then execute either a paired cohort or a Codex-only
cohort selected by the completed Ollama diagnostic.

**Architecture:** Keep the downstream candidate pipeline unchanged so provider
path is the experimental variable. Add an experiment-only Codex JSONL client,
an external bubblewrap shell, and pure comparison policy for schedule,
eligibility, qualification, transcript normalization, and evidence. The runner
supplies candidates to the existing browser and MoonBit path; neither provider
receives rubric or answer authority.

**Tech stack:** Node.js ESM, Node test runner, Codex CLI/App Server 0.144.4,
bubblewrap 0.9.0, Playwright, Vite, TypeScript, MoonBit JS target, SHA-256.

**Design authority:**
`docs/plans/2026-07-15-generative-ui-provider-comparison-design.md`.

## Global constraints

- Preserve the existing `GenerativeUiCandidate::validate`, preparation,
  materialization, rubric, replay, and session-commit path.
- Keep all runtime code experiment-private under `examples/web`; add no public
  Canopy, MoonBit, provider-neutral, or renderer-neutral API.
- Use `codex-cli 0.144.4`, stdio JSONL, model `gpt-5.6-luna`, reasoning effort
  `medium`, and the existing Codex login.
- Negotiate `capabilities.experimentalApi=true` during `initialize` before
  `thread/start` sets `allowProviderModelFallback=false`.
- Give every slot a new ephemeral thread and empty `/work`; run provider attempts
  sequentially, never concurrently.
- Preserve candidate UTF-8 bytes exactly. The JavaScript provider boundary may
  enforce only the frozen byte cap before MoonBit receives the candidate.
- Use the same semantic prompt, normalized fixture bytes, capability JSON,
  candidate schema, maximum candidate bytes, and 120-second slot timeout for
  both providers.
- Freeze comparison-only Ollama seeds
  `[1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710]`. Preserve the
  existing three-slot feasibility settings and map each repeated comparison index
  to its exact manifest seed.
- Never retry or replace a failed scheduled slot.
- Stop globally on safety, identity, credential, or budget failure; classify all
  remaining slots as not run.
- Freeze all 60 provider-labeled slot positions before Stage 1. The selected
  branch is immutable: `paired` activates all 60; `codex_only` activates 30
  Codex slots and terminally marks 30 Ollama slots `ollama_not_operational`.
- Stage 1 reaches terminal records for 18 slots while executing 18 paired or
  nine Codex-only requests. Stage 2 executes the remaining 42 paired or 21
  Codex-only requests only when every branch-specific predicate passes.
- Treat provider identity as time-bounded. Do not claim a frozen hosted model or
  a statistically superior provider.
- Require an absolute `--run-root` under
  `$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/`; fail if
  `XDG_STATE_HOME` is unset, the path is inside the repository, or its directory
  and file modes are not `0700` and `0600`. Keep raw artifacts private and
  append-only. Commit only the reviewed normalized transcript and aggregate
  evidence; downgrade auditability if raw artifacts are lost.
- Complete the seven-step Ollama diagnostic in order. Select `paired` only when
  the corrected request succeeds for all three fixtures, preserves identity,
  and reaches MoonBit preparation. Select `codex_only` for a safe, complete
  Ollama runtime, model, request, timeout, HTTP, candidate, or preparation
  failure. A safety, credential, budget, isolation, or evidence-integrity
  failure authorizes no manifest or scored request.
- Run the reviewed Codex synthetic smoke independently of Ollama qualification.
- Freeze the per-request observed-token ceiling as
  `max(16000, ceilTo1000(4 * smokeTotalTokens))`; stop before manifest creation
  if it exceeds 32,000. Freeze the run ceiling as the accepted value times the
  active-request count: 60 for `paired`, 30 for `codex_only`.
- No credentialed candidate request may run before deterministic isolation tests
  and an independent review pass.
- Run `moon check` after each project-file edit. Use one file per edit call.
- Write and run failing tests before each behavioral implementation.

## Responsibility and file map

### New runtime and policy files

- `examples/web/src/genui-codex-app-server.js` — App Server request construction,
  JSONL lifecycle state, identity checks, terminal-item validation, candidate-byte
  extraction, and normalized provider result.
- `examples/web/scripts/genui-codex-sandbox.mjs` — private Codex home, minimal
  configuration, bubblewrap argv/environment, process lifecycle, canary checks,
  and cleanup.
- `examples/web/scripts/genui-provider-comparison.mjs` — pure branch and schedule
  generation, Stage 1 eligibility, provider qualification, transcript
  normalization, raw artifact digesting, aggregate evidence, and finalizer CLI.
- `examples/web/scripts/build-genui-provider-comparison-manifest.mjs` — immutable
  diagnostic-selected branch manifest construction and exclusive file creation.
- `examples/web/scripts/run-genui-provider-comparison-study.mjs` — preflight,
  branch-specific sequential execution, browser/MoonBit handoff, journal writes,
  global stops, Stage 1 gate, and finalization.
- `examples/web/scripts/smoke-genui-codex-provider.mjs` — exactly one
  credentialed synthetic request through the production sandbox, protocol, and
  unchanged browser/MoonBit path before the scored manifest exists.
- `examples/web/scripts/diagnose-genui-ollama.mjs` — ordered seven-step diagnostic,
  known-working-model runtime control, one-variable-at-a-time probe records, and
  the all-three-fixture development qualification result.

### New test files

- `examples/web/src/genui-codex-app-server.test.mjs` — deterministic JSONL
  protocol and terminal-result fixtures.
- `examples/web/scripts/genui-codex-sandbox.test.mjs` — mount, config, credential,
  cleanup, and known-positive detector controls.
- `examples/web/scripts/genui-provider-comparison.test.mjs` — paired and
  Codex-only branches, stage gates, thresholds, global stops, transcript
  redaction, raw-loss downgrade, manifest, runner, and finalizer tests.
- `examples/web/scripts/diagnose-genui-ollama.test.mjs` — diagnostic probe order,
  single-dimension changes, runtime-control branching, private evidence, and
  three-fixture exit-gate tests.

### Existing files to modify

- `examples/web/src/genui-feasibility-provider.js` — extract and export the frozen
  Ollama request builder so normal generation and diagnostics share exact bytes.
- `examples/web/src/genui-feasibility-provider.test.mjs` — prove the extraction is
  byte-equivalent and that HTTP failures remain terminal and unretried.
- `examples/web/scripts/build-genui-feasibility-manifest.mjs` — export the existing
  clean-repository and digest helpers for the comparison manifest builder; do not
  change the frozen v2 manifest shape.
- `examples/web/scripts/run-genui-feasibility-study.mjs` — reuse existing exported
  preflight, environment-isolation, durable-journal, capability, and repository
  checks; modify only if a comparison test proves an export is missing.

### Frozen and result artifacts

- `examples/web/studies/2026-07-15-genui-provider-comparison-v1.json` — reviewed
  60-slot branching manifest with diagnostic digest, active/not-run
  classification, numeric limits, and all identity/input/contract digests.
- `docs/evidence/2026-07-15-generative-ui-provider-comparison-v1-transcript.jsonl`
  — normalized, redacted audit transcript with stable opaque IDs.
- `docs/evidence/2026-07-15-generative-ui-provider-comparison-v1.json` — aggregate
  outcome, qualification, reliability, latency, token, failure, auditability,
  and artifact-digest evidence.
- `$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/` — private raw
  journal, provider bytes, stderr, JSONL, canary records, response bodies, and
  logs; mode `0700` for directories and `0600` for files, outside the repository
  and every Playwright, Vite, build, and test cleanup path.

## Existing API reuse check

- Reuse `buildFeasibilityPrompt`, `canonicalJson`, `sha256Hex`,
  `GENUI_PROVIDER_SETTINGS`, and `readOllamaIdentity` from
  `examples/web/src/genui-feasibility-provider.js`.
- Preserve `callOllamaSlot` and its three-slot contract. Extract its request and
  provider lifecycle into an explicit-seed `callOllamaAttempt` core for the
  comparison instead of passing repeated indices 3–9 to `callOllamaSlot`.
- Reuse `GENUI_FEASIBILITY_FIXTURES` and `capabilitiesJsonForFixture` from
  `examples/web/src/genui-feasibility-fixtures.js` and `GENUI_CANDIDATE_SCHEMA`
  from `examples/web/src/genui-candidate-schema.js`.
- Reuse `createRunCapability`, `buildValidationEnv`, `appendJournalEvent`,
  `verifyFrozenRepository`, and `runDeterministicPreflight` from
  `examples/web/scripts/run-genui-feasibility-study.mjs`.
- Reuse `parseJournal` from
  `examples/web/scripts/finalize-genui-feasibility-study.mjs`; do not reuse its
  nine-slot validation or old positive/negative decision rule.
- Reuse the existing Playwright request gate, browser transaction, MoonBit
  preparation/materialization/rubric/replay, and session commit unchanged.
- Use Node core `child_process`, `readline`, `fs`, `path`, `os`, `crypto`, and
  `AbortSignal`; add no npm dependency.
- Checked but rejected: `codex exec` hides required thread, turn, item, usage, and
  model-reroute events; App Server WebSocket is experimental and adds no value
  over stdio; App Server `readOnly` does not hide readable host paths; direct
  Ollama request duplication would let diagnostic and scored request bytes drift.


## Expected implementation surface and task boundaries

Plan for roughly 1,500–2,500 added or changed lines across 12–15 files. The
comparable existing provider, manifest, runner, finalizer, and focused-test
modules total about 1,700 lines. The new JSONL protocol and sandbox boundaries
therefore make the earlier 500–780-line estimate unsafe.

The twelve tasks split the work at independently testable and reviewable commit
boundaries. They cover the protocol, sandbox, policy, manifest, runner, Ollama
request reuse, Ollama qualification, verification, smoke and budget freeze,
manifest freeze, scored execution, and evidence closure.

---

### Task 1: Codex App Server protocol boundary

**Files:**
- Create: `examples/web/src/genui-codex-app-server.js`
- Create: `examples/web/src/genui-codex-app-server.test.mjs`

**Interfaces:**

- Produce `createCodexAppServerSession({ frozenIdentity, spawnProcess }, deps)
  -> Promise<{ runSlot, close, identity }>`; `runSlot({ fixture, slotId })`
  starts one ephemeral thread and returns `Promise<ProviderTerminalResult>`.
- `spawnProcess()` returns a child-process-compatible object with writable stdin,
  readable stdout/stderr, `kill(signal)`, and an exit result. A session performs
  one initialization/account/catalog sequence and runs slots sequentially until
  closed or failed; recovery creates a new session and cannot change the failed
  slot.
- A successful result contains the unchanged `candidateJson`, case/slot identity,
  selected catalog-entry digest, auth mode, CLI version, slug, effort, prompt and
  candidate digests, elapsed time, token counts, and normalized transcript events.
- Every rejected path returns one provider-independent terminal classification;
  global safety/identity/credential conditions are marked for runner-wide stop.

- [ ] Write JSONL fixtures for initialize success, missing experimental opt-in,
  accepted fallback disablement, `account/read`, paginated `model/list`, missing
  model, unsupported effort, duplicate/cyclic catalog cursor, catalog drift,
  auth drift, and model reroute.
- [ ] Write lifecycle fixtures for unique request IDs, exact thread/turn matching,
  ordered start/completion, malformed JSONL, unknown response ID, wrong IDs,
  out-of-order notification, EOF, failed/interrupted turn, timeout, and process
  exit.
- [ ] Write terminal-item fixtures proving reasoning metadata followed by exactly
  one final agent message is accepted. Reject zero or duplicate final messages,
  approval requests, command/file/MCP/dynamic tool/subagent/web/image/plan/
  compaction/hook/unknown items; never preserve reasoning content.
- [ ] Write byte fixtures with non-ASCII text and insignificant JSON whitespace;
  assert the result preserves exact UTF-8 bytes and rejects oversize or invalid
  UTF-8 without `JSON.parse`/reserialization.
- [ ] Run the focused test and confirm failure because the module is absent:

  ```bash
  cd examples/web
  node --test src/genui-codex-app-server.test.mjs
  ```

- [ ] Implement the lifecycle as a deterministic reducer plus a thin stream and
  timeout shell. Keep request construction and event transition decisions pure;
  only the shell writes stdin, reads lines, measures time, and terminates the
  child process.
- [ ] Send exactly one `initialize` with `experimentalApi=true`, one `initialized`
  notification, `account/read` with refresh disabled, and `model/list` per process
  before any candidate request. Reject a response before moving to the next state.
- [ ] Start a new ephemeral thread per slot with empty cwd, model, `medium` effort,
  no fallback, external sandbox metadata, no tools, no apps/environments/roots,
  and one turn containing only the frozen prompt and candidate output schema.
- [ ] Run the focused test until all protocol fixtures pass.
- [ ] Run `moon check`; commit only the protocol module and its test:

  ```bash
  git add examples/web/src/genui-codex-app-server.js \
    examples/web/src/genui-codex-app-server.test.mjs
  git commit -m "feat(genui): add fail-closed Codex app server client"
  ```

### Task 2: External Codex sandbox and credential lifecycle

**Files:**
- Create: `examples/web/scripts/genui-codex-sandbox.mjs`
- Create: `examples/web/scripts/genui-codex-sandbox.test.mjs`

**Interfaces:**

- Produce `prepareCodexSandbox({ runRoot, codexBinary, authSource, canaries }, deps)
  -> Promise<{ spawnProcess, contract, cleanup }>`.
- `contract` contains only reviewable versions/digests, mount/config key sets, and
  canary outcomes; it never contains auth bytes, host absolute paths, or secrets.
- `cleanup()` is idempotent, terminates descendants, deletes the private auth copy,
  and preserves only explicitly selected raw audit files outside cleanup paths.

- [ ] Write a detector positive control that observes a host canary through
  `/proc/<child-pid>/root` in an intentionally permissive namespace.
- [ ] Write the production namespace test proving the same detector cannot see the
  host canary, repository, worktree, host home, `/bin/sh`, coreutils, Git, Node,
  package managers, skills, memories, hooks, apps, plugins, or unrelated Codex
  state; assert `/work` is empty.
- [ ] Write positive tests that the static Codex binary, TLS/DNS inputs, `/proc`,
  `/dev`, tmpfs `/tmp`, `/work`, and the experiment-private Codex home are present.
- [ ] Write config tests for history `none`, analytics/feedback/update checks off,
  web search off, every forbidden tool/app/plugin feature off, instruction and
  context injection off, empty MCP/hooks/skills/apps/plugins, and no inherited
  shell environment. Compare every key path to the pinned v0.144.4 config schema.
- [ ] Write credential tests proving mode `0600`, no real Codex-home mount, no auth
  bytes in argv/env/contract/stderr/transcript, canary rejection, and deletion on
  success, protocol failure, timeout, and signal interruption.
- [ ] Run the focused test and confirm failure because the launcher is absent:

  ```bash
  cd examples/web
  node --test scripts/genui-codex-sandbox.test.mjs
  ```

- [ ] Implement the bubblewrap argv and minimal config generator. Mount only the
  design-approved roots; pass the smallest environment needed for TLS, DNS,
  locale, and the private `CODEX_HOME`.
- [ ] Start Codex only through this launcher. Do not expose a direct unsandboxed
  process path in the production runner.
- [ ] Run the focused test until every known-positive and fail-closed control passes.
- [ ] Run `moon check`; commit the launcher and test:

  ```bash
  git add examples/web/scripts/genui-codex-sandbox.mjs \
    examples/web/scripts/genui-codex-sandbox.test.mjs
  git commit -m "feat(genui): isolate Codex provider process"
  ```

### Task 3: Pure comparison policy and evidence finalizer

**Files:**
- Create: `examples/web/scripts/genui-provider-comparison.mjs`
- Create: `examples/web/scripts/genui-provider-comparison.test.mjs`

**Interfaces:**

- Produce `buildComparisonSchedule({ fixtures, repeats, randomizationSeed,
  ollamaSeeds, branch })`.
- Produce `evaluateStage1Eligibility({ manifest, slots, audit })`.
- Produce `qualifyProvider({ providerId, slots })`.
- Produce `normalizeProviderTranscript({ providerId, rawEvents, canaries })`.
- Produce `finalizeComparisonEvidence({ manifest, manifestSha256, frozenCommit,
  preflight, journal, rawArtifacts })` and a CLI that writes normalized transcript
  and aggregate evidence with exclusive creation.

- [ ] Write schedule tests for 60 immutable provider-labeled slots, 30 per
  provider and 10 per fixture. The `paired` branch activates all slots, preserves
  adjacent balanced pairs, and maps each repeated index to its exact Ollama seed.
  The `codex_only` branch activates only the 30 Codex slots, terminally marks all
  Ollama slots `ollama_not_operational`, and preserves the same slot identities
  and order. Require no seed field on Codex slots.
- [ ] Write Stage 1 tests that require 18 terminal slot records in both branches,
  with 18 active requests in `paired` and nine in `codex_only`. Independently
  fail each active-provider predicate: fixture preparation coverage, safety,
  mutation, credential leakage, identity drift, replay mismatch, and
  manifest/schedule/evidence/retention audit.
- [ ] Write qualification boundary tests by hand for 23/30 versus 24/30 overall,
  6/10 versus 7/10 per fixture, and each zero-tolerance predicate. Assert both
  qualifying providers remain candidates in `paired`; assert unavailable Ollama
  is not scored as a failure in `codex_only`.
- [ ] Write journal tests for strict schedule order, one terminal per slot, one
  start per active slot, no retry/replacement, ordinary failure continuation,
  global-stop filling, Stage 1 ineligibility filling 42 or 21 remaining active
  slots, preclassified unavailable slots, and crash/interruption classification.
- [ ] Write transcript tests for stable opaque request/thread/turn IDs, timing
  fields, methods, item types, usage, model observations, and terminal status;
  reject absolute paths, account metadata, secrets, and injected canaries.
- [ ] Write raw-artifact tests proving every raw digest is recorded, missing raw
  artifacts set auditability unavailable, aggregate evidence remains conservative,
  and no candidate/prompt/credential bytes enter aggregate evidence.
- [ ] Run the focused test and confirm failure because the policy module is absent:

  ```bash
  cd examples/web
  node --test scripts/genui-provider-comparison.test.mjs
  ```

- [ ] Implement policy as pure data transformations. Keep filesystem reads,
  exclusive writes, timestamps, and hashing in a thin finalizer shell.
- [ ] Run the focused test until all schedule, threshold, journal, transcript, and
  auditability cases pass.
- [ ] Run `moon check`; commit the policy and tests:

  ```bash
  git add examples/web/scripts/genui-provider-comparison.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "feat(genui): add provider comparison policy"
  ```

### Task 4: Immutable comparison manifest builder

**Files:**
- Create: `examples/web/scripts/build-genui-provider-comparison-manifest.mjs`
- Modify: `examples/web/scripts/build-genui-feasibility-manifest.mjs`
- Modify: `examples/web/scripts/genui-provider-comparison.test.mjs`

**Interfaces:**

- Manifest builder consumes the completed diagnostic summary, both provider
  identities, frozen input and validation-command digests, pure schedule output,
  conservative numeric limits, and the logical private-artifact contract.
- A safe completed diagnostic selects `paired` after a passing Ollama
  qualification or `codex_only` after an Ollama runtime/model/request/timeout/
  HTTP/candidate/preparation failure. Safety, credential, budget, isolation, or
  evidence-integrity failure is non-manifestable.
- The builder refuses dirty repositories, existing output paths, raw paths
  inside the repository, and a branch inconsistent with the diagnostic summary.
  Tests use injected summaries and never create the live manifest.

- [ ] Extend tests to require manifest version, study ID, claim scope, source
  commit, diagnostic digest, selected branch, all 60 slots, active/not-run
  classifications, decision rules, provider ordering, the exact ten-value
  Ollama seed vector and per-slot mapping, candidate/prompt/schema/fixture/
  capability/rubric/preparation digests, Ollama identity, Codex CLI/catalog/slug/
  effort/auth identity, bubblewrap/config contract, branch-specific numeric
  limits, commands, and logical private/public artifact locations.
- [ ] Add red tests proving the builder rejects a dirty repository, an existing
  output, an absolute raw path serialized into public evidence, a repository-local
  raw root, an incomplete seven-step diagnosis, branch/diagnostic mismatch,
  unsafe diagnostic failure, and any symbolic or out-of-range token limit. Add
  positive tests for both a passing `paired` summary and a safe Ollama-failed
  `codex_only` summary.
- [ ] Run the focused test and confirm failure at the missing builder import:

  ```bash
  cd examples/web
  node --test scripts/genui-provider-comparison.test.mjs
  ```

- [ ] Export only the existing clean-repository and digest helpers from the old
  builder. Assert its v2 manifest snapshot remains byte-for-byte unchanged.
- [ ] Implement the new builder with exclusive output creation and an in-memory
  dependency-injected path for tests. Require the private artifact contract to
  name `$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/` without
  serializing a host-specific absolute path.
- [ ] Run focused tests and `moon check`; commit the builder separately:

  ```bash
  git add examples/web/scripts/build-genui-provider-comparison-manifest.mjs \
    examples/web/scripts/build-genui-feasibility-manifest.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "feat(genui): build immutable provider manifest"
  ```

### Task 5: Comparison runner and credentialed smoke entry point

**Files:**
- Create: `examples/web/scripts/run-genui-provider-comparison-study.mjs`
- Create: `examples/web/scripts/smoke-genui-codex-provider.mjs`
- Modify: `examples/web/scripts/genui-provider-comparison.test.mjs`

**Interfaces:**

- Runner consumes only the reviewed manifest, an absolute validated `runRoot`,
  the sandbox factory, injected Codex and Ollama attempt functions, and the
  unchanged browser/MoonBit request gate. Task 5 tests the injected provider
  boundary; Task 6 binds the explicit-seed Ollama core.
- Smoke CLI owns one fixed synthetic fixture that cannot equal any scored case
  ID. It uses the same sandbox, Codex session, prompt/schema, timeout, request
  gate, and MoonBit path, then writes exclusive private raw and safe-summary
  files under `runRoot`.

- [ ] Add runner tests for unused outputs, clean frozen commit, preflight before
  provider access, shared request inputs, `paired` and `codex_only` execution,
  all ten repeated indices passing their exact manifest seed to the injected
  Ollama attempt in `paired`, new Codex thread per slot, no retry, process
  restart after failure, branch-specific Stage 1 gate, optional Stage 2, global
  stop, durable journal ordering, inactive-slot not-run records, and finalizer
  invocation. Assert the runner never invokes Ollama in `codex_only` and never
  changes the manifest-selected branch.
- [ ] Add raw-root tests requiring an absolute descendant of `XDG_STATE_HOME`,
  rejecting unset `XDG_STATE_HOME`, repository-local paths, symlink escapes,
  directories not mode `0700`, files not mode `0600`, and pre-existing outputs.
- [ ] Add smoke tests for a distinct synthetic fixture, exactly one provider call,
  production sandbox/session/request-gate injection, successful MoonBit replay,
  exclusive outputs, cleanup, canary rejection, and no second request after any
  failure.
- [ ] Run the focused test and confirm failure at the missing runner and smoke
  imports.
- [ ] Implement append-and-fsync journal events before and after each slot.
  Ordinary slot failures continue; global failures terminate the active process
  and fill all remaining slots without provider access.
- [ ] Route candidate bytes through the existing Playwright capability gate and
  MoonBit pipeline. Do not add a provider-only validation or commit route.
- [ ] Implement the smoke CLI with its fixed synthetic fixture and exactly one
  terminal attempt. Keep it independent of the scored schedule and manifest.
- [ ] Run focused and old feasibility tests to prove no baseline drift:

  ```bash
  cd examples/web
  node --test scripts/genui-provider-comparison.test.mjs \
    scripts/run-genui-feasibility-study.test.mjs
  ```

- [ ] Run `moon check`; commit runner and smoke separately from the manifest:

  ```bash
  git add examples/web/scripts/run-genui-provider-comparison-study.mjs \
    examples/web/scripts/smoke-genui-codex-provider.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "feat(genui): orchestrate provider comparison"
  ```
### Task 6: Byte-equivalent Ollama request-core extraction

**Files:**
- Modify: `examples/web/src/genui-feasibility-provider.js`
- Modify: `examples/web/src/genui-feasibility-provider.test.mjs`
- Modify: `examples/web/scripts/genui-provider-comparison.test.mjs`
- Modify: `examples/web/scripts/run-genui-provider-comparison-study.mjs`

**Interfaces:**

- Produce `buildOllamaGenerationRequest({ fixture, seed, frozenIdentity })` and
  `callOllamaAttempt({ fixture, seed, frozenIdentity }, deps)` from the existing
  provider module. `callOllamaSlot` maps its unchanged three-slot setting to the
  shared core; the comparison runner passes the exact reviewed manifest seed.

- [ ] Add red tests that snapshot the current Ollama URL, method, headers, and
  request body. Require `callOllamaSlot` to remain byte-for-byte identical for all
  three legacy seeds, require `callOllamaAttempt` to preserve those bytes, and
  cover all ten comparison seeds without treating repeated index as feasibility
  `slotId`.
- [ ] Run provider and comparison tests and confirm failure at the missing request
  builder, explicit-seed core, and production runner binding.
- [ ] Extract request construction and provider lifecycle from `callOllamaSlot`
  without changing its three-slot validation, settings, identity checks, terminal
  classes, or telemetry. The new core accepts only an integer seed.
- [ ] Bind the comparison runner to `scheduleSlot.ollamaSeed`; reject a missing
  seed or value outside the manifest vector before provider access. Never pass a
  comparison repeated index to `callOllamaSlot`.
- [ ] Run focused tests and `moon check`; commit the byte-equivalent extraction:

  ```bash
  git add examples/web/src/genui-feasibility-provider.js \
    examples/web/src/genui-feasibility-provider.test.mjs \
    examples/web/scripts/run-genui-provider-comparison-study.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "refactor(genui): extract explicit-seed Ollama attempt"
  ```

### Task 7: Seven-step Ollama diagnostic and three-fixture gate

**Files:**
- Create: `examples/web/scripts/diagnose-genui-ollama.mjs`
- Create: `examples/web/scripts/diagnose-genui-ollama.test.mjs`
- Modify: `examples/web/scripts/build-genui-provider-comparison-manifest.mjs`
- Modify: `examples/web/scripts/genui-provider-comparison.test.mjs`

**Interfaces:**

- Produce `buildOllamaDiagnosticPlan({ frozenIdentity, fixtures })` as the ordered
  sequence: environment/model inspection, load without generation, minimal text,
  JSON object mode, unrelated minimal JSON Schema, frozen candidate schema with a
  synthetic prompt, then all three trusted fixture prompts through the selected
  corrected request.
- Produce a safe qualification summary containing probe order, the one changed
  request dimension per transition, request/response and server-log digests,
  identity observations, preparation classifications, and
  `qualifiedForComparison`. Raw bodies and logs exist only below `runRoot`.
- If `gemma4:e2b` fails before the Canopy prompt, run one known-working installed
  model as a runtime control. The control diagnoses runtime versus model failure;
  it never becomes a comparison arm.
- The manifest builder accepts either: (a) a passing summary proving all seven
  steps completed, the selected request returned candidate bytes for all three
  fixtures, identity matched before and after each request, every candidate
  reached MoonBit preparation, and request settings plus digest were frozen; or
  (b) a safe failed summary proving the diagnostic followed the frozen order,
  retained the first failure, completed any required runtime control, preserved
  identity and evidence integrity, and made no request after the terminal gate.
  It selects `paired` for (a) and `codex_only` for (b).

- [ ] Add red tests for exact probe order, stop-at-first-failing-prerequisite,
  one-variable-at-a-time transitions, conditional runtime control, HTTP 500 JSON
  and text bodies, timeout, invalid identity, body truncation, header allowlist,
  server-log digest, exclusive output, no retry, and no mutation of v1/v2 inputs.
- [ ] Add three-fixture gate tests for missing fixture, candidate absence,
  identity drift, preparation failure, request-digest mismatch, runtime-control
  substitution, and the passing case. Require unsafe, incomplete, or
  non-terminal summaries to block manifest creation; require safe Ollama
  qualification failures to select `codex_only`, and the passing summary to
  select `paired`.
- [ ] Run the diagnostic and comparison tests and confirm failure at the missing
  diagnostic module and qualification contract:

  ```bash
  cd examples/web
  node --test scripts/diagnose-genui-ollama.test.mjs \
    scripts/genui-provider-comparison.test.mjs
  ```

- [ ] Implement the deterministic probe plan and state transition. Each probe
  writes exclusive raw evidence under `runRoot`; public-safe output contains only
  bounded metadata and digests.
- [ ] Implement the three-fixture qualification summary and deterministic
  manifest branch gate. A passing qualification selects `paired`; a safe,
  terminal Ollama failure selects `codex_only`; incomplete diagnosis or any
  safety, identity, credential, budget, isolation, or evidence-integrity failure
  makes manifest creation impossible.
- [ ] Run focused tests and `moon check`; commit the diagnostic gate separately:

  ```bash
  git add examples/web/scripts/diagnose-genui-ollama.mjs \
    examples/web/scripts/diagnose-genui-ollama.test.mjs \
    examples/web/scripts/build-genui-provider-comparison-manifest.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "feat(genui): qualify Ollama comparison request"
  ```
### Task 8: Deterministic verification and pre-credential review

**Files:** No product-file changes. Review fixes receive their own commits.

- [ ] Run the complete focused Node suite:

  ```bash
  cd examples/web
  node --test src/genui-feasibility-fixtures.test.mjs \
    src/genui-feasibility-provider.test.mjs \
    src/genui-feasibility-demo.test.mjs \
    src/genui-feasibility-flow.test.mjs \
    src/genui-codex-app-server.test.mjs \
    scripts/genui-codex-sandbox.test.mjs \
    scripts/genui-provider-comparison.test.mjs \
    scripts/diagnose-genui-ollama.test.mjs \
    scripts/run-genui-feasibility-study.test.mjs
  ```

- [ ] Run MoonBit preparation/materialization/rubric/replay tests and the workspace
  check:

  ```bash
  NEW_MOON_MOD=0 moon test ffi/jsx
  NEW_MOON_MOD=0 moon check
  ```

- [ ] Build JavaScript, typecheck, and verify development browser behavior:

  ```bash
  NEW_MOON_MOD=0 moon build --target js
  cd examples/web
  npx tsc --noEmit
  npx playwright test tests/genui.spec.ts --project=chromium --grep feasibility
  ```

- [ ] Build production and verify the preview request gate and local-provider
  marker without weakening existing assertions:

  ```bash
  cd examples/web
  NEW_MOON_MOD=0 npm run build
  npx playwright test --config=playwright.preview.config.ts \
    --project=chromium --grep "local study runner|local provider marker"
  ```

- [ ] Run `moon info && moon fmt`; assert no unintended `.mbti` drift.
- [ ] Obtain an independent different-model review of the full diff. Require exact
  citations for protocol ordering, experimental negotiation, sandbox mounts,
  credential handling, state-machine terminality, schedule math, seven-step
  Ollama qualification, transcript redaction, XDG raw retention, conservative
  budget math, and unchanged MoonBit/browser paths.
- [ ] Fix every validated blocker, rerun the narrow failing check after each edit,
  then rerun this task's full deterministic verification.
- [ ] Record the reviewed commit SHA. No credentialed request may use a later
  unreviewed commit.
### Task 9: One credentialed Codex smoke and conservative budget freeze

**Files:**
- Modify: `examples/web/scripts/build-genui-provider-comparison-manifest.mjs`
- Modify: `examples/web/scripts/genui-provider-comparison.test.mjs`
- Execute: `examples/web/scripts/smoke-genui-codex-provider.mjs`, created and
  reviewed in Task 5; this task does not modify it.
- Create private smoke artifacts under `$RUN_ROOT/smoke/`, where `RUN_ROOT` is an
  absolute descendant of `$XDG_STATE_HOME/canopy/genui-provider-benchmark/`.

- [ ] Require `XDG_STATE_HOME` to be set. Define a fresh versioned `RUN_ROOT`,
  create it and its smoke child with mode `0700`, and prove that neither resolves
  inside the repository.
- [ ] Verify the Task 8 reviewed commit is checked out, the tree is clean, the
  installed binary reports exactly `codex-cli 0.144.4`, bubblewrap reports
  `0.9.0`, and the real auth file is readable only by the owner.
- [ ] Run the sandbox positive controls and capture their raw/digest record under
  `RUN_ROOT` before provider access.
- [ ] Execute exactly one credentialed request against a synthetic fixture absent
  from the three scored fixtures. Use the production sandbox, protocol, prompt
  builder, schema, timeout, MoonBit preparation path, and XDG run root:

  ```bash
  cd examples/web
  export RUN_ROOT="${XDG_STATE_HOME:?XDG_STATE_HOME must be set}/canopy/genui-provider-benchmark/2026-07-15-provider-comparison-v1"
  install -d -m 0700 "$RUN_ROOT/smoke"
  node scripts/smoke-genui-codex-provider.mjs \
    --run-root "$RUN_ROOT" \
    --raw-output "$RUN_ROOT/smoke/raw.json" \
    --summary-output "$RUN_ROOT/smoke/summary.json"
  ```

  If the command, isolation checks, or MoonBit path fails, stop without creating
  a scored manifest or making another credentialed request.
- [ ] Require one completed turn, exactly one final agent message, no forbidden
  item, exact candidate bytes, successful MoonBit preparation, replay equality,
  cleanup success, mode `0600` outputs, and no canary in stderr, JSONL,
  transcript, or diagnostics. Token telemetry must be present with a positive
  integer `totalTokens` and non-negative integer component counts.
- [ ] Freeze numeric limits with this preregistered rule:
  - slot positions: 60, with the single smoke recorded separately;
  - active scored requests: 60 for `paired` or 30 for `codex_only`;
  - candidate bytes: existing `GENUI_PROVIDER_SETTINGS.maxCandidateBytes` per
    active slot;
  - slot wall time: 120,000 ms per active request;
  - per-request observed-token ceiling:
    `max(16000, ceilTo1000(4 * smokeTotalTokens))`;
  - pre-manifest stop: reject a derived per-request ceiling above 32,000;
  - run observed-token ceiling: accepted per-request ceiling multiplied by the
    branch's active-request count, with an absolute maximum of 1,920,000 for
    `paired` or 960,000 for `codex_only`;
  - run wall-time ceiling: the branch's active-request count multiplied by the
    slot timeout, plus five minutes of fixed orchestration allowance.
- [ ] Add exact boundary tests for both branches: missing, non-integer, negative,
  or zero smoke totals stop before manifest creation; totals 1 and 4,000 freeze
  16,000; 4,001 freezes 17,000; 8,000 freezes 32,000; 8,001 stops before
  manifest creation. Prove each manifest contains numbers only, never a formula
  or symbolic value.
- [ ] Rerun comparison tests and `moon check`; commit only numeric-limit logic,
  never private smoke artifacts:

  ```bash
  cd examples/web
  node --test scripts/genui-provider-comparison.test.mjs
  cd ../..
  moon check
  git add examples/web/scripts/build-genui-provider-comparison-manifest.mjs \
    examples/web/scripts/genui-provider-comparison.test.mjs
  git commit -m "test(genui): freeze conservative comparison budgets"
  ```
### Task 10: Execute Ollama diagnosis and freeze the manifest

**Files:**
- Create: `examples/web/studies/2026-07-15-genui-provider-comparison-v1.json`
- Create private diagnostic artifacts under `$RUN_ROOT/diagnostics/`; no raw
  diagnostic path may be inside the repository.

- [ ] From the clean post-smoke commit, execute the Task 7 diagnostic plan in
  order: environment/model inspection, load-only, minimal text, JSON object,
  unrelated minimal JSON Schema, frozen schema with synthetic prompt, then all
  three trusted fixture prompts through the selected corrected request. Change
  one request dimension per transition and never retry a failed probe.
- [ ] If `gemma4:e2b` fails before the Canopy prompt, run one known-working
  installed model as the runtime control. Record the distinction and stop; the
  control cannot become the comparison arm.
- [ ] Execute the diagnostic with the reviewed XDG run root:

  ```bash
  cd examples/web
  node scripts/diagnose-genui-ollama.mjs \
    --manifest studies/2026-07-15-genui-local-llm-v2.json \
    --run-root "$RUN_ROOT" \
    --summary-output "$RUN_ROOT/diagnostics/qualification-summary.json"
  ```

- [ ] Verify the safe summary proves either a complete three-fixture
  qualification or a terminal safe failure at the first failed prerequisite.
  In both cases require frozen order, exact request transitions, identity
  preservation, complete raw digests, bounded public metadata, mode-`0600` raw
  bodies and logs, and no provider request after the terminal outcome.
- [ ] Classify the branch without discretion: select `paired` only if all seven
  steps completed, all three fixtures returned candidate bytes, every identity
  observation matched, every candidate reached MoonBit preparation, and the
  selected request settings and digest are fixed. Select `codex_only` only for a
  completed safe Ollama failure. Stop with no manifest on incomplete diagnosis
  or any safety, identity, credential, budget, isolation, or evidence-integrity
  failure.
- [ ] Run the manifest builder once with exclusive creation:

  ```bash
  node scripts/build-genui-provider-comparison-manifest.mjs \
    --ollama-manifest studies/2026-07-15-genui-local-llm-v2.json \
    --codex-smoke-summary "$RUN_ROOT/smoke/summary.json" \
    --ollama-qualification-summary "$RUN_ROOT/diagnostics/qualification-summary.json" \
    --output studies/2026-07-15-genui-provider-comparison-v1.json
  ```

- [ ] Confirm the manifest contains all 60 immutable slot positions, the
  diagnostic-selected branch, active/not-run classification, exact numeric
  limits from Task 9, and no later branch-switch mechanism. `paired` has 60
  active requests; `codex_only` has 30 active Codex requests and 30 inactive
  Ollama positions recorded as not run. Recompute every referenced source,
  input, identity, request, configuration, and raw-artifact digest independently.
- [ ] Obtain an independent review of the manifest, every code change since the
  Task 8 reviewed commit, branch derivation, schedule balance, identities,
  limits, commands, logical artifact paths, and the complete Ollama diagnostic
  record.
- [ ] If review changes executable code or manifest semantics, discard the
  manifest, fix and re-review the code, then use a new versioned manifest path.
  Never overwrite the reviewed file.
- [ ] Commit the accepted manifest alone and record its reviewed commit SHA.
  Stage 1 must run from that exact clean commit:

  ```bash
  git add examples/web/studies/2026-07-15-genui-provider-comparison-v1.json
  git commit -m "experiment(genui): freeze provider comparison manifest"
  ```
### Task 11: Execute Stage 1 and conditional Stage 2

**Files:**
- Create private journal and provider artifacts only below the reviewed
  `$RUN_ROOT`; no raw output may be inside the repository.

- [ ] Confirm the frozen commit, clean tree, manifest digest, selected branch,
  unused `$RUN_ROOT/journal.jsonl` and `$RUN_ROOT/raw/` paths, `0700`/`0600`
  modes, credential/config modes, and deterministic preflight.
- [ ] Execute Stage 1 once:

  ```bash
  cd examples/web
  node scripts/run-genui-provider-comparison-study.mjs \
    --manifest studies/2026-07-15-genui-provider-comparison-v1.json \
    --run-root "$RUN_ROOT" \
    --stage stage1
  ```

  Require terminal records for all 18 Stage 1 positions in exact manifest order.
  `paired` performs 18 active requests. `codex_only` performs nine active Codex
  requests and writes the nine frozen Ollama not-run records without provider
  access. Do not rerun or replace any slot after ordinary or process failure.
- [ ] Finalize and independently verify the branch-specific Stage 1 eligibility
  object from the frozen predicates. In `paired`, both providers must pass. In
  `codex_only`, only Codex is active and Ollama's preclassified not-run records
  are not failures.
- [ ] If ineligible, do not contact any provider again. Finalize every remaining
  position in manifest order: 42 active positions become not run in `paired`;
  21 active Codex positions become not run and 21 inactive Ollama positions
  retain `ollama_not_operational` in `codex_only`.
- [ ] If eligible, execute exactly the branch's remaining active requests:

  ```bash
  node scripts/run-genui-provider-comparison-study.mjs \
    --manifest studies/2026-07-15-genui-provider-comparison-v1.json \
    --run-root "$RUN_ROOT" \
    --stage stage2
  ```

  `paired` performs 42 requests. `codex_only` performs 21 Codex requests and
  writes the 21 frozen Ollama not-run records without provider access. Apply the
  same no-retry rule and stop globally on safety, identity, credential, budget,
  isolation, or evidence-integrity failure.
- [ ] After finalization, require exactly one terminal record for all 60 manifest
  positions, make the raw artifact tree read-only, and record each artifact
  digest plus availability state. Preserve the XDG tree; do not move it into the
  repository for review or archival.
### Task 12: Commit evidence and close the engineering decision

**Files:**
- Create:
  `docs/evidence/2026-07-15-generative-ui-provider-comparison-v1-transcript.jsonl`
- Create: `docs/evidence/2026-07-15-generative-ui-provider-comparison-v1.json`
- Modify: `docs/plans/2026-07-15-generative-ui-provider-comparison-design.md`
  only to record the observed outcome and evidence links; do not rewrite the
  frozen decision rule.

- [ ] Generate normalized transcript and aggregate evidence once with exclusive
  output creation:

  ```bash
  cd examples/web
  node scripts/genui-provider-comparison.mjs \
    --manifest studies/2026-07-15-genui-provider-comparison-v1.json \
    --run-root "$RUN_ROOT" \
    --transcript-output ../../docs/evidence/2026-07-15-generative-ui-provider-comparison-v1-transcript.jsonl \
    --evidence-output ../../docs/evidence/2026-07-15-generative-ui-provider-comparison-v1.json
  ```

- [ ] Verify every manifest position has exactly one terminal class, inactive
  Ollama positions remain `ollama_not_operational`, qualification thresholds
  use 24/30 overall and 7/10 per fixture for each active provider, zero-tolerance
  predicates are enforced, and all qualifying active providers remain candidates.
- [ ] Verify aggregate evidence records the selected branch and diagnostic
  outcome. For each active provider it contains Wilson intervals, fixture and
  overall pass rates, p50/p95 latency, token usage, failure counts, identity
  observations, raw digests, and auditability; inactive providers receive no
  fabricated rates or failures. Include the explicit time-bounded/non-superiority
  caveat. Evidence may contain the logical run ID but no absolute XDG path.
- [ ] Run secret/path canary scans over stderr, raw JSONL, normalized transcript,
  diagnostics, and aggregate evidence. A detector must first fire on an injected
  known-positive canary.
- [ ] Rerun the deterministic verification from Task 8 against the frozen commit.
- [ ] Obtain a final different-model review of normalized transcript, aggregate
  math, raw-digest coverage, claim scope, artifact-path redaction, and outcome
  wording.
- [ ] Record the observed outcome and evidence links in the design document without
  changing the frozen decision rule.
- [ ] Commit normalized transcript, aggregate evidence, and the outcome link
  separately from code. Never commit auth state, raw provider messages, raw
  prompts/candidates, absolute XDG paths, or participant/product-value claims:

  ```bash
  git add \
    docs/evidence/2026-07-15-generative-ui-provider-comparison-v1-transcript.jsonl \
    docs/evidence/2026-07-15-generative-ui-provider-comparison-v1.json \
    docs/plans/2026-07-15-generative-ui-provider-comparison-design.md
  git commit -m "experiment(genui): record provider comparison evidence"
  ```

- [ ] Record one branch-valid engineering outcome: `paired` permits neither,
  Ollama only, Codex only, or both; `codex_only` permits Codex or neither and
  records Ollama as unavailable. Open a separate user-value campaign only if
  later requested; this benchmark cannot establish usefulness.

## Acceptance criteria

- [ ] Codex App Server cannot start a scored turn without experimental negotiation,
  exact model selection, fallback disabled, expected auth mode, and catalog digest.
- [ ] The external namespace exposes no repository, worktree, host home, shell,
  executable toolchain, unrelated Codex state, or inherited secret.
- [ ] Every forbidden item, lifecycle mismatch, timeout, malformed line, duplicate
  final message, identity drift, leak, and budget stop fails closed.
- [ ] Candidate bytes reach the unchanged MoonBit/browser path without JavaScript
  semantic interpretation.
- [ ] The ordered Ollama diagnostic changes one request dimension per probe,
  retains failure bodies and logs privately, and uses a known-working model only
  as the conditional runtime control.
- [ ] A manifest exists only when the diagnostic is complete and safe. A passing
  Ollama qualification selects `paired`; a terminal safe Ollama failure selects
  `codex_only`; incomplete or unsafe evidence blocks manifest creation.
- [ ] Every raw journal, provider message, stderr stream, response body, and log is
  created exclusively below `$XDG_STATE_HOME/canopy/genui-provider-benchmark/`
  with directory mode `0700` and file mode `0600`; no raw artifact or absolute
  XDG path is committed.
- [ ] The manifest freezes all 60 slot positions, selected branch, and
  active/not-run classification before Stage 1. The runner performs no retry,
  replacement, branch change, adaptive slot change, or concurrent provider
  request.
- [ ] The manifest freezes all ten Ollama seeds. Every repeated index in `paired`
  reaches its exact seed without changing the legacy three-slot
  `callOllamaSlot` contract; `codex_only` never invokes Ollama.
- [ ] A positive integer `smokeTotalTokens` is required. The per-request
  observed-token ceiling is `max(16000, ceilTo1000(4 * smokeTotalTokens))`;
  missing, invalid, or zero telemetry blocks manifest creation, as do derived
  values above 32,000. The run ceiling is the accepted per-request value times
  the branch's active-request count: 60 for `paired` or 30 for `codex_only`,
  capped at 1,920,000 or 960,000 respectively.
- [ ] Stage 2 runs only after every branch-specific Stage 1 eligibility predicate
  passes.
- [ ] Qualification math, normalized transcript, raw-loss downgrade, and aggregate
  evidence pass deterministic boundary tests.
- [ ] One reviewed synthetic Codex smoke succeeds before any scored request.
- [ ] Focused Node, MoonBit, TypeScript, development browser, production build, and
  production preview verification pass.
- [ ] Independent reviews pass before the credentialed smoke, manifest freeze, and
  final recommendation.
