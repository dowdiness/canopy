# §P0b First Real Workspace Memo (Smoke Wiring Proof) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a wbtest in `ffi/lambda/workspace_memo_smoke_wbtest.mbt` that drives `@workspace.Coordinator::register_dep` / `unregister_dep` / `destroy_editor` gateway / `read_protected` against the first **real-cell** workspace memo (an `@incr.Derived[Int]` summing two Lambda editors' `parser_source` lengths through the global `coordinator` singleton).

**Architecture:** One new wbtest file in `ffi/lambda/`, four `test "..."` blocks (sanity / reactivity / destroy refusal / clean teardown assertions). No new production code, no new public API, no `.mbti` changes. Each test fully sets up and tears down its own coordinator state per spec §3.7 (helper at `ffi/lambda/lifecycle_phase1_wbtest.mbt:11` only clears FFI handle maps; coordinator state leaks across tests, but freshly-allocated monotonic `EditorId`s prevent cross-test correctness coupling).

**Tech Stack:** MoonBit (whitebox tests), `@workspace.Coordinator` (`workspace/coordinator/methods.mbt`), `@incr.Runtime`/`Derived`/`Watch` (loom/incr), `@editor.SyncEditor`, `assemble_lambda_handle` factory (`ffi/lambda/lifecycle.mbt:34`).

**Spec:** `docs/superpowers/specs/2026-05-28-p0b-first-workspace-memo-design.md` (v1 + Codex round-1 + round-2 fixes inline).

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `ffi/lambda/workspace_memo_smoke_wbtest.mbt` | Create | The 4-test wbtest. ~120 LOC including required per-test bypass-destroy cleanup. |
| `ffi/lambda/moon.pkg.json` | None | No changes — wbtests live in the same package; no new deps. |
| `ffi/lambda/pkg.generated.mbti` | None expected | No public API change. Verification step confirms. |

---

## Cross-task reference: bypass-destroy cleanup pattern

All four tests use this teardown idiom (mirroring `lifecycle_phase1_wbtest.mbt:110-121`). It is duplicated in each test body (NOT factored into a helper) per spec §4's "duplicated rather than helperized at this scale, to keep the proven-end-to-end-path visible in each test body":

```moonbit
// After unregister_dep × 2 and w.dispose():
let _ = coordinator.destroy_editor(h_a.editor_id)
h_a.companion.dispose_analysis_attachment()
lambda_handles.remove(handle_a)
view_states.remove(handle_a)
pretty_view_states.remove(handle_a)
let _ = coordinator.destroy_editor(h_b.editor_id)
h_b.companion.dispose_analysis_attachment()
lambda_handles.remove(handle_b)
view_states.remove(handle_b)
pretty_view_states.remove(handle_b)
if last_created_handle.val == Some(handle_b) {
  last_created_handle.val = None
}
```

**Why bypass the FFI `destroy_editor(handle: Int)` wrapper** (`ffi/lambda/lifecycle.mbt:90-117`): it returns `Unit` and swallows the coordinator's `Err` into a `println`. Tests need to assert on the `Result`, so they call `coordinator.destroy_editor(h.editor_id)` directly and manually drain FFI bookkeeping. Same reasoning the existing PR4 wbtest uses.

**Why `let _ = ...` rather than `match`** at the cleanup site for tests 5.1/5.2/5.3 (NOT 5.4): teardown's job is to leave coordinator state clean; the return value isn't being asserted on (that's §5.4's job, where every step IS asserted).

---

### Task 1: Scaffold file + Test 5.1 (sanity sum)

**Files:**
- Create: `ffi/lambda/workspace_memo_smoke_wbtest.mbt`

- [ ] **Step 1: Verify baseline test count**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/scratch && NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: `Total tests: 1182, passed: 1182, failed: 0. [js]` (or close to 1182 — record the actual baseline). Each new `test "..."` block adds +1.

- [ ] **Step 2: Create the file with header + sanity sum test**

Write the following exactly (note: no `pub` on tests; `///|` block separator is required between top-level items):

```moonbit
// Whitebox integration test for the §P0b first real workspace memo.
// Proves end-to-end that Coordinator::register_dep / unregister_dep /
// destroy_editor gateway / read_protected hold against real Lambda
// editor cells built by the production `assemble_lambda_handle`
// factory + global `coordinator` singleton.
//
// Per spec §3.7, each test manually drives full teardown (unregister
// every registered dep, dispose the watch, bypass-destroy each editor,
// drain FFI bookkeeping) so correctness does not depend on coordinator
// state being empty at test start.
//
// Spec: docs/superpowers/specs/2026-05-28-p0b-first-workspace-memo-design.md

///|
test "smoke 5.1: sanity sum equals known value across two editors" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_1_a")
  let handle_b = create_editor("smoke_5_1_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  // Build the workspace memo on the coordinator's runtime.
  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match coordinator.read_protected(
      h_a.editor_id, h_a.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.1 read h_a: \{r}")
    }
    let sb = match coordinator.read_protected(
      h_b.editor_id, h_b.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.1 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  // Drive the editors to known sources.
  h_a.editor.set_text("abc")
  h_b.editor.set_text("defgh")
  assert_eq(w.read().unwrap(), 3 + 5)

  // Teardown per spec §3.7 (bypass-destroy + FFI drain).
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  let _ = coordinator.destroy_editor(h_a.editor_id)
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  let _ = coordinator.destroy_editor(h_b.editor_id)
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}
```

- [ ] **Step 3: Run only this new test**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_smoke_wbtest.mbt 2>&1 | tail -10`

Expected: 1 test passes. If it fails:
- **`@incr.Derived(rt, fn)` constructor not found** — verified at `loom/incr/cells/pkg.generated.mbti:38` as `Derived::Derived(Runtime, () -> T raise Failure, label? : String) -> Self[T]`. The bare-name `Derived(rt, fn)` form works because of MoonBit's named-constructor convention (see `~/.claude/moonbit-base.md` "Custom constructors for structs"). If it doesn't resolve, use `@incr.Derived::Derived(coordinator.runtime(), fn() { ... })` explicitly.
- **`compute fn must `raise Failure`** — the closure type is `() -> T raise Failure` (`loom/incr/cells/pkg.generated.mbti:38`). `abort(...)` returns `noreturn` and satisfies any return type without affecting the raise clause, so no `raise` annotation needed in the closure. If the type-checker complains, swap `abort(...)` for `fail(...)` which raises Failure directly.
- **`sum_d.id()` not found** — verified at `loom/incr/cells/pkg.generated.mbti:44` as `Derived::id(Self[T]) -> @types.CellId`. This exists.
- **`@incr` import error** — `ffi/lambda/moon.pkg.json` must list `dowdiness/incr` (or alias) under imports. The existing PR4 code in `ffi/lambda/lifecycle.mbt` uses `@incr.Runtime` and `@incr.Derived[T]`, so this should already be present.

- [ ] **Step 4: Verify full workspace tests still pass**

Run: `NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: baseline + 1 (1183/1183 if baseline was 1182).

---

### Task 2: Test 5.2 (reactivity on editor mutation)

**Files:**
- Modify: `ffi/lambda/workspace_memo_smoke_wbtest.mbt` (append new test)

- [ ] **Step 1: Append the reactivity test**

Add to the end of the file (after the §5.1 test's closing `}`):

```moonbit

///|
test "smoke 5.2: mutation in editor A invalidates workspace memo and recomputes" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_2_a")
  let handle_b = create_editor("smoke_5_2_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match coordinator.read_protected(
      h_a.editor_id, h_a.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.2 read h_a: \{r}")
    }
    let sb = match coordinator.read_protected(
      h_b.editor_id, h_b.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.2 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  // Prime with initial values.
  h_a.editor.set_text("ab")
  h_b.editor.set_text("cd")
  assert_eq(w.read().unwrap(), 2 + 2)

  // Mutate editor A's source; the workspace memo must recompute on next read.
  h_a.editor.set_text("abcdef")
  assert_eq(w.read().unwrap(), 6 + 2)

  // Teardown per spec §3.7.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  let _ = coordinator.destroy_editor(h_a.editor_id)
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  let _ = coordinator.destroy_editor(h_b.editor_id)
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}
```

- [ ] **Step 2: Run only this new test**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_smoke_wbtest.mbt 2>&1 | tail -10`

Expected: 2 tests pass. If the second assertion (`8` after mutation) fails with `4` (the stale value):
- The workspace memo's compute closure did register `parser_source` as a dependency on first read, but `set_text` is not invalidating it — investigate `SyncEditor::set_text` propagation. Confirm by adding `println(w.read().unwrap())` between the two `set_text` calls and the assertion. This is a real bug if it fires; surface it before continuing.

- [ ] **Step 3: Verify full workspace tests still pass**

Run: `NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: baseline + 2.

---

### Task 3: Test 5.3 (destroy gateway refusal under live dep)

**Files:**
- Modify: `ffi/lambda/workspace_memo_smoke_wbtest.mbt` (append new test)

- [ ] **Step 1: Append the destroy-refusal test**

Add to the end of the file:

```moonbit

///|
test "smoke 5.3: destroy_editor refused while workspace memo dep is live" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_3_a")
  let handle_b = create_editor("smoke_5_3_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match coordinator.read_protected(
      h_a.editor_id, h_a.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.3 read h_a: \{r}")
    }
    let sb = match coordinator.read_protected(
      h_b.editor_id, h_b.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.3 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  h_a.editor.set_text("hi")
  h_b.editor.set_text("world")
  let pre_sum = w.read().unwrap()

  // Destroy must refuse with the precise AbortReport shape spec §5.3 asserts.
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon, got Ok")
    Err(report) => {
      assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
      assert_eq(report.editor_id, h_a.editor_id)
      assert_eq(report.cell_id, Some(sum_d.id()))
    }
  }

  // Editor A must still be alive — re-read the memo and assert the sum is unchanged.
  assert_eq(w.read().unwrap(), pre_sum)

  // Teardown per spec §3.7.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  let _ = coordinator.destroy_editor(h_a.editor_id)
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  let _ = coordinator.destroy_editor(h_b.editor_id)
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}
```

- [ ] **Step 2: Run only this new test**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_smoke_wbtest.mbt 2>&1 | tail -10`

Expected: 3 tests pass. If `report.cell_id` assertion fails with a different `CellId` than `sum_d.id()`:
- This is the Codex round-1 finding #2 fragility actually firing. Check whether any prior coordinator dep registrations leaked into this test (run alone, see if it passes). If running alone fixes it, it means the §3.7 isolation contract is being violated by an earlier test in the file.

- [ ] **Step 3: Verify full workspace tests still pass**

Run: `NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: baseline + 3.

---

### Task 4: Test 5.4 (clean teardown with assertions on each step)

**Files:**
- Modify: `ffi/lambda/workspace_memo_smoke_wbtest.mbt` (append new test)

- [ ] **Step 1: Append the clean-teardown-assertions test**

Add to the end of the file:

```moonbit

///|
test "smoke 5.4: clean teardown sequence — each step returns Ok" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_4_a")
  let handle_b = create_editor("smoke_5_4_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match coordinator.read_protected(
      h_a.editor_id, h_a.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.4 read h_a: \{r}")
    }
    let sb = match coordinator.read_protected(
      h_b.editor_id, h_b.cells.parser_source,
    ) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.4 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  h_a.editor.set_text("x")
  h_b.editor.set_text("yz")
  let _ = w.read().unwrap() // prime

  // Teardown — every step's outcome asserted.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()

  // After unregister + dispose, destroy must succeed.
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(report) => fail("expected Ok destroying h_a after unregister, got \{report}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(report) => fail("expected Ok destroying h_b after unregister, got \{report}")
  }

  // Drain FFI bookkeeping so leaks don't pollute later tests.
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

- [ ] **Step 2: Run only this new test**

Run: `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda -f workspace_memo_smoke_wbtest.mbt 2>&1 | tail -10`

Expected: 4 tests pass.

- [ ] **Step 3: Verify full workspace tests still pass**

Run: `NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: baseline + 4.

---

### Task 5: Verification gate + commit

**Files:**
- Touched only: `ffi/lambda/workspace_memo_smoke_wbtest.mbt`

- [ ] **Step 1: Format the new file**

Run: `NEW_MOON_MOD=0 moon fmt`

Expected: no changes, or whitespace-only reformatting. If a structural reformat happens, re-run the per-file test (Task 4 Step 2) to confirm semantics intact.

- [ ] **Step 2: Regenerate `.mbti` interfaces and confirm zero public-API drift**

Run: `NEW_MOON_MOD=0 moon info && git diff --stat -- '*.mbti'`

Expected: empty output (no `.mbti` files modified). The wbtest adds tests only — no `pub` symbols — so `pkg.generated.mbti` must not change. If it does, revert and investigate (most likely a stray `pub` snuck into the test file or a helper file).

- [ ] **Step 3: Final workspace-wide check + test**

Run: `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test 2>&1 | tail -3`

Expected: `moon check` clean; `moon test` reports baseline + 4 passing.

- [ ] **Step 4: Stage the file and inspect the diff**

Run: `git add ffi/lambda/workspace_memo_smoke_wbtest.mbt && git diff --cached --stat`

Expected: exactly one new file, ~250 lines (4 tests × ~60 lines each including teardown duplication).

- [ ] **Step 5: Commit**

Run:

```bash
git commit -m "$(cat <<'EOF'
test(ffi/lambda): §P0b first real workspace memo smoke wbtest

Drives Coordinator::register_dep / unregister_dep / destroy_editor
gateway / read_protected end-to-end against the first **real-cell**
workspace memo — an @incr.Derived[Int] summing two Lambda editors'
parser_source lengths through the global `coordinator` singleton.

Four scenarios per spec §5: sanity sum, reactivity on editor mutation,
destroy gateway refusal under live dep, clean teardown with assertions
on each step.

Per spec §3.7, each test manually drives full teardown (unregister
every registered dep, dispose the watch, bypass-destroy each editor,
drain FFI bookkeeping). reset_coordinator_for_phase1_tests only clears
FFI handle maps; coordinator state leaks across tests, but freshly-
allocated monotonic EditorIds prevent cross-test correctness coupling.

Spec: docs/superpowers/specs/2026-05-28-p0b-first-workspace-memo-design.md
Plan: docs/superpowers/plans/2026-05-28-p0b-first-workspace-memo-implementation.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Confirm commit landed**

Run: `git log --oneline -1 && git status`

Expected: top commit is the test commit; working tree clean (or only the spec + plan untracked if those weren't committed earlier).

---

## Notes for the implementer

- **Do NOT route through the FFI `destroy_editor(handle: Int)` wrapper** (`ffi/lambda/lifecycle.mbt:90`). It returns `Unit` and `println`s on `Err`. Every test asserts on the `Coordinator::destroy_editor` `Result` directly and manually drains FFI state, mirroring `lifecycle_phase1_wbtest.mbt:110-121`.
- **Test names matter for `moon test -f`**. Keep them as `"smoke 5.X: ..."` so they sort and grep cleanly.
- **If any test hangs** during `w.read()`: the on_change callback may be in a loop. Check that the coordinator's stub `on_change` (in `Coordinator::new` at `workspace/coordinator/methods.mbt:7-15`) is still a no-op. If somebody wired a non-trivial on_change, that's an out-of-band substrate change and the test setup needs to adapt — surface to the user.
- **If `moon fmt` reshapes the multi-line `coordinator.runtime().derived(fn() { ... })` block**: that's expected; trust the formatter's output (the spec/plan code is illustrative, not byte-exact-mandated).
- **If `set_text` doesn't propagate invalidation** (Task 2 Step 2 fails with stale sum): that's a real bug in the substrate or a misunderstanding of `SyncEditor`'s mutation contract. Do NOT try to "fix" it with a manual `runtime.fire_on_change()` or similar workaround — surface to the user. The spec assumed reads from a Derived inside another Derived auto-track deps and re-fire on input change; if that assumption is wrong, the smoke milestone needs a deeper rethink.
- **`.mbti` drift in Step 2 of Task 5**: a wbtest file should not touch `.mbti` because it adds no `pub` symbols. If `moon info` modifies `pkg.generated.mbti`, you accidentally added a `pub` keyword somewhere — search for it and remove.
