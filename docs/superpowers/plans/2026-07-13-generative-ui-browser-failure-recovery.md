# Generative UI Browser Failure Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add browser evidence for invalid/stale candidate rejection and real DOM apply failure/recovery through the existing GenUI session boundary, then record safety metrics and acceptance evidence without adding a provider or parallel lifecycle.

**Architecture:** Keep lifecycle, validation, dry-run, revision, and recovery policy in the existing MoonBit packages. Add only a thin underscored browser observability surface in `examples/web/src/genui.js` that calls existing FFI exports. Playwright induces DOM failure by monkeypatching the page root, then restores the method and invokes the same real session API for recovery. Cancellation and late candidate chunks remain cognition-only because the current candidate replay export is synchronous.

**Tech Stack:** MoonBit (`NEW_MOON_MOD=0`), Vite, TypeScript, Playwright, existing `@moonbit/crdt-jsx` FFI exports, Markdown evidence.

## Global Constraints

- Do not connect a live Gemini or other provider.
- Treat candidate input as untrusted; do not add raw HTML, arbitrary code, navigation, persistence, network, or generated side effects.
- Preserve the functional-core / imperative-shell boundary.
- Reuse existing lifecycle/session/recovery APIs; do not add a second controller or fake DOM.
- Run `NEW_MOON_MOD=0 moon check` after every MoonBit file edit.
- Use one file per edit call and re-read after line-count changes.
- Keep browser cancellation claims separate from the synchronous candidate replay boundary.
- Do not touch the Rabbita pointer branch or unrelated submodule state.

---

### Task 1: Add thin browser observability

**Files:**
- Modify: `examples/web/src/genui.js`

**Interfaces:**
- Produces `window.__canopyGenUiTest` with call-through methods only:
  - `replayCandidate(candidateJson, capabilitiesJson)` delegates to the existing `replayCandidate` function.
  - `replayCandidateAtRevision(baseRevision, candidateJson, capabilitiesJson)` delegates to the existing imported FFI function and returns its parsed result without changing commit policy.
  - `sessionRevision()` returns the existing `jsxSessionRevision` value.
  - `resetSession()` delegates to the existing `resetState` function.
- The surface must not implement lifecycle transitions, validation, revision changes, or recovery.

- [x] Step 1: Add the underscored test surface beside the existing candidate/session functions.
- [x] Step 2: Run the web TypeScript check or Vite build to catch syntax/import errors.

Run: `npm run build` from `examples/web`
Expected: Vite build succeeds.

- [x] Step 3: Re-read the edited region and verify the surface contains no duplicated policy.

### Task 2: Add failing browser scenarios

**Files:**
- Modify: `examples/web/tests/genui.spec.ts`

**Interfaces:**
- Consumes `window.__canopyGenUiTest` from Task 1.
- Uses the existing `#html-preview` root and existing Data Explorer controls.
- Uses a valid candidate fixture and a forbidden `raw_html` candidate fixture defined in the test file.

- [x] Step 1: Add a test for invalid candidate rejection with unchanged revision and preview.
- [x] Step 2: Add a test for stale base-revision rejection with unchanged revision and preview.
- [x] Step 3: Add a test that replaces the preview root insertion method with a throwing wrapper, asserts `DomApplyError`, unchanged revision, and no committed success state.
- [x] Step 4: Restore the insertion method, submit the same valid candidate, and assert revision advances once and the candidate surface is present.
- [x] Step 5: Add host-state assertions for filter, selection, detail text, and focus around the failure/recovery sequence.
- [x] Step 6: Add deterministic replay assertions comparing normalized preview markup, mounted-node count, success, and revision from two fresh sessions.
- [x] Step 7: Run only the new tests and confirm failures identify missing observability or behavior rather than silently passing.

Run: `npx playwright test tests/genui.spec.ts --grep "candidate|recovery|replay"`
Expected before implementation: failing tests due to missing test surface or assertions.

### Task 3: Implement the minimum browser support

**Files:**
- Modify: `examples/web/src/genui.js`

- [x] Step 1: Implement only the call-through methods specified in Task 1.
- [x] Step 2: Run `npm run build` from `examples/web`.
- [x] Step 3: Run the focused Playwright scenarios from Task 2.

Expected: invalid/stale/apply-failure/recovery/determinism tests pass.

### Task 4: Record safety metrics and acceptance evidence

**Files:**
- Modify: `docs/plans/2026-07-12-generative-ui-input-vertical-slice.md`
- Modify: `examples/web/tests/genui.spec.ts`

**Interfaces:**
- Records concrete evidence for AC-01 through AC-15.
- Leaves cancellation/late-candidate browser evidence explicitly marked as cognition-only because the browser candidate API is synchronous.
- Records zero-count safety metrics and reproducible latency/rejection/repair/heap observations from an attached raw JSON measurement artifact.

- [x] Step 1: Map each acceptance criterion to exact landed implementation and test paths.
- [x] Step 2: Mark only criteria with concrete evidence as complete; leave any unsupported claim unchecked.
- [x] Step 3: Replace stale Issue #888 wording with merged PR #892 evidence.
- [x] Step 4: Add a dated evidence table for focused MoonBit tests and browser tests.
- [x] Step 5: Add a dedicated Playwright measurement test with fixed denominators: five valid replay latency samples, three invalid attempts, three stale-base attempts, one forced failure plus repair, and two deterministic fresh replays.
- [x] Step 6: Attach raw JSON containing every `performance.now()` duration, attempt/result counts, state snapshots, repair count, and `performance.memory` availability/values.
- [x] Step 7: Add the measured safety metrics, including zero counts and unavailable measurements where the runtime cannot report them; label cognition-derived cancellation values separately.
- [x] Step 8: Self-review the plan for stale future-tense Phase 0–4 descriptions and distinguish historical implementation steps from remaining gates.

### Task 5: Verify the complete slice

**Files:**
- No source changes.

- [x] Step 1: Run focused MoonBit checks/tests for `lib/cognition`, `ffi/jsx`, and `lang/jsx/proj`.
- [x] Step 2: Run scoped `moon fmt` and `moon info` only if MoonBit files changed; inspect generated interface drift.
- [x] Step 3: Run `npm run build` from `examples/web`.
- [x] Step 4: Run the complete `examples/web/tests/genui.spec.ts` suite.
- [x] Step 5: Run `git diff --check` and inspect the final diff for only the intended files.
- [x] Step 6: Report that live-provider work remains gated on the recorded evidence.

## Verification record

- `NEW_MOON_MOD=0 moon check lib/cognition ffi/jsx lang/jsx/proj` passed.
- Focused MoonBit tests passed: cognition `120/120`, ffi/jsx `49/49`, and
  lang/jsx/proj `43/43`.
- Scoped `moon fmt` and `moon info` passed with no generated interface drift.
- `npm run build` passed.
- Playwright GenUI suite passed: `14/14`; the final measurement JSON is tracked
  at `docs/plans/evidence/2026-07-13-generative-ui-safety-metrics.json` and
  matches the values recorded in the vertical-slice plan.
- The live-provider gate remains closed because AC-12 and AC-14 are still
  explicitly unchecked.
