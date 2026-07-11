# §P0b Phase 1b WS2 — Markdown + JSON FFI Helpers Design

**Date:** 2026-05-25
**Belongs to slice:** §P0b Phase 1b — third of three Phase 1b workstreams enumerated at `docs/superpowers/plans/2026-05-24-p0b-phase1-implementation.md:2083-2085`.
**Pairs with:** `docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md` (PR4 / Lambda reference pattern).
**Status:** Design approved after two Codex consults (stage-1 NEEDS-REVISION → re-scope → stage-2 NEEDS-REVISION → resolutions inline below).

## 0. Background

WS1 (`get_diagnostics_json` migration, canopy #349, commit `52b13a0`) shipped 2026-05-25, demonstrating production-accessor migration to `coordinator.read_protected` for the Lambda FFI. WS2 brings the **structural** half of PR4 — `assemble_<lang>_handle` + `<Lang>ProtectedCells` + coordinator-routed destroy — to Markdown and JSON FFI surfaces.

The plan §2084 frames WS2 as **"Symmetric to Lambda's PR4"**. Critically, this means structurally symmetric (per-language coordinator participation), **not** cross-language symmetric (shared runtime across all three FFI surfaces). Cross-language sharing is explicitly Phase 2 per spec §1.31; the first real cross-language consumer (the impact-BFS workspace memo from `project_incr_impact_bfs_cycle_trap`) is a separate future workstream.

## 1. Scope

**In scope:**

- `ffi/markdown/` and `ffi/json/` each gain: per-package `let coordinator = @workspace.Coordinator::new()`, `<Lang>Handle` priv struct, `<Lang>ProtectedCells` priv struct (7 fields), `assemble_<lang>_handle` atomic ctor, coordinator-routed `destroy_<lang>_editor`.
- Each PR co-migrates ONE FFI accessor through `coordinator.read_protected` so the cells bundle ships live, not as dead code under a `warnings = "-7"` suppression. JSON: `json_get_errors`. Markdown: `markdown_compute_view_patches_json` (rewritten — see §6).
- Spec §12 tests 1–4 per language (test 5 is workspace-generic per Codex round-2 Q4).
- Behavior-equivalence + destroyed-editor regression tests for each migrated accessor.

**Out of scope:**

- Cross-language coordinator sharing (Phase 2; see §0 rationale).
- Lambda-side changes (`ffi/lambda/*` is untouched).
- Migration of the other ~12 unmigrated Markdown/JSON FFI accessors (WS3+).
- Any change to `@editor`, `@workspace.Coordinator`, `@protocol`, or language-companion packages.

## 2. The contract in one paragraph

Each FFI surface (Lambda, Markdown, JSON) holds its own `@workspace.Coordinator` singleton at module scope, owning its own `@incr.Runtime`. Editor construction funnels through a single `assemble_<lang>_handle` ctor that performs editor-creation + cells-bundle-construction + coordinator registration as one atomic transaction. Destroy routes through `Coordinator::destroy_editor` — on `Err(AbortReport { kind: DestroyWhileDependedUpon })` the FFI keeps bookkeeping intact (Phase 1 behavior matching Lambda). Migrated accessors read cells through `coordinator.read_protected`; on any Err they collapse to the accessor's empty-string return ("[]" / "null" / ""). The per-language coordinators are intentionally independent at this phase — no cross-language dep registry, no shared runtime.

## 3. Hard constraints

| § | Constraint | Where addressed |
|---|------------|-----------------|
| 3.1 | Single-threaded MoonBit runtime per FFI bundle. JS-side ESM gives each FFI bundle its own module scope (empirically verified — see §4); the per-language coordinator is the only viable shape under the current build. | Per-language `let coordinator = ...`, no shared singleton package. §5. |
| 3.2 | Empty-document behavior must match `SyncEditor::get_errors` (`editor/sync_editor_parser.mbt:107` short-circuits empty input to `[]`). | Codex round-2 finding #1 — JSON migration adds explicit empty-doc guard. §6.1. |
| 3.3 | `diff_view_nodes` is package-private (`editor/view_updater.mbt:77`). The Markdown accessor rewrite cannot import it. | Codex round-2 finding #2 — Markdown FFI duplicates the ~80-line helper locally. §6.2. |
| 3.4 | `get_text()` reads `TextState` directly (`editor/sync_editor_text.mbt:172`), not `parser_source` (`editor/sync_editor_parser.mbt:145`). Text state is the input to all Derived cells; reading it raw doesn't violate any cell-protection invariant. | Codex round-2 finding #3 — Markdown rewrite uses 3 protected reads + 1 raw `ed.get_text()`. §6.2. |
| 3.5 | Destroy ordering: `coordinator.destroy_editor` → on Ok, remove FFI-side bookkeeping. Markdown/JSON have no per-editor disposable scope (no typecheck pipeline), so the ordering is strictly simpler than Lambda's. | §5.3. |
| 3.6 | Atomic-construction order: ctor → cells bundle → `coordinator.register_editor` → `handles[id] = struct`. Failure at any step leaves `handles` untouched. Mirrors PR4 spec §8.3. | §5.2. |
| 3.7 | Cell-inventory must be symmetric across the two new languages. Each gets the same 7-cell SyncEditor generic surface. Both `<Lang>ProtectedCells` field shapes are identical except for the `T` type parameter (`@md.Block` vs `@djson.JsonValue`). | §5.1. |

## 4. Why per-language coordinators (not shared)

The original brainstorm proposed a shared `ffi/coordinator/` singleton package. Codex round-1 finding #4 flagged this as an unverified JS-bundle assumption. Empirical verification (2026-05-25):

- `scripts/build-js.sh:19-28` produces three separate FFI entry artifacts.
- Each is a self-contained ESM bundle: `lambda.js` 2.7 MB, `json.js` 1.4 MB, `markdown.js` 1.2 MB.
- Each contains all shared deps inlined (`SyncEditor`: 218/89/85 matches; `@core.ProjNode`: 228/147/134 matches across lambda/json/markdown.js).
- No `import` statements at module head; only `export { ... }` at module tail. Vite imports each as an independent ESM module → ESM gives each its own scope.
- `moon build --help` shows no shared-emit flag. No `format`/`external` field in any workspace `moon.pkg` link config.

Conclusion: a hypothetical `ffi/coordinator/` package's `let coordinator = ...` would be inlined into each of the three bundles, executed once per bundle at module init, producing three distinct `Coordinator` instances at runtime. The shared-singleton goal is structurally unachievable under the current JS build.

The spec's §1.31 deferral of "multi-language editors-in-one-tab (cross-language shared runtime)" to Phase 2 is therefore load-bearing for WS2's scoping. The first real cross-language consumer will need to either:
- restructure to one shared JS bundle, OR
- use a `globalThis`-coalesced coordinator via `extern "js"` FFI, OR
- pass the coordinator through the JS layer as an opaque handle.

None of these are appropriate to land speculatively in WS2 without a concrete consumer driving the design.

## 5. Components per FFI

### 5.1 `<Lang>ProtectedCells` (7 fields, symmetric across Markdown/JSON)

| Field | Source (on `SyncEditor[T]`) | Label |
|-------|-----------------------------|-------|
| `parser_syntax_tree` | `editor.parser_syntax_tree()` | `"parser_syntax_view"` |
| `parser_ast` | `editor.parser_ast()` | `"parser_ast_view"` |
| `parser_source` | `editor.parser_source()` | `"parser_source_view"` |
| `parser_diagnostics` | `editor.parser_diagnostics()` | `"parser_diagnostics_view"` |
| `cached_proj_node` | `editor.cached_proj_node()` | `"cached_proj_node"` |
| `registry_memo` | `editor.registry_memo()` | `"proj_registry"` |
| `source_map_memo` | `editor.source_map_memo()` | `"source_map"` |

Constructor calls `@workspace.ProtectedCell::from_derived(label, cell)` for each field. The bundle exposes `to_protected_reads(self) -> Array[ProtectedRead]` returning the erased registration list in declared order.

Mirrors `ffi/lambda/protected_cells.mbt` lines 18–101 for the SyncEditor-generic subset; **omits** Lambda's `proj_memo`, `escalation_memo`, `typecheck_output` (Lambda-only companion/typecheck fields).

### 5.1.1 Handle namespace change (verified non-issue)

The legacy Markdown/JSON FFIs allocated handles from offset bases (`markdown_next_handle = 20000`, `json_next_handle = 10000`) "to avoid collision with lambda registry" per the file headers. Under coordinator-allocated `EditorId`s, each per-language coordinator allocates from 0 independently — Lambda already shipped this change in PR4. JS-side consumers (`examples/web/src/json-editor.ts:11`, `markdown-editor.ts:28`) store the handle returned from `create_*_editor` in a const and never compare against a literal, so the offset's defensive role (rejecting cross-FFI handle confusion) is not exercised in practice. ESM module isolation already ensures each FFI bundle's accessors are only callable from JS code that imported THAT bundle. The offsets are dropped.

### 5.2 `<Lang>Handle` (3 fields) and `assemble_<lang>_handle`

```
priv struct <Lang>Handle {
  editor : @editor.SyncEditor[<T>]
  editor_id : @workspace.EditorId
  cells : <Lang>ProtectedCells
}
```

No `companion` field (Markdown/JSON `new_*_editor` returns only `SyncEditor[T]`). No `typecheck` field (no typecheck pipeline).

`assemble_<lang>_handle(agent_id : String) -> EditorId` performs four steps in order:

1. `let editor = @<lang>_companion.new_<lang>_editor(agent_id, parent_runtime=coordinator.runtime())`
2. `let cells = <Lang>ProtectedCells::<Lang>ProtectedCells(editor)`
3. `let editor_id = coordinator.register_editor(agent_id, cells.to_protected_reads())`
4. `<lang>_handles[editor_id.0] = { editor, editor_id, cells }`

`create_<lang>_editor(agent_id)` becomes `assemble_<lang>_handle(agent_id).0`. The `<lang>_next_handle` counter is removed (`EditorId.0` replaces it).

### 5.3 `destroy_<lang>_editor`

```
pub fn destroy_<lang>_editor(handle : Int) -> Unit {
  let h = match <lang>_handles.get(handle) { Some(v) => v; None => return }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => { println("destroy_<lang>_editor refused: \{report}"); return }
  }
  <lang>_handles.remove(handle)
  <lang>_view_states.remove(handle)
}
```

Same shape as Lambda's `destroy_editor` (`ffi/lambda/lifecycle.mbt:127-154`), minus the `pretty_view_states.remove` (Markdown/JSON have no pretty view), minus the `last_created_handle` reset (no `get_*_companion`-style legacy accessor), minus the `typecheck.scope.dispose` (no typecheck bundle).

Phase 1 refusal behavior matches Lambda: log + skip teardown so cached state remains readable.

### 5.4 `warnings = "-7"` carve-out

Each FFI's `moon.pkg` gets a `warnings = "-7"` line and a header comment mirroring `ffi/lambda/moon.pkg:22-29`:

> "Most fields of `<Lang>ProtectedCells` are read by whitebox tests in `lifecycle_phase1_wbtest.mbt`. Until WS3+ migrates additional production accessors, per-field unused warnings still fire."

## 6. Migrated FFI accessors

### 6.1 PR-C — `json_get_errors`

Current body (`ffi/json/json_ffi.mbt:55-60`):

```
match json_editors.get(handle) {
  Some(ed) => ed.get_errors().to_json().stringify()
  None => "[]"
}
```

Rewrite:

1. Look up handle in `json_handles`. None → return `"[]"`.
2. **Empty-document guard** (Codex round-2 #1): if `h.editor.get_text() == ""` return `"[]"`. Preserves `SyncEditor::get_errors`'s empty-input short-circuit (`editor/sync_editor_parser.mbt:107`) which the raw `read_protected(parser_diagnostics)` migration would lose.
3. `match coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics)`:
   - `Ok(diagset)` → `diagset.format().to_json().stringify()`. The `.format()` call is the same conversion `SyncEditor::get_errors` uses internally at `editor/sync_editor_parser.mbt:111`, producing the `Array[String]` shape that legacy JSON consumers expect.
   - `Err(_)` → `"[]"`.

Structural twin of `ffi/lambda/diagnostics.mbt:51` Lambda WS1 pattern.

### 6.2 PR-B — `markdown_compute_view_patches_json`

Current body (`ffi/markdown/markdown_ffi.mbt:126-142`) calls `@editor.compute_view_patches(state, ed)` which internally calls `editor.get_view_tree()` + `editor.get_errors()` (`editor/view_updater.mbt:45,53`). Both bypass `coordinator.read_protected` → co-migrating this accessor as-is proves nothing about the cells bundle being live (Codex round-1 #2).

Rewrite:

1. Look up handle in `markdown_handles`. None → return `"[]"`.
2. Lookup-or-create `markdown_view_states[handle]` (unchanged from legacy).
3. Read three protected cells up front (any Err → return `"[]"`):
   - `coordinator.read_protected(h.editor_id, h.cells.cached_proj_node)` → `Option[ProjNode[@md.Block]]`
   - `coordinator.read_protected(h.editor_id, h.cells.source_map_memo)` → `@core.SourceMap`
   - `coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics)` → `@loom.DiagnosticSet`; call `.format()` on the value to get the `Array[String]` shape (same conversion `SyncEditor::get_errors` uses at `editor/sync_editor_parser.mbt:111`)
4. Read text state raw: `let source_text = h.editor.get_text()` (Codex round-2 #3 — text state is not a Derived cell; passing it raw is correct).
5. Manually assemble the `ViewNode?`:
   - If `cached_proj_node` is `Some(proj)`, call `@protocol.proj_to_view_node(proj, source_map, source_text=Some(source_text), annotations={})`.
   - Else `current = None`.
6. Compute the diff against `state.previous` using a **locally duplicated `diff_view_nodes` helper** (~80 lines cloned from `editor/view_updater.mbt:77-143`; Codex round-2 #2 — the editor-pkg helper is private). Walks Full/Replace/Update/Insert/Remove patches identically.
7. Convert diagnostics strings to `@protocol.Diagnostic` array if non-empty (mirroring `view_updater.mbt:53-71` with `state.had_errors` toggle). Append `SetDiagnostics` patch.
8. Update `state.previous = current`. Return `Json::array(patches.map(p => p.to_json())).stringify()`.

**Annotations assumption** (Codex round-2 #4 nit): Markdown's `new_markdown_editor` passes no `LanguageCapabilities` today, so `annotations={}` is the correct production value. If a future workstream adds capabilities to Markdown, this accessor will silently emit empty annotations until updated — recorded as a §9 follow-up.

## 7. Test plan

### 7.1 Per-language structural tests (`<lang>_lifecycle_phase1_wbtest.mbt`)

Mirroring `ffi/lambda/lifecycle_phase1_wbtest.mbt` tests 1–4. **Test 5 (ProtectedCellDisposed defense-in-depth) is omitted per Codex round-2 Q4**; the workspace-generic coverage at `workspace/coordinator/coordinator_wbtest.mbt:33` is sufficient.

| Test | Mirrors Lambda line | What it verifies |
|------|---------------------|------------------|
| 1 — all-7-cells readable | wbtest lines 46–82 (10 cells for Lambda, 7 for Markdown/JSON) | Every protected cell is reachable via `coordinator.read_protected(id, h.cells.<cell>)` → `Ok(_)`. Reads ALL 7, not a spot-check (PR4 retrospective). |
| 2 — DestroyWhileDependedUpon → unregister → destroy | wbtest lines 95–108 | `register_dep(synth_id, id, parser_ast_id)` → `destroy_editor` Err(DestroyWhileDependedUpon) → `unregister_dep` → `destroy_editor` Ok. |
| 3 — Read-after-destroy returns EditorDestroyed | wbtest lines 110–139 | Create + destroy + `read_protected` → Err(AbortReport { kind: EditorDestroyed, editor_id, agent_id, cell_label }). |
| 4 — CellNotInProtectedSurface guard | wbtest lines 141–155 | Two editors A, B; `read_protected(B.editor_id, A.cells.parser_ast)` → Err(CellNotInProtectedSurface). |

Each test gets a `clear_<lang>_handles` helper (mirroring `clear_lambda_handles` in `ffi/lambda/lifecycle_phase1_wbtest.mbt:13-24`) that resets state between tests by directly emptying the handles + view_states maps (not by calling `destroy_<lang>_editor`, which can refuse if deps are stale).

### 7.2 Per migrated accessor — behavior-equivalence + destroyed-editor regression

**`json_get_errors`** (PR-C):
- **Pre-destroy parse-error path**: input `"{ invalid"`, assert output is non-empty JSON array containing the parse-error string.
- **Pre-destroy empty-input path**: input `""`, assert output is exactly `"[]"` (preserves `SyncEditor::get_errors` empty-doc guard; Codex round-2 #1).
- **Post-destroy collapses to "[]"**: any of the above; after `coordinator.destroy_editor`, accessor returns `"[]"` even though the parse-error state still exists in the underlying Derived cell.

**`markdown_compute_view_patches_json`** (PR-B):
- **Pre-destroy initial-render path**: empty `ViewUpdateState`, valid markdown input, assert output contains a `FullTree` patch with a non-null root.
- **Pre-destroy incremental-diff path**: two-call sequence with a single-block edit between, assert second call returns `UpdateNode`/`ReplaceNode`/`InsertChild`/`RemoveChild` patches matching the change, not `FullTree`.
- **Post-destroy collapses to "[]"**: any of the above; after `coordinator.destroy_editor`, accessor returns `"[]"`.

Per `[[feedback-verify-test-for-flagged-risk]]`: each behavioral risk in the rewrite (empty-doc guard, incremental diff, post-destroy collapse) has its own explicit test, not "trusted to the suite."

### 7.3 Expected test-count delta

- 4 structural tests × 2 languages = +8
- Behavior-equivalence + destroyed-editor regression: ~3 per migrated accessor × 2 = +6

Workspace test count: **1171 → ~1185**.

## 8. PR decomposition

Two **independent** PRs (no Lambda-side touch, no inter-PR ordering dependency):

- **PR-B (Markdown)**: ~250 lines of new code + ~80-line `diff_view_nodes` duplicate. Files: new `ffi/markdown/protected_cells.mbt`, new `ffi/markdown/lifecycle_phase1_wbtest.mbt`, edits to `ffi/markdown/markdown_ffi.mbt` + `ffi/markdown/moon.pkg`. Co-migrates `markdown_compute_view_patches_json`.
- **PR-C (JSON)**: ~150 lines of new code (no diff helper needed). Files: new `ffi/json/protected_cells.mbt`, new `ffi/json/lifecycle_phase1_wbtest.mbt`, edits to `ffi/json/json_ffi.mbt` + `ffi/json/moon.pkg`. Co-migrates `json_get_errors`.

Either order is fine. Either can ship without the other being merged. Neither requires changes outside its `ffi/<lang>/` directory plus its `moon.pkg`.

## 9. Out-of-scope / followups

| Item | When |
|------|------|
| Migrate remaining ~12 Markdown/JSON FFI accessors through `coordinator.read_protected` | WS3+ (depends on Markdown/JSON consumer pressure). |
| First real cross-language workspace memo via `register_dep` | Separate Phase 1b workstream (plan §2085). |
| Cross-language shared coordinator (one runtime across Lambda/Markdown/JSON editors) | Phase 2. Requires solving the JS bundle structure (§4). |
| Markdown `LanguageCapabilities` (`annotations`) wiring through the migrated accessor | When/if a Markdown capability adds annotations. Currently `annotations={}` is correct (§6.2). |
| Extract duplicated `diff_view_nodes` (when WS3+ migrates `json_compute_view_patches_json` and creates a second copy) | At that workstream's discretion. |
| Drop `warnings = "-7"` from each FFI's `moon.pkg` | When all 7 cells per language are read by production accessors. |

## 10. Codex review trail

| Round | Verdict | Key findings | Resolution |
|-------|---------|--------------|------------|
| 1 (stage-1, original design) | NEEDS-REVISION | (#1) PR-A wbtest references not byte-equivalent; (#2 CRITICAL) Markdown co-migration of `compute_view_patches` bypasses coordinator; (#3) audit table wrong on `compute_view_patches` cell consumption; (#4) UNVERIFIED — JS bundle artifact behavior assumption; (#5 nit) destroy regression-test obligation. | Empirical verification (§4) → cross-language sharing dropped from WS2 scope per spec §1.31 + plan §2084; #1 moot (no singleton extract); #2 resolved via accessor rewrite (§6.2); #3 fixed (audit corrected); #4 deferred to Phase 2; #5 included in test plan. |
| 2 (stage-1, revised design) | NEEDS-REVISION | (#1) JSON empty-doc guard regression; (#2) `diff_view_nodes` private to editor pkg; (#3) `get_text()` reads TextState not parser_source; (#4 nit) annotations remain empty under current Markdown/JSON config. Q1: per-language scoping confirmed correct. Q4: drop test 5 per language; covered by workspace-generic. Q5: no other blockers. | All four findings inline-resolved in §3, §6.1, §6.2, §9. |

## 11. References

- `ffi/lambda/lifecycle.mbt` — reference `assemble_lambda_handle` pattern.
- `ffi/lambda/protected_cells.mbt` — reference `LambdaProtectedCells` shape (10 cells → Markdown/JSON 7).
- `ffi/lambda/diagnostics.mbt` — WS1 accessor-rewrite pattern (mirrored for `json_get_errors`).
- `ffi/lambda/lifecycle_phase1_wbtest.mbt` — reference test template for §7.1.
- `docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md` §8, §12 — PR4 spec for cells bundle + test plan.
- `docs/superpowers/plans/2026-05-24-p0b-phase1-implementation.md:2083-2085` — Phase 1b workstream enumeration.
- `editor/view_updater.mbt` — source for the duplicated `diff_view_nodes` helper.
- `editor/pkg.generated.mbti` — SyncEditor surface (lines 326–343 for the 7 generic Derived cells).
- `workspace/coordinator/pkg.generated.mbti` — Coordinator API.
- `protocol/pkg.generated.mbti` — `proj_to_view_node` signature.
