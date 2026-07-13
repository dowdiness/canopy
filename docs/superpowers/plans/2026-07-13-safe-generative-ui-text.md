# Safe Generative UI Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` or `subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Commit every bounded validated Generative UI text value safely and exactly, including JSX-significant characters, without adding candidate-specific syntax to the generic JSX parser.

**Architecture:** Candidate lowering becomes a pure typed projection in `ffi/jsx`: it creates `@jsx_ast.JsxNode` and matching `@canopy_core.ProjNode` values directly, then reuses the existing reconciliation, dry-run, and DOM-patch pipeline. A separate pure render-baseline planner/reducer owns remount decisions and logical commit state. The session remains the imperative shell: parser lifecycle, registry clearing, DOM calls, and source restoration.

**Tech Stack:** MoonBit; `@cognition`; `@jsx_ast`; Canopy `@canopy_core.ProjNode`; JSX `reconcile` and `DryRunModel`; `@qc` QuickCheck; JavaScript FFI DOM fixture; Playwright GenUI suite.

## Global Constraints

- Keep typed JSX construction in `ffi/jsx`; `lib/cognition` remains renderer-neutral.
- Do not add a candidate-only token, grammar rule, or hidden DOM attribute side effect.
- Preserve the replay adapter’s existing unknown/disposed/stale-session rejection before candidate or capabilities decoding.
- Synthetic Root uses node ID `0`; every mounted candidate node uses one unique preorder ID in `[-1025, -2]`; `-1` remains the root-container parent sentinel.
- Candidate attempts always plan a remount. Source renders after a successful candidate remount until a source commit succeeds.
- `committed_source` remains paired with the parser and is never overwritten by a candidate commit.
- Dry-run failure preserves physical DOM. DOM-apply failure preserves only logical source/revision/mounted-ID state, marks dirty, and relies on the next successful remount; do not claim DOM rollback.
- Use `@qc.quick_check_fn` only over states reachable from the reducer constructor. Record the failure seed or shrunk counterexample when a property fails.
- Run `moon check ffi/jsx` immediately after every MoonBit source/test/package edit.

---

### Task 1: Replace source-string candidate lowering with typed projection lowering

**Files:**
- Modify: `ffi/jsx/generative_ui_adapter.mbt`
- Modify: `ffi/jsx/moon.pkg`
- Create: `ffi/jsx/generative_ui_projection_wbtest.mbt`
- Modify: `ffi/jsx/session_contract_wbtest.mbt`

**Interfaces:**
- Consumes: `@cognition.GenerativeUiCandidate::root`, `@cognition.GenerativeUiCandidateNode`, `@jsx_ast.JsxNode`, `@jsx_ast.JsxAttr`, `@canopy_core.ProjNode::ProjNode`.
- Produces: private `candidate_to_projection(candidate : @cognition.GenerativeUiCandidate) -> @canopy_core.ProjNode[@jsx_ast.JsxNode]`.
- Produces: a private recursive lowering boundary that returns paired typed AST/projection nodes and owns the preorder synthetic-ID cursor.
- Produces: a Root wrapper with ID `0`; all mounted Element/Text nodes receive unique IDs beginning at `-2` and descending once per mounted node.

- [ ] **Step 1: Add failing typed-projection tests.**
  - In `generative_ui_projection_wbtest.mbt`, construct validated candidate fixtures containing `<`, `>`, `{`, `}`, `&`, single/double quotes, entity-looking strings, and Unicode text.
  - Assert `candidate_to_projection` produces `JsxNode::Text` carrying the exact original MoonBit `String`, not an `ExprSpan`, not HTML, and not escaped source text.
  - Add a table/column/filter/summary fixture whose metadata includes `&amp;lt;`, `&amp;amp;`, quotes, and Unicode. Assert the typed `JsxAttr::StringLit` values are the escaped transport values expected by the existing one-pass `data-genui-*` normalizer.
  - Add a full-tree traversal assertion: every projection node ID is unique, no node has ID `-1`, Root is `0`, and mounted IDs are within `[-1025, -2]`.
  - Add a bounded QuickCheck generator for valid raw candidate trees. Validate each generated raw tree against fixture capabilities before lowering. Run the same whole-tree ID and exact-text assertions for every generated candidate plus a fixed special-string corpus.
  - Change the existing source-string snapshot and “rejects JSX syntax in text” tests in `session_contract_wbtest.mbt` to assert typed projection structure and text preservation instead.

- [ ] **Step 2: Verify the tests fail before implementation.**
  - Add the existing QuickCheck dependencies to `ffi/jsx/moon.pkg` under `for "wbtest"`, matching `core/moon.pkg`.
  - Run `moon test ffi/jsx`.
  - Confirm the test compile fails because `candidate_to_projection` is absent or because the old string-lowering contract cannot satisfy the typed assertions.

- [ ] **Step 3: Implement the minimal typed lowering.**
  - Replace `lower_generative_ui_candidate` and source-string helpers in `generative_ui_adapter.mbt` with `candidate_to_projection` and recursive typed lowering.
  - Map Stack/Panel/Table/Column/Filter/Summary to the same generic JSX elements and `data-genui-*` metadata currently emitted by the source-string adapter.
  - Reuse the existing attribute escaping transformation before constructing `JsxAttr::StringLit`; do not introduce a second entity decoder.
  - Construct the AST `children` arrays and the matching projection `children` arrays from one recursive result so their shapes cannot diverge.
  - Use source spans `0..0` for all synthetic nodes. Assign Root `0`; decrement only for mounted Element/Text nodes, never allocating `-1`.
  - Lower `GenerativeUiCandidateNode::Text` directly to `JsxNode::Text(value)` with exact `String` equality. Do not parse candidate text and do not reject syntax characters.

- [ ] **Step 4: Verify the pure projection boundary.**
  - Run `moon check ffi/jsx`.
  - Run `moon test ffi/jsx`.
  - Confirm special-character text, ID properties, and metadata transport tests pass. On any QuickCheck failure, retain its seed/counterexample in the failing test output before changing production code.

- [ ] **Step 5: Commit the pure lowering slice.**
  - Stage only `ffi/jsx/generative_ui_adapter.mbt`, `ffi/jsx/moon.pkg`, `ffi/jsx/generative_ui_projection_wbtest.mbt`, and the targeted test edits.
  - Commit with a focused message such as `feat: lower generative UI candidates to typed JSX`.

### Task 2: Add a pure session-baseline planner and property tests

**Files:**
- Create: `ffi/jsx/render_baseline.mbt`
- Create: `ffi/jsx/render_baseline_wbtest.mbt`
- Modify: `ffi/jsx/moon.pkg`

**Interfaces:**
- Consumes: render kind (`Source` or `Candidate`), source structural-transition boolean, and immutable baseline state.
- Produces: private `SessionBaseline` containing `mounted_origin : Source | Candidate`, `dirty : Bool`, and `revision : Int`.
- Produces: private `plan_render(baseline, kind, structural_transition) -> RenderPlan`, where `RenderPlan` contains `must_remount`.
- Produces: private `finish_render(baseline, plan, outcome) -> (SessionBaseline, SessionBaselineEffect)`, where outcomes are `Success`, `DryRunFail`, `DomFail`, and `ProjectionFail`, and effects include `RestoreCommittedSource` only when the shell must restore a source parser.

- [ ] **Step 1: Write failing transition and property tests.**
  - Define exact example tests for initial source success, candidate success, source success following candidate success, dry-run failure, DOM failure, and source projection failure.
  - Assert every candidate plan remounts; source plans after Candidate origin remount even for equal root tags; Source origin only avoids remount when not dirty and without a structural transition.
  - Define a bounded generator of `(render kind, structural-transition flag, outcome)` event sequences. Fold only from `SessionBaseline::initial()`; never generate arbitrary invalid baseline fields.
  - Property assertions: candidate attempts remount; any dirty baseline remounts; first source attempt after a candidate success remounts; failures do not advance revision or replace mounted origin; successes advance revision once; source failures retain Candidate origin; source `ProjectionFail` emits `RestoreCommittedSource`.

- [ ] **Step 2: Verify the baseline tests fail.**
  - Run `moon test ffi/jsx`.
  - Confirm missing `SessionBaseline`, render-plan, and outcome interfaces prevent compilation.

- [ ] **Step 3: Implement the pure planning/reduction boundary.**
  - Keep all types and functions package-private in `render_baseline.mbt`.
  - Encode Candidate origin as the single successful-baseline fact; do not add a redundant `force_source_remount` boolean.
  - Plan remount before an outcome is known. Complete a plan only after the shell reports the outcome.
  - On `Success`, increment revision exactly once and set origin to the completed render kind. On `DryRunFail` and `DomFail`, retain revision/origin and make the resulting baseline dirty. On `ProjectionFail`, retain revision/origin/dirty and emit `RestoreCommittedSource` only for Source rendering.

- [ ] **Step 4: Verify the functional core.**
  - Run `moon check ffi/jsx`.
  - Run `moon test ffi/jsx`.
  - Confirm all example transitions and generated reachable-state properties pass.

- [ ] **Step 5: Commit the baseline slice.**
  - Stage only the new baseline implementation and whitebox test, plus any `moon.pkg` change not already committed in Task 1.
  - Commit with a focused message such as `feat: model JSX render baselines purely`.

### Task 3: Integrate typed candidate commits with the existing session shell

**Files:**
- Modify: `ffi/jsx/session.mbt`
- Modify: `ffi/jsx/session_contract_wbtest.mbt`
- Modify: `ffi/jsx/generative_ui_replay_adapter.mbt` only if the changed private candidate-commit result mapping needs an explicit lifecycle outcome; preserve its early session/revision gate.

**Interfaces:**
- Consumes: `candidate_to_projection`, `SessionBaseline`, `plan_render`, `finish_render`, existing `@jsx_proj.reconcile`, `DryRunModel::apply`, and `apply_patches_with_registry`.
- Produces: `jsx_session_commit_candidate` that commits typed candidate projections without parser-source lowering.
- Preserves: JSON response schema, session handles, `jsx_session_render`, `jsx_session_replay_candidate_json`, and stale/disposed error precedence.

- [ ] **Step 1: Write failing session-boundary tests.**
  - Add deterministic DOM-fixture coverage for normal JSX → candidate → normal JSX. Assert each success advances revision once, the final DOM contains only normal JSX nodes, and reported mounted IDs match the final reachable set.
  - Add candidate → candidate coverage with shifted children. Assert the second candidate replaces the first in sibling order rather than reconciling synthetic IDs against the prior candidate registry.
  - Add replay coverage proving special-character candidate text commits successfully and the DOM fixture exposes exactly the original text.
  - Add metadata round-trip coverage proving `data-genui-*` values containing `&amp;lt;`, `&amp;amp;`, quotes, and Unicode reach the DOM with their original candidate values.
  - Add source projection failure after candidate success. Assert revision and mounted IDs do not advance, parser restoration is requested by the baseline effect, Candidate origin remains active, and a subsequent source success remounts and commits.
  - Preserve/update existing dry-run and DOM-apply failure tests: dry-run failure leaves physical DOM intact; DOM-apply failure makes no physical rollback assertion but preserves logical revision/mounted IDs and repairs on the next successful remount.

- [ ] **Step 2: Verify the integration tests fail.**
  - Run `moon test ffi/jsx`.
  - Confirm the current `jsx_session_commit_candidate` still calls source-string lowering and cannot satisfy direct-text, candidate-origin, and remount assertions.

- [ ] **Step 3: Refactor the session as a thin shell over the baseline.**
  - Replace the session’s independent revision/dirty bookkeeping with one `SessionBaseline`; derive JSON response revision from it.
  - Extract the shared dry-run/registry/DOM commit procedure so source projection and typed candidate projection invoke the same shell path with a `RenderPlan`.
  - Source rendering: update/read the parser, compute structural transition only for Source projections, obtain a Source plan, and execute `RestoreCommittedSource` when the finished plan requests it.
  - Candidate rendering: validate base revision before any renderer work, obtain the typed candidate projection, obtain a Candidate plan, and never call `parser.set_source` or mutate `committed_source`.
  - Clear the registry only after dry-run success when the plan requires remount. Advance `mounted_ids`, `last_proj`, dry-run model, baseline, and source state only after DOM success.
  - Keep `committed_source` updates exclusive to successful ordinary source commits. A failed DOM apply leaves logical session state untouched except for the dirty baseline; it may leave physical DOM partial or empty.
  - Keep the replay adapter’s first handle/revision lookup before chunk splitting, candidate decode, capability decode, and candidate validation.

- [ ] **Step 4: Verify the session boundary.**
  - Run `moon check ffi/jsx` after the session edit.
  - Run `moon test ffi/jsx` and inspect all session-contract, typed-projection, and QuickCheck properties.
  - Run `moon test lang/jsx/proj` to confirm the reused patch and dry-run contract remains valid.

- [ ] **Step 5: Commit the shell integration slice.**
  - Stage only the session, replay-adapter changes if any, and targeted session tests.
  - Commit with a focused message such as `fix: commit generative UI text without source parsing`.

### Task 4: Regenerate interfaces and run end-to-end verification

**Files:**
- Modify only if generated output changes: `ffi/jsx/pkg.generated.mbti`
- Modify only if browser coverage needs a new observable regression: `examples/web/tests/genui.spec.ts`

**Interfaces:**
- Consumes: all three prior tasks and the existing GenUI replay-browser action.
- Produces: verified JS build artifacts and an intentional interface diff, if any.

- [ ] **Step 1: Run focused formatting and interface generation.**
  - Run `moon fmt ffi/jsx`.
  - Run `moon info ffi/jsx`.
  - Inspect `ffi/jsx/pkg.generated.mbti`; no new public candidate/session API is expected because the typed projection and baseline helpers are package-private. Investigate any unexpected public interface drift before retaining it.

- [ ] **Step 2: Run focused MoonBit validation.**
  - Run `moon check ffi/jsx`.
  - Run `moon test ffi/jsx`.
  - Run `moon test lang/jsx/proj`.
  - Run `git diff --check` and confirm no staged or unstaged change includes the pre-existing `loom` or `rabbita` submodule pointers.

- [ ] **Step 3: Rebuild and run browser coverage.**
  - Run `bash scripts/build-js.sh` so the JS-only `ffi/jsx` package is exercised in its deployment target.
  - Run `CANOPY_SKIP_MOON_BUILD=1 bash scripts/test-web-e2e.sh tests/genui.spec.ts`.
  - If `examples/web/tests/genui.spec.ts` changed, ensure it observes one end-to-end special-text candidate result instead of asserting implementation details.

- [ ] **Step 4: Run workspace safety verification.**
  - Run `moon check` and record the expected pre-existing reserved-keyword warning separately from this change.
  - Confirm every task-owned source/test/generated-interface file is intentional and that `loom` and `rabbita` remain uncommitted.

- [ ] **Step 5: Commit verification-generated task files.**
  - Stage only task-owned formatting, test, generated-interface, and browser-regression files.
  - Commit with a focused message such as `test: cover generative UI text replay invariants` if a separate verification commit is needed; otherwise amend only mechanical generation output into the relevant prior task commit.
