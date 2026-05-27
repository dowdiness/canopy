# §P0b — First Real Workspace Memo (Smoke Wiring Proof) Design

**Date:** 2026-05-28
**Belongs to slice:** §P0b Phase 1b — backlog item "first real workspace memo registered with `register_dep`" (carried in `project_shared_runtime_workspace_contract` memory under the "Phase 1b queue items" list since PR4 retro 2026-05-25).
**Pairs with:** `docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md` (PR3/PR4 coordinator + atomic-construction substrate).
**Status:** Brainstorm-approved by user 2026-05-28; pending Codex stage-2 design validation, then `superpowers:writing-plans` handoff.

## 0. Background

The coordinator infrastructure that owns `register_dep` / `unregister_dep` / `destroy_editor`-gateway / `read_protected` has shipped through canopy PRs #345 (atomic ctor), #347 (coordinator package), #348 (Lambda FFI atomic boundary), #349 (WS1 production accessor), #351 + #352 (Markdown + JSON parity). Across all six PRs, no production caller has invoked `Coordinator::register_dep` — the only exerciser is `workspace/coordinator/coordinator_wbtest.mbt`, which uses **synthetic** `ProtectedCell` values constructed inside the test itself.

This milestone closes that gap: the smallest caller that drives `register_dep` against **real protected cells** of **real editors** built by the production `assemble_lambda_handle` factory and registered with the global `coordinator` singleton. The deliverable is a wbtest, not a production memo — by explicit user choice, the success criterion is "prove the wiring works end-to-end," not "ship a user-visible aggregator."

## 1. Scope

**In scope:**

- One new file: `ffi/lambda/workspace_memo_smoke_wbtest.mbt`.
- Four test scenarios (§5) exercising: sanity read, reactivity on editor mutation, destroy-gateway refusal under live dep, clean teardown.
- One `@incr.Derived[Int]` workspace memo, GC-rooted by a test-owned `Watch`, depending on two real `parser_source` protected cells from two Lambda editors built by `assemble_lambda_handle`.

**Out of scope:**

- New coordinator API. Notably **no** `Coordinator::register_workspace_memo` — test owns the `Watch` directly and calls `register_dep` / `unregister_dep` manually. Spec §6 ownership convergence is deferred to a follow-up; the §10 "Spec gaps" section records this explicitly.
- Production accessor migration. No FFI surface change. No `.mbti` drift.
- `Coordinator::destroy_editor` mid-dispose-raise ordering hardening (the deferred-from-PR4 concern). This smoke test cannot surface it — see §6.1.
- Cross-language coordinators. Per WS2 spec §4, JS-bundle isolation makes shared-runtime cross-language a Phase 2 concern. This memo is Lambda-only.
- Markdown / JSON parity workspace memos. Symmetric follow-ups; out of scope for this milestone by the "smallest deliverable" criterion.
- Variety in cell types or editor count beyond N=2 with one cell each (brainstorm Approaches B/C rejected as adding diff with little epistemic gain).

## 2. The contract in one paragraph

A workspace memo is an `@incr.Derived[T]` whose compute closure reads protected cells from one or more editors via `coordinator.read_protected(editor_id, cell)`. It is GC-rooted by a `Watch` (held by the memo's owner — test or coordinator). For each `(editor_id, cell)` it reads, its owner calls `coordinator.register_dep(memo_id, editor_id, cell_id)` after construction. While any such dep edge is live, `coordinator.destroy_editor(editor_id)` returns `Err(AbortReport { kind: DestroyWhileDependedUpon, ... })`; the editor stays alive and the memo's reads continue to succeed. On owner-driven teardown, the owner calls `coordinator.unregister_dep` for each edge it registered, disposes the `Watch`, then `destroy_editor` for each editor succeeds. Spec §6 says the coordinator eventually owns this lifecycle; in this milestone the test owns it as a deliberate Phase-1 shape.

## 3. Hard constraints

| § | Constraint | Where addressed |
|---|------------|-----------------|
| 3.1 | Real editor cells only — no synthetic `ProtectedCell` construction. The PR3 wbtest already covers synthetic-cell variants of all 5 `AbortKind` paths; this test's marginal value is in driving the live substrate. | §4 components — `h_a.cells.parser_source` etc., never `ProtectedCell::from_derived` directly. |
| 3.2 | Global coordinator singleton — uses `coordinator` from `ffi/lambda/lifecycle.mbt`, not a freshly-allocated test-local `Coordinator::new()`. Reason: the milestone is "first production caller registers a real dep on real cells in the real coordinator." | §4 components. Test top calls `reset_coordinator_for_phase1_tests()` (defined `ffi/lambda/lifecycle_phase1_wbtest.mbt:11`, package-scope accessible from the new sibling wbtest) **only to clear FFI handle maps** — see §3.7 for the actual coordinator-state contract. |
| 3.3 | Test owns the `Watch` and the `register_dep`/`unregister_dep` calls — no new coordinator API. | §6.2 explicitly records this as deviating from spec §6 ownership; §10 lists the follow-up. |
| 3.4 | `abort` on `read_protected` `Err` inside the compute fn. Phase 1 invariant: live `register_dep` ⇒ destroy refused ⇒ `read_protected` returns `Ok`. Any Err implies a contract violation, not a recoverable runtime condition. Per `[[feedback-no-safe-recovery-abort-ok]]`. | §4 compute fn. |
| 3.5 | The four scenarios stay in independent `test "..."` blocks (not chained into one large test). Per `[[feedback-codex-broad-vs-scoped-review]]` — independence makes the "what does this scenario prove" review-able per test name. | §5. |
| 3.6 | Cannot exercise `Coordinator::destroy_editor` mid-dispose-raise. None of Lambda's 10 ProtectedCells has a `dispose` closure that raises in normal flow. | §6.1, §10. |
| 3.7 | **Coordinator state leaks across tests by design.** `reset_coordinator_for_phase1_tests` only force-clears the FFI-side `lambda_handles` / `view_states` / `pretty_view_states` / `last_created_handle` maps. The coordinator's `editors` registry, `deps` registry, and `next_id` counter all persist across tests (helper docstring at `ffi/lambda/lifecycle_phase1_wbtest.mbt:14-20` is explicit about this; PR4 deliberately avoided routing through `coordinator.destroy_editor` because the gateway can refuse). Each test therefore MUST execute full manual cleanup at its end (unregister all registered deps, dispose the watch, destroy the editors). Test correctness must not depend on coordinator state being empty at test start; instead, each test ends with the coordinator-state delta it introduced fully reversed. | §5 — every scenario has an explicit "Teardown" sentence; §10 records the eventual coordinator-side `reset_for_tests` helper as deferred. |

## 4. Components

**File:** `ffi/lambda/workspace_memo_smoke_wbtest.mbt`. New file; not appended to `lifecycle_phase1_wbtest.mbt`. Reason: the workspace-memo concern is a distinct domain from PR4's atomic-construction tests; a sibling file keeps blame, naming, and test discovery clean.

**Imports:** `@workspace` for `read_protected`/`register_dep`/`unregister_dep`/`destroy_editor`/`AbortReport`/`AbortKind` constructors; `@incr` for `Runtime::derived` and `Watch`.

**Per-test setup** (each of the four `test "..."` blocks performs the same prelude — duplicated rather than helperized at this scale, to keep the proven-end-to-end-path visible in each test body):

1. `reset_coordinator_for_phase1_tests()` — clears the FFI-side handle maps only. Coordinator state (editors / deps / next_id) persists across tests per §3.7; correctness comes from each test's own mandatory teardown (§5) and from monotonic `next_id` (`workspace/coordinator/methods.mbt:44-45`) ensuring this test's freshly-allocated `EditorId`s do not intersect leaked edges.
2. `let h_a = assemble_lambda_handle("editor_a_<scenario>")` — full atomic construction via the production factory.
3. `let h_b = assemble_lambda_handle("editor_b_<scenario>")` — second editor in the same coordinator.
4. Construct the workspace memo:

   ```text
   let sum_d : @incr.Derived[Int] = coordinator.runtime().derived(fn() {
     let sa = coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source)
       .unwrap_or_else(fn(r) { abort("workspace memo smoke: \{r}") })
     let sb = coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source)
       .unwrap_or_else(fn(r) { abort("workspace memo smoke: \{r}") })
     sa.length() + sb.length()
   })
   ```

5. `let w = sum_d.watch()` — primes the cell on first read + GC-roots it for the test's duration.
6. Two `coordinator.register_dep` calls:

   ```text
   coordinator.register_dep(sum_d.id(), h_a.editor_id, h_a.cells.parser_source.cell_id())
   coordinator.register_dep(sum_d.id(), h_b.editor_id, h_b.cells.parser_source.cell_id())
   ```

The exact mutation API used in scenario 2 (`set_text` / `apply_edit` / equivalent) is to be confirmed during implementation by reading the live `SyncEditor` surface — if no public mutation method exists at the cell layer, implementation may need to introduce one (in which case it's a real spec gap; surface it then, do not silently improvise). The protected-cell *read* path is fully proven by PR3/PR4; the protected-cell *invalidation-on-input-mutation* path is the smoke test's primary new claim, so the chosen mutation API matters.

## 5. Test scenarios

Each is its own `test "..."` block.

**5.1 Sanity sum.** After setup, set both editors' sources to known strings (`"abc"`, `"defgh"`). Assert `w.read().unwrap() == 3 + 5`. **Teardown** (required per §3.7): `unregister_dep` both edges, `w.dispose()`, `destroy_editor(h_a.editor_id)`, `destroy_editor(h_b.editor_id)`. Return values not asserted here (that's §5.4's job); the goal is to leave coordinator state unchanged from test start.

**5.2 Reactivity on editor mutation.** After setup with both sources at known values, prime read. Mutate `h_a`'s source to a new string. Read again. Assert the new sum reflects the mutated length. This is the smoke test's primary new claim: invalidation propagates from a real `parser_source` input through `read_protected` into the workspace memo. **Teardown:** same as §5.1.

**5.3 Destroy gateway refusal under live dep.** After setup, assert `coordinator.destroy_editor(h_a.editor_id)` returns an `Err(AbortReport { ... })` whose `kind == DestroyWhileDependedUpon`, `editor_id == h_a.editor_id`, and `cell_id == Some(sum_d.id())` — matching the implementation at `workspace/coordinator/methods.mbt:130-137` which puts the *workspace memo's* `CellId` (the first found `referring[0]`) in the report. Other `AbortReport` fields (`agent_id`, `cell_label`, `domain_tag`) are not asserted by this scenario. The `referring[0] == sum_d.id()` determinism rests on this test's own state, not on coordinator-wide cleanliness: within scenario 5.3, the only workspace memo whose dep-edges reference `h_a.editor_id` is `sum_d` (because `h_a.editor_id` is freshly allocated by this test's `assemble_lambda_handle` call, and `register_dep` was only called for `sum_d`), so the `referring` array contains exactly one entry. **Then** assert that `h_a` is still alive: re-reading the workspace memo succeeds and the sum is unchanged from before the failed destroy. **Teardown:** same as §5.1.

**5.4 Clean teardown — assertions on each step.** This scenario's distinct value over §5.1/§5.2/§5.3's implicit teardown is that each cleanup step's return value is explicitly asserted. After setup, call:

```text
coordinator.unregister_dep(sum_d.id(), h_a.editor_id, h_a.cells.parser_source.cell_id())
coordinator.unregister_dep(sum_d.id(), h_b.editor_id, h_b.cells.parser_source.cell_id())
w.dispose()
```

Then assert:

```text
coordinator.destroy_editor(h_a.editor_id) == Ok(())
coordinator.destroy_editor(h_b.editor_id) == Ok(())
```

No additional teardown — the asserted steps ARE the teardown.

## 6. What this design deliberately defers

### 6.1 `Coordinator::destroy_editor` mid-dispose-raise

The PR3 implementation flips `alive = false` BEFORE the dispose loop (`workspace/coordinator/methods.mbt:139-142`). The intent is: a re-entrant `read_protected` during dispose cannot observe `alive=true` paired with disposed watches. The deferred-from-PR4 concern is: if any `(p.dispose)()` in the loop raises, the editor is left in a zombie state (`alive=false`, partially-disposed protected cells, still present in `self.editors`).

This smoke test cannot surface that concern because none of the 10 Lambda `ProtectedCell.dispose` closures raises in normal flow. Surfacing it requires a synthetic poison `ProtectedCell` whose `dispose` raises — that's a separate "destroy ordering hardening" follow-up PR, which will exercise the synthetic-cell path that PR3 wbtest already uses, just with an injected raise. Not bundled here because (a) it's orthogonal to the "real cells / register_dep" claim of this milestone, (b) it would re-open coordinator API design, and (c) the smoke test's value is exactly in *not* mixing concerns.

### 6.2 Spec §6 coordinator-owned lifecycle

The spec's §6 statement that "coordinator owns workspace-memo lifecycle" implies a `Coordinator::register_workspace_memo(memo, deps) -> WatchHandle` API that:

- accepts the `Derived[T]` and a list of `(EditorId, ProtectedCell[_])` deps,
- internally calls `register_dep` for each,
- owns the `Watch`,
- on `dispose_workspace_memo(handle)` (or via `WatchHandle::dispose`), calls `unregister_dep` for each registered edge before disposing the watch.

This milestone deliberately does **not** introduce that API. The test drives the substrate by hand. Two reasons: (a) the user's stated goal is "prove the wiring works" — not "ship the ownership API," (b) the ownership API's shape is a meaningful design question on its own (handle vs raw `Watch`, dep-list at construction vs incremental, what happens if a registered dep's editor was already destroyed). Conflating it with the smoke milestone risks repeating the §P0b PR-shape brainstorm trajectory (5 non-convergent Codex rounds 2026-05-24). The follow-up gets its own spec.

### 6.3 Cross-language coordinators

Per WS2 spec §4, the three FFI bundles each compile to their own JS module with their own `coordinator` singleton. Cross-language workspace memos require either a single shared JS bundle, a `globalThis`-coalesced coordinator via `extern "js"`, or a backend-FFI redesign. All Phase 2. Not touched here.

## 7. Why a wbtest rather than production code

The deliverable could in principle live as production code in `ffi/lambda/` (e.g., a `lambda_workspace_summary.mbt` module exposing some derived value to JS). That would force the design surface to grow: where in the FFI API surface does it sit, what JSON shape does it return, what's its consumer's lifecycle obligation. The user's chosen criterion — "prove the wiring works" — is exactly the criterion that says "stop short of those questions." A wbtest gives full coverage of the substrate claim with zero FFI-API design surface, and leaves the "what's the first user-visible workspace aggregator" question fully open for a separate brainstorm.

## 8. Why ABORT inside the compute fn

The compute fn calls `unwrap_or_else(fn(r) { abort(...) })` rather than constructing a fallback `Int`. Three reasons:

1. **Contract invariant.** A live `register_dep(memo_id, editor_id, cell_id)` edge means `destroy_editor(editor_id)` refuses → editor stays alive → its protected cell stays alive → `read_protected` returns `Ok`. The only way to reach `Err` is for a caller to have violated the contract (e.g. forgot to register the dep, or registered then read a different cell, or disposed the cell out-of-band). Abort surfaces the violation loudly; a silent fallback hides it.
2. **Memory precedent.** `[[feedback-no-safe-recovery-abort-ok]]` records the project rule: keep `abort` when catching would produce silently wrong results. A summary memo returning `0` on `Err` would silently produce a wrong sum.
3. **Test discipline.** The smoke test stays on the happy path. The unhappy paths are PR3's domain. Mixing them would dilute the milestone's narrative.

The abort report string interpolates the `AbortReport`'s `Show` impl so test failures carry full diagnostic context.

## 9. Verification gate

Before opening the PR, all four must pass:

- `NEW_MOON_MOD=0 moon check` workspace-wide: clean.
- `NEW_MOON_MOD=0 moon test` workspace-wide: 1182 baseline → 1186 (+4 new tests; one per §5 scenario). Exact baseline to confirm at implementation time.
- `git diff *.mbti` → zero hits. No public API change.
- Codex stage-4 scoped review (interaction effects: register/unregister symmetry, destroy-refusal report fidelity, teardown sequence) + broad open-ended review. Pair confirmed load-bearing for this workstream per `[[feedback-codex-broad-vs-scoped-review]]`.

## 10. Spec gaps surfaced

- **§6.2** — Coordinator-owned workspace-memo lifecycle API not delivered; follow-up spec/PR required.
- **§6.1** — Mid-dispose-raise hardening; separate follow-up PR with synthetic poison cell.
- **§4 mutation API** — exact `SyncEditor` text-mutation method to use in scenario 5.2 is not pinned in this spec. If no suitable public mutation method exists, implementer must surface this as a real spec gap rather than improvising (e.g. add a `set_source_for_tests` and document it, or surface the design question).
- **Coordinator-side reset helper** — this spec works around the leak documented in §3.7 by requiring per-test manual cleanup. A real fix is a `Coordinator::reset_for_tests()` (or test-mode flag) that clears `editors`, `deps`, and resets `next_id`. Cleaner long-term, but a workspace/coordinator/ API addition and out of scope here per "smallest design surface." If a future test cannot reliably cleanup (e.g. a deliberate panic test that bypasses teardown), revisit then.
- **Panic-safety of test-owned lifecycle** — per §3.7, if a test panics between `register_dep` and the corresponding `unregister_dep`, the coordinator retains the leaked dep. Monotonic `next_id` ensures the leaked dep cannot cause a *correctness* failure in subsequent tests (their freshly-allocated EditorIds don't intersect with the leaked edges), but it does cause memory growth and could be confusing in introspection. Documented as known behavior; the coordinator-side reset helper above would close it.

## 11. Decision summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Realness | Real editors via `assemble_lambda_handle` | User-chosen; PR3 wbtest already covers synthetic-cell variants. |
| Coordinator scope | Per-language (Lambda only) | WS2 §4 — JS-bundle isolation makes cross-language Phase 2. |
| Editor count | 2 | Smallest N that proves "cross-editor" rather than "self-edge." |
| Cell type variety | 1 (`parser_source` on both editors) | Heterogeneity adds little epistemic gain (Approach B rejected). |
| Memo ownership | Test owns `Watch`; manual `register_dep`/`unregister_dep` | Smallest design surface (Option A in user's §6 question). |
| Test location | `ffi/lambda/workspace_memo_smoke_wbtest.mbt` (new file) | Distinct domain from PR4 atomic-construction tests. |
| Compute fn Err policy | `abort` | Phase 1 invariant + `[[feedback-no-safe-recovery-abort-ok]]`. |
| Test scenarios | 4 (sanity / reactivity / destroy refusal / clean teardown) | Cover each load-bearing edge once; no scenario-bundling. |
| Destroy mid-dispose-raise | Out of scope | Synthetic poison cell required; orthogonal milestone. |
| §6 ownership API | Deferred | Avoids conflating substrate proof with API design. |
