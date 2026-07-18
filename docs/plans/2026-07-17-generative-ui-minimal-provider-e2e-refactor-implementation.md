# Generative UI minimal provider E2E refactor implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. The provider process lifecycle remains in the main context because timeout, signal, and process-tree ordering are load-bearing algorithms.

**Goal:** Separate provider child-process lifecycle from command orchestration, shorten deterministic lifecycle tests without weakening the real descendant-process check, and report live validation status accurately.

**Architecture:** The existing command runner remains the only executable entry point and continues to own CLI validation, private artifact creation, candidate classification, browser evaluation, and terminal result policy. One private support module owns the fixed Codex spawn contract, timeout and interrupt state, whole-process-tree termination, and bounded stdout/stderr settlement. Production timing remains unchanged; tests may inject shorter grace periods.

**Tech Stack:** Node.js ESM, `node:test`, Playwright Chromium, existing JavaScript browser adapter, existing MoonBit JSX evaluator.

## Global Constraints

- Send no credentialed provider request during this refactor.
- Preserve exactly one provider spawn and no retry.
- Preserve every Codex argument, working-directory, sandbox, and output path.
- Preserve output directory mode `0700`, durable file mode `0600`, and exclusive writes.
- Preserve candidate bytes until the existing MoonBit path owns semantic validation.
- Preserve every MoonBit classification, rubric result, replay result, and session-commit result.
- Keep the package command and current runner exports stable.
- Add no provider interface, scheduler, manifest, journal, or production API.
- Use one file per edit call and run `NEW_MOON_MOD=0 moon check` after every project-file edit.
- Keep the real Unix descendant-process test; injected fake timers cannot replace it.
- Report deterministic implementation verification separately from the unmet post-fix credentialed success signal.

---

### Task 1: Pin injectable lifecycle timing

**Files:**
- Modify: `examples/web/scripts/run-genui-minimal-provider-e2e.test.mjs`

**Interfaces:**
- Consumes: existing `runProviderAttempt(run, options, deps)` test seam.
- Produces: a failing contract that `deps.terminationGraceMs` and `deps.outputSettleMs` bound fake-process termination without changing production defaults.

- [ ] **Step 1: Strengthen the fake timeout test before structural changes**

Record elapsed wall time around the existing timeout test. Pass short positive `terminationGraceMs` and `outputSettleMs` dependency values, retain the exact expected `SIGTERM` then `SIGKILL` sequence, and assert completion well below the current five-second production grace. The assertion must fail against the current implementation because it ignores both injected values.

- [ ] **Step 2: Confirm the safety test fails for the intended reason**

Run only `provider timeout kills the process group and settles inherited output`. Expected: the signal assertions still pass, but the new elapsed-time bound fails after the current production grace expires.

- [ ] **Step 3: Re-run the existing structural safety net unchanged**

Run the remaining lifecycle tests individually: exact one invocation, live descendant cleanup, and interrupt without retry. Expected: all pass before extraction. This establishes that the branch starts from the known behavior being moved.

---

### Task 2: Extract the provider process lifecycle

**Files:**
- Create: `examples/web/scripts/genui-minimal-provider-process.mjs`
- Modify: `examples/web/scripts/run-genui-minimal-provider-e2e.mjs`
- Test: `examples/web/scripts/run-genui-minimal-provider-e2e.test.mjs`

**Interfaces:**
- Consumes: run paths, selected model, timeout, fixed provider invocation descriptor, and injectable process capabilities.
- Produces: `runProviderProcess(run, options, deps)`, returning the same observed process result and `invocationCount: 1` used by `runProviderAttempt`.
- Preserves: `runProviderAttempt` as the runner-level export responsible for mapping provider process results to existing terminal classifications.

- [ ] **Step 1: Move process-only behavior verbatim into the support module**

Move the child spawn, fixed Codex arguments, process observation, Unix process-group termination, Windows tree termination, and pipe settlement. Do not move CLI parsing, run-directory ownership, candidate classification, browser invocation, or terminal-result policy. Keep argument order and observable return fields unchanged.

- [ ] **Step 2: Add bounded timing dependencies at the lifecycle boundary**

Use positive internal defaults of 5,000 milliseconds for termination grace and pipe settlement. Accept test-only dependency overrides through the existing dependency object. These values control only waiting; they must not change timeout classification, signal order, invocation count, or production behavior.

- [ ] **Step 3: Delegate from the runner without changing its public contract**

Import the process function and call it from `runProviderAttempt`. Keep `runProviderAttempt` responsible for schema/work preparation, provider terminal classification, candidate presence, and safe messages. Re-export no new package command and introduce no provider-generic interface.

- [ ] **Step 4: Make the red timing contract pass**

Run the focused fake timeout test. Expected: pass quickly with the exact `SIGTERM` and `SIGKILL` sequence.

- [ ] **Step 5: Prove real process-tree cleanup remains effective**

Run the live descendant-process test with a shortened but nonzero injected termination grace. Expected: one spawn, `provider_timeout`, heartbeat observed before termination, and `ESRCH` when probing the grandchild after cleanup.

- [ ] **Step 6: Run the complete deterministic runner suite**

Run `node --test scripts/run-genui-minimal-provider-e2e.test.mjs`. Expected: 18 tests pass, zero failures, with materially lower wall time than the previous approximately 153-second full run when browser build state is warm.

- [ ] **Step 7: Commit the implementation separately from the design**

Commit the support module, runner delegation, and lifecycle test changes as one refactor commit. Do not amend the preceding design commit.

---

### Task 3: Verify unchanged product and evidence boundaries

**Files:**
- Verify: `examples/web/scripts/genui-minimal-provider-process.mjs`
- Verify: `examples/web/scripts/run-genui-minimal-provider-e2e.mjs`
- Verify: `examples/web/tests/genui-minimal-provider.spec.ts`
- Update remotely: PR #908 description only if its validation wording is ambiguous.

**Interfaces:**
- Consumes: Task 2 implementation.
- Produces: deterministic verification evidence and an explicit live-validation status; no credentialed artifact.

- [ ] **Step 1: Run focused and full local verification**

Run the provider unit suite, JSX MoonBit package tests, workspace `moon check`, TypeScript check, production web build, default Web Playwright suite, dedicated fake-provider browser/MoonBit path, and `git diff --check`. Each command must report its own exit status; do not infer success from a piped or wrapped status.

- [ ] **Step 2: Audit the structural boundary**

Confirm the support module imports only Node process/stream primitives and does not import fixtures, candidate schema, browser code, rubric code, or MoonBit adapters. Confirm the runner remains the sole owner of filesystem artifact and browser orchestration policy.

- [ ] **Step 3: Obtain an independent different-model review**

Require exact file-and-line evidence for process ordering, timeout/interrupt terminality, exactly-one invocation, unchanged Codex flags, and the distinction between deterministic verification and live feature validation. Fix every validated blocker and rerun its narrow reproducer.

- [ ] **Step 4: State the unmet live success criterion explicitly**

Ensure PR #908 says the only credentialed invocation failed before generation, the schema was corrected deterministically afterward, no second credentialed request was sent, and Required test 8/design success remains unmet. Do not describe the feature as live-validated or recommend merge on the basis of fake-provider success alone.

- [ ] **Step 5: Push and require green aggregate CI**

Push the refactor commits, run raw `gh pr checks 908`, and require `All Checks Passed` to be `pass`. If any job fails, inspect the failing job output, fix the source problem, and repeat focused verification before pushing.

## Acceptance criteria

- Provider process lifecycle has one focused private module and no generalized provider abstraction.
- Current CLI, runner exports, Codex arguments, artifact layout, classifications, and exit semantics remain unchanged.
- Fake timeout and interruption tests finish with injected bounded waits while retaining exact signal and no-retry assertions.
- A real descendant process is terminated and independently probed as absent.
- Complete Node, MoonBit, TypeScript, build, browser, and CI checks pass.
- No credentialed provider request is sent.
- PR #908 explicitly marks post-fix credentialed success and Required test 8 as unmet.
