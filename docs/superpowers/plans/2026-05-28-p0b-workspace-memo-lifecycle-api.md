# §P0b Workspace Memo Lifecycle API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Coordinator::register_workspace_memo` + `WorkspaceMemoHandle[T]` in `workspace/coordinator/`, collapsing the smoke test's manual `watch` + N×`register_dep` + N×`unregister_dep` + `dispose` choreography into two calls with register/unregister symmetry owned by the handle.

**Architecture:** One new production file in `workspace/coordinator/` defines the handle struct and the two methods (same package as the `Coordinator` struct, so it reaches the private `editors`/`deps` registries). One new wbtest in `ffi/lambda/` proves it end-to-end against real Lambda editor cells through the global `coordinator` singleton, porting the four smoke scenarios + adding 5 API-specific scenarios.

**Tech Stack:** MoonBit; `@workspace.Coordinator` (`workspace/coordinator/{methods,types}.mbt`); `@incr.Derived`/`Watch` (loom/incr); `assemble_lambda_handle` factory (`ffi/lambda/lifecycle.mbt:34`).

**Spec:** `docs/superpowers/specs/2026-05-28-p0b-workspace-memo-lifecycle-api-design.md` (Codex stage-2 validated, 3 rounds).

**Implementation discipline (per `~/.claude/CLAUDE.md` Algorithm Implementation Process):** production-API steps below give precise *prose* (signature + ordered behavior + invariants + exact `AbortReport` fields), not paste-ready bodies — write the body against the tests and `moon check`, not against a plan snippet. Test steps give concrete code (the safety net). Two implementation-time verification points are called out inline (P1 `cell_label` availability, P2 `Watch::read` raise behavior).

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `workspace/coordinator/workspace_memo.mbt` | Create | `WorkspaceMemoHandle[T]` struct + `Coordinator::register_workspace_memo` + `WorkspaceMemoHandle::{read,id,dispose}`. ~70 LOC. |
| `workspace/coordinator/pkg.generated.mbti` | Regenerated | `moon info` adds the two new public symbols. Reviewed in Task 7. |
| `ffi/lambda/workspace_memo_handle_wbtest.mbt` | Create | 9-scenario integration wbtest (3 ported A + 4 B + 1 C + 1 D). |
| `ffi/lambda/pkg.generated.mbti` | None expected | wbtest adds no `pub` symbols. Verified in Task 7. |

---

## Cross-task reference: per-test prelude & teardown (ffi/lambda wbtest)

Every scenario uses the same prelude and teardown idiom as `ffi/lambda/workspace_memo_smoke_wbtest.mbt`, **except** that `handle.dispose()` replaces the manual `unregister_dep` × N + `w.dispose()`. Duplicated per test (not helperized) to keep the proven path visible, matching the smoke wbtest's choice.

**Prelude:**
```moonbit
reset_coordinator_for_phase1_tests()
let handle_a = create_editor("wmh_<scenario>_a")
let handle_b = create_editor("wmh_<scenario>_b")
let h_a = lambda_handles.get(handle_a).unwrap()
let h_b = lambda_handles.get(handle_b).unwrap()
```

**FFI bookkeeping drain (after the API-level teardown):**
```moonbit
h_a.companion.dispose_analysis_attachment()
lambda_handles.remove(handle_a)
view_states.remove(handle_a)
pretty_view_states.remove(handle_a)
h_b.companion.dispose_analysis_attachment()
lambda_handles.remove(handle_b)
view_states.remove(handle_b)
pretty_view_states.remove(handle_b)
if last_created_handle.val == Some(handle_b) {
  last_created_handle.val = None
}
```

Per spec §6.5 / first-workspace-memo spec §3.7: coordinator state leaks across tests by design; monotonic `next_id` keeps each test's freshly-allocated `EditorId`s disjoint from leaked edges, so correctness does not depend on a clean coordinator at test start.

---

### Task 0: Worktree prep + baseline

**Files:** none.

- [ ] **Step 1: Initialize submodules in the worktree**

Git worktrees do not auto-checkout submodules. Run from the worktree root:

Run: `git -C /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/p0b-workspace-memo-api submodule update --init --recursive`
Expected: loom, event-graph-walker, etc. checked out. (Skip if already present.)

- [ ] **Step 2: Record baseline test count**

Run (from the worktree root): `NEW_MOON_MOD=0 moon test 2>&1 | tail -3`
Expected: `Total tests: <N>, passed: <N>, failed: 0`. Record `<N>`; the gate target is `<N> + 9`.

---

### Task 1: Production API — `WorkspaceMemoHandle` + `register_workspace_memo`

**Files:**
- Create: `workspace/coordinator/workspace_memo.mbt`

- [ ] **Step 1: Define the handle struct**

`pub struct WorkspaceMemoHandle[T]` with **all-private fields** (mirror `Coordinator`'s `priv`-per-field style in `types.mbt:140-145`):
- `coordinator : Coordinator` — by-value; its `HashMap`/`Ref` fields share the same underlying registries, so `dispose` mutates the same `deps` map `register` populated (Codex-confirmed sound).
- `memo_id : @incr.CellId`
- `watch : @incr.Watch[T]`
- `deps : Array[(EditorId, @incr.CellId)]` — the *deduplicated* edge list this handle registered.

- [ ] **Step 2: Implement `Coordinator::register_workspace_memo`**

Signature:
```moonbit
pub fn[T] Coordinator::register_workspace_memo(
  self : Coordinator,
  memo : @incr.Derived[T],
  deps : Array[(EditorId, @incr.CellId)],
) -> Result[WorkspaceMemoHandle[T], AbortReport]
```

Behavior, in this exact order (spec §4.1):
1. **Guard 0a (defect):** if `deps.is_empty()`, `abort(...)` with a message explaining a workspace memo needs ≥1 dep. Use `guard !deps.is_empty() else { abort(...) }` (note: `!x`, not the deprecated `not(x)`).
2. **Guard 0b (defect):** let `memo_id = memo.id()`; if `self.deps` already has an entry for `memo_id`, `abort(...)` (double-registration). Use `guard self.deps.get(memo_id) is None else { abort(...) }`. Sound only because 0a guarantees a registered memo owns ≥1 edge ⇒ a `deps` entry.
3. **Dedup** `deps` into a stable-order `distinct` array (skip a tuple already in `distinct` via `.contains`).
4. **Validate all, mutate nothing.** For each `(editor_id, cell_id)` in `distinct`:
   - `self.editors.get(editor_id.0)` → `None` ⇒ `return Err(AbortReport(kind=EditorDestroyed, editor_id~, agent_id="<unknown>", cell_id~))`.
   - registration not `alive` ⇒ `return Err(AbortReport(kind=EditorDestroyed, editor_id~, agent_id=reg.agent_id, cell_id~))`.
   - cell not in `reg.protected_reads` (use `.any(fn(p) { p.cell_id == cell_id })`, exactly as `read_protected` does at `methods.mbt:179`) ⇒ `return Err(AbortReport(kind=CellNotInProtectedSurface, editor_id~, agent_id=reg.agent_id, cell_id~))`.
   - **(P1 — verify at impl time)** `AbortReport`'s `cell_label?` is optional (`types.mbt:42-51`). For the not-in-surface case the cell has no entry to read a label from, so leave `cell_label` unset. The spec's "labeled error" aspiration only holds for cells that *are* in the surface — which don't error. Do **not** invent a label.
5. **Establish GC root.** `let w = memo.watch()` then prime via `w.read()` (mirrors `ProtectedCell::from_derived`, `types.mbt:99-100`).
   - **(P2 — verify at impl time)** `Watch::read(Self[T]) -> Result[T, CycleError]` has **no `raise` clause** (`loom/incr/cells/pkg.generated.mbti:347`), so priming returns a `Result` and cannot raise — a cycle is surfaced as `Err`, not a throw. Therefore the spec §4.1-step-2 "dispose-on-raise" safeguard has nothing to catch via this path; **omit the wrapper** unless `moon check` proves `w.read()` can raise here (it should not). Discard the primed value with `let _ = w.read()`.
6. **Register edges.** For each dep in `distinct`: `self.register_dep(memo_id, d.0, d.1)`.
7. `return Ok({ coordinator: self, memo_id, watch: w, deps: distinct })`.

- [ ] **Step 3: Implement the handle methods**

```moonbit
pub fn[T] WorkspaceMemoHandle::read(self) -> Result[T, @incr.CycleError]   // delegate to self.watch.read()
pub fn[T] WorkspaceMemoHandle::id(self) -> @incr.CellId                     // return self.memo_id
pub fn[T] WorkspaceMemoHandle::dispose(self) -> Unit
```

`dispose` behavior (spec §4.2), idempotent:
1. `guard !self.watch.is_disposed() else { return }` — second call is a no-op.
2. for each `(editor_id, cell_id)` in `self.deps`: `self.coordinator.unregister_dep(self.memo_id, editor_id, cell_id)` (already idempotent at `methods.mbt:77-97`).
3. `self.watch.dispose()`.

- [ ] **Step 4: Type-check the coordinator package**

Run: `NEW_MOON_MOD=0 moon check`
Expected: clean. Fix any error before proceeding (e.g. private-field access, `is None` guard syntax, `AbortReport` field names).

- [ ] **Step 5: Regenerate interface and commit**

Run: `NEW_MOON_MOD=0 moon info && moon fmt`
Then inspect: `git -C /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/p0b-workspace-memo-api diff -- workspace/coordinator/pkg.generated.mbti`
Expected: exactly two added public symbols (`WorkspaceMemoHandle` + its 3 methods, and `Coordinator::register_workspace_memo`). No changes to existing signatures (no trait-bound widening).

```bash
git add workspace/coordinator/workspace_memo.mbt workspace/coordinator/pkg.generated.mbti
git commit -m "feat(coordinator): add register_workspace_memo + WorkspaceMemoHandle"
```

---

### Task 2: Ported scenario A1 — sanity sum (TDD entry point)

**Files:**
- Create: `ffi/lambda/workspace_memo_handle_wbtest.mbt`

- [ ] **Step 1: Write the file header + A1 test**

```moonbit
// Whitebox integration test for the §P0b workspace memo lifecycle API.
// Proves Coordinator::register_workspace_memo + WorkspaceMemoHandle drive
// register_dep / unregister_dep / destroy_editor gateway / read_protected
// end-to-end against real Lambda editor cells via the global `coordinator`.
//
// Spec: docs/superpowers/specs/2026-05-28-p0b-workspace-memo-lifecycle-api-design.md

///|
test "wmh A1: sanity sum equals known value across two editors" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("wmh_a1_a")
  let handle_b = create_editor("wmh_a1_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()
  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("wmh A1 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("wmh A1 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let handle = match coordinator.register_workspace_memo(sum_d, [
    (h_a.editor_id, h_a.cells.parser_source.cell_id()),
    (h_b.editor_id, h_b.cells.parser_source.cell_id()),
  ]) {
    Ok(h) => h
    Err(r) => fail("register_workspace_memo: \{r}")
  }
  h_a.editor.set_text("abc")
  h_b.editor.set_text("defgh")
  assert_eq(handle.read().unwrap(), 3 + 5)
  handle.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_a: \{r}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_b: \{r}")
  }
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}
```

- [ ] **Step 2: Run only this test**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 1 test passes. If `register_workspace_memo` or `handle.read()`/`.dispose()` don't resolve, the Task-1 API has a signature mismatch — fix it there, not here.

- [ ] **Step 3: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh A1 sanity sum via register_workspace_memo"
```

---

### Task 3: Ported scenarios A2 (reactivity) + A3 (clean teardown)

**Files:**
- Modify: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (append)

- [ ] **Step 1: Append A2 (reactivity on mutation)**

Same prelude + memo + `register_workspace_memo` as A1 (scenario tag `a2`). Then:
```moonbit
  h_a.editor.set_text("ab")
  h_b.editor.set_text("cd")
  assert_eq(handle.read().unwrap(), 2 + 2)
  h_a.editor.set_text("abcdef")
  assert_eq(handle.read().unwrap(), 6 + 2)
```
Then `handle.dispose()`, the two asserted `destroy_editor` calls, and the FFI drain (see cross-task reference).

- [ ] **Step 2: Append A3 (clean teardown — destroy succeeds after dispose)**

Same prelude + memo + register (tag `a3`). Set sources `"x"`/`"yz"`, `let _ = handle.read().unwrap()` to prime, then:
```moonbit
  handle.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("A3 expected Ok destroying h_a after dispose, got \{r}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("A3 expected Ok destroying h_b after dispose, got \{r}")
  }
```
Then the FFI drain only (editors already destroyed).

- [ ] **Step 3: Run the file**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 3 tests pass. If A2's post-mutation assert reads the stale `4`, invalidation isn't propagating through the handle — surface it (do NOT add a manual fire); the smoke test proved this path, so a failure means an API regression in `register_workspace_memo`'s priming/registration.

- [ ] **Step 4: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh A2 reactivity + A3 clean teardown"
```

---

### Task 4: Rejection scenarios B1 (bad cell + atomicity) + B2 (dead editor)

**Files:**
- Modify: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (append)

- [ ] **Step 1: Append B1 (bad-cell rejection + atomicity)**

Prelude builds two editors (tag `b1`). Build a trivial `Derived[Int]` (e.g. `@incr.Derived(coordinator.runtime(), fn() { 0 })`). Declare a dep naming **editor A** but with **editor B's** `parser_source` cell id — a real cell, not in A's protected surface:
```moonbit
  let bad : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() { 0 })
  match coordinator.register_workspace_memo(bad, [
    (h_a.editor_id, h_b.cells.parser_source.cell_id()),
  ]) {
    Ok(_) => fail("B1 expected CellNotInProtectedSurface, got Ok")
    Err(report) =>
      assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  // Atomicity: nothing was registered, so destroy must succeed immediately.
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("B1 atomicity: destroy h_a should be Ok (no leaked dep), got \{r}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("B1 destroy h_b: \{r}")
  }
```
Then FFI drain. (No handle to dispose — registration failed.)

- [ ] **Step 2: Append B2 (dead-editor rejection)**

Prelude builds two editors (tag `b2`). Destroy editor A first (it has no deps, so it succeeds), then register a memo naming it:
```moonbit
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("B2 setup: destroy h_a should be Ok, got \{r}")
  }
  let m : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() { 0 })
  match coordinator.register_workspace_memo(m, [
    (h_a.editor_id, h_a.cells.parser_source.cell_id()),
  ]) {
    Ok(_) => fail("B2 expected EditorDestroyed, got Ok")
    Err(report) => assert_eq(report.kind, @workspace.EditorDestroyed)
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("B2 destroy h_b: \{r}")
  }
```
Then FFI drain. **Note:** after destroying `h_a`, do NOT call `h_a.companion.dispose_analysis_attachment()` again in the drain if `destroy_editor` already disposed it — `destroy_editor` (`methods.mbt:140-142`) runs the protected-cell dispose closures, not the companion attachment; the FFI wrapper does the companion dispose. Since this test bypasses the FFI wrapper, still call the companion dispose once in the drain. Verify no double-dispose abort at impl time; if one occurs, drop the `h_a` companion dispose for this scenario only.

- [ ] **Step 3: Run the file**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh B1 bad-cell+atomicity, B2 dead-editor rejection"
```

---

### Task 5: Panic scenarios B3 (double-registration) + B4 (empty deps)

**Files:**
- Modify: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (append)

MoonBit runs a test whose name starts with `panic ` expecting an `abort`. These two lock the §4.1 guards 0b and 0a.

- [ ] **Step 1: Append B3 (double-registration aborts)**

```moonbit
///|
test "panic wmh B3: registering the same memo twice aborts" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("wmh_b3_a")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let m : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    match coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s.length()
      Err(r) => abort("wmh B3 read: \{r}")
    }
  })
  let _first = coordinator.register_workspace_memo(m, [
    (h_a.editor_id, h_a.cells.parser_source.cell_id()),
  ])
  // Second registration of the same memo must abort (guard 0b).
  let _second = coordinator.register_workspace_memo(m, [
    (h_a.editor_id, h_a.cells.parser_source.cell_id()),
  ])
}
```
No teardown — the test aborts before reaching it. (Coordinator-state leak is acceptable per spec §6.5; monotonic `next_id` isolates later tests.)

- [ ] **Step 2: Append B4 (empty deps aborts)**

```moonbit
///|
test "panic wmh B4: registering with empty deps aborts" {
  reset_coordinator_for_phase1_tests()
  let m : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() { 0 })
  let _ = coordinator.register_workspace_memo(m, [])
}
```

- [ ] **Step 3: Run the file**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 7 tests pass (the two `panic ` tests pass by aborting as expected).

- [ ] **Step 4: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh B3/B4 panic guards (double-reg, empty deps)"
```

---

### Task 6: Gateway scenario C — destroy refusal under live handle

**Files:**
- Modify: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (append)

- [ ] **Step 1: Append C**

Prelude builds two editors (tag `c`) + the sum memo + `register_workspace_memo` (bind `handle`). Set sources `"hi"`/`"world"`, prime `let pre = handle.read().unwrap()`. Then:
```moonbit
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => fail("C expected DestroyWhileDependedUpon, got Ok")
    Err(report) => {
      assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
      assert_eq(report.editor_id, h_a.editor_id)
      @debug.assert_eq(report.cell_id, Some(handle.id()))
    }
  }
  // Operational aliveness: editor A still accepts writes + propagates.
  assert_eq(handle.read().unwrap(), pre)
  h_a.editor.set_text("hello-after-refused-destroy")
  assert_eq(handle.read().unwrap(), 27 + 5)
```
Then `handle.dispose()`, the two asserted `destroy_editor` calls, FFI drain.

- [ ] **Step 2: Run the file**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 8 tests pass. If `report.cell_id` mismatches `Some(handle.id())`: within this test only `handle`'s edges reference the freshly-allocated `h_a.editor_id`, so `referring[0]` (`methods.mbt:122-127`) is deterministically the memo's id — a mismatch means a leaked edge from an earlier test, i.e. a §6.5 isolation violation; run the file alone to confirm.

- [ ] **Step 3: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh C destroy refusal under live handle"
```

---

### Task 7: Idempotency scenario D + verification gate

**Files:**
- Modify: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (append)

- [ ] **Step 1: Append D (double dispose is a no-op)**

Prelude builds two editors (tag `d`) + sum memo + register (bind `handle`). Set sources `"x"`/`"yz"`, prime. Then:
```moonbit
  handle.dispose()
  handle.dispose() // second dispose must be a safe no-op
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("D destroy h_a after double dispose: \{r}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("D destroy h_b: \{r}")
  }
```
Then FFI drain.

- [ ] **Step 2: Run the file**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_handle_wbtest.mbt 2>&1 | tail -10`
Expected: 9 tests pass.

- [ ] **Step 3: Format + regenerate interfaces**

Run: `NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info`
Then: `git -C /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/p0b-workspace-memo-api diff --stat -- '*.mbti'`
Expected: only `workspace/coordinator/pkg.generated.mbti` changed (already committed in Task 1; should be no new diff here). `ffi/lambda/pkg.generated.mbti` must be unchanged — the wbtest adds no `pub` symbols. If it changed, a stray `pub` snuck into the wbtest; remove it.

- [ ] **Step 4: Full workspace check + test**

Run: `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test 2>&1 | tail -3`
Expected: `moon check` clean; `moon test` reports `<baseline from Task 0> + 9` passing, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add ffi/lambda/workspace_memo_handle_wbtest.mbt
git commit -m "test(ffi/lambda): wmh D idempotent dispose + verification gate"
```

- [ ] **Step 6: Codex pre-merge review (paired scoped + broad)**

Before opening the PR, run Codex stage-4 review per spec §8 and `[[feedback-codex-broad-vs-scoped-review]]`: a scoped pass (all-or-nothing registration, dispose idempotency, register/unregister symmetry, destroy-gateway report fidelity, guard 0a/0b) and a broad open-ended pass. This is a delegation checkpoint — log both entries. Address findings before merge.

---

## Self-review notes (author)

- **Spec coverage:** §4.1 guards 0a/0b → Task 1 Step 2 + Tasks 5; all-or-nothing validation → Task 1 + Task 4 B1; §4.2 dispose idempotency → Task 1 Step 3 + Task 7 D; §4.4 undeclared-read precondition → not testable by construction (documented-only), correctly no task. §5 destroy non-reopen → exercised by Task 6 C (gateway) + the fact dispose only touches the memo watch. §6 scenarios A1–D → Tasks 2–7. §8 gate → Task 7.
- **Type consistency:** `register_workspace_memo(Derived[T], Array[(EditorId, CellId)]) -> Result[WorkspaceMemoHandle[T], AbortReport]`; `handle.read()/id()/dispose()` used identically in every task. `@incr.Derived(rt, fn)` constructor and `cells.parser_source.cell_id()` match the smoke wbtest.
- **Open impl-time verification points:** P1 (`cell_label` not available for not-in-surface errors — pass `cell_id` only), P2 (`Watch::read` has no raise clause — omit the dispose-on-raise wrapper). Both are flagged at their step.
