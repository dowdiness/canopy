# §P0b Phase 1 — Workspace Coordinator Skeleton Design

**Date:** 2026-05-24
**Belongs to slice:** §P0b of `docs/research/2026-05-22-spec-aware-workspace.md`.
**Pairs with:** `docs/research/2026-05-23-shared-runtime-workspace-contract.md` (v2.1, APPROVED) and `docs/research/2026-05-24-shared-runtime-call-flow-grounding.md` (call-flow map).
**Status:** Design approved; awaiting plan (§11). Revision pass complete after three Codex consults.
**Codex review:** Two SHIP IT (skeleton design + VersionedFlatProj migration) + one REVISE→addressed (spec-level review, summarized in §10).

## 0. Background

This is the second brainstorm at the §P0b API surface. The first (2026-05-24, same day) ran five Codex review rounds with seventeen substantive findings without converging. Root cause was jumping to coordinator-API design without grounding in the actual call flow.

That gap was closed by the grounding doc shipped earlier in the day on branch `docs/p0b-call-flow-grounding`. This design uses the grounding doc's §5 atomic-boundary candidates and §6 inviolable constraints as substrate; the brainstorm session that produced this spec narrowed in three Codex passes (one skeleton review, one migration-safety review, one implicit pass in the grounding doc itself).

## 1. Scope

In scope:

- The Phase 1 coordinator API surface: types, methods, lifecycle invariants, atomic registration.
- The atomic-boundary location for editor construction (candidate A from grounding §5.1 — the FFI-internal helper).
- A full Lambda protected-surface enumeration (10 cells) with factory call sites.
- The runtime-threading mechanism through `SyncEditor::new_generic` (option (c) — framework-layer change).
- A unified Memo → Derived migration for the entire Lambda editor stack (eliminates the BackdateEq holdout) so the Phase 1 surface uses **only** target-named `@incr` APIs.

Out of scope (deferred to later phases — see §9):

- Markdown and JSON FFI helpers (their existing FFI ctors stay untouched in Phase 1).
- Production-call-site migration of read accessors to go through `Coordinator::read_protected`.
- The first real workspace memo using `Coordinator::register_dep`.
- Diagnostic richness beyond `AbortReport` (live introspection, trace mode, leak detector, `audit_leaks()`).
- Multi-language editors-in-one-tab (cross-language shared runtime — Phase 2 contract concern).

## 2. The contract in one paragraph

A workspace `Coordinator` owns a shared `@incr.Runtime` and claims the single-occupancy `Runtime::set_on_change` slot at construction. Each Lambda editor is assembled by an FFI-internal helper (`assemble_lambda_handle`) that performs five sequential steps as one atomic transaction: construct editor on the shared runtime, build typecheck bundle, build the typed `LambdaProtectedCells` bundle (each factory creates a `Watch` and primes it once), register the erased protected-read list with the coordinator (which assigns an `EditorId`), and store FFI-side state. The coordinator exposes a typed checked-read API — `Coordinator::read_protected[T](editor_id, cell) -> Result[T, AbortReport]` — that validates editor liveness, watch liveness, and cell-membership-in-protected-set before invoking the underlying `Watch::read`. Destroy goes through `Coordinator::destroy_editor` which returns `Result[Unit, AbortReport]` and refuses while any workspace memo's dep edges point at the editor.

**Decision A coverage scope:** Phase 1 ships the *mechanism* for Decision A end-to-end (no-silent-stale-data via typed reads). Full *enforcement* requires Phase 1b to migrate production FFI accessors off `Derived::read_or_abort()` to `Coordinator::read_protected`; until then, any caller that captures an editor cell directly (`editor.parser_ast().read_or_abort()`) bypasses the coordinator and can produce silent stale data on a destroyed editor. §9 enumerates this boundary; the spec deliberately stages production migration so the coordinator API + tests + diagnostics can settle before the call-site sweep.

## 2.5 Decisions encoded by this spec

Walking the grounding doc's §6 (inviolable constraints) and §7 (open questions) and recording where each is addressed.

### Constraint coverage (grounding §6.1–§6.10)

| § | Constraint | Where addressed |
|---|---|---|
| 6.1 | `Runtime::set_on_change` single-occupancy | `Coordinator::new` claims the slot with a stub multiplexer (§7 `Coordinator::new` body, lines 281-285) |
| 6.2 | `Runtime::gc()` semantics + two-pass settle | Phase 1 doesn't run `gc()`; §3 `Runtime::gc_root_count` lets us mode-1-check at registration |
| 6.3 | Single-threaded MoonBit runtime | Load-bearing assumption named explicitly here; relied on by destroy/read ordering (§7) and dep-registry mutation (§7 `register_dep`). Re-entrancy hardening is Phase 2 (§G in Codex review trail) |
| 6.4 | Parser owns Runtime today | §5.5 framework-layer threading via `parent_runtime?` on `SyncEditor::new_generic` |
| 6.5 | Heterogeneous protected-cell set (Markdown 7 / Lambda 9 / Lambda+FFI 10) | `ProtectedRead` erased registration (§6 ProtectedRead lines 207-217) + per-language typed bundle (§8.1 `LambdaProtectedCells`) |
| 6.6 | Persistent Observer/Watch requires priming before first `gc()` | Factories prime via `let _ = watch.read()` at construction (§6 factory bodies) |
| 6.7 | Labels set per cell at construction (12+ sites) | **Decision: report-time composition** — coordinator stores raw labels in `ProtectedRead.label`; `AbortReport` composes the prefix `{agent_id}.{label}` when materializing the report. Construction-time threading is rejected for Phase 1 (avoids the 12-site plumbing surface) |
| 6.8 | `Runtime::gc` is `pub` and reachable | Out-of-scope for Phase 1 (convention-only; §11 risk #2 in v2.1 contract memory). Lint backstop is a Phase 2 concern |
| 6.9 | Typecheck pipeline interior is loom-example code | Coordinator's protected-cell set only refers to `TypecheckBundle.output` (§8.1 row 10); interior cells reached by BFS |
| 6.10 | `_legacy` wrapper strategy pins out candidate B | Candidate A picked; existing `new_lambda_editor` 2-tuple shape preserved; `parent_runtime?` is an additive pass-through param |

### Open question resolutions (grounding §7)

| § | Question | Decision |
|---|---|---|
| 7.1 | Is the dep-edge sufficient as implicit registration? | **Yes for Phase 1.** Protected surface = the 10 cells enumerated in §8.1. Cells reached by dep-BFS but not enumerated (`eval_memo`, `snapshot_signal`, intermediate typecheck per-def cells) survive via dep edges from the enumerated anchors. Coordinator does not walk the dep graph; it enumerates the explicit list and trusts loom's BFS to keep the cone reachable |
| 7.2 | Label-prefix: 12-site plumbing or report-time composition? | **Report-time composition** (see §6.7 row above). Raw labels in code; coordinator composes editor identity into `AbortReport` |
| 7.3 | Where would `LambdaEditorBundle` live (candidate D)? | N/A — candidate A picked |
| 7.4 | Per-language factory parameter or per-language coordinator ctors (candidate E)? | N/A — candidate A picked. Each language gets its own FFI helper (§9 names Markdown/JSON helpers as Phase 1b non-goals) |
| 7.5 | Symmetric or non-symmetric `lifetime_scope` across Markdown/JSON/Lambda? | **Non-symmetric in Phase 1.** Only Lambda gets coordinator-aware ctor and `EditorId` registration. Markdown and JSON keep their current FFI shape (`destroy_markdown_editor`/`destroy_json_editor` untouched, no coordinator awareness). Phase 1b adds symmetric helpers if the multi-language story crystallizes; Phase 2 contract concern otherwise |

## 3. Loom prerequisite — one PR

**Loom A:** Add `Runtime::gc_root_count(self, id : @types.CellId) -> Int` to `loom/incr/cells/introspection.mbt` (~4 impl lines, already drafted in `.worktrees/proto-shared-runtime-verify/`).

Reads `self.core.gc_root_counts.get(id)`. Returns `0` for unknown / disposed cells (matches the canonical "soft-fail returns identity-of-empty" idiom used by `Runtime::dependents`). Touch surface: one source file + auto-regenerated `pkg.generated.mbti`. 585 incr tests pass unchanged per the proto verification.

Used by Phase 1's mode-1 check (registration-time fail-fast if a protected cell isn't observer-rooted). Phase 1 can ship with this check feature-flagged off — the fallback path is first-read-after-first-gc through `Watch::read` returning `Err(CycleError)` / disposed-Watch abort — but having the check available immediately is preferable.

> **Note:** the earlier proposal to also add `Memo::watch()` upstream is no longer required — see §4 for why.

## 4. Loom example migration — Memo → Derived sweep (Loom B)

After §5's canopy migration, the Lambda editor stack uses zero `Memo[T]` cells. The corresponding loom-side migration removes the remaining `Memo` usages from `loom/examples/lambda/`.

**`loom/examples/lambda/src/typecheck/typecheck.mbt`:**

| Site | Change |
|---|---|
| Lines 35, 37, 38 — `mut resolve_memos : Array[@incr.Memo[TypedTerm]]` (+ env_memos + type_memos) | Change `Memo` → `Derived` |
| Lines 40, 41 — `body_resolve_memo`, `body_memo` | Same |
| Lines 79, 94, 133 — `source_term : @incr.Memo[TypedTerm]` parameters | Same |
| Lines 271, 286, 287 — array literal type annotations | Same |
| Lines 276, 293, 298, 317, 332, 342, 354 — `chain_scope.memo(...)` | `chain_scope.derived(...)` |
| Read sites inside compute closures | `m.get()` (Memo) → `d.get_or_abort()` (Derived) — same strict-read semantics per Codex Q D citation `memo.mbt:171` / `facade.mbt:155` |

**`loom/examples/lambda/src/callers/callers.mbt`:**

| Site | Change |
|---|---|
| Lines 477, 481, 497 — `scope.memo(...)` for `facts`, `callers_index`, `visibility` | `scope.derived(...)` |
| Field types if any | Memo → Derived |

Delegatable to Sonnet under tight spec — mechanical sed-shaped rewrites. Estimated ~35 line touches.

## 5. Canopy migration — Memo → Derived sweep (Canopy 1)

Eliminates the final Memo holdouts on the canopy side. Depends on Loom A + B landing on the loom submodule first.

### 5.1 VersionedFlatProj custom Eq

`lang/lambda/flat/versioned_flat_proj.mbt`:

- Add `pub impl Eq for VersionedFlatProj with op_equal(self, other) { self.changed_at == other.changed_at }`.
- Drop the `pub impl @incr.HasChangedAt` (line 23) and `pub impl @incr.BackdateEq` (line 28) impls — Codex Q E confirmed no external consumers call these.
- Inline comment update: replace the BackdateEq rationale at `lang/lambda/companion/lambda_editor.mbt:9-12` with a note explaining the custom `Eq` and the invariant it depends on (`changed_at` advances iff `has_changes` at `projection_memo.mbt:103-112`).

Codex Q A verified the invariant: `to_flat_proj_incremental` reuses prev FlatProj entries when CST nodes are physically equal (`lang/lambda/proj/flat_proj.mbt:79, 102`); the synthetic Unit body case is forced into the changed path via `-1` at `projection_memo.mbt:78`. So `changed_at` non-advancement implies semantic equivalence of `proj` content for downstream readers.

Codex Q C verified that `Derived[T]` with `T : Eq` invokes the type's custom `op_equal` for backdating (`memo.mbt:485` uses the captured `==` from `Memo::new`, which `Derived::Derived` wraps at `facade.mbt:145`). The custom `Eq` impl is the path that matters.

### 5.2 proj_memo construction

`lang/lambda/flat/projection_memo.mbt`:

| Line | Change |
|---|---|
| 12 | `@incr.Memo[VersionedFlatProj]` → `@incr.Derived[VersionedFlatProj]` in the tuple return type |
| 34 | `@incr.Memo::new_memo(rt, …, label="proj_flat")` → `@incr.Derived::Derived(rt, …, label="proj_flat")` |
| 129 | `proj_memo.get().proj` → `proj_memo.get_or_abort().proj` |

`lang/lambda/companion/lambda_editor.mbt`:

| Line | Change |
|---|---|
| 13 | `priv proj_memo : @incr.Memo[..VersionedFlatProj]` → `@incr.Derived[..VersionedFlatProj]` |
| 103 | `Ref[@incr.Memo[..VersionedFlatProj]?]` → `Ref[@incr.Derived[..VersionedFlatProj]?]` |
| 9-12 | Update inline comment per §5.1 |

### 5.3 typed_term_memo construction (FFI)

`ffi/lambda/lifecycle.mbt:32`:

- `let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(...)` → `let typed_term_memo : @cells.Derived[@typecheck.TypedTerm] = scope.derived(...)`.

This depends on Loom B's `build_typecheck_pipeline` signature change (its `source_term` parameter type becomes `Derived[TypedTerm]`).

### 5.4 SyncEditor / LambdaCompanion accessor expansion

Mechanical pub-getter additions for the 8 cells that are currently `priv`. Delegatable to Haiku.

```moonbit
// editor/sync_editor.mbt — new pub methods on SyncEditor[T]
pub fn[T] SyncEditor::parser_ast(self) -> @incr.Derived[T]
pub fn[T] SyncEditor::parser_source(self) -> @incr.Derived[String]
pub fn[T] SyncEditor::parser_diagnostics(self) -> @incr.Derived[DiagnosticSet]
pub fn[T] SyncEditor::cached_proj_node(self) -> @incr.Derived[@core.ProjNode[T]?]
pub fn[T] SyncEditor::registry_memo(self) -> @incr.Derived[Map[NodeId, ProjNode[T]]]
pub fn[T] SyncEditor::source_map_memo(self) -> @incr.Derived[@core.SourceMap]

// lang/lambda/companion/lambda_editor.mbt — new pub methods on LambdaCompanion
pub fn LambdaCompanion::proj_memo(self) -> @incr.Derived[VersionedFlatProj]
pub fn LambdaCompanion::escalation_memo(self) -> @incr.Derived[Array[EvalResult]]
```

Each is `priv field → pub fn`; no logic changes. Eight new methods + corresponding `.mbti` updates.

### 5.5 Runtime threading through new_generic

`editor/sync_editor.mbt:41` — `SyncEditor::new_generic` gains `parent_runtime?: @incr.Runtime`:

```moonbit
pub fn[T] SyncEditor::new_generic(
  agent_id    : String,
  make_parser : (String, @incr.Runtime?) -> @loom.Parser[T],   // signature widened
  build_memos : (@loom.Parser[T]) -> (..., ..., ...),
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,                              // NEW
  capabilities~ : ...,
) -> SyncEditor[T] {
  let parser = make_parser("", parent_runtime?~)               // forwarded
  let (cached, registry, source_map) = build_memos(parser)
  // ... struct literal, unchanged ...
}
```

`lang/lambda/companion/lambda_editor.mbt:96-139` — `new_lambda_editor` gains thin pass-through:

```moonbit
pub fn new_lambda_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@ast.Term], LambdaCompanion) {
  // ... three Ref allocations unchanged ...
  let make_parser = fn(s : String, rt? : @incr.Runtime) -> @loom.Parser[@ast.Term] {
    @loom.new_parser(s, @parser.lambda_grammar, runtime?=rt)
  }
  let editor = @editor.SyncEditor::new_generic(
    agent_id, make_parser, build_memos,
    capture_timeout_ms?~,
    parent_runtime?~,
    capabilities=...,
  )
  // ... companion struct construction unchanged ...
}
```

Symmetric pass-through in `new_markdown_editor` and `new_json_editor`. Optional parameter defaults to `None` (= make a fresh private runtime, current behavior). 222+ existing call sites that destructure the return tuple without touching params don't change.

## 6. Coordinator types

```moonbit
// In a new package: workspace/coordinator/

pub(all) struct EditorId(Int) derive(Eq, Hash, Show)

pub(all) enum AbortKind {
  EditorDestroyed
  DestroyWhileDependedUpon
  CellNotInProtectedSurface
  CycleDetected
  ProtectedCellDisposed
} derive(Eq, Show)

pub(all) struct AbortReport {
  kind       : AbortKind
  editor_id  : EditorId
  agent_id   : String
  cell_id    : @incr.CellId?
  cell_label : String?
  domain_tag : String?
} derive(Show)

fn AbortReport::AbortReport(
  kind~ : AbortKind, editor_id~ : EditorId, agent_id~ : String,
  cell_id? : @incr.CellId, cell_label? : String, domain_tag? : String,
) -> AbortReport {
  { kind, editor_id, agent_id, cell_id, cell_label, domain_tag }
}

pub struct ProtectedRead {
  cell_id     : @incr.CellId
  label       : String
  is_disposed : () -> Bool                                  // for ProtectedCellDisposed defense-in-depth
  dispose     : () -> Unit
}

fn ProtectedRead::ProtectedRead(
  cell_id~ : @incr.CellId, label~ : String,
  is_disposed~ : () -> Bool, dispose~ : () -> Unit,
) -> ProtectedRead {
  { cell_id, label, is_disposed, dispose }
}

pub struct ProtectedCell[T] {
  cell_id     : @incr.CellId
  label       : String
  read        : () -> Result[T, @incr.CycleError]
  is_disposed : () -> Bool
  dispose     : () -> Unit
}

fn[T] ProtectedCell::ProtectedCell(
  cell_id~ : @incr.CellId, label~ : String,
  read~ : () -> Result[T, @incr.CycleError],
  is_disposed~ : () -> Bool, dispose~ : () -> Unit,
) -> ProtectedCell[T] {
  { cell_id, label, read, is_disposed, dispose }
}

pub fn[T] ProtectedCell::from_derived(label : String, d : @incr.Derived[T]) -> ProtectedCell[T] {
  let watch = d.watch()
  let _ = watch.read()                                      // §6.6 priming
  ProtectedCell(
    cell_id=d.id(),
    label~,
    read=fn() { watch.read() },
    is_disposed=fn() { watch.is_disposed() },
    dispose=fn() { watch.dispose() },
  )
}

// SPEC GAP — DEFERRED PAST PR3 (2026-05-25):
//   `ReachableDerived::id()` is not exposed in incr v0.6.x's public surface
//   (only `Derived::id`). The factory below cannot compile against current
//   incr. The §P0b Phase 1 Lambda protected surface uses only Derived (10
//   cells, all `from_derived`), so the factory was dropped from PR3 (commit
//   `11479b1`). When a Phase 1b ReachableDerived cell needs protection, add
//   `ReachableDerived::id()` upstream first, then re-introduce this factory.
// pub fn[T : Eq] ProtectedCell::from_reachable_derived(
//   label : String, r : @incr.ReachableDerived[T],
// ) -> ProtectedCell[T] {
//   let watch = r.watch()
//   let _ = watch.read()
//   ProtectedCell(
//     cell_id=r.id(),
//     label~,
//     read=fn() { watch.read() },
//     is_disposed=fn() { watch.is_disposed() },
//     dispose=fn() { watch.dispose() },
//   )
// }

pub fn[T] ProtectedCell::erase(self : ProtectedCell[T]) -> ProtectedRead {
  let c = self
  ProtectedRead(
    cell_id=c.cell_id, label=c.label,
    is_disposed=c.is_disposed, dispose=c.dispose,
  )
}

priv struct EditorRegistration {
  agent_id  : String
  protected : Array[ProtectedRead]
  alive     : Ref[Bool]
}

pub struct Coordinator {
  runtime  : @incr.Runtime
  editors  : Map[Int, EditorRegistration]
  deps     : Map[@incr.CellId, Array[(EditorId, @incr.CellId)]]
  next_id  : Ref[Int]
}

fn Coordinator::Coordinator(runtime~ : @incr.Runtime) -> Coordinator {
  { runtime, editors: Map::new(), deps: Map::new(), next_id: Ref::new(0) }
}

pub fn Coordinator::new() -> Coordinator {
  let runtime = @incr.Runtime::new(on_change=fn() {
    // Phase 1 stub — claims the §6.1 single-occupancy slot so no editor
    // can install its own. Phase 2 multiplexes registered listeners.
  })
  Coordinator(runtime~)
}

pub fn Coordinator::runtime(self : Coordinator) -> @incr.Runtime {
  self.runtime
}
```

Rationale notes (do not repeat in code comments):

- `EditorId` is `pub(all)`: FFI needs `.0` access to thread the int through the JS bridge, and tests can construct freely for assertions.
- `AbortKind` is closed (not `extenum`) — closing matches v2.1 contract Decision B; per-language extension goes through the `domain_tag: String?` field.
- `ProtectedRead` / `ProtectedCell` use named-field structs with custom `Type::Type` constructors per `moonbit-base.md` convention. `Coordinator` likewise.
- `EditorRegistration` is `priv`: never appears in `.mbti` consumer-visible fields.
- The factories construct a `Watch[T]` at call time. `Watch` is its own GC root via the underlying `add_read_root` call (`loom/incr/cells/observer.mbt:18-23`). Disposing the watch releases the root.

## 7. Coordinator method bodies (7 methods)

```moonbit
pub fn Coordinator::register_editor(
  self      : Coordinator,
  agent_id  : String,
  protected : Array[ProtectedRead],
) -> EditorId {
  let id = self.next_id.val
  self.next_id.val = id + 1
  // No prime loop here — factories prime at construction time.
  // No rooting loop here — each Watch is its own root from .watch().
  self.editors.set(id, EditorRegistration {
    agent_id, protected, alive: Ref::new(true),
  })
  EditorId(id)
}

pub fn Coordinator::register_dep(
  self           : Coordinator,
  workspace_memo : @incr.CellId,
  editor_id      : EditorId,
  editor_cell    : @incr.CellId,
) -> Unit {
  let entry = match self.deps.get(workspace_memo) {
    Some(arr) => arr
    None      => {
      let arr = Array::new()
      self.deps.set(workspace_memo, arr)
      arr
    }
  }
  let edge = (editor_id, editor_cell)
  if !entry.contains(edge) { entry.push(edge) }
}

pub fn Coordinator::unregister_dep(
  self           : Coordinator,
  workspace_memo : @incr.CellId,
  editor_id      : EditorId,
  editor_cell    : @incr.CellId,
) -> Unit {
  // Idempotent: removes the edge if present; no-op if absent.
  // Phase 1 callers: tests for the destroy gateway. Phase 1b+ callers:
  // workspace memos that need to release a dep on their own dispose.
  guard self.deps.get(workspace_memo) is Some(entry) else { return }
  let edge = (editor_id, editor_cell)
  entry.remove(edge)                                        // Array::remove by value, idempotent
  if entry.is_empty() {
    self.deps.remove(workspace_memo)
  }
}

pub fn Coordinator::destroy_editor(
  self      : Coordinator,
  editor_id : EditorId,
) -> Result[Unit, AbortReport] {
  guard self.editors.get(editor_id.0) is Some(reg) else {
    return Err(AbortReport(
      kind=EditorDestroyed, editor_id~, agent_id="<unknown>",
    ))
  }
  guard reg.alive.val else {
    return Err(AbortReport(
      kind=EditorDestroyed, editor_id~, agent_id=reg.agent_id,
    ))
  }
  // Decision A — refuse destroy while workspace deps reference editor.
  let referring : Array[@incr.CellId] = []
  for ws_memo, edges in self.deps {
    for edge in edges {
      if edge.0 == editor_id { referring.push(ws_memo) }
    }
  }
  if referring.length() > 0 {
    return Err(AbortReport(
      kind=DestroyWhileDependedUpon,
      editor_id~, agent_id=reg.agent_id, cell_id=referring[0],
    ))
  }
  // Flip alive=false BEFORE disposing watches — under single-threaded MoonBit
  // (§6.3) this isn't a race, but it preserves the invariant "if a read sees
  // alive=true then watches are also usable." Hardens against re-entrant reads
  // during disposal (Codex spec-review G) and against a Phase 2 multi-threaded
  // relaxation surprising the destroy path.
  reg.alive.val = false
  // Now release the GC roots — next gc() can sweep upstream cells.
  for p in reg.protected { (p.dispose)() }
  // Keep `reg` in the map (alive=false) so a stray read_protected after
  // destroy can return AbortReport with full agent_id context rather than
  // the unknown-handle path above.
  Ok(())
}

pub fn[T] Coordinator::read_protected(
  self      : Coordinator,
  editor_id : EditorId,
  cell      : ProtectedCell[T],
) -> Result[T, AbortReport] {
  guard self.editors.get(editor_id.0) is Some(reg) else {
    return Err(AbortReport(
      kind=EditorDestroyed, editor_id~, agent_id="<unknown>",
      cell_id=cell.cell_id, cell_label=cell.label,
    ))
  }
  guard reg.alive.val else {
    return Err(AbortReport(
      kind=EditorDestroyed, editor_id~, agent_id=reg.agent_id,
      cell_id=cell.cell_id, cell_label=cell.label,
    ))
  }
  guard reg.protected.iter().any(fn(p) { p.cell_id == cell.cell_id }) else {
    return Err(AbortReport(
      kind=CellNotInProtectedSurface,
      editor_id~, agent_id=reg.agent_id,
      cell_id=cell.cell_id, cell_label=cell.label,
    ))
  }
  // Defense-in-depth against out-of-band Watch::dispose. Under normal flow this
  // is unreachable because alive=true ⟹ no destroy ran ⟹ no watch disposed.
  // Out-of-band disposal is a contract violation (§11 in v2.1 contract), but
  // catching it here surfaces a typed AbortReport instead of the underlying
  // Watch::read abort at `loom/incr/cells/observer.mbt:86-88`.
  guard !(cell.is_disposed)() else {
    return Err(AbortReport(
      kind=ProtectedCellDisposed,
      editor_id~, agent_id=reg.agent_id,
      cell_id=cell.cell_id, cell_label=cell.label,
    ))
  }
  match (cell.read)() {
    Ok(value) => Ok(value)
    Err(cycle) => Err(AbortReport(
      kind=CycleDetected,
      editor_id~, agent_id=reg.agent_id,
      cell_id=cell.cell_id, cell_label=cell.label,
      domain_tag=Some(cycle.format_path()),
    ))
  }
}
```

Residual hole (Phase 2 hardening): out-of-band `Watch::dispose` is now caught structurally via the `is_disposed` guard above (returns `AbortKind::ProtectedCellDisposed`). Out-of-band `Runtime::gc()` calls that sweep an upstream cell can still leave the watch alive but its target invalid — the underlying `Watch::read` would then hard-abort. The contract §11 already classifies all out-of-band runtime mutation as convention-violation territory; lint backstop or upstream privatization of `Runtime::gc` is the long-term mitigation.

## 8. Lambda FFI helper

### 8.1 LambdaProtectedCells bundle

Lives in `ffi/lambda/` alongside the helper (Lambda-specific types stay out of the coordinator package).

```moonbit
pub struct LambdaProtectedCells {
  parser_syntax_tree : ProtectedCell[@seam.SyntaxNode]
  parser_ast         : ProtectedCell[@ast.Term]
  parser_source      : ProtectedCell[String]
  parser_diagnostics : ProtectedCell[DiagnosticSet]
  cached_proj_node   : ProtectedCell[@core.ProjNode[@ast.Term]?]
  registry_memo      : ProtectedCell[Map[NodeId, ProjNode[@ast.Term]]]
  source_map_memo    : ProtectedCell[@core.SourceMap]
  proj_memo          : ProtectedCell[VersionedFlatProj]
  escalation_memo    : ProtectedCell[Array[EvalResult]]
  typecheck_output   : ProtectedCell[ModuleTypeResult]
}

fn LambdaProtectedCells::LambdaProtectedCells(
  editor    : @editor.SyncEditor[@ast.Term],
  companion : @lang_lambda.LambdaCompanion,
  typecheck : TypecheckBundle,
) -> LambdaProtectedCells {
  {
    parser_syntax_tree: ProtectedCell::from_derived("parser_syntax_view",       editor.parser_syntax_tree()),
    parser_ast        : ProtectedCell::from_derived("parser_ast_view",          editor.parser_ast()),
    parser_source     : ProtectedCell::from_derived("parser_source_view",       editor.parser_source()),
    parser_diagnostics: ProtectedCell::from_derived("parser_diagnostics_view",  editor.parser_diagnostics()),
    cached_proj_node  : ProtectedCell::from_derived("cached_proj_node",         editor.cached_proj_node()),
    registry_memo     : ProtectedCell::from_derived("proj_registry",            editor.registry_memo()),
    source_map_memo   : ProtectedCell::from_derived("source_map",               editor.source_map_memo()),
    proj_memo         : ProtectedCell::from_derived("proj_flat",                companion.proj_memo()),
    escalation_memo   : ProtectedCell::from_derived("escalation_memo",          companion.escalation_memo()),
    typecheck_output  : ProtectedCell::from_derived("typecheck_pipeline",       typecheck.output),
  }
}

pub fn LambdaProtectedCells::to_protected_reads(self : LambdaProtectedCells) -> Array[ProtectedRead] {
  [
    self.parser_syntax_tree.erase(),
    self.parser_ast.erase(),
    self.parser_source.erase(),
    self.parser_diagnostics.erase(),
    self.cached_proj_node.erase(),
    self.registry_memo.erase(),
    self.source_map_memo.erase(),
    self.proj_memo.erase(),
    self.escalation_memo.erase(),
    self.typecheck_output.erase(),
  ]
}
```

### 8.2 assemble_lambda_handle + FFI ctors

```moonbit
// ffi/lambda/lifecycle.mbt — replaces the 5-step duplicated sequence
// in create_editor (lifecycle.mbt:90-104) and create_editor_with_undo
// (undo.mbt:7-27).

priv struct LambdaHandle {
  editor    : @editor.SyncEditor[@ast.Term]
  companion : @lang_lambda.LambdaCompanion
  typecheck : TypecheckBundle
  editor_id : @workspace.EditorId
  cells     : LambdaProtectedCells
}

// Global coordinator singleton — claimed once, used by all create_editor* calls.
let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()

fn assemble_lambda_handle(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @workspace.EditorId {
  // Step 1 — language ctor with shared runtime.
  let (editor, companion) = @lang_lambda.new_lambda_editor(
    agent_id,
    capture_timeout_ms?~,
    parent_runtime=coordinator.runtime(),
  )

  // Step 2 — typecheck bundle on the same runtime.
  let typecheck = new_typecheck_bundle(
    editor.parser_runtime(),
    editor.parser_syntax_tree(),
  )

  // Step 3 — build the typed protected-cell bundle.
  //          Each factory creates a Watch and primes it (§6.6).
  let cells = LambdaProtectedCells::LambdaProtectedCells(editor, companion, typecheck)

  // Step 4 — register with coordinator. Erased reads derived from typed cells.
  let editor_id = coordinator.register_editor(agent_id, cells.to_protected_reads())

  // Step 5 — store FFI-side state keyed by the new EditorId.
  lambda_handles.set(editor_id.0, LambdaHandle {
    editor, companion, typecheck, editor_id, cells,
  })
  last_created_handle.val = Some(editor_id.0)

  editor_id
}

pub fn create_editor(agent_id : String) -> Int {
  assemble_lambda_handle(agent_id).0
}

pub fn create_editor_with_undo(agent_id : String, capture_timeout_ms : Int) -> Int {
  assemble_lambda_handle(agent_id, capture_timeout_ms~).0
}

pub fn destroy_editor(handle : Int) -> Unit {
  guard lambda_handles.get(handle) is Some(h) else { return }
  // Defer to coordinator gateway for dep-graph check.
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => {
      // Phase 1: log + skip teardown (contract-correct: don't tear down
      // state while deps exist). Phase 2 surfaces this to JS via a
      // dedicated FFI error channel.
      println("destroy_editor refused: " + report.to_string())
      return
    }
  }
  h.typecheck.scope.dispose()                              // typecheck-internal Scope (per-def cells)
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}
```

### 8.3 Atomic-boundary observation

Steps 1-4 of `assemble_lambda_handle` complete before any new handle becomes externally visible. If any step aborts (loom-side panic, factory panic on disposed cell, register_editor panic from an out-of-band ID collision in `coordinator.next_id`), no `LambdaHandle` lands in the map and the externally-visible side effect (the handle stored in `lambda_handles`) doesn't occur. `EditorId` allocation is internal to `register_editor` (monotonic counter; no duplicate path possible under single-threaded MoonBit). Codex r4 #6 atomic-boundary requirement (from the prior brainstorm trail) satisfied.

## 9. Phase 1 non-goals (explicit)

Naming these here prevents scope creep at plan-writing time.

1. **Markdown / JSON FFI helpers are NOT in Phase 1.** Their FFI ctors (`ffi/markdown/markdown_ffi.mbt`, `ffi/json/json_ffi.mbt`) keep their current shape. The Phase 1 PR lands no `assemble_markdown_handle` / `assemble_json_handle`. Cross-language editors-in-one-tab is a Phase 2 contract concern.

2. **`coordinator.read_protected` is NOT yet called from production code.** Phase 1 ships the API + tests; production FFI accessors (`get_diagnostics_json`, `get_view_patches_json`, etc.) keep their current `.read_or_abort()` calls. Phase 1b migrates production accessors to go through `read_protected` for the typed-error path.

3. **`coordinator.register_dep` is NOT yet called from production code.** Phase 1 ships the API + a synthetic-dep test exercising the destroy gateway's `DestroyWhileDependedUpon` path. The first real workspace memo lands in Phase 1b or 2 (e.g., the impact map from `project_incr_impact_bfs_cycle_trap`).

## 10. Codex review trail

Three design-review consults; spec is at its post-revision state.

### Consult 1 — Skeleton design (2026-05-24, sonnet earlier draft → claude opus 4.7 [1m] revision → Codex gpt-5.2 reasoning-high)

Result: REVISE → SHIP IT after v6 revision. Five substantive findings:

| # | Finding | Resolution |
|---|---|---|
| A | `read_protected.cell.read()` can hard-abort on out-of-band gc | Migrated factories to `Watch::read() -> Result[T, CycleError]`; surfaced as `AbortKind::CycleDetected` in the report |
| B | `prime()` alone violates §6.6 | Factories own the `Watch` from `.watch()` (which is the GC root) + prime via `let _ = watch.read()` |
| C | Closure-capture of Memo/Derived doesn't anchor against `gc_root_counts` | Same fix as B; `Watch` is the rooting handle |
| D | Splitting Observer install (caller) from registration (coord) broke atomicity | `Coordinator::register_editor` no longer needs a Scope; `Watch` lifecycle owned by factory |
| G | `read_protected` didn't validate `cell.cell_id ∈ editor.protected` | Added `AbortKind::CellNotInProtectedSurface` membership check |

E (O(deps) destroy scan) and F (`Ref[Bool]` adequate for alive flag) PASSed unchanged.

### Consult 2 — VersionedFlatProj Memo→Derived migration safety (2026-05-24)

Result: SHIP IT — all six questions PASS with citations. Key invariant confirmed: `to_flat_proj_incremental` reuses prev FlatProj entries when CST nodes are physically equal (`flat_proj.mbt:79, 102`); synthetic Unit body case forced into changed path via `-1` (`projection_memo.mbt:78`). Custom `Eq` based on `changed_at` preserves O(1) backdating semantics. `Derived[T]` with `T : Eq` uses the captured `==` at `memo.mbt:485` (`facade.mbt:145` wraps Memo).

### Consult 3 — Spec-level review (2026-05-24, post-write)

Result: REVISE → addressed in this revision. Eight substantive findings, all actionable:

| # | Finding | Resolution in this spec |
|---|---|---|
| A | §6 single-threaded constraint not named; §6.7 label policy only implied | §2.5 constraint-coverage table; §2.5 §6.7 row picks report-time composition |
| B | §7 open questions Q1/Q2/Q5 not explicitly answered | §2.5 open-question table answers all three |
| C | `ProtectedCellDisposed` defined but unreturnable; test 2 references nonexistent dep-clear; §8.3 mentions nonexistent duplicate-id panic | Added `is_disposed: () -> Bool` to ProtectedCell + guard in `read_protected`; added `Coordinator::unregister_dep`; rewrote §8.3 atomicity paragraph |
| D | Plan-writer would have to make non-trivial design calls | §13 enumerates 5 specific plan-time decisions with recommendations |
| E | Tests don't verify Decision A end-to-end (production accessors bypass coord) | §2 contract paragraph now states the Phase 1 vs Phase 1b coverage boundary; §12 closes with a Test-level Decision A note |
| F | Failure-mode coverage gap (forgotten register_dep, disposed-watch unreached) | Same fixes as C+E |
| G | `destroy_editor` disposes watches before `alive=false` (re-entrancy risk) | Swapped to flip alive=false first; comment in body |
| H | §13 open-questions list incomplete | §13 expanded from 1 to 5 plan-time decisions |
| I | Contract doc path doesn't resolve on current branch; "Section N —" headings confusing | §14 References notes the branch + commits; §6-§8 headings simplified ("Coordinator types" / "Coordinator method bodies" / "Lambda FFI helper") |

## 11. Sequencing

```
Loom A — Runtime::gc_root_count (single PR, ~10 lines)
  └─→ Loom B — typecheck.mbt + callers.mbt Memo→Derived migration (delegatable to Sonnet)
        └─→ Canopy 1 — VersionedFlatProj Eq + proj_memo migration + typed_term_memo
              migration + accessor expansion + new_generic runtime threading
              (compositional rewrite; submodule bump consumes Loom A+B)
              └─→ Canopy 2 — §P0b Phase 1 coordinator implementation
                    └─→ (Phase 1b / Phase 2 work begins)
```

Loom A + Loom B can ship together as one loom PR if review appetite permits.

Canopy 1 + Canopy 2 should remain separate PRs — the Memo sweep is a mechanical rewrite reviewable on its own, and the coordinator package is novel architecture worth its own review pass.

The §P0b Phase 1 coordinator (Canopy 2) itself decomposes into roughly:

- New `workspace/coordinator/` package (§6 + §7 code, 7 methods) — ~280 lines including tests.
- `editor/sync_editor.mbt` accessor expansion + `new_generic` signature change — ~30 lines + .mbti updates.
- `lang/lambda/companion/lambda_editor.mbt` `new_lambda_editor` pass-through param — ~10 lines.
- `lang/markdown/companion/markdown_companion.mbt` + `lang/json/companion/json_companion.mbt` symmetric `parent_runtime?~` pass-through — ~5 lines each.
- New `LambdaProtectedCells` bundle in `ffi/lambda/` — ~50 lines.
- `ffi/lambda/lifecycle.mbt` `assemble_lambda_handle` + revised `create_editor` / `create_editor_with_undo` / `destroy_editor` — ~80 lines.
- Phase 1 tests per §12 (6 tests, ~150 lines).

Plan-writing in the next session (writing-plans skill) will decompose this further with file:line breakdown.

## 12. Phase 1 verification

The contract v2.1 §10 lists tests 1-5 for Phase 1. This skeleton supports four of them; the fifth (`audit_leaks`) is Phase 2.

1. **Construction-and-read roundtrip:** Create an editor; read each of the 10 protected cells via `read_protected`; expect `Ok(value)`.
2. **DestroyWhileDependedUpon refuses, then succeeds after `unregister_dep`:** `register_dep(some_synthetic_cell_id, editor_id, parser_ast_id)`; call `destroy_editor`; expect `Err(AbortReport { kind: DestroyWhileDependedUpon, … })`. Then `unregister_dep(some_synthetic_cell_id, editor_id, parser_ast_id)` and retry destroy; expect `Ok(())`.
3. **Read-after-destroy returns EditorDestroyed:** Create + destroy + read; expect `Err(AbortReport { kind: EditorDestroyed, agent_id, cell_id, cell_label })`.
4. **CellNotInProtectedSurface guard:** Construct two editors A and B; attempt `read_protected(B.editor_id, A.cells.parser_ast)`; expect `Err(AbortReport { kind: CellNotInProtectedSurface, … })`.
5. **ProtectedCellDisposed defense-in-depth:** Construct an editor, then call `.dispose()` on one of its `LambdaProtectedCells` watches directly (test-only out-of-band path that bypasses `destroy_editor`); attempt `read_protected` on that cell; expect `Err(AbortReport { kind: ProtectedCellDisposed, … })`. Verifies the `cell.is_disposed()` guard in `read_protected`.
6. **CycleDetected mapping:** Construct a synthetic Derived chain with a cycle; register; read; expect `Err(AbortReport { kind: CycleDetected, domain_tag: Some(formatted_path), … })`. Verifies the `Watch::read -> Err(CycleError)` → `AbortReport` mapping.
7. **(Phase 2)** `audit_leaks()` after a destroy without `gc()` returns an empty leak set, and an out-of-band-`gc()` scenario surfaces a `LeakKind::ObserverNotInScope` entry.

The verification prototype at `.worktrees/proto-shared-runtime-verify/` already exercises a version of tests 1-3 against pre-target-API names; rewriting against the v6 API surface is part of Canopy 2.

**Test-level Decision A boundary:** Tests 1-6 verify the coordinator-mediated path. They do NOT verify that production accessors (`editor.parser_ast()` etc.) bypass `read_protected` — that's intentional per §9 non-goal #2. A workspace memo that captures an editor cell directly and forgets `register_dep` is a contract violation that Phase 1 doesn't detect; Phase 1b's migration of production accessors closes this gap.

## 13. Decisions for plan-writing to make

The brainstorm session encoded most architectural decisions in §2.5. The remaining open calls that plan-writing must make explicitly (a competent engineer cannot infer these from the spec):

1. **Loom A vs Loom A+B bundling.** Recommended: separate PRs (reviewable). Acceptable: bundled (one submodule bump). Either fine.
2. **`unregister_dep` exposure scope.** Phase 1's only caller is tests (§12 test 2). Plan must decide whether to ship it as `pub` (preferred — Phase 1b workspace memos will need it on their own dispose) or as `priv` with a `#[test]` test-only export. Recommended: `pub` from day one.
3. **`AbortReport.domain_tag` semantic.** Plan must decide whether labels-passed-in-`domain_tag` are pure prose (current spec design — `cycle.format_path()` for CycleDetected) or include structured fields. Recommended: free-form prose in Phase 1; structured payload deferred to Phase 2 diagnostic-richness work.
4. **Mode-1 (registration-time gc_root_count check) on/off.** Loom A ships the introspection; spec doesn't say whether `register_editor` actually CHECKS that each `cell_id`'s `gc_root_count > 0` after `Watch::watch()`. Recommended: ON (since the factory always calls `.watch()` first, this should always pass; mode-1 catches an upstream bug if it doesn't).
5. **Test-helper visibility for ProtectedCell disposal (§12 test 5).** Test needs a way to call `.dispose()` on a single `ProtectedCell` from the test code. Plan must decide: expose `ProtectedCell::dispose` as `pub`, or use a whitebox `_wbtest.mbt`. Recommended: whitebox test (keeps the public API surface minimal — `dispose` is an implementation detail of `destroy_editor`'s teardown).

These five calls are concrete and small. Each can be settled in a 2-line discussion with the user before plan-writing starts, OR plan-writing can adopt the recommendations and flag any pushback in plan review.

## 14. References

Source files reviewed during this design:

- `loom/incr/cells/observer.mbt:1-200` — Watch/Observer semantics
- `loom/incr/cells/pkg.generated.mbti` — Scope, Watch, Derived, ReachableDerived APIs
- `loom/incr/docs/api-reference.md:1-1290` — Read vocabulary migration, type constraints, custom Eq semantics
- `lang/lambda/flat/versioned_flat_proj.mbt:1-29` — BackdateEq impl
- `lang/lambda/flat/projection_memo.mbt:24-149` — proj_memo construction + changed_at invariant
- `lang/lambda/companion/lambda_editor.mbt:1-180` — LambdaCompanion + new_lambda_editor
- `editor/sync_editor.mbt:41-77` — SyncEditor::new_generic
- `ffi/lambda/lifecycle.mbt:1-60` — Today's FFI ctor and TypecheckBundle
- `loom/examples/lambda/src/typecheck/typecheck.mbt:35-360` — Memo usage to migrate
- `loom/examples/lambda/src/callers/callers.mbt:18, 477-497` — Memo usage to migrate

Related research:

- `docs/research/2026-05-22-spec-aware-workspace.md` — §P0a + §P0b umbrella (on `main`)
- `docs/research/2026-05-23-shared-runtime-workspace-contract.md` (v2.1) — Phase 1 contract. **Not on current branch** — committed on `docs/shared-runtime-workspace-contract` (local, not pushed; commits `b69b45a` + `1d58fba`). Cross-session memory at `~/.claude/memory/project_shared_runtime_workspace_contract.md` mirrors the contract decisions
- `docs/research/2026-05-23-runtime-safety-decision.md` — Gate #1 verdict (path (i): shared runtime + workspace-side constraints)
- `docs/research/2026-05-24-shared-runtime-call-flow-grounding.md` — Call-flow map (§6 constraints, §7 open questions). On current branch
- `~/.claude/memory/project_shared_runtime_workspace_contract.md` — Cross-session memory of the contract trail (read-accessible from any branch)
- `~/.claude/memory/feedback_ground_before_design.md` — Methodology rule the grounding doc operationalized
- `~/.claude/memory/delegation-log.md` — All three Codex consults logged (2026-05-24 entries: skeleton design REVISE→SHIP IT, VersionedFlatProj migration SHIP IT, spec-level review REVISE→this revision)
