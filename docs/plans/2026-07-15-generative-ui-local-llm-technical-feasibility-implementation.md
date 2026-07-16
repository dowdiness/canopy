# Generative UI local-LLM technical feasibility implementation plan

**Status:** Executed v2 (`NOT_YET_FEASIBLE`); aggregate evidence retained, raw execution audit lost; v1 result preserved

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove whether a frozen local Ollama model can generate bounded candidates for three structurally different data fixtures, while MoonBit remains the sole candidate parser and semantic interpreter and only rubric-passing prepared output reaches the existing session commit boundary.

**Architecture:** The local provider returns an untrusted whole-response candidate. Trusted JavaScript fixture adapters normalize frozen JSON/CSV sources without inspecting that candidate. One MoonBit preparation core reuses the current decoder, capability checks, and `GenerativeUiCandidate::validate`, then performs candidate-selected filter, projection, and aggregation over the normalized dataset. A separate MoonBit fixture rubric consumes only generic evidence. Evaluate-and-commit passes the internal validated safe-output candidate directly to the existing dry-run, DOM apply, and revision transaction without serializing it through JavaScript. Production replays recorded controls through the same MoonBit preparation/commit path but contains no provider endpoint or provider settings.

**Tech Stack:** MoonBit JS FFI, existing `dowdiness/cognition` Generative UI domain, MoonBit `Json`/collection APIs, JavaScript ES modules for trusted ingestion and transport, Vite middleware, Ollama `/api/generate`, Node test runner, Playwright, SHA-256 evidence digests.

## Global Constraints

- The design source is `docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility.md`.
- The MoonBit runtime validator is the sole trust authority; the provider JSON Schema is generation guidance only.
- Provider output never owns source data, effects, DOM access, mutable host state, or revision commit authority.
- The fixture rubric stays out of the provider prompt, provider schema, generic validator, normalized dataset, and generic materialization core.
- Generic validation, materialization, rubric, dry-run, or application failure must leave the last valid UI, host state, and committed revision unchanged.
- Three predetermined slots run once for each frozen valid fixture. No retry, replacement, prompt edit, or preferred-result rerun is allowed.
- Production contains recorded controls and the shared deterministic path, but no Ollama URL, local-provider route, model setting, credential path, external request, or telemetry collector.
- This work may establish `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE` only. It makes no usability, adoption, task-performance, model-superiority, or product-value claim.
- Use one file per edit call. Run `NEW_MOON_MOD=0 moon check` after every file edit before editing another file.
- Write failing behavioral tests before each implementation. For MoonBit files, also use `moon ide` where it resolves; if mixed-manifest IDE lookup still fails, inspect the defining `.mbt` and `.mbti` directly rather than retrying the same command.
- Before implementing Task 2, an independent reviewer using a model different from the driving model must inspect the operator, aggregation, rubric-separation, and commit-gating design and answer: “Is this algorithm correct? What edge cases break it?”
- Plans remain prose-only for non-trivial algorithms. Base the implementation on failing tests and the invariants below.

## File and Responsibility Map

- `ffi/jsx/generative_ui_replay_adapter.mbt`: one shared candidate decode/validate core and one private transaction accepting an already validated candidate.
- `ffi/jsx/generative_ui_feasibility_materializer.mbt`: normalized-dataset decoder, pure candidate-directed filter/project/aggregate materialization, generic evidence, inert safe-output construction, and digest.
- `ffi/jsx/generative_ui_feasibility_rubric.mbt`: separate frozen case rubrics that consume generic evidence only.
- `ffi/jsx/generative_ui_feasibility_adapter.mbt`: one preparation core plus evaluate-only and evaluate-and-commit FFI shells.
- `ffi/jsx/generative_ui_feasibility_wbtest.mbt`: operator, aggregation, rubric separation, replay equality, and no-session/no-DOM-effect contracts.
- `ffi/jsx/session_contract_wbtest.mbt`: existing replay behavior and validated-candidate transaction regression contracts.
- `ffi/jsx/moon.pkg`: JavaScript export list for the two experiment-only feasibility entry points.
- `examples/web/src/genui-feasibility-fixtures.js`: trusted frozen-source ingestion, versioned normalized dataset JSON, user tasks, host capabilities, and task values; no candidate parsing or expected outcomes.
- `examples/web/src/fixtures/inventory.json`: nested JSON fixture source.
- `examples/web/src/fixtures/incidents-csv.js`: one canonical raw CSV string used by browser and Vite middleware.
- `examples/web/src/genui-candidate-schema.js`: provider-only, case-neutral JSON Schema for the bounded raw candidate shape.
- `examples/web/src/genui-recorded-candidates.js`: hand-authored recorded control candidates for production replay; controls are not represented as local-model evidence.
- `examples/web/src/genui-feasibility-fixtures.test.mjs`: trusted-ingestion, immutability, rubric-absence, and source-shape contracts.
- `examples/web/src/genui-feasibility-flow.js`: evaluate-only/evaluate-and-commit FFI selection and terminal result preservation; no candidate parsing, domain operation, or DOM rendering logic.
- `examples/web/src/genui-feasibility-*.test.mjs`: Node behavioral tests for fixture ingestion, provider contract, and browser-shell ordering.
- `examples/web/vite-plugin-genui-feasibility.ts`: development-only request-size/method checks and Ollama transport adapter.
- `examples/web/vite.config.ts`: clean cutover from the Spike 0 plugin to the feasibility plugin.
- `examples/web/src/genui.js`: browser FFI wrappers, dedicated feasibility session ownership, recorded/live action wiring, and visible status rendering.
- `examples/web/genui.html`: fixture selector, recorded action, dedicated committed-output root, terminal status, and development-only attempt metadata.
- `examples/web/tests/genui.spec.ts`: deterministic development browser contracts.
- `examples/web/preview-tests/genui-preview.spec.ts`: production recorded replay and forbidden-endpoint/bundle checks.
- `examples/web/playwright.feasibility.config.ts`: isolated, non-reusing live-study server and long timeout.
- `examples/web/tests/genui-feasibility-live.spec.ts`: exactly nine credential-free local attempts and raw slot evidence.
- `examples/web/scripts/build-genui-feasibility-manifest.mjs`: provider-read-only model discovery, canonical manifest construction, and no candidate generation.
- `examples/web/scripts/run-genui-feasibility-study.mjs`: clean-commit freeze, deterministic preflight, live execution, journal ownership, digest aggregation, and final technical decision evidence.
- `examples/web/scripts/finalize-genui-feasibility-study.mjs`: provider-disabled interrupted-run classification and negative evidence emission.
- `examples/web/studies/2026-07-15-genui-local-llm-v1.json`: committed, versioned study manifest frozen after model discovery and implementation review but before the first provider request.
- `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility.json`: generated final evidence; written only by the frozen study runner or provider-disabled finalizer.
- Remove after clean cutover: `examples/web/vite-plugin-genui-spike.ts`, `examples/web/src/genui-spike-case.js`, `examples/web/src/genui-spike-recipe.js`, and `examples/web/src/genui-spike-recipe.test.mjs`.

---

### Task 1: Refactor Replay Around an Opaque Validated-Candidate Transaction

**Files:**
- Modify: `ffi/jsx/generative_ui_replay_adapter.mbt`
- Modify: `ffi/jsx/session_contract_wbtest.mbt`

**Interfaces:**
- Consumes: existing `decode_candidate_json`, `decode_capabilities_json`, `GenerativeUiCandidate::validate`, lifecycle transitions, and `jsx_session_commit_candidate`.
- Produces: one private decode/capability/validation result and one private transaction that accepts an opaque `GenerativeUiCandidate`.
- Invariant: `jsx_session_replay_candidate_json` preserves its public signature, error precedence, diagnostics, lifecycle transitions, mounted IDs, and revision behavior.
- Invariant: the validated candidate remains inside MoonBit. The private transaction neither reparses nor revalidates candidate JSON.

- [x] **Step 1: Map reuse before extracting private helpers.**
  - Inspect `decode_candidate_json`, `decode_capabilities_json`, `GenerativeUiCandidate::validate`, `commit_candidate_with_lifecycle`, `jsx_session_commit_candidate`, and result rendering.
  - Check MoonBit core `Result`, `Json`, `Array::map`, `Option`, and tuple/enum error representation. Reuse them; do not create a second candidate decoder, capability parser, or session transaction.
  - Record why the async driver is not involved: this refactor begins after replay has assembled a whole candidate.

- [x] **Step 2: Write failing white-box regression contracts.**
  - Valid and invalid replay inputs retain their exact existing result codes, diagnostic order, mounted IDs, and revision fields.
  - Malformed candidate JSON still precedes capability decoding; invalid capabilities still precede semantic validation.
  - `raw_html`, `expression`, and a disallowed binding remain rejected before lifecycle dry-run.
  - A prevalidated safe Stack/Panel/Text candidate can enter the extracted private transaction without a second JSON decode.
  - Dry-run, DOM-apply, stale-revision, and successful commit paths retain existing lifecycle transitions and revision behavior.
  - Run `NEW_MOON_MOD=0 moon check` immediately after editing the test file.

- [x] **Step 3: Run the focused test and confirm the expected failure.**
  - Run `moon test ffi/jsx/session_contract_wbtest.mbt`.
  - Expected: compile failure because the new private helper boundary is absent.

- [x] **Step 4: Extract the shared validation and validated-candidate transaction.**
  - Return either the opaque validated candidate or the exact existing error code/message/diagnostic payload.
  - Move lifecycle dry-run, `jsx_session_commit_candidate`, DOM-apply result handling, and revision transitions behind the private validated-candidate transaction.
  - Route existing replay through decode → validate → private transaction with no externally observable change.
  - Make no change to `GenerativeUiCandidate`, session handles, renderer semantics, or public exports.
  - Run `NEW_MOON_MOD=0 moon check` immediately after editing `generative_ui_replay_adapter.mbt`.

- [x] **Step 5: Verify and commit the internal trust boundary.**
  - Run `moon test ffi/jsx/session_contract_wbtest.mbt`.
  - Run `moon test ffi/jsx`.
  - Expected: all focused and package tests pass; existing replay errors, lifecycle events, mounted IDs, and revisions remain unchanged.
  - Run `moon info && moon fmt`, inspect `ffi/jsx/pkg.generated.mbti`, and confirm there is no public interface change.
  - Commit message: `refactor(genui): isolate validated candidate transaction`.

### Task 1.5: Reject Duplicate Candidate Attributes

**Files:**
- Modify: `lib/cognition/generative_ui_candidate.mbt`
- Modify: `lib/cognition/generative_ui_candidate_test.mbt`

- [x] **Step 1: Write failing duplicate-attribute contracts.**
  - Add raw-candidate validation cases for duplicate `data`, `selection`,
    `field`, `operator`, `aggregation`, `label`, and `value` attributes.
  - Require `InvalidAttributeValue` at the duplicated component path; do not add
    a public diagnostic variant.
  - Run `moon test lib/cognition/generative_ui_candidate_test.mbt` and confirm
    the duplicate inputs are incorrectly accepted before implementation.

- [x] **Step 2: Reject duplicate names before attribute interpretation.**
  - Extend the existing attribute diagnostic pass with `Set[String]`; report
    each repeated name once and preserve existing unknown-attribute diagnostics.
  - Do not change first-match lookup, component topology, capability semantics,
    or any public signature.
  - Run `NEW_MOON_MOD=0 moon check` immediately after each file edit.

- [x] **Step 3: Verify and commit the prerequisite fix separately.**
  - Run `moon test lib/cognition/generative_ui_candidate_test.mbt` and
    `moon test lib/cognition`.
  - Run `moon info && moon fmt`; confirm
    `lib/cognition/pkg.generated.mbti` is unchanged.
  - Commit message: `fix(cognition): reject duplicate candidate attributes`.

### Task 2: Freeze Fixtures and Add the MoonBit Preparation Core

**Files:**
- Create: `ffi/jsx/generative_ui_feasibility_materializer.mbt`
- Create: `ffi/jsx/generative_ui_feasibility_rubric.mbt`
- Create: `ffi/jsx/generative_ui_feasibility_adapter.mbt`
- Create: `ffi/jsx/generative_ui_feasibility_wbtest.mbt`
- Modify: `ffi/jsx/moon.pkg`
- Create: `examples/web/src/fixtures/inventory.json`
- Create: `examples/web/src/fixtures/incidents-csv.js`
- Create: `examples/web/src/genui-feasibility-fixtures.js`
- Create: `examples/web/src/genui-recorded-candidates.js`
- Create: `examples/web/src/genui-feasibility-fixtures.test.mjs`
- Remove after replacement tests pass: `examples/web/src/genui-spike-case.js`, `examples/web/src/genui-spike-recipe.js`, `examples/web/src/genui-spike-recipe.test.mjs`

**Interfaces:**
- JavaScript produces `GENUI_FEASIBILITY_FIXTURES`, `getFeasibilityFixture(caseId)`, `capabilitiesJsonForFixture(fixture)`, and `normalizedDatasetJsonForFixture(fixture)`. The last function emits only the canonical design's exact `schema_version: 1` object: ordered declarations, ordered rows, and duplicate-observable `[field, scalar]` pairs.
- MoonBit produces `__jsx_evaluate_feasibility_candidate_json(candidate_json, capabilities_json, dataset_json)` and `__jsx_commit_feasibility_candidate_json(handle, base_revision, candidate_json, capabilities_json, dataset_json)`.
- Both FFI entry points call one private `prepare_feasibility_candidate` core. Evaluate-only returns preparation evidence without a session; evaluate-and-commit passes the internal validated safe-output candidate directly to Task 1’s private transaction.
- Result schema carries `schema_version: 1`, terminal classification, the canonical ordered generic-evidence object, rubric result, lowercase safe-output SHA-256 digest, and nullable session result. It never returns a serialized safe candidate for JavaScript to interpret.
- Recorded controls remain case-neutral raw candidates. They enter the same MoonBit preparation core and are not represented as local-model evidence.

**Frozen fixtures:**
- `orders-pending-attention`: existing flat JSON order array; binding `orders`; fields `id`, `name`, `status`, `amount`; selection key `id`; task value `pending`; allowed operators include `eq` and `contains`; allowed aggregations include `sum`, `average`, and `count`.
- `incidents-critical-resolution`: raw CSV with `incident_id`, `service`, `severity`, and `resolution_minutes`; binding `incidents`; selection key `incident_id`; task value `critical`; at least two critical rows produce an average resolution time of `120`.
- `inventory-low-stock`: nested JSON object whose `items` array contains `sku`, `product`, `category`, and `on_hand`; binding `inventory`; selection key `sku`; numeric task value `10`; at least two rows are below the threshold and their `on_hand` sum is `11`.

**Pure algorithm invariants:**
- Trusted JavaScript ingestion accepts only native JSON strings, finite numbers, booleans, and null; rejects missing or extra fields, duplicate or missing CSV headers, ragged rows, empty or duplicate stable keys, a selection key absent from the field declarations, a missing or non-string row selection value, disagreement between that value and the row stable key, non-finite numbers, unsupported nested values, row/field order disagreement, and dataset/capability disagreement before candidate evaluation.
- MoonBit rechecks the exact dataset version and property set, source-format enum, case, binding, selection key, ordered unique field declarations including that selection key, duplicate-observable row pairs, finite numbers, complete rows, non-empty unique stable keys, exact string equality between every row selection value and stable key, and exact single-binding capability consistency at the FFI boundary.
- MoonBit alone decodes the raw candidate. The only materializable topology is direct `Stack([Text(title), Table(children)])`; no provider Panel or nested Stack is accepted. Table children are exactly two to four unique Columns followed by one Filter and one Summary. Any missing, duplicated, reordered, nested, or extra node is a generic materialization failure.
- The runtime validator has already rejected duplicate attributes and approved every binding, field, selection key, operator, and aggregation. The materializer still rejects missing or structurally ambiguous normalized data and never broadens authority.
- `eq`/`neq` compare equal scalar variants exactly. `contains` accepts strings and compares `String::to_lower` results without locale-specific behavior. `gt`/`lt` require finite numeric row and task values. JSON number token spelling is discarded after finite `Double` decoding.
- Filtering preserves source order. Projection preserves candidate column order. Normalized rows and candidate values are immutable.
- `count` returns matched-row count. `sum`, `average`, `minimum`, and `maximum` require finite numeric field values and a finite result after evaluation; overflow is a generic materialization failure before evidence or safe-output construction. Empty numeric sets alone produce `null`; they cannot produce `NaN`, infinity, or an exception.
- The safe output is deterministic: root Stack; provider title as typed Text; one Panel per matched source row, containing one `label: scalar` Text per projected column in candidate order; and one `aggregation field: scalar` summary Text. Scalar text uses the frozen variant formatter: original String, `Double::to_string`, lowercase Bool, or `null`.
- One in-memory safe tree produces both the revalidated raw Stack/Panel/Text candidate and the canonical compact projection JSON. Hash exactly that JSON's UTF-8 bytes with `@crypto.sha256` and encode lowercase with `bytes_to_hex_string`; never synthesize HTML, expression, URL, attribute, event handler, query state, or selection state.
- Generic evidence is the canonical `schema_version: 1` object ordered as `schema_version`, `case_id`, `source_format`, `binding`, `filter`, `projected_fields`, `matched_stable_keys`, `summary`, and `safe_output_sha256`. It uses native JSON scalars and contains no expected rows, expected aggregate, or task pass/fail rule.
- The separate rubric file consumes generic evidence only. It cannot inspect source rows, raw candidate JSON, provider data, session state, or the prepared candidate.

- [x] **Step 1: Obtain independent algorithm review before tests.**
  - Provide the approved design, this task, `generative_ui_candidate.mbt`, Task
    1's private transaction, and current Spike 0 fixture code to a
    different-model reviewer.
  - The first review failed on duplicate attributes, wire/hash ambiguity, and
    candidate topology. The second review retained duplicate rejection as a
    prerequisite and found stable-key/selection-value identity plus aggregate
    overflow unspecified. Apply Task 1.5 and all frozen direct-shape, identity,
    and finite-result contracts, then require a fresh pass/fail review with no
    more than three findings, exact file/line evidence, and tool calls.
  - Resolve every correctness finding before continuing. Do not implement
    materialization code before a pass.

- [x] **Step 2: Add frozen sources and failing trusted-ingestion tests one file at a time.**
  - Inventory JSON uses a nested `items` array and no expected-output fields. Incidents CSV has one canonical raw string and no duplicate copy.
  - Test the exact version/property/source-format contract, ordered field declarations and row pairs, flat JSON, nested JSON path, restricted CSV, scalar typing, finite-number checks, empty/duplicate stable keys, duplicate/missing row fields, source order, immutability, exact capability equality, and every malformed-source rejection above.
  - Prove fixture objects and recorded candidates contain no expected filter field, expected columns, matched keys, expected aggregate, or rubric result.
  - Run `node --test src/genui-feasibility-fixtures.test.mjs` and confirm the missing-ingestion failure.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 3: Implement trusted fixture ingestion and recorded controls.**
  - Parse only frozen source formats into the exact versioned normalized-dataset wire shape. The adapter never receives or imports provider candidate JSON.
  - Reuse the existing orders fixture; do not copy its rows. Recorded controls contain only declarative candidate structure and host references.
  - Run the focused Node test, then `NEW_MOON_MOD=0 moon check` after each implementation file edit.

- [x] **Step 4: Write failing MoonBit preparation and rubric contracts.**
  - Cover all three recorded candidates and normalized datasets.
  - Cover candidate decode/capability/semantic rejection; exact direct topology and every duplicate/missing/reordered component; `eq`, `neq`, `contains`, `gt`, `lt`; `count`, `sum`, `average`, `minimum`, `maximum`; empty numeric sets; non-finite values; number-spelling normalization; source/column order; immutable inputs; exact evidence order; exact safe-output text/tree/JSON/hash bytes; and JSX-significant text.
  - Prove a runtime-valid candidate using an allowed but task-wrong field materializes generically, then fails the separate rubric without reaching the session transaction.
  - Prove evaluate-only creates no session or revision, and evaluate-only/evaluate-and-commit produce identical preparation classification, generic evidence, rubric result, and safe-output digest for the same bytes.
  - Prove the safe-output candidate reaches Task 1’s private transaction without candidate JSON serialization or a second semantic interpretation.
  - Run `moon test ffi/jsx/generative_ui_feasibility_wbtest.mbt` and confirm the missing-core failure.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 5: Implement normalized-dataset decoding and generic materialization.**
  - Reuse MoonBit `Json`/`FromJson`, `Result`, `Option`, `Map`, `Set`, `Array::filter`/`map`/`fold`/`search_by`/`all`, `@cmp.minimum`/`maximum`, `String::to_lower`, `@utf8.encode`, and `@crypto.sha256`/`bytes_to_hex_string`.
  - Keep parsing, filter/project/aggregate decisions, evidence construction, safe-output validation, projection hashing, and prepared-candidate retention in MoonBit. Do not add a JavaScript candidate decoder or materializer.
  - Run `NEW_MOON_MOD=0 moon check` after each MoonBit file edit.

- [x] **Step 6: Implement separate rubrics and the two FFI shells.**
  - Rubrics assert task-required filter/operator, minimum projected fields, matched stable row keys, summary field/aggregation, and exact summary value using generic evidence only.
  - Both FFI shells call one preparation function. Only a rubric-passing prepared value may call the private validated-candidate transaction.
  - Add only the two double-underscore experimental functions plus `moonbitlang/x/crypto` and `moonbitlang/core/encoding/utf8` imports to `moon.pkg`.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 7: Remove the answer-specific Spike 0 recipe files.**
  - Delete only after every old responsibility has an explicit replacement.
  - Do not leave aliases, compatibility exports, stale `spike` names, or a JavaScript candidate interpreter.
  - Run `NEW_MOON_MOD=0 moon check` after each removal.

- [x] **Step 8: Verify and commit the MoonBit functional core.**
  - Run `node --test src/genui-feasibility-fixtures.test.mjs` from `examples/web`.
  - Run `moon test ffi/jsx/generative_ui_feasibility_wbtest.mbt`.
  - Run `moon test ffi/jsx`.
  - Run `moon info && moon fmt`; inspect `ffi/jsx/pkg.generated.mbti` and confirm only the two experimental exports were added.
  - Expected: all ingestion, operator, aggregation, immutability, safe-output, rubric-separation, replay-equality, and session-gating cases pass.
  - Commit message: `feat(genui): add MoonBit feasibility preparation core`.

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
- Produces: `buildFeasibilityPrompt(fixture)`, `readOllamaIdentity(modelTag, deps)`, `callOllamaSlot({ fixture, slotId, frozenIdentity }, deps)`, and terminal provider result classifications.
- Endpoint: `POST /api/genui-feasibility` with exactly `{ studyId: String, runCapability: String, caseId: String, slotId: 0 | 1 | 2 }`.
- The server loads one committed study manifest and one ephemeral 256-bit run capability at startup. The mutable model tag is lookup metadata only; the model-manifest SHA-256 digest, canonical `/api/show` details digest, Ollama version, effective template/parameter digests, settings, cases, and slots come only from that manifest.
- Provider settings: `stream: false`, `format: GENUI_CANDIDATE_SCHEMA`, `temperature: 0.2`, `num_ctx: 4096`, `num_predict: 512`, fixed slot seeds `1701`, `1702`, `1703`, `keep_alive: "5m"`, and `120000` ms timeout.
- Response: untouched `response` string plus case ID, slot ID, lookup tag, frozen model-manifest/details digests, Ollama version/template/parameter digests, seed, settings, prompt/candidate digests, elapsed time, provider duration, and token counts.

- [x] **Step 1: Write failing provider-contract tests.**
  - Schema accepts every recorded control shape and contains no fixture binding, field, filter value, expected row key, or expected aggregate constant.
  - Prompt contains the selected fixture source, question, task filter value, and capability manifest but no rubric object or expected outcome.
  - Request rejects unknown properties, wrong study ID or run capability, unknown case or slot, and a duplicate slot before any Ollama access.
  - Model-manifest digest, canonical `/api/show` details digest, Ollama version, template digest, or parameter digest drift returns `model_identity_mismatch` without calling `/api/generate`.
  - A tag remap before or during generation is detected by before/after identity reads; the returned candidate is rejected even if `/api/generate` succeeded.
  - Fake provider success preserves the untouched candidate string and reports the frozen identity, settings, and output digests. HTTP error, timeout/abort, invalid provider envelope, and oversize candidate each receive distinct provider classifications. Candidate syntax is not parsed here and no path retries the fake provider.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 2: Run provider tests and confirm failure.**
  - Run `node --test src/genui-feasibility-provider.test.mjs` from `examples/web`.
  - Expected: missing provider/schema modules.

- [x] **Step 3: Implement the case-neutral provider schema and prompt.**
  - Provider schema may be narrower than the MoonBit validator but cannot grant authority.
  - Use the existing raw component/attribute wire format; do not introduce another recipe format.
  - Prompt explicitly states that output is untrusted and may be rejected; it does not expose the rubric.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 4: Implement identity-checked, one-attempt Ollama transport.**
  - Reuse current request-size, response-envelope, timeout, metric, and no-store response behavior.
  - Read `/api/version`, `/api/tags`, and `/api/show` through injected dependencies. Canonicalize and hash the complete relevant `/api/show` identity payload. Compare model-manifest digest, details digest, Ollama version, and effective template/parameter digests with the manifest immediately before generation.
  - Execute exactly one `/api/generate` request per accepted endpoint call. Re-read model-manifest and details identity after the response and before exposing candidate bytes; any drift returns `model_identity_mismatch`.
  - Treat `response` as an opaque bounded string. Only MoonBit Task 2 parses candidate syntax or semantics.
  - Inject provider fetch, identity reader, monotonic clock, and digest function for deterministic Node tests; keep Vite adaptation thin.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 5: Cut Vite configuration over behind the study gate.**
  - Replace the old plugin import and registration; retain `apply: "serve"` so no production route exists.
  - Install the route only when live mode, committed manifest path, and ephemeral run capability are all present at server startup. There is no default model or mutable model override.
  - Parse and hash the manifest once. Claim each allowed `(caseId, slotId)` in memory before identity or provider access so duplicate calls fail closed.
  - Remove the old plugin file after the new provider tests pass.
  - Run `NEW_MOON_MOD=0 moon check` after each edit/removal.

- [x] **Step 6: Verify and commit the provider shell.**
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
- Produces: `runFeasibilityCandidate({ mode, candidateJson, fixture, evaluateCandidate, commitCandidate })`.
- `mode: "evaluate"` calls the MoonBit evaluate-only FFI once. `mode: "commit"` calls the MoonBit evaluate-and-commit FFI once; JavaScript never sequences validation, materialization, or rubric logic itself.
- Terminal classifications: `candidate_decode_error`, `capability_decode_error`, `candidate_validation_error`, `dataset_decode_error`, `materialization_error`, `rubric_failure`, `commit_failure`, `replay_mismatch`, or `success`.
- The feasibility UI owns a dedicated session rooted at `#genui-feasibility-preview`; it never reuses or resets the source-editor `#html-preview` session.

- [x] **Step 1: Write failing shell-order and result-preservation tests.**
  - Evaluate mode invokes only the evaluate callback; commit mode invokes only the commit callback. Each is called exactly once with the raw candidate string, capabilities JSON, and normalized dataset JSON.
  - The shell never parses `candidateJson`, reconstructs a safe candidate, or receives a materializer/rubric callback.
  - Every MoonBit terminal classification is preserved without collapsing its generic evidence, rubric result, safe-output digest, or session result.
  - A previous successful visible result remains the caller’s last result after every later failure.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 2: Run the focused flow test and confirm failure.**
  - Run `node --test src/genui-feasibility-flow.test.mjs` from `examples/web`.
  - Expected: missing flow module.

- [x] **Step 3: Implement the thin FFI-selection shell.**
  - Keep the flow module free of candidate parsing, host data operations, DOM lookups, fetch, model settings, fixture answers, and mutable session globals.
  - Preserve MoonBit classifications and evidence verbatim; do not infer success from markup or provider status.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [x] **Step 4: Rebuild the browser section around the approved study boundary.**
  - Replace the Spike 0 answer form with a fixture selector, question/source label, one recorded-replay action, dedicated committed-output root, terminal status, and replay metadata.
  - Production and ordinary development expose only “Replay recorded control.” Neither mode asks a participant question or records feedback.
  - Initialize/dispose a dedicated feasibility session. A fresh live-study slot starts from the same baseline revision; normal recorded-demo replay may preserve its last successful session.
  - Dynamically import and call the MoonBit evaluate-only/evaluate-and-commit functions. Do not expose provider code, model settings, or a live action in production.
  - Preserve the existing fixed explorer, source editor, and their host selection/filter state.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 5: Expose a development-only live-study test seam.**
  - `window.__canopyGenUiFeasibilityTest.runSlot({ studyId, runCapability, caseId, slotId })` performs one endpoint call and one MoonBit evaluate-and-commit call.
  - `evaluateSavedCandidate({ caseId, candidateJson })` performs one provider-free MoonBit evaluate-only call. `resetSlotSession()` disposes and recreates only the dedicated feasibility session at the frozen baseline.
  - Only the isolated live harness supplies the ephemeral run context; public page and recorded-demo controls cannot call the endpoint.
  - `runSlot` returns the exact raw candidate string to the Playwright harness for ignored local journaling and offline replay, plus terminal classification, generic evidence, rubric result, safe-output digest, session result, revision, provider telemetry, and provider digests. Browser code does not persist the candidate or run capability.
  - Keep the seam under `import.meta.env.DEV` so production tree-shaking removes the attempt API.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [x] **Step 6: Verify and commit the browser transaction.**
  - Run `node --test src/genui-feasibility-flow.test.mjs src/genui-feasibility-fixtures.test.mjs`.
  - Run `moon test ffi/jsx/generative_ui_feasibility_wbtest.mbt`.
  - Run `npx tsc --noEmit` from `examples/web` after `moon build --target js`.
  - Expected: fixture ingestion, thin-shell, MoonBit preparation, and TypeScript checks pass.
  - Commit message: `feat(genui): gate MoonBit preparation before commit`.

### Task 5: Prove Deterministic Browser and Production Boundaries

**Files:**
- Modify: `examples/web/tests/genui.spec.ts`
- Modify: `examples/web/preview-tests/genui-preview.spec.ts`

**Interfaces:**
- Uses only public UI controls and the development-only test seam introduced in Task 4.
- Preserves all existing lifecycle, stale-generation, cancellation, dry-run, DOM-failure, revision, and host-state tests unrelated to Spike 0.

- [x] **Step 1: Replace the old fixed-answer browser test with failing feasibility contracts.**
  - Stub the development endpoint for each fixture and verify the raw candidate reaches one MoonBit evaluate-and-commit call; JavaScript performs no candidate parse or domain operation.
  - Assert committed output and generic evidence derive matched row keys and summary from the normalized host dataset. Provider-supplied answer text cannot determine either value.
  - Return a runtime-invalid candidate and prove committed markup/revision and fixed-explorer selection/filter/focus remain unchanged.
  - Return a runtime-valid but task-wrong candidate and prove MoonBit reports rubric failure before session commit, preserving the same state.
  - Inject session dry-run and DOM-apply failures through existing failure seams and prove the dedicated revision does not falsely advance.
  - Replay a recorded control twice from equivalent baselines and assert identical markup, generic evidence, rubric result, and safe-output digest.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 2: Update failing production-preview contracts.**
  - Recorded-control UI is visible and works in production.
  - `POST /api/genui-feasibility` returns 404.
  - Fetch every JavaScript asset referenced by `genui.html` and assert none contains `127.0.0.1:11434`, `GENUI_OLLAMA_MODEL`, `/api/genui-feasibility`, `promptTokens`, or `outputTokens`.
  - Include a known-positive control by asserting the development source module does contain at least one forbidden marker before trusting the production absence check.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 3: Build and run the focused development browser tests.**
  - Run `moon build --target js` from the repository root.
  - Run `npx playwright test tests/genui.spec.ts --grep "feasibility|recorded|rubric" --project=chromium --workers=1` from `examples/web`.
  - Expected: all new feasibility contracts pass with no Ollama process.

- [x] **Step 4: Run production isolation and smoke the real page.**
  - Run `npx playwright test -c playwright.preview.config.ts --project=chromium --workers=1`.
  - Expected: recorded replay succeeds, provider endpoint is 404, and production assets contain no forbidden provider markers.
  - Start the development server through the supervised launcher, open `/genui.html`, replay each recorded fixture, and visually confirm fixture selection, status, committed output, and error preservation.
  - Stop the supervised server after the browser check.

- [x] **Step 5: Run affected suites and commit.**
  - Run `node --test src/genui-feasibility-*.test.mjs`.
  - Run `moon test ffi/jsx`.
  - Run the complete `examples/web` Playwright suite once.
  - Expected: all affected fixture, provider, flow, MoonBit, development E2E, and preview E2E suites pass.
  - Commit message: `test(genui): verify feasibility transaction boundaries`.

### Task 6: Freeze and Execute the Nine-Slot Local Study

**Files:**
- Create: `examples/web/playwright.feasibility.config.ts`
- Create: `examples/web/tests/genui-feasibility-live.spec.ts`
- Create: `examples/web/scripts/build-genui-feasibility-manifest.mjs`
- Create: `examples/web/scripts/run-genui-feasibility-study.mjs`
- Create: `examples/web/scripts/finalize-genui-feasibility-study.mjs`
- Create: `examples/web/scripts/run-genui-feasibility-study.test.mjs`
- Create and commit before execution: `examples/web/studies/2026-07-15-genui-local-llm-v1.json`
- Generate: `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility.json`

**Interfaces:**
- Dedicated Playwright config always starts a fresh Vite server with `reuseExistingServer: false`, one Chromium worker, no retries, and a timeout covering nine 120-second slots.
- Live test runs the manifest’s frozen case/slot schedule in order, cross-checks every case against `GENUI_FEASIBILITY_FIXTURES`, resets the dedicated session before every slot, and invokes `evaluateSavedCandidate` exactly once for every returned raw candidate.
- The study runner records the frozen Git commit and committed manifest digest before any request, refuses a dirty tree, runs deterministic preflight once, invokes the live test once, and writes final evidence even when the decision is negative.
- The Playwright harness durably appends `started` to the runner-owned ignored journal before each browser endpoint call. Each completed attempt appends its terminal result and exact raw candidate bytes; evidence finalization retains only approved digests and classifications.
- The separate provider-disabled finalizer may reopen an interrupted journal only to classify the trailing `started` slot as `interrupted`, classify later slots as `not_run_interrupted`, and emit complete negative evidence. It imports no provider adapter, receives no endpoint or run capability, and cannot start Vite or Playwright.

- [x] **Step 1: Write failing live-harness and finalizer tests without enabling the study in CI.**
  - Skip the live harness unless `GENUI_FEASIBILITY_LIVE=1`.
  - Execute exactly nine calls through `window.__canopyGenUiFeasibilityTest.runSlot`.
  - Append `started` before each fake provider call and one terminal entry afterward; never retry or substitute.
  - Simulate a process interruption after `started`. Prove the provider-disabled finalizer records `interrupted` plus every later `not_run_interrupted` slot, emits nine terminal slots and `NOT_YET_FEASIBLE`, and makes zero provider calls.
  - Prove execute mode refuses any existing journal or evidence for the same study ID.
  - Write raw slot output under Playwright’s ignored `test-results` directory in a `finally` block so timeout, provider failure, or assertion failure does not erase evidence.
  - Run `NEW_MOON_MOD=0 moon check` after the test file edit.

- [x] **Step 2: Add the isolated live-study Playwright config.**
  - Force `workers: 1`, `retries: 0`, a fresh server, and explicit base URL.
  - The study runner supplies the frozen `GENUI_FEASIBILITY_MANIFEST` path and a freshly generated ephemeral `GENUI_FEASIBILITY_RUN_CAPABILITY` to the server process, then passes the capability separately to the Playwright harness. Neither value uses a `VITE_` prefix or enters browser assets, and per-slot model or manifest changes are prohibited.
  - Run `NEW_MOON_MOD=0 moon check` after the file edit.

- [x] **Step 3: Write the manifest builder, study runner, finalizer, and refusal behavior.**
  - Refuse a dirty tree, absent committed manifest, manifest digest mismatch, or manifest/model identity mismatch before starting the server. Generate the 256-bit run capability with Node’s CSPRNG only after preflight passes; dependency-inject deterministic bytes in unit tests.
  - The manifest builder accepts the selected lookup tag explicitly, performs provider-read-only discovery, freezes the model-manifest SHA-256 digest plus a canonical digest of the complete relevant `/api/show` identity payload, and emits the versioned manifest without generating a candidate.
  - Record `git rev-parse HEAD`, committed manifest digest, lookup tag, model-manifest/details digests, Ollama version, effective template/parameter digests, explicit generation settings, fixture/normalizer/capability/schema/prompt/rubric digests, validation/build/test commands, raw exit codes, and raw slot classifications.
  - Run deterministic checks once: MoonBit package tests, Node unit tests, JS build, TypeScript check, focused development E2E, and production-preview E2E.
  - If preflight fails, make no Ollama requests and write `NOT_YET_FEASIBLE` with the failed check.
  - If preflight passes, invoke the dedicated live Playwright command once. Missing raw slot output is a failed slot and cannot trigger a rerun.
  - For every returned candidate, retain the exact raw bytes and digest, perform the real evaluate-and-commit path once, reset to the same baseline, then perform one provider-free evaluate-only replay from those bytes. Compare preparation classification, generic evidence, rubric result, and safe-output digest.
  - Select `TECHNICALLY_FEASIBLE` only when every deterministic criterion passes, every slot has a terminal classification, every completed candidate has `replay_equal: true`, and every fixture has at least one `success`; otherwise select `NOT_YET_FEASIBLE`.
  - Run `NEW_MOON_MOD=0 moon check` after each file edit.

- [x] **Step 4: Verify harness mechanics with a fake local provider before real model use.**
  - Run the dedicated server against a deterministic fake `fetch` or route fixture that yields one success, one generic rejection, and one provider failure per case.
  - Confirm exactly nine calls, no retry, stable slot IDs/seeds, complete raw output, dirty-tree refusal, and correct positive/negative decision aggregation.
  - This fake run is harness validation only and must not be written as local-model evidence.

- [x] **Step 5: Review implementation, then freeze the model-bound manifest.**
  - Commit all implementation and deterministic tests before model discovery or the first real Ollama request.
  - Run an independent different-model implementation review against the committed diff. Require explicit inspection of prompt/rubric separation, MoonBit parser/materializer authority, transaction gating, production isolation, immutable model identity, replay comparison, and no-retry slot accounting.
  - Resolve findings in a new implementation commit and rerun deterministic checks.
  - Run the provider-read-only manifest builder exactly once as `node examples/web/scripts/build-genui-feasibility-manifest.mjs --model gemma4:e2b --output examples/web/studies/2026-07-15-genui-local-llm-v1.json`, inspect every frozen field and digest, and commit the versioned manifest. Run a final independent review against that exact clean commit.
  - The lookup tag is not identity. Any code, prompt, fixture, schema, rubric, model-manifest/details digest, Ollama version, effective parameter, generation setting, schedule, manifest, or decision-rule change after this point starts a new versioned study.

- [x] **Step 6: Execute the real frozen study once.**
  - Run from repository root with `GENUI_FEASIBILITY_LIVE=1` and the committed manifest path:
    `GENUI_FEASIBILITY_MANIFEST=examples/web/studies/2026-07-15-genui-local-llm-v1.json node examples/web/scripts/run-genui-feasibility-study.mjs`.
  - Expected: one final evidence JSON containing nine terminal slots and either `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE`; a negative decision is a valid completed study result.
  - Do not rerun failed or missing slots. A new run requires new versioned evidence and an explicit changed-input reason.

- [x] **Step 7: Verify and commit evidence separately.**
  - Validate the evidence JSON parses, all digests and nine slots are present, the decision follows the frozen rule, and no raw source rows, credentials, environment dump, or private user data were retained.
  - Run `slopless` on the design and implementation-plan Markdown; save raw findings under `.slopless/findings` and fix concrete prose findings while leaving document-level readability metrics as advisory.
  - Run `moon info && moon fmt`; inspect `.mbti` drift and confirm no unintended public trait-bound or type-surface changes.
  - Commit the evidence and any final status-only design update separately from implementation with message `docs(genui): record local feasibility result`.

The v1 execution stopped at deterministic preflight before provider access.
The inherited study-mode environment made the development E2E Vite process
require an ephemeral run capability that is intentionally created only after
preflight. The frozen rule therefore selected `NOT_YET_FEASIBLE`, classified
all nine slots as `not_run_preflight_failure`, and prohibited a v1 rerun.

## v2 Harness Correction Continuation

### Task 7: Isolate Validation Child Environments

**Files:**

- Modify: `examples/web/scripts/run-genui-feasibility-study.mjs`
- Test: `examples/web/scripts/run-genui-feasibility-study.test.mjs`

**Interfaces:**

- Consumes: a plain parent environment object, a validation command's explicit
  manifest `env` object, and the existing validation-command list.
- Produces: `buildValidationEnv(parentEnv, explicitEnv) -> object`, plus
  `runDeterministicPreflight(validationCommands, parentEnv = process.env)`.
  Every validation spawn uses the fresh environment returned by the helper.

- [x] **Step 1: Write failing pure and spawn-wiring tests.**

  Add `buildValidationEnv` and `runDeterministicPreflight` to the runner imports.
  Add two pure Node tests:

  ```javascript
  test('validation environment removes inherited study state and preserves unrelated keys', () => {
    assert.deepEqual(
      buildValidationEnv(
        {
          PATH: '/bin',
          GENUI_FEASIBILITY_LIVE: '1',
          GENUI_FEASIBILITY_RUN_CAPABILITY: 'ambient-secret',
        },
        {},
      ),
      { PATH: '/bin' },
    );
  });

  test('validation environment applies explicit manifest study state after isolation', () => {
    assert.deepEqual(
      buildValidationEnv(
        {
          PATH: '/bin',
          GENUI_FEASIBILITY_LIVE: '1',
          CONTROL: 'ambient',
        },
        {
          GENUI_FEASIBILITY_LIVE: '0',
          CONTROL: 'manifest',
        },
      ),
      {
        PATH: '/bin',
        GENUI_FEASIBILITY_LIVE: '0',
        CONTROL: 'manifest',
      },
    );
  });
  ```

  Add one integration test through the real preflight spawn:

  ```javascript
  test('deterministic preflight isolates ambient study state at the child process', () => {
    const assertionScript = `
      const assert = require('node:assert/strict');
      assert.equal(process.env.GENUI_FEASIBILITY_LIVE, '0');
      assert.equal(process.env.GENUI_FEASIBILITY_RUN_CAPABILITY, undefined);
      assert.equal(process.env.UNRELATED_PARENT_KEY, 'preserved');
    `;
    const preflight = runDeterministicPreflight(
      [{
        id: 'environment-boundary',
        command: process.execPath,
        args: ['-e', assertionScript],
        cwd: '.',
        env: { GENUI_FEASIBILITY_LIVE: '0' },
      }],
      {
        GENUI_FEASIBILITY_LIVE: '1',
        GENUI_FEASIBILITY_RUN_CAPABILITY: 'ambient-secret',
        UNRELATED_PARENT_KEY: 'preserved',
      },
    );

    assert.equal(preflight.passed, true);
    assert.equal(preflight.checks[0].exitCode, 0);
  });
  ```

- [x] **Step 2: Run the focused test and confirm RED.**

  Run from `examples/web`:

  ```bash
  node --test scripts/run-genui-feasibility-study.test.mjs
  ```

  Expected: failure because `buildValidationEnv` is not exported.

- [x] **Step 3: Implement the pure environment boundary and use it at spawn.**

  Add to `run-genui-feasibility-study.mjs`:

  ```javascript
  export function buildValidationEnv(parentEnv, explicitEnv) {
    const childEnv = { ...parentEnv };
    for (const key of Object.keys(childEnv)) {
      if (key.startsWith('GENUI_FEASIBILITY_')) delete childEnv[key];
    }
    Object.assign(childEnv, explicitEnv);
    return childEnv;
  }
  ```

  Pass the injected environment through the existing spawn path:

  ```javascript
  function runCommand(check, parentEnv) {
    // Existing cwd and spawn result handling remain unchanged.
    const result = spawnSync(check.command, check.args, {
      cwd,
      env: buildValidationEnv(parentEnv, check.env),
      stdio: 'inherit',
    });
    // Existing result object remains unchanged.
  }

  export function runDeterministicPreflight(
    validationCommands,
    parentEnv = process.env,
  ) {
    // Existing loop remains unchanged except:
    const result = runCommand(command, parentEnv);
  }
  ```

  Do not mutate `process.env`, scrub after the explicit overlay, or change the
  live-provider process environment.

- [x] **Step 4: Confirm GREEN and regression coverage.**

  Run from `examples/web`:

  ```bash
  node --test scripts/run-genui-feasibility-study.test.mjs
  ```

  Expected: all runner/finalizer/manifest tests pass.

  Run from the repository root after each edited file:

  ```bash
  NEW_MOON_MOD=0 moon check
  ```

- [x] **Step 5: Commit the correction separately.**

  ```bash
  git add examples/web/scripts/run-genui-feasibility-study.mjs \
    examples/web/scripts/run-genui-feasibility-study.test.mjs
  git commit -m "fix(genui): isolate validation child environments"
  ```

### Task 8: Freeze the Versioned v2 Study

**Files:**

- Modify: `examples/web/scripts/build-genui-feasibility-manifest.mjs`
- Test: `examples/web/scripts/run-genui-feasibility-study.test.mjs`
- Create: `examples/web/studies/2026-07-15-genui-local-llm-v2.json`

**Interfaces:**

- Consumes: the same selected `gemma4:e2b` lookup tag and provider-read-only
  identity discovery used by v1.
- Produces: study ID `genui-local-llm-v2`, a non-empty
  `changedInputReason`, and v2-only journal, raw-output, and evidence paths.
  `manifestVersion` remains `1` because the manifest schema is unchanged.

- [x] **Step 1: Write the failing v2 manifest assertions.**

  Extend the existing manifest-builder test:

  ```javascript
  assert.equal(manifest.manifestVersion, 1);
  assert.equal(manifest.studyId, 'genui-local-llm-v2');
  assert.equal(
    manifest.changedInputReason,
    'validation children remove inherited GENUI_FEASIBILITY_* before manifest env overlay',
  );
  assert.equal(
    manifest.journalPath,
    'examples/web/test-results/genui-feasibility-live-v2/journal.jsonl',
  );
  assert.equal(
    manifest.rawOutputPath,
    'examples/web/test-results/genui-feasibility-live-v2/raw-slots.json',
  );
  assert.equal(
    manifest.evidencePath,
    'docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json',
  );
  ```

- [x] **Step 2: Run the focused test and confirm RED.**

  Run from `examples/web`:

  ```bash
  node --test scripts/run-genui-feasibility-study.test.mjs
  ```

  Expected: the current v1 study ID, absent changed-input reason, and v1
  output paths fail the new assertions.

- [x] **Step 3: Change only the versioned manifest metadata and paths.**

  In the manifest object returned by `buildManifest`, retain all frozen
  generation settings, schedule, inputs, commands, and decision rules. Replace
  or add only:

  ```javascript
  studyId: 'genui-local-llm-v2',
  changedInputReason:
    'validation children remove inherited GENUI_FEASIBILITY_* before manifest env overlay',
  journalPath: 'examples/web/test-results/genui-feasibility-live-v2/journal.jsonl',
  rawOutputPath: 'examples/web/test-results/genui-feasibility-live-v2/raw-slots.json',
  evidencePath: 'docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json',
  ```

- [x] **Step 4: Confirm GREEN, then commit the builder change.**

  Run:

  ```bash
  node --test examples/web/scripts/run-genui-feasibility-study.test.mjs
  NEW_MOON_MOD=0 moon check
  git add examples/web/scripts/build-genui-feasibility-manifest.mjs \
    examples/web/scripts/run-genui-feasibility-study.test.mjs
  git commit -m "test(genui): define corrected v2 feasibility study"
  ```

- [x] **Step 5: Generate and inspect the v2 manifest exactly once.**

  From a clean repository root:

  ```bash
  node examples/web/scripts/build-genui-feasibility-manifest.mjs \
    --model gemma4:e2b \
    --output examples/web/studies/2026-07-15-genui-local-llm-v2.json
  ```

  Verify the v2 identity and paths, the changed-input reason, exactly nine
  unchanged schedule slots, seven validation commands, frozen input digests,
  and unchanged decision rule. Commit:

  ```bash
  git add examples/web/studies/2026-07-15-genui-local-llm-v2.json
  git commit -m "test(genui): freeze corrected local feasibility study"
  ```

- [x] **Step 6: Review the exact frozen v2 commit before execution.**

  A different-model reviewer must inspect the committed environment-ordering
  tests, runner boundary, manifest source commit, digests, model identity,
  schedule, output paths, and decision rule. Resolve any finding in a new
  commit and generate a new versioned study; do not mutate a reviewed manifest.

### Task 9: Execute v2 Once and Record Its Result

**Files:**

- Create: `docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json`
- Modify: `docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility.md`
- Modify: `docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility-implementation.md`

**Interfaces:**

- Consumes: one clean, reviewed v2 frozen commit with absent v2 output paths.
- Produces: one immutable v2 evidence object selecting only
  `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE`.

- [x] **Step 1: Execute the frozen v2 study exactly once.**

  From the repository root:

  ```bash
  GENUI_FEASIBILITY_LIVE=1 \
  GENUI_FEASIBILITY_MANIFEST=examples/web/studies/2026-07-15-genui-local-llm-v2.json \
  node examples/web/scripts/run-genui-feasibility-study.mjs
  ```

  Do not rerun, replace a slot, edit the manifest, or overwrite evidence. If
  execution stops, preserve the v2 journal and evidence as the v2 result.

- [x] **Step 2: Validate the evidence before committing it.**

  Confirm that JSON parsing succeeds; the evidence references the reviewed
  v2 frozen commit and manifest digest; all nine slots have one terminal
  classification; the decision follows the frozen rule; and no raw candidate,
  fixture row, credential, environment dump, or product-value claim is
  retained.

  Post-study verification later deleted the ignored v2 journal and raw-slot
  archive when Playwright cleaned `examples/web/test-results`. The study was
  not rerun and the missing files were not reconstructed. The incident record
  preserves the surviving manifest/evidence digests and limits the claim to
  the conservative aggregate result.

- [x] **Step 3: Update status without changing the recorded outcome.**

  Record the v2 decision and observed boundary in the design. Mark Tasks 7-9
  complete only after their evidence exists. Keep the v1 result and evidence
  intact.

- [x] **Step 4: Run final verification and independent review.**

  Run from the repository root:

  ```bash
  node --test examples/web/scripts/run-genui-feasibility-study.test.mjs \
    examples/web/src/genui-feasibility-fixtures.test.mjs \
    examples/web/src/genui-feasibility-provider.test.mjs \
    examples/web/src/genui-feasibility-demo.test.mjs \
    examples/web/src/genui-feasibility-flow.test.mjs
  NEW_MOON_MOD=0 moon test
  NEW_MOON_MOD=0 moon info
  NEW_MOON_MOD=0 moon fmt
  ```

  Run from `examples/web`:

  ```bash
  npx playwright test --config=playwright.feasibility.config.ts \
    --project=chromium
  npx playwright test --config=playwright.preview.config.ts \
    --project=chromium --workers=1
  npx tsc --noEmit
  ```

  Inspect `.mbti` drift and require a different-model review of the final clean
  committed range, including the v2 evidence.

- [ ] **Step 5: Commit evidence separately and complete the branch workflow.**

  ```bash
  git add docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json \
    docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility.md \
    docs/plans/2026-07-15-generative-ui-local-llm-technical-feasibility-implementation.md
  git commit -m "docs(genui): record corrected local feasibility result"
  ```

  Push the branch, open the pull request, and use the repository's automatic PR
  lifecycle until the required aggregate CI gate is green.

## Reuse Check

### Existing project APIs reused

- `GenerativeUiCandidate::validate`, `GenerativeUiRawNode`, `GenerativeUiHostCapabilities`, and structured diagnostics remain the sole raw-candidate semantic authority.
- `decode_candidate_json` and `decode_capabilities_json` remain the only candidate and capability wire decoders.
- `candidate_to_projection`, `jsx_session_commit_candidate`, session dry-run, DOM apply, and revision commit remain the only output commit path.
- Existing session failure and host-state browser seams are reused instead of adding rollback or a second DOM owner.
- Existing order fixture data is imported from `src/fixtures/orders.json`; it is not copied into the study catalog.

### MoonBit core APIs checked and reused

- `Json`/`FromJson`, `Result`, and `Option` decode and classify the experimental boundary.
- `Map` and `Set` represent normalized scalar rows and uniqueness checks; no duplicate container is introduced.
- `Array::filter`, `map`, `fold`, `find_first`, and `every` implement source-order-preserving filter/project/aggregate operations; list comprehensions remain an equivalent candidate where clearer during implementation.
- `@cmp.minimum`/`maximum` implement numeric extrema; no hand-written min/max branch is introduced.
- `@buffer.Buffer` is used for deterministic text construction; repeated string concatenation in a loop is rejected.
- `@encoding.encode` plus `@crypto.sha256` and `bytes_to_hex_string` produce the opaque safe-output digest inside MoonBit.

### Existing APIs checked but not used

- `GenerativeUiLifecycle` and the async Promise/Abort driver are not used by evaluate-only because they own request/session state; the private commit transaction retains lifecycle semantics.
- `genui-data.ts` order-specific filter and summary helpers remain for the fixed explorer but are not generalized into the multi-schema study; their UI-state contract is narrower than the frozen normalized dataset.
- Spike 0 `parseGenUiRecipe` and its answer-specific schema are removed because they encode the expected pending filter, required columns, and sum.
- Direct projection metadata is not treated as host data materialization; projection JSON is reused only as a deterministic digest source for the already validated safe output.
- JavaScript `JSON.parse` is used only for trusted fixture ingestion and provider-envelope decoding. It is not used for raw candidate interpretation.

### New responsibility boundaries

- The Task 1 private transaction accepts only an opaque validated candidate and owns all session effects.
- Trusted fixture adapters normalize frozen source formats but never receive candidate bytes.
- The MoonBit preparation core owns normalized-data decoding, candidate-directed filter/project/aggregate operations, generic evidence, safe-output construction, safe-output validation, and safe-output digest.
- The fixture-specific rubric owns expected outcomes but no source access, candidate access, validation, materialization, or commit authority.
- The JavaScript flow selects evaluate-only or evaluate-and-commit and preserves terminal results; it does not order or implement trust stages.
- The provider adapter owns one local request, immutable-identity checks, and metrics but no candidate parser, trust policy, or retry policy.

## Final Acceptance

- All nine frozen slots have terminal classifications and no slot was retried or replaced.
- Every provider candidate was treated as opaque bytes until the same MoonBit parser/validator used by replay accepted it.
- Generic materialization and fixture-specific rubric evaluation occurred only inside one MoonBit preparation core; rubric failures never reached session commit.
- Online evaluate-and-commit and provider-free evaluate-only replay agree on preparation classification, generic evidence, rubric result, and safe-output digest for every returned candidate.
- All failure classes preserve the last valid dedicated UI, fixed-explorer state, and committed revision.
- Recorded production replay uses the same MoonBit preparation/commit path without any provider marker or endpoint in production assets.
- The evidence file selects only `TECHNICALLY_FEASIBLE` or `NOT_YET_FEASIBLE` and contains no product-value or usability claim.
