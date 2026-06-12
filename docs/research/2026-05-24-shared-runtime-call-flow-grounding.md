# Shared-runtime workspace: call-flow grounding for §P0b Phase 1

**Date:** 2026-05-24
**Status:** Future-planning grounding draft — not current architecture or an implemented contract.
**Post-S4 PR1 note (2026-06-12):** the per-language FFI globals this doc traces (`lambda_handles`, `view_states`, `markdown_view_states`, …) were replaced by per-package `@host.HostRegistry` instances in the `ffi/host` extraction; file:line anchors into `ffi/*` predate that and no longer resolve, but the destroy-ordering analysis remains valid.
**Belongs to slice:** §P0b of `docs/research/2026-05-22-spec-aware-workspace.md`.
**Pairs with:** `docs/research/2026-05-23-observer-discipline-contract.md`.

This document is research substrate for future shared-runtime coordinator
work. It maps the baseline Lambda editor call flow that future work must
account for, but it does **not** describe an implemented shared-runtime
design and does **not** propose API shape. The next session can use it as
the substrate for a fresh PR-shape brainstorm.

The §P0b Phase 1 PR-shape brainstorm 2026-05-24 ran 5 Codex review rounds
without convergence (17 substantive findings, trajectory: structural →
mechanical → architectural → second-order architectural). Root cause was
jumping to coordinator-API design without grounding in the actual call
flow — Codex was effectively reading these files *for* the design each
round. This doc closes that gap.

## 0. Scope and non-scope

In scope: every file the Phase 1 contract obligation touches today, on
`main` at `d779071` (loom v0.6.0 bump merged via PR #340; typecheck
Observer rooting shipped via PR #339; callers migrated off
`Runtime::read` via PR #332).

Out of scope:

- API shape, coordinator surface, PR shape, anything resembling a
  proposal. This is read-only mapping.
- Revising the v2.1 contract itself. The API has migrated since the
  contract was written (e.g. `Memo` → `Derived` for most projection
  cells; PR #339 typecheck Observer rooting) but the *shape* of the
  obligations the contract specifies is unchanged. Contract drift is a
  separate downstream task.
- Sister languages (Markdown, JSON). Lambda is the lead case; the
  others are noted only where their construction shape differs.
- Loom-internal call flow below `Parser::new`. Treated as a black box
  with a documented surface (see §6).

---

## 1. New-editor construction call flow

### 1.1 The production entry points

Two FFI entry points construct a complete editor instance for JS
consumers today:

- **`create_editor(agent_id: String) -> Int`** at
  `ffi/lambda/lifecycle.mbt:90-104`. Default capture timeout (500 ms);
  no undo customization.
- **`create_editor_with_undo(agent_id: String, capture_timeout_ms: Int) -> Int`**
  at `ffi/lambda/undo.mbt:7-27`. Identical sequence with a custom
  capture timeout.

Both perform the same five-step sequence:

1. Allocate a fresh `Int` handle from `next_handle` (shared counter at
   `ffi/lambda/lifecycle.mbt:56`).
2. Call `@lang_lambda.new_lambda_editor(agent_id, capture_timeout_ms?~)`,
   destructuring the returned `(SyncEditor[@ast.Term], LambdaCompanion)`
   tuple.
3. Call `new_typecheck_bundle(editor.parser_runtime(), editor.parser_syntax_tree())`
   (defined at `ffi/lambda/lifecycle.mbt:27-50`).
4. Store the 3-field `LambdaHandle { editor, companion, typecheck }`
   into `lambda_handles: Map[Int, LambdaHandle]` (lifecycle.mbt:53)
   under the new handle.
5. Update `last_created_handle.val = Some(handle)` (used by the legacy
   `get_sync_editor()` / `get_lambda_companion()` accessors at
   lifecycle.mbt:63-85).

This 5-step sequence is duplicated **verbatim** across both FFI ctors.
Codex round 4 finding #6 from the 2026-05-24 brainstorm flagged this:
the atomic-construction boundary is split across two functions, so any
new step the §P0b coordinator needs (e.g. `coord.register_editor(...)`,
protected-cell registration) has to be inserted at two sites or
hoisted into a shared helper that does not exist today.

### 1.2 What `new_lambda_editor` actually does

`new_lambda_editor` is defined at
`lang/lambda/companion/lambda_editor.mbt:96-139`. Its body:

1. Allocates three `Ref[..?]` side-channels for cells the
   `build_memos` callback will publish back out to the enclosing
   scope: `proj_memo_ref` (line 103), `escalation_memo_ref`
   (line 106), `cached_proj_node_ref` (line 109). These exist because
   `SyncEditor::new_generic`'s `build_memos` signature returns a fixed
   3-tuple (`cached_proj_node`, `registry_memo`, `source_map_memo`)
   but Lambda needs to also keep `proj_memo` and `escalation_memo`
   for the companion and capabilities closures.
2. Calls `@editor.SyncEditor::new_generic(agent_id, make_parser, build_memos, capture_timeout_ms~, capabilities~)`
   with two inline closures. The `make_parser` closure (line 114)
   constructs `@loom.new_parser(s, @parser.lambda_grammar, runtime?=rt)` so
   each editor receives the `parent_runtime` passed into `new_lambda_editor`
   (when provided) and shares that `Runtime` with downstream projections.
   The `build_memos` closure (lines 115-128) calls
   `@lambda_flat.build_lambda_projection_memos(parser)` (which
   returns a 4-tuple — see §2.1), assigns into the three `Ref`s,
   then calls `@lambda_eval.build_eval_memo(parser)` and
   `@lambda_eval.build_escalation_memo(parser, eval_memo)`. Returns
   the 3-tuple `SyncEditor` expects.
3. Closes over the three `Ref`s in
   `build_lambda_capabilities(cached_proj_node_ref, escalation_memo_ref)`
   (line 143-167). The capabilities closures call `read_or_abort()`
   on whichever Derived is in the `Ref` each time they fire.
4. Constructs the companion struct literal at line 134, unwrapping
   `proj_memo_ref.val` and `escalation_memo_ref.val` (they are
   guaranteed `Some` because `build_memos` ran before the
   constructor returns).
5. Returns the `(editor, companion)` tuple.

The function has a fixed return type and currently accepts an optional
`parent_runtime?` parameter; it threads that parent runtime from
`SyncEditor::new_generic` callers through to the parser constructor path.

### 1.3 What `SyncEditor::new_generic` actually does

Defined at `editor/sync_editor.mbt:41-77`. Three steps relevant here:

1. `let parser = make_parser("")` (line 52) — invokes the
   language-specific `make_parser` closure with an empty initial
   source. This is the *only* place in the editor stack where the
   Parser is constructed and where the Runtime is materialized.
2. `let (cached_proj_node, registry_memo, source_map_memo) = build_memos(parser)`
   (line 53) — invokes the language-specific projection-memo
   builder.
3. Constructs the `SyncEditor` struct literal (lines 55-76).
   Fields relevant to §P0b: `parser` (line 58), `cached_proj_node`
   (line 60), `registry_memo` (line 61), `source_map_memo`
   (line 62). No `lifetime_scope`, no `observers` collection.

`SyncEditor::new_generic` accepts optional `parent_runtime?` and passes it
to `make_parser("", parent_runtime)` directly. If omitted, the parser owns
its own fresh runtime; if provided, it shares parser + projection memos on
the same runtime.

### 1.4 Non-FFI callers and sister languages

`new_lambda_editor`: 222 grep hits across 23 non-build files. Three
production sites (the two FFI ctors in §1.1 plus
`lang/lambda/top.mbt:17` which is a `pub using` re-export). Remaining
19 files are tests and demos (`examples/ideal/main/`) consuming
`(editor, _) = ...` or `.0` — none construct typecheck.

Sister-language ctors take only `agent_id` + `capture_timeout_ms?`:
`new_markdown_editor` (markdown_companion.mbt:7-17) returns a bare
`SyncEditor[@markdown.Block]`; `new_json_editor`
(json_companion.mbt:8-18) returns a bare `SyncEditor[@json.JsonValue]`.
Their FFI counterparts (markdown_ffi.mbt:17-22, json_ffi.mbt:19-24)
store the SyncEditor directly with no `TypecheckBundle`. Implication:
the protected-cell set is heterogeneous across languages — Markdown
and JSON need only the 7 generic cells; Lambda adds 2 companion +
1 typecheck.

`workspace/probe/gate1_runtime_safety_wbtest.mbt:9-16` documents runtime
threading behavior using `new_lambda_editor(..., parent_runtime=shared)`
in the positive path; the same file also includes a control case with no
`parent_runtime`.

---

## 2. Cell construction inventory

Below is every cell construction site reached during a single
`create_editor` call, in invocation order, with cell type and label.
The eventual coordinator's protected-cell registry would need to
enumerate this list.

### 2.1 Lambda projection cells (4 cells)

Created by `@lambda_flat.build_lambda_projection_memos(parser)`,
called from inside `new_lambda_editor`'s `build_memos` closure.
File: `lang/lambda/flat/projection_memo.mbt`.

| Field name        | Type                                      | Label              | Site (file:line)                      |
|-------------------|-------------------------------------------|--------------------|---------------------------------------|
| `proj_memo`       | `@incr.Memo[VersionedFlatProj]`           | `proj_flat`        | projection_memo.mbt:34, label at :118 |
| `cached_proj_node`| `@incr.Derived[@core.ProjNode[@ast.Term]?]` | `cached_proj_node` | projection_memo.mbt:126, label at :148 |
| `registry_memo`   | `@incr.Derived[Map[NodeId, ProjNode[...]]]` | `proj_registry`    | projection_memo.mbt:161, label at :229 |
| `source_map_memo` | `@incr.Derived[@core.SourceMap]`           | `source_map`       | projection_memo.mbt:238, label at :318 |

Note: `proj_memo` stays a `Memo` (not migrated to `Derived`) because
`VersionedFlatProj` uses `BackdateEq` for O(1) revision comparison;
exposing it through `Derived` would force full structural equality on
`FlatProj` each recompute. See the inline comment at
`lang/lambda/companion/lambda_editor.mbt:9-12`.

All four cells are constructed on `parser.runtime()` (resolved via
`let rt = parser.runtime()` at projection_memo.mbt:17). None is
attached to a `Scope`; reachability today is by struct-field
retention only — `cached_proj_node` / `registry_memo` / `source_map_memo`
sit in `SyncEditor`'s `priv` fields (sync_editor.mbt:14-16), and
`proj_memo` sits in `LambdaCompanion`'s `priv proj_memo` field
(lambda_editor.mbt:13).

### 2.2 Lambda evaluation cells (2 cells)

| Field name        | Type                                      | Label             | Site                                      |
|-------------------|-------------------------------------------|-------------------|-------------------------------------------|
| `eval_memo`       | `@incr.Derived[Array[EvalResult]]`        | `eval_memo`       | `lang/lambda/eval/eval_memo.mbt:210`, label at :218 |
| `escalation_memo` | `@incr.Derived[Array[EvalResult]]`        | `escalation_memo` | `lang/lambda/eval/batch_escalation.mbt:36`, label at :47 |

Constructed on `parser.runtime()` (resolved via
`@incr.Derived::Derived(parser.runtime(), …)`). `eval_memo` is a local
variable inside `new_lambda_editor`'s `build_memos` closure and is
**not retained** anywhere directly — its only reference is the dependency
edge from `escalation_memo`'s compute closure
(`tier1_results = eval_memo.get_or_abort()` at batch_escalation.mbt:39).
`escalation_memo` is stored in the companion's `priv escalation_memo`
field (lambda_editor.mbt:16).

This is a §4 protected-surface concern. If `escalation_memo` is
observer-rooted, BFS preserves `eval_memo` via the dep edge. But if
the coordinator only enumerates *stored* cell handles (as the contract
implies in §4), `eval_memo` is implicit and the future audit must walk
deps, not just struct fields.

### 2.3 Parser-internal cells (1 Signal + 5 Derived = 6 cells)

Created by `Parser::new` at `loom/loom/src/pipeline/parser.mbt:38-89`.
The Parser owns its Runtime when `runtime?` is omitted (line 45).
After the engine is primed via initial `parse()`, the Parser
constructor builds:

| Field             | Type                              | Label                      | parser.mbt line |
|-------------------|-----------------------------------|----------------------------|-----------------|
| `snapshot_signal` | `@incr.Signal[ParseSnapshot[Ast]]`| `parser_snapshot`          | 47 / 52         |
| `snapshot_view`   | `@incr.Derived[ParseSnapshot[Ast]]`| `parser_snapshot_view`    | 54 / 58         |
| `source_view`     | `@incr.Derived[String]`           | `parser_source_view`       | 59 / 63         |
| `syntax_view`     | `@incr.Derived[@seam.SyntaxNode]` | `parser_syntax_view`       | 64 / 68         |
| `ast_view`        | `@incr.Derived[Ast]`              | `parser_ast_view`          | 69 / 73         |
| `diagnostics_view`| `@incr.Derived[DiagnosticSet]`    | `parser_diagnostics_view`  | 74 / 78         |

`SyncEditor`'s accessors `parser_runtime()` and `parser_syntax_tree()`
(`editor/sync_editor_parser.mbt:123-134`) expose the Parser's
runtime + `syntax_view` directly to the FFI typecheck setup. The
contract's §4 lists `parser.ast()`, `parser.source()`,
`parser.diagnostics()`, and `parser_syntax_tree()` (which returns
`syntax_view`) as protected; this is the full ground-truth set.

The cell *labels* are set inside loom, not in canopy. The §P0b
contract's "label_prefix" plumbing concern lives at the Parser
ctor signature: there is no current way for a canopy caller to
inject an `agent_id.lang.` prefix into these labels without changing
`Parser::new` upstream.

### 2.4 Typecheck pipeline cells (FFI-allocated)

Built by `new_typecheck_bundle(rt, syntax_tree)` at
`ffi/lambda/lifecycle.mbt:27-50`. The bundle creates one `Scope` and
calls `@typecheck.build_typecheck_pipeline(rt, scope, typed_term_memo)`.

Bundle-level cells (the two registration targets):

| Field             | Type                              | Label                | Site                          |
|-------------------|-----------------------------------|----------------------|-------------------------------|
| `typed_term_memo` | `@cells.Memo[TypedTerm]`          | `lambda-typed-term`  | lifecycle.mbt:32, label at :34 |
| `output`          | `@incr.Derived[ModuleTypeResult]` | `typecheck_pipeline` | typecheck.mbt:99, label at :115 |

`build_typecheck_pipeline_internal` (typecheck.mbt:91-117) constructs
the top-level pipeline on `parent_scope`. When `output` is primed,
`rebuild_chain` allocates a dynamic child scope
(`parent_scope.child()`) and stores it in `PipelineState`; later
structural changes dispose and replace that child scope. The per-def
cells live inside this dynamic `chain_scope` (labels
`def_term_{name}`, `resolve_{name}`, `env_{name}`, `type_{name}`;
body cells `body_term`, `resolve_body`, `body_type`). Today canopy
uses `build_typecheck_pipeline` (no index); the loom example uses
`_with_index` which adds `typecheck_index` (MemoMap) +
`typecheck_diags` Derived — that variant is the unimplemented
"TypecheckIndex + hover" item.

After `output` is built, the bundle runs the two-step GC anchor
(per the **incr** skill):

- `observer = scope.add_observer(output.observe())` at lifecycle.mbt:37.
- `let _prime = observer.get()` at lifecycle.mbt:48 — populates
  `gc_dependencies` before any `gc()` cycle could run. Shipped in PR
  #339 (commit `5fbf3bb`).

This is the **only** persistent Observer in the whole lambda editor
construction today. Every other cell is reachable solely via
struct-field retention plus dep-graph BFS from this one root, or via
transient observers per call.

### 2.5 Total cell counts

Per-editor (no defs): ~16 cells. Per-editor (10 defs): ~46 cells.
Persistent Observers: **1** (on `TypecheckBundle.output`). The contract's
§4 protected-surface count for Lambda + FFI is 10 cells — the seven
parser/projection cells + 2 companion cells + 1 FFI typecheck output.

---

## 3. Scope ownership graph

Today the Lambda FFI owns exactly **one root `@incr.Scope` per editor**
in `TypecheckBundle`. The typecheck pipeline also owns dynamic child
scopes beneath that root. The editor itself does not own a `Scope`.

### 3.1 Scope inventory

- `TypecheckBundle.scope` (lifecycle.mbt:31). Parent:
  `editor.parser_runtime()`. Owns: the persistent `Observer`
  (lifecycle.mbt:37), the `typed_term_memo` (lifecycle.mbt:32), and
  the top-level `typecheck_pipeline` derived that
  `build_typecheck_pipeline` builds against `parent_scope` at
  typecheck.mbt:99. Dispose is the only published lifecycle action —
  called from `destroy_editor` (lifecycle.mbt:110).
- Dynamic typecheck child scopes. `rebuild_chain` creates a
  `parent_scope.child()` and stores it in `PipelineState` as the
  current `chain_scope`; subsequent structural changes replace it.
  These scopes are typecheck-owned, not editor-owned.
- *(no editor-owned Scope in the editor stack)*

### 3.2 Cells with no Scope

These cells are reachable only through struct-field references and
the dep-graph BFS from `TypecheckBundle.observer`:

- Parser-internal: 1 Signal + 5 Derived. The typecheck observer pins
  only the dependency cone it actually reads:
  `output` → `typed_term_memo` → `syntax_view` → `snapshot_signal`.
  Sibling parser deriveds (`snapshot_view`, `source_view`,
  `ast_view`, `diagnostics_view`) are not dependencies of
  `syntax_view`; an explicit `gc()` can still sweep them unless a
  future coordinator/editor scope roots them separately.
- `cached_proj_node` / `registry_memo` / `source_map_memo` (3
  Derived in SyncEditor). **NOT reachable from typecheck**. Today
  they survive because no `gc()` is ever called in the running
  app (no Effects → no gc trigger → no sweep). The probe
  (gate1_runtime_safety_wbtest.mbt) demonstrated that calling
  `rt.gc()` explicitly on a shared-runtime configuration sweeps
  these immediately.
- `companion.proj_memo` (`Memo`) and `companion.escalation_memo`
  (`Derived`). Same status.
- `eval_memo` (local var). Reachable from `escalation_memo`'s dep
  edge only.

### 3.3 Parent-scope candidates

Two candidate parent-scope roots for a future
`SyncEditor.lifetime_scope`:

- **`editor.parser.runtime()`** — the obvious anchor. Parented to
  the Parser's Runtime. Disposing the scope (on `destroy_editor`)
  would tear down children before the Parser/Runtime are dropped.
- **A coordinator-owned scope** — if the workspace coordinator
  becomes the shared-runtime owner, the editor's `lifetime_scope`
  parents to a coordinator-level scope, not directly to the
  Runtime. This is what `coordinator.register_editor` would do
  in the contract's §6 mechanism.

The cell-creation sites (§2) all currently pass `rt` directly (not a
`Scope`) to `@incr.Memo::new_memo` / `@incr.Derived::Derived`. To
move those constructions onto a scope, every call site has to
forward a `parent_scope` value or call `scope.memo` / `scope.derived`
instead. This is the §P0b "thread a scope through ~12 sites" surface
the brainstorm flagged.

### 3.4 Dispose chain today

Single chain, single entry:

```
destroy_editor(handle)
  → h.typecheck.scope.dispose()        // disposes: typed_term_memo + pipeline cells + observer
  → lambda_handles.remove(handle)       // editor + companion lose their owner reference
  → view_states.remove(handle)
  → pretty_view_states.remove(handle)
  → if last_created_handle == Some(handle): last_created_handle.val = None
```

The editor's own cells (Parser-internal, projection, eval) have no
dispose hook. They become unreachable when the handle is dropped,
which sufficies as long as the Runtime is owned only by that Parser
(today's invariant). Under a shared Runtime, this no longer holds —
sweeping them out becomes the coordinator's responsibility.

---

## 4. Destroy flow today

### 4.1 The function

`destroy_editor(handle: Int)` at `ffi/lambda/lifecycle.mbt:108-119`.

```
pub fn destroy_editor(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.typecheck.scope.dispose()
    None => ()
  }
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}
```

Behavior:

- Unknown handle is a safe no-op (the test
  `destroy_editor_wbtest.mbt:37` pins this).
- The `view_states` and `pretty_view_states` maps are FFI-scoped state
  for incremental view-patch updates (per-editor). Both are defined in
  other FFI files (`ffi/lambda/view.mbt` and `ffi/lambda/pretty.mbt`,
  not read in this grounding session — they hold no reactive cells).

What this does NOT do today:

- Drop the editor's Runtime explicitly. The Runtime is owned by
  `editor.parser`; dropping the editor reference (via map removal)
  drops the Parser, which drops the Runtime. Under a private-runtime
  invariant, this is safe.
- Notify any other editor. No cross-editor invariant exists today.
- Run `Runtime::gc()`. Today nothing runs gc.
- Audit cell leaks.

### 4.2 Callers of `destroy_editor`

Production: only the FFI export itself (used externally from JS via
the FFI surface). No internal MoonBit caller.

Tests: `ffi/lambda/canopy_test.mbt:87, 101, 113` and
`ffi/lambda/destroy_editor_wbtest.mbt:26, 40, 48, 56`. Pattern:
construct via `create_editor` → mutate → call `destroy_editor` → check
handle state.

### 4.3 Sister editor destroy paths

- `ffi/markdown/markdown_ffi.mbt:25-28` — `destroy_markdown_editor`:
  removes from `markdown_editors` map and `markdown_view_states` map.
  No typecheck, no Scope dispose.
- `ffi/json/json_ffi.mbt:28-31` — `destroy_json_editor`: same shape,
  no typecheck.

These do *not* dispose any Scope today because they own none. Under
the coordinator design, all three destroy paths would need a unified
shape that calls `coord.destroy_editor(handle)`.

### 4.4 Atomic-boundary observation

Today, destroy is one step (the dispose) followed by bookkeeping. The
coordinator design needs destroy to be three sequential steps with a
"can-destroy" gateway (Decision A: refuse destroy while workspace
deps reference the editor). The current call site at lifecycle.mbt:108
does not return a status — it is `Unit`-returning, and callers (FFI
consumers) cannot observe a refusal today.

---

## 5. Atomic-boundary candidates with tradeoffs

Where could a single "commit point" for the editor-creation transaction
live? The contract's mechanism-1 (typed checked-read API) and §6
(coordinator-owned dep-graph registry + lifecycle gateway) both
require that the coordinator be handed a complete, fully-constructed
editor + protected-cell-set in a single registration call. The
question is *which* function performs the prior assembly.

Five candidate locations, in order of widening blast radius:

### 5.1 Candidate A — FFI-internal `assemble_lambda_handle` helper

A private helper in `ffi/lambda/` doing the 5-step sequence
duplicated in `create_editor` / `create_editor_with_undo`. Both
ctors call it; helper is the single atomic boundary for the FFI
path. Smallest diff; eliminates Codex r4 #6 duplication. Doesn't
generalize to Markdown/JSON (different FFI files, no typecheck) and
can't house an editor-owned `lifetime_scope` because
`new_lambda_editor` has already returned by the time the helper
runs.

### 5.2 Candidate B — `new_lambda_editor` returns a 3-tuple

Make `new_lambda_editor` itself construct `TypecheckBundle` and
return `(editor, companion, typecheck)`. Single atomic boundary at
the language-companion layer. Typecheck is logically a Lambda
concept. But: typecheck lives in
`loom/examples/lambda/src/typecheck/` — pulling it into
`lang/lambda/companion/` either requires moving the package or
inverting the current loom-canopy dep direction (verify before
proposing). Changes the public ctor signature broadly across 23
non-FFI callers. The legacy-shim alternative reintroduces the very
split Codex r4 #6 warned against — so this candidate effectively
forces all callers to migrate.

### 5.3 Candidate C — generalize `SyncEditor::new_generic`

Extend `build_memos` to return a bundle of language-specific extras
(companion + typecheck). Framework-layer atomic boundary; one
registration call site for all languages. Couples the generic editor
framework to Lambda-specific concepts (companions are Lambda-only;
typecheck is Lambda-only). Likely the wrong factoring direction —
pushes language-specifics up into framework.

### 5.4 Candidate D — separate `LambdaEditorBundle` type

A new struct `LambdaEditor { editor, companion, typecheck }` in a
new package; FFI stores `Map[Int, LambdaEditor]` in place of
`Map[Int, LambdaHandle]`. Gives a clean home for `lifetime_scope`
ownership; bundle constructor is the atomic boundary. Cost: another
package + another type, with dep-graph implications (depends on
companion + typecheck) and possibly a cycle to resolve. Touches at
least: 1 new package, lifecycle.mbt, undo.mbt, destroy_editor /
view tests.

### 5.5 Candidate E — coordinator-driven atomic ctor

`coordinator.create_lambda_editor(agent_id, ...)` is the single
public entry point; coordinator constructs editor + projection +
typecheck, wires `lifetime_scope`, commits via `register_editor`.
Coordinator invariants (singleton Runtime, lifecycle registry,
on_change multiplexer) enforced from step zero. Largest blast
radius: contract §7.1's "200+ raw call sites" migration, collapsed
by `_legacy` wrapper to ~10 deliberate-touch sites + mechanical
test updates.

### 5.6 Notes on Codex r4 finding #6

Codex r4 finding #6 in the 2026-05-24 brainstorm was that splitting
the atomic boundary across two functions (e.g. editor-construction
in `new_lambda_editor` and typecheck-construction in
`new_typecheck_bundle`, both called from the FFI ctor) is brittle
under §P0b: the coordinator needs registration to happen as part of
a single sequence whose intermediate states are not observable. The
current FFI pattern violates this in two ways:

1. Between `new_lambda_editor` returning and `new_typecheck_bundle`
   being called, the editor exists with its 7 generic Memos
   unrooted — no `gc()` is dangerous, but no `gc()` happens.
2. The two FFI ctors (`create_editor` + `create_editor_with_undo`)
   are independent functions, so any future `coord.register_editor`
   call has to be inserted at two sites.

Codex r5 invalidated an r4 attempt to split mechanism-1 into
`register_dep` (eager) plus `read_protected` (lazy). r5's reasoning:
the atomic boundary must include typecheck, because typecheck is one
of the protected cells, so a coordinator that registers the editor
*before* typecheck exists has nothing to register. This is the
"atomic-boundary-location" question the post-grounding session must
answer — likely by choosing one of candidates A-E.

---

## 6. Constraints the eventual coordinator must respect

Enumerated from observed call flow + loom internals. None of these are
flexible.

### 6.1 `Runtime::set_on_change` is single-occupancy

At `loom/incr/cells/runtime.mbt:451-453`, `set_on_change` writes to a
`mut Option` slot — second registrar overwrites the first. Verified
by `workspace/probe/gate1_runtime_safety_wbtest.mbt` §A. Coordinator
must own the single slot and multiplex internally; no editor may
install its own. Today no editor calls `set_on_change`;
`on_status_change` is a separate `SyncStatus` signal independent of
`Runtime::on_change`.

### 6.2 `Runtime::gc()` semantics

Synchronous mark+sweep starting from `gc_root_counts` (Observer-pinned
cells). Post-sweep drains pending broadcast events
(runtime.mbt:564-568), so full settled state needs two `gc()` passes.
Mechanism 4's `audit_leaks()` cadence must respect this. Implicit
pins via `gc_role = Root` (Effects); production canopy creates zero
Effects in the editor stack (grep 2026-05-23). All Memos are
`gc_role = Interior` and depend on explicit Observer rooting.

### 6.3 Single-threaded MoonBit runtime

No concurrent editor construction today. Coordinator atomic-commit
can stay non-locking; "single-threaded coord" assumption is
load-bearing for keeping the design simple.

### 6.4 Parser owns its Runtime today

`Parser::new(source, lang, runtime?)` (parser.mbt:38-46) creates a
fresh `Runtime` when `runtime?` is omitted (line 44-46). Canopy's
`make_parser` closure does not pass `runtime~` (lambda_editor.mbt:114),
so each editor today constructs a private runtime. Sharing requires
either threading runtime through `new_lambda_editor` →
`SyncEditor::new_generic` → `make_parser` → `new_parser(..., runtime=)`,
or adding a sibling ctor entry point.

### 6.5 The protected-cell set is heterogeneous

Markdown / JSON: 7 cells (parser × 4 + projection × 3). Lambda +
companion: 9 cells. Lambda + FFI typecheck: 10. Coordinator's
protected-cell registry shape must accept any subset. Codex r4 #1
proposed erased `ProtectedRead { cell_id, prime }` for registration +
typed `ProtectedCell[T]` for read API — still on the table.

### 6.6 Persistent Observer requires priming before first `gc()`

PR #339 fix (`let _prime = observer.get()` at lifecycle.mbt:48)
established the rule: Observer alone is insufficient until the Memo
has computed once (`gc_dependencies` empty before first compute; see
`feedback-incr-gc-anchor-needs-priming`). Coordinator registration
either primes at registration time or accepts that fail-fast falls
back to first-read-after-first-gc mode. Without the loom
`gc_root_count` patch (proto worktree), registration-time mode-1
check is unimplementable.

### 6.7 Labels are set per cell at construction (12+ sites)

§2 enumerates the sites. Contract's `label_prefix` plumbing would
require touching each. Alternative: keep raw labels and have the
coordinator's diagnostic report layer compose the prefix from editor
identity at report time. Avoids the 12-site plumbing. Open question.

### 6.8 `Runtime::gc` is `pub` and reachable from any caller

Out-of-band `gc()` is convention-only (contract §11 risk #2). Hard
enforcement would require privatizing `Runtime::gc` (upstream loom
change) or removing `SyncEditor::parser_runtime` from public surface.
Both out-of-scope for §P0b Phase 1. Mitigation: code review + lint
backstop.

### 6.9 The typecheck pipeline's interior is loom-example code

`build_typecheck_pipeline` lives at
`loom/examples/lambda/src/typecheck/typecheck.mbt:76` — loom-example
code consumed by canopy via the loom submodule. Interior cells
(per-def `resolve_*` / `env_*` / `type_*`) are loom-owned and not
directly exposed; coordinator's protected-cell set may only refer to
`TypecheckBundle.output`.

### 6.10 `_legacy` wrapper strategy pins out candidate B

Contract §7.1 keeps `new_lambda_editor` returning its current 2-tuple
so tests/demos don't migrate atomically. The new coordinator-aware
ctor sits alongside. Excludes candidate B (changing the public return
type) unless paired with a renamed shim.

---

## 7. Open questions surfaced by grounding

Observations the post-grounding design session should resolve before
proposing API:

1. **Is the dep-edge sufficient as implicit registration?** `eval_memo`
   (§2.2) is a local variable retained only through the dep edge to
   `escalation_memo`. Contract §4 is ambiguous about whether "the
   protected surface" includes dep-BFS-reachable cells or only
   explicitly-handled ones.
2. **Label-prefix: 12-site plumbing or report-time composition?** §6.7.
   Either is compatible with Decision B.
3. **Where would `LambdaEditorBundle` live (candidate D)?** §5.4 —
   would invert the loom/canopy dep direction; pre-design check.
4. **Per-language factory parameter or per-language coordinator
   ctors (candidate E)?** §5.5. Trade-off between coordinator
   language-agnosticism and registration-API complexity.
5. **Symmetric or non-symmetric `lifetime_scope` across Markdown /
   JSON / Lambda?** §4.3. Symmetry simplifies the destroy gateway;
   non-symmetry minimizes diff.

## 8. Reading order for next session

1. §1.1-1.3 — construction sequence.
2. §2 — cell inventory + 1-observer fact.
3. §3 — current scope ownership (or lack of it).
4. §5 candidates A-E — choose first, then sketch.
5. §6 — treat as inviolable; observed facts of current code.
6. §7 — cross-reference before sketching anything API-shaped.

Any prototype artifacts from scratch worktrees are intentionally omitted
from this document. Reconstruct future sketches from the tracked
research docs below and the source files listed here.

## 9. References

Source files traced: `lang/lambda/companion/lambda_editor.mbt`,
`editor/sync_editor.mbt` + `editor/sync_editor_parser.mbt`,
`ffi/lambda/lifecycle.mbt` + `ffi/lambda/undo.mbt`,
`lang/lambda/flat/projection_memo.mbt`,
`lang/lambda/eval/eval_memo.mbt` + `.../batch_escalation.mbt`,
`lang/markdown/companion/markdown_companion.mbt`,
`lang/json/companion/json_companion.mbt`,
`ffi/markdown/markdown_ffi.mbt` + `ffi/json/json_ffi.mbt`,
`loom/loom/src/pipeline/parser.mbt` + `loom/loom/src/factories.mbt`,
`loom/incr/cells/runtime.mbt:451-460`,
`loom/examples/lambda/src/typed_parser.mbt` +
`loom/examples/lambda/src/typecheck/typecheck.mbt:76-220`,
`workspace/probe/gate1_runtime_safety_wbtest.mbt:1-80`.

Related research: `docs/research/2026-05-22-spec-aware-workspace.md`;
`docs/research/2026-05-23-observer-discipline-contract.md`;
`docs/research/2026-05-23-runtime-safety-decision.md`.
