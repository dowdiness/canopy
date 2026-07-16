# Generative UI local-LLM technical feasibility implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove whether a frozen local Ollama model can generate bounded candidates for three structurally different data fixtures, while MoonBit remains the trust authority and only rubric-passing host-materialized output reaches the existing session commit boundary.

**Architecture:** The local provider returns an untrusted whole-response candidate. A validate-only MoonBit FFI path reuses the current decoder, capability checks, and `GenerativeUiCandidate::validate`; a pure browser-side host materializer then performs the frozen filter, projection, and aggregation and produces a safe Stack/Panel/Text output candidate plus evidence. A separate fixture rubric evaluates that evidence, and only a passing output candidate is committed through the existing replay, dry-run, DOM apply, and revision transaction. Production replays recorded control candidates through the same deterministic path but contains no provider endpoint or provider settings.

**Tech Stack:** MoonBit JS FFI, existing `dowdiness/cognition` Generative UI domain, JavaScript ES modules, Vite middleware, Ollama `/api/generate`, Node test runner, Playwright, SHA-256 evidence digests.

## Global Constraints

- The design source is `docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility.md`.
- The MoonBit runtime validator is the sole trust authority; the provider JSON Schema is generation guidance only.
- Provider output never owns source data, effects, DOM access, mutable host state, or revision commit authority.
- The fixture rubric stays out of the provider prompt, provider schema, generic validator, and host materializer.
- Generic validation, materialization, rubric, dry-run, or application failure must leave the last valid UI, host state, and committed revision unchanged.
- Three predetermined slots run once for each frozen valid fixture. No retry, replacement, prompt edit, or preferred-result rerun is allowed.
- Production contains recorded controls and the shared deterministic path, but no Ollama URL, local-provider route, model setting, credential path, external request, or telemetry collector.
- This work may establish `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE` only. It makes no usability, adoption, task-performance, model-superiority, or product-value claim.
- Use one file per edit call. Run `NEW_MOON_MOD=0 moon check` after every file edit before editing another file.
- Write failing behavioral tests before each implementation. For MoonBit files, also use `moon ide` where it resolves; if mixed-manifest IDE lookup still fails, inspect the defining `.mbt` and `.mbti` directly rather than retrying the same command.
- Before implementing Task 2, an independent reviewer using a model different from the driving model must inspect the operator, aggregation, rubric-separation, and commit-gating design and answer: “Is this algorithm correct? What edge cases break it?”
- Plans remain prose-only for non-trivial algorithms. Base the implementation on failing tests and the invariants below.

## File and Responsibility Map

- `ffi/jsx/generative_ui_replay_adapter.mbt`: one shared decode-and-validate core plus an experiment-only validate-without-commit FFI entry point.
- `ffi/jsx/session_contract_wbtest.mbt`: typed validation-only success, failure, and no-session/no-DOM-effect contracts.
- `ffi/jsx/moon.pkg`: JavaScript export list for the experiment-only validator.
- `examples/web/src/genui-feasibility-fixtures.js`: frozen input fixtures, user tasks, host capabilities, task filter values, and source normalization; no expected outcomes.
- `examples/web/src/fixtures/inventory.json`: nested JSON fixture source.
- `examples/web/src/fixtures/incidents-csv.js`: one canonical raw CSV string used by browser and Vite middleware.
- `examples/web/src/genui-candidate-schema.js`: provider-only, case-neutral JSON Schema for the bounded raw candidate shape.
- `examples/web/src/genui-candidate-materializer.js`: pure generic extraction, filter/project/aggregate logic, safe output-candidate construction, and evidence production.
- `examples/web/src/genui-feasibility-rubric.js`: frozen task-specific expected structure and outcome checks; never imported by provider code.
- `examples/web/src/genui-recorded-candidates.js`: hand-authored recorded control candidates for production replay; controls are not represented as local-model evidence.
- `examples/web/src/genui-feasibility-flow.js`: validate → materialize → rubric → commit orchestration and terminal classifications; no DOM rendering logic.
- `examples/web/src/genui-feasibility-*.test.mjs`: Node behavioral tests for fixture normalization, materialization, rubric separation, provider contract, and transaction ordering.
- `examples/web/vite-plugin-genui-feasibility.ts`: development-only request-size/method checks and Ollama transport adapter.
- `examples/web/vite.config.ts`: clean cutover from the Spike 0 plugin to the feasibility plugin.
- `examples/web/src/genui.js`: browser FFI wrappers, dedicated feasibility session ownership, recorded/live action wiring, and visible status rendering.
- `examples/web/genui.html`: fixture selector, recorded/live action, dedicated committed-output root, terminal status, and development-only attempt metadata.
- `examples/web/tests/genui.spec.ts`: deterministic development browser contracts.
- `examples/web/preview-tests/genui-preview.spec.ts`: production recorded replay and forbidden-endpoint/bundle checks.
- `examples/web/playwright.feasibility.config.ts`: isolated, non-reusing live-study server and long timeout.
- `examples/web/tests/genui-feasibility-live.spec.ts`: exactly nine credential-free local attempts and raw slot evidence.
- `examples/web/scripts/run-genui-feasibility-study.mjs`: clean-commit freeze, deterministic preflight, live execution, digest aggregation, and final technical decision evidence.
- `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility.json`: generated final evidence; written only by the frozen study runner.
- Remove after clean cutover: `examples/web/vite-plugin-genui-spike.ts`, `examples/web/src/genui-spike-case.js`, `examples/web/src/genui-spike-recipe.js`, and `examples/web/src/genui-spike-recipe.test.mjs`.

---

### Task 1: Add a Validation-Only MoonBit Trust Boundary

**Files:**
- Modify: `ffi/jsx/generative_ui_replay_adapter.mbt`
- Modify: `ffi/jsx/session_contract_wbtest.mbt`
- Modify: `ffi/jsx/moon.pkg`

**Interfaces:**
- Consumes: existing `decode_candidate_json`, `decode_capabilities_json`, `GenerativeUiCandidate::validate`, and diagnostic rendering used by `commit_candidate_with_lifecycle`.
- Produces: `pub fn __jsx_validate_candidate_json(candidate_json : String, capabilities_json : String) -> String`.
- Result schema: `schema_version: 1`, `success: Bool`, `diagnostics: Array[String]`, and nullable `error` with the existing `CandidateDecodeError`, `CapabilityDecodeError`, or `CandidateValidationError` codes.
- Invariant: the new entry point creates no session, touches no DOM, starts no lifecycle, and advances no revision.
- Invariant: commit and validate-only paths call one private decode/capability/semantic-validation core so their acceptance behavior cannot drift.

- [ ] **Step 1: Map reuse before defining the shared helper.**
  - Inspect `decode_candidate_json`, `decode_capabilities_json`, `GenerativeUiCandidate::validate`, `render_result_json`, and the existing session result JSON structs.
  - Check MoonBit core `Result`, `Json`, `Array::map`, and tuple/enum error representation. Reuse `Result`, `Json`, and `Array::map`; do not create a second candidate decoder or capability parser.
  - Record why the async driver and `GenerativeUiLifecycle` are not reused here: validation-only must have no request/session state.

- [ ] **Step 2: Write failing white-box contracts.**
  - A valid Stack/Text candidate with empty capabilities returns success without installing a document or creating a session.
  - Malformed JSON returns `CandidateDecodeError` with no mounted IDs or revision field.
  - A disallowed binding returns `CandidateValidationError` and preserves structured diagnostics.
  - `raw_html` and `expression` candidates remain rejected.
  - The same valid and invalid inputs produce the same accept/reject classification through validate-only and existing replay validation when replay is given a valid session.
  - Run `NEW_MOON_MOD=0 moon check` immediately after editing the test file.

- [ ] **Step 3: Run the focused test and confirm the expected failure.**
  - Run `moon test ffi/jsx -f session_contract_wbtest.mbt`.
  - Expected: compile failure because `__jsx_validate_candidate_json` is absent.

- [ ] **Step 4: Extract the shared private validation core.**
  - Return either the opaque validated candidate or the exact error code/message/diagnostic payload needed by both callers.
  - Preserve all existing replay error precedence and messages.
  - Make no change to `GenerativeUiCandidate`, lifecycle semantics, session handles, or revision behavior.
  - Run `NEW_MOON_MOD=0 moon check` immediately after editing `generative_ui_replay_adapter.mbt`.

- [ ] **Step 5: Export the validate-only function to JavaScript.**
  - Add only `__jsx_validate_candidate_json` to the JS export list.
  - Keep the double-underscore experimental name; do not present it as a renderer-neutral or provider-neutral public contract.
  - Run `NEW_MOON_MOD=0 moon check` immediately after editing `moon.pkg`.

- [ ] **Step 6: Verify and commit the trust boundary.**
  - Run `moon test ffi/jsx -f session_contract_wbtest.mbt`.
  - Run `moon test ffi/jsx`.
  - Expected: all focused and package tests pass; existing replay errors and revisions remain unchanged.
  - Run `moon info && moon fmt`, inspect `ffi/jsx/pkg.generated.mbti`, and confirm the only intended interface addition is the experimental function.
  - Commit message: `feat(genui): expose validation-only candidate boundary`.

### Task 2: Freeze Fixtures, Pure Materialization, and Separate Rubrics

**Files:**
- Create: `examples/web/src/fixtures/inventory.json`
- Create: `examples/web/src/fixtures/incidents-csv.js`
- Create: `examples/web/src/genui-feasibility-fixtures.js`
- Create: `examples/web/src/genui-candidate-materializer.js`
- Create: `examples/web/src/genui-feasibility-rubric.js`
- Create: `examples/web/src/genui-recorded-candidates.js`
- Create: `examples/web/src/genui-candidate-materializer.test.mjs`
- Remove after replacement tests pass: `examples/web/src/genui-spike-case.js`, `examples/web/src/genui-spike-recipe.js`, `examples/web/src/genui-spike-recipe.test.mjs`

**Interfaces:**
- Produces: `GENUI_FEASIBILITY_FIXTURES`, `getFeasibilityFixture(caseId)`, and `capabilitiesJsonForFixture(fixture)`.
- Produces: `materializeValidatedCandidate(candidateJson, fixture)` returning either a generic materialization error or `{ outputCandidateJson, evidence }`.
- Produces: `evaluateFixtureRubric(caseId, evidence)` returning `{ passed, failures }` without changing evidence.
- Produces: `RECORDED_GENUI_CANDIDATES`, one case-neutral raw candidate per frozen fixture.
- Materialization evidence includes case ID, source format, binding, filter field/operator/value, projected fields, matched stable row keys in source order, summary field/aggregation/value, and the safe output candidate.

**Frozen fixtures:**
- `orders-pending-attention`: existing flat JSON order array; binding `orders`; fields `id`, `name`, `status`, `amount`; selection key `id`; task value `pending`; allowed operators include `eq` and `contains`; allowed aggregations include `sum`, `average`, and `count`.
- `incidents-critical-resolution`: raw CSV with `incident_id`, `service`, `severity`, and `resolution_minutes`; binding `incidents`; selection key `incident_id`; task value `critical`; at least two critical rows produce an average resolution time of `120`.
- `inventory-low-stock`: nested JSON object whose `items` array contains `sku`, `product`, `category`, and `on_hand`; binding `inventory`; selection key `sku`; numeric task value `10`; at least two rows are below the threshold and their `on_hand` sum is `11`.

**Pure algorithm invariants:**
- Exactly one root Stack, one title Text, and one Table are materializable. The Table contains two to four unique Columns, exactly one Filter, and exactly one Summary. Ambiguity is a generic materialization failure.
- The runtime validator has already approved every binding, field, selection key, operator, and aggregation. The materializer still treats missing or structurally ambiguous data as failure; it never broadens authority.
- `eq`/`neq` compare equal primitive types exactly. `contains` accepts strings and compares case-insensitively. `gt`/`lt` require finite numeric row and task values.
- Filtering preserves source order. Projection preserves candidate column order. Source rows and candidate objects are never mutated.
- `count` returns matched-row count. `sum`, `average`, `minimum`, and `maximum` require finite numeric field values. Empty numeric sets produce `null`; they cannot produce `NaN`, infinity, or an exception.
- The output candidate uses only Stack, Panel, and Text nodes. Model text and host data remain Text values; no HTML, expression, URL, attribute, or event-handler node is synthesized.
- The generic materializer never checks expected row IDs, expected aggregate values, required task fields, or expected column sets. Those checks belong only to the rubric.

- [ ] **Step 1: Obtain independent algorithm review before tests.**
  - Provide the approved design, this task, `generative_ui_candidate.mbt`, and current Spike 0 recipe/materialization code to a different-model reviewer.
  - Require pass/fail plus no more than three findings with exact file/line evidence and tool calls.
  - Resolve every correctness finding before continuing. Do not implement algorithm code before a pass.

- [ ] **Step 2: Add frozen source fixtures one file at a time.**
  - Inventory JSON uses a nested `items` array and no expected-output fields.
  - Incidents CSV has one canonical raw string; no duplicate CSV copy is added elsewhere.
  - Run `NEW_MOON_MOD=0 moon check` after each created file.

- [ ] **Step 3: Add the fixture catalog without outcome answers.**
  - Normalize JSON array, nested JSON path, and CSV source into immutable row arrays.
  - Include question, binding, field types, selection keys, allowed operators/aggregations, and the task filter value.
  - Do not include expected filter field, expected projected fields, expected matched keys, or expected summary value.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 4: Write failing materializer and rubric-separation tests.**
  - Cover all three recorded candidates and all frozen sources.
  - Cover `eq`, `neq`, `contains`, `gt`, `lt`, `count`, `sum`, `average`, `minimum`, `maximum`, empty numeric sets, non-finite values, source-order stability, column-order stability, immutable inputs, duplicate/missing components, and JSX-significant text.
  - Prove a runtime-valid candidate using an allowed but task-wrong field can materialize generically while the separate rubric rejects it and no expected value enters materialization.
  - Prove rubric data is absent from fixture objects and recorded candidates.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [ ] **Step 5: Run Node tests and confirm failure.**
  - Run `node --test src/genui-candidate-materializer.test.mjs` from `examples/web`.
  - Expected: module-not-found or missing-export failure for the materializer/rubric modules.

- [ ] **Step 6: Implement pure fixture normalization and materialization.**
  - Use `Array.prototype.filter`, `map`, `reduce`, `find`, `every`, and `Set`; do not add a dependency or mutable global cache.
  - Compile evidence into a safe Stack/Panel/Text output candidate only after all generic operations succeed.
  - Run `NEW_MOON_MOD=0 moon check` after each implementation file edit.

- [ ] **Step 7: Implement separate rubrics and recorded controls.**
  - Rubrics assert task-required filter/operator, minimum projected fields, matched stable row keys, summary field/aggregation, and exact summary value.
  - Recorded controls are valid generic candidates but contain no expected rows or summary answers.
  - Label them controls in exported names and comments; do not imply they came from Ollama.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [ ] **Step 8: Remove the answer-specific Spike 0 recipe files.**
  - Delete only after every old responsibility has an explicit replacement.
  - Do not leave aliases, compatibility exports, or stale `spike` names.
  - Run `NEW_MOON_MOD=0 moon check` after each removal.

- [ ] **Step 9: Verify and commit the functional core.**
  - Run `node --test src/genui-candidate-materializer.test.mjs`.
  - Expected: all operator, aggregation, fixture, immutability, safe-output, and rubric-separation cases pass.
  - Commit message: `feat(genui): add frozen host materialization fixtures`.

### Task 3: Replace Spike 0 with a Frozen Ollama Attempt Adapter

**Files:**
- Create: `examples/web/src/genui-candidate-schema.js`
- Create: `examples/web/src/genui-feasibility-provider.js`
- Create: `examples/web/src/genui-feasibility-provider.test.mjs`
- Create: `examples/web/vite-plugin-genui-feasibility.ts`
- Modify: `examples/web/vite.config.ts`
- Remove: `examples/web/vite-plugin-genui-spike.ts`

**Interfaces:**
- Produces: `GENUI_CANDIDATE_SCHEMA`, a case-neutral schema for one Stack title plus one Table containing two-to-four Columns, one Filter, and one Summary.
- Produces: `buildFeasibilityPrompt(fixture)`, `callOllamaSlot({ fixture, slotId, model }, deps)`, and terminal provider result classifications.
- Endpoint: `POST /api/genui-feasibility` with exactly `{ caseId: String, slotId: 0 | 1 | 2 }`.
- Provider settings: `stream: false`, `format: GENUI_CANDIDATE_SCHEMA`, `temperature: 0.2`, `num_predict: 512`, fixed slot seeds `1701`, `1702`, `1703`, `keep_alive: "5m"`, and `120000` ms timeout.
- Default model: `gemma4:e2b`, overridable only by `GENUI_OLLAMA_MODEL` before server start.
- Response: raw `candidateJson` string plus case ID, slot ID, model, seed, fixed settings, prompt SHA-256, candidate SHA-256, elapsed time, provider duration, prompt-token count, and output-token count.

- [ ] **Step 1: Write failing provider-contract tests.**
  - Schema accepts every recorded control shape and contains no fixture binding, field, filter value, expected row key, or expected aggregate constant.
  - Prompt contains the selected fixture source, question, task filter value, and capability manifest but no rubric object or expected outcome.
  - Request rejects unknown properties, unknown case IDs, and slot IDs outside `0..2` before provider access.
  - Fake provider success preserves the raw candidate string and reports frozen settings/digests.
  - HTTP error, timeout/abort, invalid envelope, non-JSON candidate, and oversize candidate each receive distinct terminal classifications. No path retries the fake provider.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [ ] **Step 2: Run provider tests and confirm failure.**
  - Run `node --test src/genui-feasibility-provider.test.mjs` from `examples/web`.
  - Expected: missing provider/schema modules.

- [ ] **Step 3: Implement the case-neutral provider schema and prompt.**
  - Provider schema may be narrower than the MoonBit validator but cannot grant authority.
  - Use the existing raw component/attribute wire format; do not introduce another recipe format.
  - Prompt explicitly states that output is untrusted and may be rejected; it does not expose the rubric.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [ ] **Step 4: Implement one-attempt Ollama transport.**
  - Reuse current request-size, response-envelope, timeout, metric, and no-store response behavior.
  - Inject `fetch`, monotonic clock, and digest function into the pure attempt function for deterministic Node tests; keep Vite request/response adaptation thin.
  - Execute exactly one provider request per accepted endpoint call.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [ ] **Step 5: Cut Vite configuration over cleanly.**
  - Replace the old plugin import and registration; retain `apply: "serve"` so no production route exists.
  - Remove the old plugin file after the new provider tests pass.
  - Run `NEW_MOON_MOD=0 moon check` after each edit/removal.

- [ ] **Step 6: Verify and commit the provider shell.**
  - Run `node --test src/genui-feasibility-provider.test.mjs`.
  - Run `npm run build` from `examples/web` after `moon build --target js` from the repository root.
  - Expected: provider tests pass and the production build succeeds without requiring Ollama.
  - Commit message: `feat(genui): add frozen local candidate adapter`.

### Task 4: Gate the Browser Transaction and Recorded Demo

**Files:**
- Create: `examples/web/src/genui-feasibility-flow.js`
- Create: `examples/web/src/genui-feasibility-flow.test.mjs`
- Modify: `examples/web/src/genui.js`
- Modify: `examples/web/genui.html`

**Interfaces:**
- Produces: `applyFeasibilityCandidate({ candidateJson, fixture, validateCandidate, materializeCandidate, evaluateRubric, commitCandidate })`.
- Terminal classifications: `candidate_decode_error`, `capability_decode_error`, `candidate_validation_error`, `materialization_error`, `rubric_failure`, `commit_failure`, or `success`.
- Validation callback invokes `__jsx_validate_candidate_json` with the raw model candidate and fixture capabilities.
- Commit callback invokes existing `jsx_session_replay_candidate_json` with the safe output candidate and empty capabilities.
- The feasibility UI owns a dedicated session rooted at `#genui-feasibility-preview`; it never reuses or resets the source-editor `#html-preview` session.

- [ ] **Step 1: Write failing transaction-order tests.**
  - Success calls validate, materialize, rubric, then commit exactly once in that order.
  - Each failure classification stops before later stages; especially, materialization and rubric failure never call commit.
  - Commit receives only the safe output candidate and empty capabilities, never the raw provider candidate or fixture rows.
  - A previous successful result remains the caller’s last result after every later failure.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [ ] **Step 2: Run the focused flow test and confirm failure.**
  - Run `node --test src/genui-feasibility-flow.test.mjs` from `examples/web`.
  - Expected: missing flow module.

- [ ] **Step 3: Implement the pure transaction orchestrator.**
  - Keep the flow module free of DOM lookups, fetch, model settings, fixture answers, and mutable session globals.
  - Preserve validator error codes and commit result instead of collapsing them into generic messages.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 4: Rebuild the browser section around the approved study boundary.**
  - Replace the Spike 0 answer form with a fixture selector, question/source label, one action button, dedicated committed-output root, terminal status, and attempt metadata.
  - Production action is “Replay recorded control.” Development additionally offers “Generate local candidate.” Neither mode asks a participant question or records feedback.
  - Initialize/dispose a dedicated feasibility session. A fresh live-study slot starts from the same baseline revision; normal recorded-demo replay may preserve its last successful session.
  - Dynamically import/use the MoonBit module for validate-only and commit. Do not expose provider code to production.
  - Preserve the existing fixed explorer, source editor, and their host selection/filter state.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [ ] **Step 5: Expose a development-only live-study test seam.**
  - `window.__canopyGenUiFeasibilityTest.runSlot(caseId, slotId)` performs one endpoint call and the shared apply flow.
  - `resetSlotSession()` disposes and recreates only the dedicated feasibility session at the frozen baseline.
  - The test seam returns terminal classification, validator/materializer/rubric/commit evidence, revision, telemetry, and digests; it stores nothing remotely.
  - Keep the seam under `import.meta.env.DEV` so production tree-shaking removes the route and attempt API.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 6: Verify and commit the browser transaction.**
  - Run `node --test src/genui-feasibility-flow.test.mjs src/genui-candidate-materializer.test.mjs`.
  - Run `npx tsc --noEmit` from `examples/web` after `moon build --target js`.
  - Expected: pure transaction and materialization tests pass; TypeScript reports no errors.
  - Commit message: `feat(genui): gate host materialization before commit`.

### Task 5: Prove Deterministic Browser and Production Boundaries

**Files:**
- Modify: `examples/web/tests/genui.spec.ts`
- Modify: `examples/web/preview-tests/genui-preview.spec.ts`

**Interfaces:**
- Uses only public UI controls and the development-only test seam introduced in Task 4.
- Preserves all existing lifecycle, stale-generation, cancellation, dry-run, DOM-failure, revision, and host-state tests unrelated to Spike 0.

- [ ] **Step 1: Replace the old fixed-answer browser test with failing feasibility contracts.**
  - Stub the development endpoint for each of the three fixtures and verify the candidate reaches validate → materialize → rubric → dedicated session commit.
  - Assert the committed safe output derives its matched row keys and summary from host data. Provider-supplied answer text cannot determine either value.
  - Return a runtime-invalid candidate and prove committed markup/revision and fixed-explorer selection/filter/focus remain unchanged.
  - Return a runtime-valid but task-wrong candidate and prove rubric failure occurs after materialization but before commit, preserving the same state.
  - Inject session dry-run and DOM-apply failures through existing failure seams and prove the dedicated revision does not falsely advance.
  - Replay a recorded control twice from equivalent baselines and assert identical markup/evidence.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [ ] **Step 2: Update failing production-preview contracts.**
  - Recorded-control UI is visible and works in production.
  - `POST /api/genui-feasibility` returns 404.
  - Fetch every JavaScript asset referenced by `genui.html` and assert none contains `127.0.0.1:11434`, `GENUI_OLLAMA_MODEL`, `/api/genui-feasibility`, `promptTokens`, or `outputTokens`.
  - Include a known-positive control by asserting the development source module does contain at least one forbidden marker before trusting the production absence check.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [ ] **Step 3: Build and run the focused development browser tests.**
  - Run `moon build --target js` from the repository root.
  - Run `npx playwright test tests/genui.spec.ts --grep "feasibility|recorded|rubric" --project=chromium --workers=1` from `examples/web`.
  - Expected: all new feasibility contracts pass with no Ollama process.

- [ ] **Step 4: Run production isolation and smoke the real page.**
  - Run `npx playwright test -c playwright.preview.config.ts --project=chromium --workers=1`.
  - Expected: recorded replay succeeds, provider endpoint is 404, and production assets contain no forbidden provider markers.
  - Start the development server through the supervised launcher, open `/genui.html`, replay each recorded fixture, and visually confirm fixture selection, status, committed output, and error preservation.
  - Stop the supervised server after the browser check.

- [ ] **Step 5: Run affected suites and commit.**
  - Run `node --test src/genui-feasibility-*.test.mjs src/genui-candidate-materializer.test.mjs`.
  - Run `moon test ffi/jsx`.
  - Run the complete `examples/web` Playwright suite once.
  - Expected: all affected unit, MoonBit, development E2E, and preview E2E suites pass.
  - Commit message: `test(genui): verify feasibility transaction boundaries`.

### Task 6: Freeze and Execute the Nine-Slot Local Study

**Files:**
- Create: `examples/web/playwright.feasibility.config.ts`
- Create: `examples/web/tests/genui-feasibility-live.spec.ts`
- Create: `examples/web/scripts/run-genui-feasibility-study.mjs`
- Generate: `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility.json`

**Interfaces:**
- Dedicated Playwright config always starts a fresh Vite server with `reuseExistingServer: false`, one Chromium worker, no retries, and a timeout covering nine 120-second slots.
- Live test runs case order as declared by `GENUI_FEASIBILITY_FIXTURES` and slot order `0, 1, 2`, resetting the dedicated session before every slot.
- The study runner records the frozen Git commit before any request, refuses a dirty tree, runs deterministic preflight once, invokes the live test once, and writes final evidence even when the decision is negative.

- [ ] **Step 1: Write the live harness without enabling it in CI.**
  - Skip unless `GENUI_FEASIBILITY_LIVE=1`.
  - Execute exactly nine calls through `window.__canopyGenUiFeasibilityTest.runSlot`.
  - Catch each terminal failure into its assigned slot; never retry or substitute.
  - Write raw slot output under Playwright’s ignored `test-results` directory in a `finally` block so timeout, provider failure, or assertion failure does not erase evidence.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 2: Add the isolated live-study Playwright config.**
  - Force `workers: 1`, `retries: 0`, a fresh server, and explicit base URL.
  - Pass the frozen `GENUI_OLLAMA_MODEL` environment into the server; do not permit per-slot model changes.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 3: Write the study runner and its refusal behavior.**
  - Refuse a dirty tree or missing model setting before starting the server.
  - Record `git rev-parse HEAD`, model, provider settings, fixture/schema/prompt/rubric file digests, validation/build/test commands, raw exit codes, and raw slot classifications.
  - Run deterministic checks once: MoonBit package tests, Node unit tests, JS build, TypeScript check, focused development E2E, and production-preview E2E.
  - If preflight fails, make no Ollama requests and write `NOT_YET_FEASIBLE` with the failed check.
  - If preflight passes, invoke the dedicated live Playwright command once. Missing raw slot output is a failed slot and cannot trigger a rerun.
  - Select `TECHNICALLY_FEASIBLE` only when every deterministic criterion passes, every slot has a terminal classification, and every fixture has at least one `success`; otherwise select `NOT_YET_FEASIBLE`.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [ ] **Step 4: Verify harness mechanics with a fake local provider before real model use.**
  - Run the dedicated server against a deterministic fake `fetch` or route fixture that yields one success, one generic rejection, and one provider failure per case.
  - Confirm exactly nine calls, no retry, stable slot IDs/seeds, complete raw output, dirty-tree refusal, and correct positive/negative decision aggregation.
  - This fake run is harness validation only and must not be written as local-model evidence.

- [ ] **Step 5: Freeze implementation and obtain pre-request review.**
  - Commit all implementation and deterministic tests before the first real Ollama request.
  - Run an independent different-model implementation review against the frozen diff. Require explicit inspection of prompt/rubric separation, validator authority, transaction gating, production isolation, and no-retry slot accounting.
  - Resolve findings in a new commit, rerun deterministic checks, and freeze the final reviewed commit. Any code, prompt, fixture, schema, rubric, model, or setting change after this point starts a new study run.

- [ ] **Step 6: Execute the real frozen study once.**
  - Run from repository root with `GENUI_FEASIBILITY_LIVE=1` and the frozen `GENUI_OLLAMA_MODEL`:
    `node examples/web/scripts/run-genui-feasibility-study.mjs`.
  - Expected: one final evidence JSON containing nine terminal slots and either `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE`; a negative decision is a valid completed study result.
  - Do not rerun failed or missing slots. A new run requires new versioned evidence and an explicit changed-input reason.

- [ ] **Step 7: Verify and commit evidence separately.**
  - Validate the evidence JSON parses, all digests and nine slots are present, the decision follows the frozen rule, and no raw source rows, credentials, environment dump, or private user data were retained.
  - Run `slopless` on the design and implementation-plan Markdown; save raw findings under `.slopless/findings` and fix concrete prose findings while leaving document-level readability metrics as advisory.
  - Run `moon info && moon fmt`; inspect `.mbti` drift and confirm no unintended public trait-bound or type-surface changes.
  - Commit the evidence and any final status-only design update separately from implementation with message `docs(genui): record local feasibility result`.

## Reuse Check

### Existing project APIs reused

- `GenerativeUiCandidate::validate`, `GenerativeUiRawNode`, `GenerativeUiHostCapabilities`, and structured diagnostics remain the sole semantic authority.
- `decode_candidate_json` and `decode_capabilities_json` remain the only wire decoders.
- `jsx_session_replay_candidate_json`, `candidate_to_projection`, session dry-run, DOM apply, and revision commit remain the only output commit path.
- Existing session failure and host-state browser seams are reused instead of adding rollback or a second DOM owner.
- Existing order fixture data is imported from `src/fixtures/orders.json`; it is not copied into the study catalog.

### MoonBit core APIs checked and reused

- `Result` represents shared validation success/failure.
- `Json` and existing `FromJson` implementations decode the wire boundary.
- `Array::map`, `String::join`, and existing diagnostic accessors render validation output.
- `Option` remains the nullable error/selection representation.
- No new MoonBit filter/aggregation loop, container, range, string builder, or numeric helper is needed; host data operations live in the pure JavaScript experiment layer.

### Existing APIs checked but not used

- `GenerativeUiLifecycle` and the async Promise/Abort driver are not used by validate-only because they own request/session state; the existing replay commit still uses lifecycle semantics.
- `genui-data.ts` order-specific filter and summary helpers remain for the fixed explorer but are not generalized into the multi-schema study; doing so would mix fixed-explorer UI state with the removable experiment.
- Spike 0 `parseGenUiRecipe` and its answer-specific schema are removed because they encode the expected pending filter, required columns, and sum.
- Direct `candidate_to_projection` metadata output is not treated as host data materialization; it is reused only when the safe output candidate reaches session commit.

### New responsibility boundaries

- The validate-only FFI exposes existing trust logic without session effects; it defines no new candidate semantics.
- The fixture catalog owns inputs and capabilities but no expected outcomes.
- The materializer owns deterministic host operations and safe output construction but no task-specific pass/fail rule.
- The rubric owns task-specific expected outcomes but no validation, materialization, or commit authority.
- The flow owns stage ordering and terminal classification but no provider transport, domain semantics, or DOM rendering.
- The provider adapter owns one local request and metrics but no trust or retry policy.

## Final Acceptance

- All nine frozen slots have terminal classifications and no slot was retried or replaced.
- Every provider candidate was treated as untrusted and passed through the same MoonBit validation core used by replay.
- Rubric failures occurred only after generic materialization and before commit.
- All failure classes preserve the last valid dedicated UI, fixed-explorer state, and committed revision.
- Recorded production replay uses the same validate/materialize/rubric/commit path without any provider marker or endpoint in production assets.
- The evidence file selects only `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE` and contains no product-value or usability claim.
