# §P0b — Workspace Memo Lifecycle API (`register_workspace_memo`) Design

**Date:** 2026-05-28
**Belongs to slice:** §P0b Phase 1b — spec gap §6.2 of `docs/superpowers/specs/2026-05-28-p0b-first-workspace-memo-design.md` ("Coordinator-owned workspace-memo lifecycle API not delivered; follow-up spec/PR required").
**Pairs with:** the first-workspace-memo smoke wbtest (PR #368, `502e8e3`), which proved the substrate but had the *test* hand-roll the lifecycle.
**Status:** Brainstorm-approved by user 2026-05-28 (static-deps design chosen over dynamic; see §2). Pending Codex stage-2 design validation, then `superpowers:writing-plans` handoff.

## 0. Background

The smoke wbtest proved `register_dep` / `unregister_dep` / `destroy_editor`-gateway / `read_protected` hold end-to-end against real Lambda editor cells. But it did so by having each test manually:

1. build the `@incr.Derived[T]` memo,
2. `let w = memo.watch()` + prime it (the GC root),
3. call `coordinator.register_dep(memo.id(), editor_id, cell_id)` once per dependency,
4. on teardown call `coordinator.unregister_dep(...)` for each *exact same* triple, then `w.dispose()`.

That is ~30 lines of choreography per memo, and three sets that must stay in sync by hand: the cells the compute closure reads, the `register_dep` calls, and the `unregister_dep` calls. A desync silently breaks the destroy gateway's protection (a read with no matching dep → editor destroyable → later `read_protected` returns `Err` → abort).

This milestone delivers the coordinator-owned API that owns that lifecycle so a consumer makes two calls instead of thirty, and register/unregister symmetry becomes structurally impossible to break.

## 1. Scope

**In scope:**

- New coordinator API `Coordinator::register_workspace_memo` returning a `WorkspaceMemoHandle[T]`.
- New public type `WorkspaceMemoHandle[T]` with `read`, `id`, `dispose`.
- Registration-time validation of each declared dep (editor alive + cell in that editor's protected surface), with **all-or-nothing** registration semantics.
- A wbtest that ports the smoke test's scenarios through the new API, plus API-specific scenarios (bad-cell rejection + atomicity, dead-editor rejection, double-registration abort, empty-deps abort, destroy-gateway refusal, idempotent dispose).

**Out of scope:**

- **Mutable deps** (`add_dep` / `remove_dep` on the handle). Deferred as an *additive* extension if a growing-editor-set aggregator is later needed — see §7. Frozen deps are mutable deps you never mutate, so this is forward-compatible, not throwaway.
- **Auto-tracked / read-intercepted deps.** Explicitly rejected in brainstorm: the consumer declares its static dep set; the coordinator does not introspect the compute closure or intercept `read_protected`.
- **Problems-panel FFI surface + UI.** The motivating consumer (a workspace-wide diagnostics aggregator) justifies the API's shape but is not built here. Same "prove the substrate, defer the UI" philosophy as the smoke milestone.
- **`destroy_editor` mid-dispose-raise hardening** (first-workspace-memo spec §6.1). Unchanged and untouched — see §5.
- **Cross-language coordinators.** Lambda-only, per WS2 §4 JS-bundle isolation.
- **Coordinator-side `reset_for_tests`.** Still deferred (first-workspace-memo spec §10); the new wbtest uses the same per-test manual cleanup contract (§6.4).

## 2. Design decision: static (frozen) deps

Confirmed with the user in brainstorm 2026-05-28:

- **Consumer:** a problems-panel aggregator reading each editor's `parser_diagnostics` (+ Lambda's typecheck output).
- **Dep dynamism:** static — the dep set is known and declared at construction, not conditionally varied per recompute.

The problems panel's *lifecycle* dynamism (editors open/close at runtime) is handled at the **consumer** layer, not by this API: the panel composes one `WorkspaceMemoHandle` per editor (or rebuilds a fixed-set aggregator), disposing an editor's handle before that editor is destroyed. A single workspace-wide memo over a *changing* editor set would require either mutable deps or a reactive editor-set cell read inside the compute — both deferred (§7). Starting static is strictly simpler (no compute-lifecycle interception, no read-set diffing, no re-entrancy or memo-cycle-trap exposure) and forward-compatible.

## 3. The contract in one paragraph

`Coordinator::register_workspace_memo(memo, deps)` validates that every declared dep names a live editor and a cell in that editor's protected surface; if any fails, it registers nothing and returns `Err(AbortReport)`. On success it watches and primes `memo` (establishing the GC root), calls `register_dep(memo.id(), editor_id, cell_id)` for each dep, and returns a `WorkspaceMemoHandle[T]` owning the watch and the dep list. `handle.read()` delegates to the watch (`Result[T, CycleError]`). `handle.dispose()` calls `unregister_dep` for every edge the handle registered, then disposes the watch; it is idempotent. While the handle is undisposed, `destroy_editor` on any depended-upon editor returns `Err(DestroyWhileDependedUpon)`; after `handle.dispose()`, `destroy_editor` succeeds.

## 4. API surface

New file `workspace/coordinator/workspace_memo.mbt` (handle type + the two methods); `WorkspaceMemoHandle` struct defined there or in `types.mbt` alongside the other coordinator types.

```text
pub struct WorkspaceMemoHandle[T] {
  // private fields: coordinator ref, memo cell id, watch, frozen dep list
}

pub fn[T] Coordinator::register_workspace_memo(
  self : Coordinator,
  memo : @incr.Derived[T],
  deps : Array[(EditorId, @incr.CellId)],
) -> Result[WorkspaceMemoHandle[T], AbortReport]

pub fn[T] WorkspaceMemoHandle::read(self) -> Result[T, @incr.CycleError]
pub fn[T] WorkspaceMemoHandle::id(self) -> @incr.CellId
pub fn[T] WorkspaceMemoHandle::dispose(self) -> Unit
```

### 4.1 `register_workspace_memo` algorithm

Order matters for the all-or-nothing property:

0. **Defect guards (both `abort` — programming defects, not runtime conditions, mirroring `register_editor`'s stance at `methods.mbt:38-42`):**
   - **0a — reject empty deps.** If `deps.is_empty()`, `abort`. A workspace memo exists to depend on editor cells across the workspace and be protected by the destroy gateway; a zero-dep memo has no cross-editor dependency and no gateway role, so it is outside this API's problem domain — the caller should watch a plain `@incr.Derived` directly. This guard is also a *prerequisite* for guard 0b: it guarantees every registered memo owns ≥1 edge, so the `self.deps` map entry is a sound double-registration signal (Codex stage-2 round-2 finding — without it, an empty-deps memo registers no edge, leaves no map entry, and escapes 0b).
   - **0b — reject double-registration.** If `self.deps` already has an entry for `memo.id()`, `abort` — a memo may be registered at most once. Reason (Codex stage-2 round-1 finding #1): `register_dep` is set-like (`methods.mbt:69-72` dedups edges), so two handles over the same `memo.id()` with overlapping edges share one entry; the first `handle.dispose()` would `unregister_dep` that edge and silently strip the destroy-gateway protection the second live handle still relies on. Sound only because 0a guarantees a registered memo always has a `self.deps` entry.
1. **Normalize + validate, mutate nothing.** Deduplicate `deps` first (defensive: keeps the handle's stored list clean so dispose's `unregister_dep` runs once per distinct edge — `unregister_dep` is already idempotent at `methods.mbt:77-97`, so this is hygiene, and it pins the contract before a future `add_dep`/`remove_dep`). Then for each distinct `(editor_id, cell_id)`:
   - editor must exist in `self.editors` and be `alive` → else `Err(AbortReport { kind: EditorDestroyed, editor_id, agent_id, cell_id })`;
   - `cell_id` must be in that editor's `protected_reads` → else `Err(AbortReport { kind: CellNotInProtectedSurface, ... })`.
   Both reuse existing `AbortKind` variants — **no new variant needed.** The register path receives only a raw `CellId`, so `cell_label` stays unset on these error reports — see §4.4 and the P1 implementation note. (Unlike `read_protected`, which is handed a `ProtectedCell` carrying its own label, registration does not look labels up from the registry.)
2. **Establish the GC root.** `let w = memo.watch()` then prime via `w.read()`. Mirrors `ProtectedCell::from_derived` (`workspace/coordinator/types.mbt:99-100`); priming populates `gc_dependencies` before any `Runtime::gc()` can sweep upstream cells. **P2 implementation finding (resolves the original Codex finding #3 dispose-on-raise aspiration):** although `Derived`'s compute closure type is `() -> T raise Failure`, `Watch::read` has signature `Self[T] -> Result[T, CycleError]` with **no `raise` effect** (`loom/incr/cells/pkg.generated.mbti:347`) — the runtime absorbs a compute `Failure` rather than re-raising it on read. So `w.read()` cannot raise to this call site: a cycle surfaces as `Err(CycleError)` (a value, not a throw), and a `Failure` never propagates here. There is therefore nothing to dispose-on-raise — a `try`/`catch` wrapper would not even type-check (MoonBit rejects `try` over a non-raising expression). The handle is always returned once `w.read()` returns, so no GC root can leak. Discard the primed value with `let _ = w.read()`.
3. **Register edges.** For each distinct dep, `register_dep(memo.id(), editor_id, cell_id)`.
4. Return `Ok(WorkspaceMemoHandle { coordinator: self, memo_id: memo.id(), watch: w, deps })`.

Validating *all* deps before watching or registering means a rejected registration leaves zero coordinator-state delta — the caller can retry or fall back cleanly. (Contrast: validating-while-registering would leave half the edges registered on the second dep failing.)

### 4.4 Caller precondition: deps must cover every cell the compute reads

The coordinator does **not** introspect the compute closure, and `read_protected` (`methods.mbt:150-218`) does **not** require a registered dep edge to serve a read (Codex stage-2 finding #2). Therefore the caller MUST declare in `deps` every `(editor_id, cell)` its compute reads via `read_protected`. An *undeclared* read silently loses the destroy-gateway protection for that editor: `destroy_editor` would succeed despite the live memo, and the memo's next read returns `Err` → `abort`. This is the inherent tradeoff of static-declared deps versus read-interception (which the brainstorm rejected): correctness of the dep set is the caller's responsibility, not something the coordinator can verify. The wbtest's B-scenarios exercise the *declared* paths; the undeclared-read gap is documented here as a precondition, not closed (closing it is exactly the read-tracking design deferred in §7).

### 4.2 `WorkspaceMemoHandle::dispose` algorithm

1. If already disposed (watch disposed), return — idempotent.
2. For each stored `(editor_id, cell_id)` dep: `self.coordinator.unregister_dep(self.memo_id, editor_id, cell_id)`. `unregister_dep` is already idempotent (no-op if absent), so a dep whose editor was force-destroyed out-of-band is harmless.
3. `self.watch.dispose()`.

Idempotency check uses `watch.is_disposed()` as the disposed flag — no separate bool field needed.

### 4.3 Why a typed handle, not a coordinator-internal registry keyed by memo id

The handle *is* the single object the consumer holds, and it remembers exactly which edges it registered. The consumer cannot desync register/unregister because it never names the edges twice — it names them once (at registration) and the handle replays them on dispose. A coordinator-internal `dispose_workspace_memo(memo_id)` would work too but reintroduces an id the caller must hold and pass back correctly; the handle is the more foolproof ownership shape and mirrors how `@incr.Watch` already bundles "the thing + its disposal."

## 5. `destroy_editor` interaction (does NOT reopen §6.1)

`handle.dispose()` disposes only the *memo's* watch. It never iterates the editors' protected-cell `dispose` closures — that is `destroy_editor`'s job. So the first-workspace-memo spec §6.1 mid-dispose-raise concern (a poison `ProtectedCell.dispose` raising inside `destroy_editor`'s loop) is neither triggered nor mitigated here; it remains a separate follow-up. The only interaction is the intended one: the gateway refuses `destroy_editor` until `handle.dispose()` has run `unregister_dep`. That ordering is the contract working as designed, and the wbtest asserts it (§6.3 scenario C).

## 6. Test scenarios (wbtest)

File: `ffi/lambda/workspace_memo_handle_wbtest.mbt` (new, sibling to the existing `workspace_memo_smoke_wbtest.mbt`). Lambda FFI package, same global `coordinator` singleton + `assemble_lambda_handle` factory.

### 6.1 Ported smoke scenarios (prove the handle replaces the manual dance)

Each mirrors a smoke scenario but uses the API: `register_workspace_memo` replaces `watch()` + N×`register_dep`; `handle.read()` replaces `w.read()`; `handle.dispose()` replaces N×`unregister_dep` + `w.dispose()`.

- **A1 Sanity sum.** Two editors, sum of `parser_source` lengths. `handle.read().unwrap() == 3 + 5`.
- **A2 Reactivity.** Mutate editor A's source; `handle.read()` reflects the new sum.
- **A3 Clean teardown.** After `handle.dispose()`, `destroy_editor` on both editors returns `Ok`.

### 6.2 API-specific scenarios (the new claims)

- **B1 Bad-cell rejection + atomicity.** Call `register_workspace_memo` with a dep naming a real editor but a `CellId` *not* in its protected surface (e.g. a foreign cell id). Assert `Err` with `kind == CellNotInProtectedSurface`. **Then** assert nothing was registered: `destroy_editor` on that editor immediately returns `Ok` (no leaked dep edge). This proves all-or-nothing registration.
- **B2 Dead-editor rejection.** Destroy an editor, then call `register_workspace_memo` naming it. Assert `Err` with `kind == EditorDestroyed`.
- **B3 Double-registration aborts (panic test).** Register a memo, then call `register_workspace_memo` again with the same `memo`. Assert it aborts (test name prefixed `panic ` per MoonBit convention). Locks the §4.1 guard 0b.
- **B4 Empty deps aborts (panic test).** Call `register_workspace_memo` with `deps == []`. Assert it aborts. Locks the §4.1 guard 0a (and thereby the soundness of 0b).

### 6.3 Gateway scenario

- **C Destroy refusal under live handle.** With a live handle, `destroy_editor(editor_a)` returns `Err(DestroyWhileDependedUpon)` with `cell_id == Some(handle.id())`. Editor stays alive: mutate its source after the refused destroy and assert the memo recomputes (operational aliveness, matching smoke 5.3's stronger check).

### 6.4 Idempotency scenario

- **D Double dispose.** Call `handle.dispose()` twice; the second is a no-op (no abort, `destroy_editor` still `Ok`).

### 6.5 Teardown contract

Per first-workspace-memo spec §3.7, coordinator state leaks across tests by design. Each test still drains FFI bookkeeping (`lambda_handles` / `view_states` / `pretty_view_states` / `last_created_handle`) and disposes the companion exactly as the smoke wbtest does. The difference: dep unregistration + watch dispose now go through `handle.dispose()` instead of manual calls. Monotonic `next_id` keeps freshly-allocated `EditorId`s disjoint from leaked edges.

## 7. What this defers (and why it stays cheap to add later)

- **Mutable deps (`add_dep` / `remove_dep`).** Additive: the frozen handle already stores its dep list; mutation methods would push/filter that list and call `register_dep` / `unregister_dep` for the delta. No signature change to `register_workspace_memo`. Only needed if a single workspace-wide memo must track a runtime-changing editor set — and only *then* does the compute closure also need to iterate a dynamic editor set (the per-recompute dynamism the user ruled out for now).
- **Problems-panel consumer.** Lives in `ffi/lambda/` + UI; consumes this API. Separate PR.
- **`destroy_editor` mid-dispose-raise** and **coordinator `reset_for_tests`** — unchanged deferrals from the first-workspace-memo spec.

## 8. Verification gate

- `git submodule update --init --recursive` in the worktree first (worktrees don't auto-checkout submodules; loom/incr must be present to build).
- `NEW_MOON_MOD=0 moon check` workspace-wide: clean.
- `NEW_MOON_MOD=0 moon test` workspace-wide: baseline + 9 (3 ported A + 4 B + 1 C + 1 D). Confirm exact baseline at implementation time.
- `NEW_MOON_MOD=0 moon info && git diff --stat -- '*.mbti'`: expect **two** `.mbti` changes — `workspace/coordinator/pkg.generated.mbti` (new public `register_workspace_memo` + `WorkspaceMemoHandle`) and nothing else. The Lambda wbtest adds no `pub` symbols. Review the coordinator `.mbti` diff for unintended trait-bound widening.
- Codex stage-4 scoped review (all-or-nothing registration, dispose idempotency, register/unregister symmetry, destroy-gateway report fidelity) + broad open-ended pass. Pair confirmed load-bearing for this workstream per `feedback-codex-broad-vs-scoped-review`.

## 9. Decision summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Dep dynamism | Static / frozen | User-confirmed; simplest; forward-compatible (mutable is additive). |
| Dep declaration | Caller passes `(EditorId, CellId)`; coordinator looks up label | Simple caller, labeled errors. |
| Registration failure | All-or-nothing, `Result[_, AbortReport]` | No partial-state leak on bad dep; reuses existing `AbortKind`. |
| Ownership | Typed `WorkspaceMemoHandle[T]` owns watch + dep list | Register/unregister symmetry structurally guaranteed. |
| Dispose | `handle.dispose()`, idempotent via `watch.is_disposed()` | Mirrors `@incr.Watch` bundling; no extra flag. |
| New `AbortKind`? | No | `EditorDestroyed` + `CellNotInProtectedSurface` already fit. |
| Empty deps (`deps == []`) | `abort` (defect guard 0a, §4.1) | No cross-editor dependency / no gateway role → outside the API's domain; also makes the double-reg signal sound (Codex round-2). |
| Double-registration of a memo | `abort` (defect guard 0b, §4.1) | Set-like `register_dep` means a second handle's protection would be stripped by the first's dispose (Codex round-1 finding #1). |
| Undeclared-read gateway gap | Documented precondition, not closed (§4.4) | Inherent to static-declared deps; closing it is the deferred read-tracking design (Codex finding #2). |
| destroy mid-dispose-raise | Untouched | Disposes only the memo watch; §6.1 stays a separate follow-up. |
| Consumer (panel) | Deferred | Prove substrate API; defer UI, as in smoke milestone. |
| Test location | `ffi/lambda/workspace_memo_handle_wbtest.mbt` (new) | Sibling to smoke wbtest; real cells + global coordinator. |
