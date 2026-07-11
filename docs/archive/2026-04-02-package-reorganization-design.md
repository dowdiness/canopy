# Package Reorganization — Rabbita-style

## Why

The Canopy project's package structure has grown organically and diverges from
MoonBit community conventions (as exemplified by rabbita). Specific pain points:

- **No public MoonBit API.** The root package is a JS FFI dumping ground. MoonBit
  consumers have no clean entry point.
- **Unnecessary nesting.** `framework/core/` and `framework/protocol/` are the
  only things inside `framework/`, adding an import layer with no benefit.
- **`projection/` is a lambda-specific facade.** It re-exports types from
  `lang/lambda/proj` and `lang/lambda/edits`, coupling a supposedly generic
  package to one language. Adding JSON/Markdown editors makes this worse.
- **No language facades.** Consumers must import 3-4 sub-packages per language
  (`proj`, `edits`, `flat`, `zipper`) instead of one unified entry.

## Scope

In:
- `framework/core/` → `core/`
- `framework/protocol/` → `protocol/`
- `projection/` (remove lambda re-exports)
- `lang/lambda/` (new facade)
- `lang/json/` (new facade)
- `ffi/` (new, JS FFI entry)
- Root `moon.pkg` and new `top.mbt`
- All `moon.pkg` files that reference moved packages

Out:
- `editor/` internals (deferred)
- Submodule reorganization (external repos)
- `alga/`, `cmd/main/`, `lib/text-change/` (unchanged)

## Current State

```
root/                        — JS FFI (canopy_*.mbt, 58 link exports)
framework/core/              — ProjNode, NodeId, SourceMap
framework/protocol/          — ViewPatch, ViewNode, UserIntent
editor/                      — SyncEditor, EphemeralHub
projection/                  — Lambda facade + TreeEditorState
relay/                       — RelayRoom
lang/lambda/proj/            — FlatProj, syntax_to_proj_node
lang/lambda/flat/            — VersionedFlatProj
lang/lambda/edits/           — TreeEditOp, actions
lang/lambda/zipper/          — Zipper navigation
lang/json/proj/              — JSON projection
lang/json/edits/             — JSON edit ops
```

Dependency tiers:
1. Foundation: `framework/core` (8+ consumers), `framework/protocol` (1 consumer)
2. Language: `lang/lambda/*`, `lang/json/*`
3. Coordination: `projection` (facade), `editor` (composition)
4. Entry: root (JS FFI), `cmd/main` (CLI)

## Desired State

```
root/                        — Public MoonBit API (top.mbt with pub using)
core/                        ← framework/core/
protocol/                    ← framework/protocol/
editor/                      — (unchanged)
projection/                  — Language-agnostic (TreeEditorState, reconcile, traits)
relay/                       — (unchanged)
lang/lambda/                 — Lambda facade (pub using from sub-packages)
  lang/lambda/proj/
  lang/lambda/flat/
  lang/lambda/edits/
  lang/lambda/zipper/
lang/json/                   — JSON facade (pub using from sub-packages)
  lang/json/proj/
  lang/json/edits/
ffi/                         — JS FFI (canopy_*.mbt + link exports)
cmd/main/                    — (unchanged)
```

Layering:
```
MoonBit consumers → root top.mbt
JS consumers     → ffi/
                     ↓
               editor / projection
                     ↓
            lang/lambda / lang/json (facades)
                     ↓
              core / protocol
                     ↓
         loom / seam / event-graph-walker
```

## Steps

### Phase 1: `framework/core/` → `core/`

1. `git mv framework/core/ core/`
2. Update `moon.pkg` in 8 consumer packages: change
   `dowdiness/canopy/framework/core` → `dowdiness/canopy/core`
   - `projection/moon.pkg`
   - `lang/lambda/proj/moon.pkg`
   - `lang/lambda/edits/moon.pkg`
   - `lang/lambda/zipper/moon.pkg`
   - `lang/json/proj/moon.pkg`
   - `lang/json/edits/moon.pkg`
   - `framework/protocol/moon.pkg`
   - `moon.pkg` (root)
3. `moon check && moon test`

### Phase 2: `framework/protocol/` → `protocol/`

1. `git mv framework/protocol/ protocol/`
2. Update `protocol/moon.pkg`: its import of `framework/core` → `core`
   (should already be done in Phase 1, verify)
3. Update `editor/moon.pkg`: change `dowdiness/canopy/framework/protocol`
   → `dowdiness/canopy/protocol`
4. Delete empty `framework/` directory
5. `moon check && moon test`

### Phase 3: Create `lang/lambda/` facade

1. Create `lang/lambda/moon.pkg` importing:
   - `dowdiness/canopy/lang/lambda/proj`
   - `dowdiness/canopy/lang/lambda/edits`
   - `dowdiness/canopy/lang/lambda/flat`
   - `dowdiness/canopy/lang/lambda/zipper`
   - `dowdiness/canopy/core`
2. Create `lang/lambda/top.mbt` with `pub using` re-exports:
   - From `@lambda_proj`: `FlatProj`, `syntax_to_proj_node`, `to_proj_node`,
     `parse_to_proj_node`, `rebuild_kind`, `to_flat_proj`,
     `to_flat_proj_incremental`, `reconcile_flat_proj`, `print_flat_proj`,
     `populate_token_spans`
   - From `@lambda_edits`: `TreeEditOp`, `EditContext`, `SpanEdit`,
     `EditResult`, `FocusHint`, `DropPosition`, `ActionGroup`, `Action`,
     `NodeContext`, `BindingSite`, `compute_text_edit`,
     `get_actions_for_node`, `resolve_binder`, `find_usages`,
     `find_binding_for_init`, `collect_lam_env`, `free_vars`
   - From `@lambda_flat`: `VersionedFlatProj`
3. `moon check && moon test`

### Phase 4: Create `lang/json/` facade

1. Create `lang/json/moon.pkg` importing:
   - `dowdiness/canopy/lang/json/proj`
   - `dowdiness/canopy/lang/json/edits`
2. Create `lang/json/top.mbt` with `pub using` re-exports:
   - From `@json_proj`: `parse_to_proj_node`, `syntax_to_proj_node`,
     `populate_token_spans`, `build_json_projection_memos`
   - From `@json_edits`: `JsonEditOp`, `JsonType`, `apply_json_edit`,
     `compute_json_edit`, `new_json_editor`
3. `moon check && moon test`

### Phase 5: Make `projection/` language-agnostic

1. Remove lambda-specific `pub using` statements from:
   - `projection/types.mbt` (remove TreeEditOp, EditContext, etc. re-exports)
   - `projection/proj_node.mbt` (remove syntax_to_proj_node, etc. re-exports)
   - `projection/flat_proj.mbt` (remove FlatProj, etc. re-exports)
   - `projection/source_map.mbt` (remove populate_token_spans re-export)
2. Move `projection/reconcile_ast.mbt` → `lang/lambda/reconcile_ast.mbt`
   (it's a backward-compat wrapper using `@ast.Term`, belongs in lambda facade)
3. Keep language-agnostic re-exports:
   - From `@core`: `ProjNode`, `NodeId`, `SourceMap`, `reconcile`,
     `collect_registry`
   - From `@loomcore`: traits `TreeNode`, `Renderable`
4. Remove `lang/lambda/proj`, `lang/lambda/edits`, `lambda/ast`, and
   `lambda` parser imports from `projection/moon.pkg`
5. Move lambda/parser test imports to `for "test"` section in
   `projection/moon.pkg` (test files still use `@ast.Term` as a concrete
   type parameter)
6. Update `editor/moon.pkg` to add import of `lang/lambda` facade
   for lambda-specific types it used via `@proj`
7. Update all `@proj.TreeEditOp` etc. references in `editor/*.mbt` to use
   the new lambda import alias
8. `moon check && moon test`

### Phase 6: Move FFI to `ffi/`

1. Verify MoonBit supports `link` exports in non-root packages by creating
   a minimal test. If unsupported, skip this phase — FFI stays at root
   alongside `top.mbt`.
2. `mkdir ffi && git mv canopy_lambda.mbt canopy_json.mbt canopy_view.mbt canopy_sync.mbt canopy_ephemeral.mbt canopy_test.mbt integration_ws_test.mbt ffi/`
3. Create `ffi/moon.pkg` with:
   - All imports currently in root `moon.pkg`
   - All 58 link exports moved from root `moon.pkg`
4. Strip imports and link exports from root `moon.pkg`
5. Update Vite/build config if it references root build output paths
6. `moon check && moon test`
7. `cd examples/web && npm run build` (verify JS build)

### Phase 7: Add `top.mbt` at root

1. Create `top.mbt` with `pub using` re-exports:
   ```moonbit
   pub using @editor { type SyncEditor, type ViewUpdateState }
   pub using @core { type ProjNode, type NodeId, type SourceMap }
   pub using @projection { type TreeEditorState }
   pub using @relay { type RelayRoom }
   pub using @protocol { type ViewPatch, type ViewNode }
   ```
2. Update root `moon.pkg` to import `editor`, `core`, `projection`,
   `relay`, `protocol` (only what's needed for re-exports)
3. `moon check && moon test`

## Acceptance Criteria

- [ ] No `framework/` directory exists
- [ ] `core/` and `protocol/` are top-level packages
- [ ] `projection/` has zero lambda-specific imports or re-exports
- [ ] `lang/lambda/` facade exists with `pub using` covering all types
  previously re-exported by `projection/`
- [ ] `lang/json/` facade exists with `pub using` covering JSON types
- [ ] FFI lives in `ffi/` (or at root if MoonBit doesn't support sub-package
  link exports)
- [ ] Root `top.mbt` re-exports key types for MoonBit consumers
- [ ] `moon check && moon test` passes (664+ tests)
- [ ] JS build works: `moon build --target js`
- [ ] Web dev server works: `cd examples/web && npm run build`
- [ ] AGENTS.md package map updated to reflect new structure
- [ ] All 7 phases are separate commits

## Validation

```bash
moon check
moon test
moon build --target js
cd examples/web && npm run build
```

## Risks

- **Phase 6 blocker:** MoonBit may not support `link` exports in non-root
  packages. Mitigation: test first, fall back to keeping FFI at root.
- **`pub using` with enums:** MoonBit's `pub using` makes enum types
  abstract (constructors unavailable). Known enum types in the re-export
  list: `TreeEditOp`, `FocusHint`, `DropPosition`, `ActionGroup`,
  `BindingSite`, `JsonEditOp`, `JsonType`. If consumers pattern-match
  on these, the facade re-export won't work. Mitigation: verify each
  enum's usage; for enums that need pattern matching, consumers import
  the sub-package directly instead of going through the facade.
- **`editor/` import churn in Phase 5:** editor is the largest package and
  has many references to `@proj.*` for lambda types. These all need updating
  to the new lambda import alias. Risk of missed references.
  Mitigation: `moon check` catches all type errors.
- **Vite config paths:** Moving FFI to `ffi/` changes the JS build output
  path. Vite config in `examples/web/` may need updating.
  Mitigation: verify with `npm run build` after Phase 6.

## Notes

- Inspired by [rabbita](https://github.com/moonbit-community/rabbita)
  package organization: root = public API, flat package names, `internal/`
  for private impl.
- `editor/` internal extraction (moving websocket/tree-edit-bridge to
  `internal/`) is deferred to a future task.
- The `pub using` enum limitation is documented in project memory
  (`moonbit_pub_using_semantics`).
