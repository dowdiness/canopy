# Package Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Canopy's package structure to match Rabbita conventions — flat package names, root as public API, FFI isolated, language facades.

**Architecture:** Incremental 8-task refactor. Each task is a single commit verified with `moon check && moon test`. Tasks are ordered dependency-first: rename foundation packages before touching consumers.

**Tech Stack:** MoonBit, moon build system, git

**Spec:** [docs/plans/2026-04-02-package-reorganization-design.md](2026-04-02-package-reorganization-design.md)

---

### Task 1: Move `framework/core/` → `core/`

**Files:**
- Move: `framework/core/` → `core/`
- Modify: `framework/protocol/moon.pkg`
- Modify: `projection/moon.pkg`
- Modify: `lang/lambda/proj/moon.pkg`
- Modify: `lang/lambda/edits/moon.pkg`
- Modify: `lang/lambda/zipper/moon.pkg`
- Modify: `lang/json/proj/moon.pkg`
- Modify: `lang/json/edits/moon.pkg`
- Modify: `moon.pkg` (root)

- [ ] **Step 1: Move the directory**

```bash
git mv framework/core core
```

- [ ] **Step 2: Update all 8 consumer `moon.pkg` files**

In each of these files, replace `"dowdiness/canopy/framework/core"` with `"dowdiness/canopy/core"`:

1. `framework/protocol/moon.pkg`
2. `projection/moon.pkg`
3. `lang/lambda/proj/moon.pkg`
4. `lang/lambda/edits/moon.pkg`
5. `lang/lambda/zipper/moon.pkg`
6. `lang/json/proj/moon.pkg`
7. `lang/json/edits/moon.pkg`
8. `moon.pkg` (root)

- [ ] **Step 3: Regenerate interfaces**

```bash
moon info
```

- [ ] **Step 4: Verify**

```bash
moon check && moon test
```

Expected: all 664+ tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: move framework/core/ to core/"
```

---

### Task 2: Move `framework/protocol/` → `protocol/`

**Files:**
- Move: `framework/protocol/` → `protocol/`
- Modify: `editor/moon.pkg`

- [ ] **Step 1: Move the directory**

```bash
git mv framework/protocol protocol
```

- [ ] **Step 2: Update `editor/moon.pkg`**

Replace `"dowdiness/canopy/framework/protocol"` with `"dowdiness/canopy/protocol"`.

- [ ] **Step 3: Delete empty `framework/` directory**

```bash
rmdir framework
```

If `framework/` is not empty (e.g., hidden files), investigate before deleting.

- [ ] **Step 4: Regenerate interfaces**

```bash
moon info
```

- [ ] **Step 5: Verify**

```bash
moon check && moon test
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: move framework/protocol/ to protocol/"
```

---

### Task 3: Create `lang/lambda/` facade

**Files:**
- Create: `lang/lambda/moon.pkg`
- Create: `lang/lambda/top.mbt`

- [ ] **Step 1: Create `lang/lambda/moon.pkg`**

```json
import {
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
  "dowdiness/canopy/lang/lambda/edits" @lambda_edits,
  "dowdiness/canopy/lang/lambda/flat" @lambda_flat,
  "dowdiness/canopy/lang/lambda/zipper" @lambda_zipper,
}
```

- [ ] **Step 2: Create `lang/lambda/top.mbt`**

This file re-exports all public types and functions from the lambda sub-packages. Copy the exact re-exports currently in `projection/`:

```moonbit
// Lambda language facade — unified entry point for lambda editor types.

///|
pub using @lambda_proj {
  type FlatProj,
  syntax_to_proj_node,
  to_proj_node,
  parse_to_proj_node,
  rebuild_kind,
  to_flat_proj,
  to_flat_proj_incremental,
  reconcile_flat_proj,
  print_flat_proj,
  populate_token_spans,
}

///|
pub using @lambda_edits {
  type TreeEditOp,
  type EditContext,
  type SpanEdit,
  type EditResult,
  type FocusHint,
  type DropPosition,
  type ActionGroup,
  type Action,
  type NodeContext,
  type BindingSite,
  compute_text_edit,
  get_actions_for_node,
  resolve_binder,
  find_usages,
  find_binding_for_init,
  collect_lam_env,
  free_vars,
}

///|
pub using @lambda_flat {
  type VersionedFlatProj,
}
```

Note: `SpanEdit` is defined in `core`, not `lambda_edits`. Check
whether `@lambda_edits` re-exports it. If not, remove from this list
(it will be available via `@core` or `@proj`). Run `moon check` to
verify.

- [ ] **Step 3: Verify**

```bash
moon check && moon test
```

If `moon check` reports errors about re-exported symbols, fix the
`pub using` list to match actual exports from each sub-package. Use
`moon ide doc "@lambda_edits.*"` and `moon ide doc "@lambda_proj.*"`
to discover the actual public API.

- [ ] **Step 4: Commit**

```bash
git add lang/lambda/moon.pkg lang/lambda/top.mbt
git commit -m "feat: add lang/lambda/ facade with pub using re-exports"
```

---

### Task 4: Create `lang/json/` facade

**Files:**
- Create: `lang/json/moon.pkg`
- Create: `lang/json/top.mbt`

- [ ] **Step 1: Create `lang/json/moon.pkg`**

```json
import {
  "dowdiness/canopy/lang/json/proj" @json_proj,
  "dowdiness/canopy/lang/json/edits" @json_edits,
}
```

- [ ] **Step 2: Create `lang/json/top.mbt`**

```moonbit
// JSON language facade — unified entry point for JSON editor types.

///|
pub using @json_proj {
  parse_to_proj_node,
  syntax_to_proj_node,
  populate_token_spans,
  build_json_projection_memos,
}

///|
pub using @json_edits {
  type JsonEditOp,
  type JsonType,
  apply_json_edit,
  compute_json_edit,
  new_json_editor,
}
```

Note: Verify each symbol exists in the respective package's public API.
Run `moon check` to catch mismatches.

- [ ] **Step 3: Verify**

```bash
moon check && moon test
```

- [ ] **Step 4: Commit**

```bash
git add lang/json/moon.pkg lang/json/top.mbt
git commit -m "feat: add lang/json/ facade with pub using re-exports"
```

---

### Task 5: Make `projection/` language-agnostic

This is the largest task. `projection/` currently re-exports lambda types
via `pub using`. After this task, it only re-exports language-agnostic
types from `core` and `loomcore`.

`editor/` has ~107 references to `@proj.*`. Of these, ~5 symbols stay
in `@proj` (generic: `NodeId`, `ProjNode`, `SourceMap`,
`collect_registry`, `Renderable`) and ~10 symbols move to the new
`@lambda` import alias.

**Files:**
- Modify: `projection/types.mbt` (remove lambda re-exports)
- Modify: `projection/proj_node.mbt` (remove lambda re-exports)
- Modify: `projection/flat_proj.mbt` (remove lambda re-exports)
- Modify: `projection/source_map.mbt` (remove lambda re-exports)
- Move: `projection/reconcile_ast.mbt` → `lang/lambda/reconcile_ast.mbt`
- Modify: `projection/moon.pkg` (remove lambda imports, keep @ast/@parser for tests)
- Modify: `lang/lambda/flat/moon.pkg` (change @proj → @lambda_proj)
- Modify: `editor/moon.pkg` (add lang/lambda facade import)
- Modify: 9 editor `.mbt` files (change `@proj.X` → `@lambda.X` for lambda-specific symbols)

- [ ] **Step 1: Remove lambda re-exports from `projection/types.mbt`**

Replace the entire file with:

```moonbit
// Re-export types from core for backward compatibility.

///|
using @loomcore {type Range}

///|
pub using @core {type NodeId}
```

- [ ] **Step 2: Remove lambda re-exports from `projection/proj_node.mbt`**

Replace the entire file with:

```moonbit
// Re-exports so @proj.ProjNode continues to work.

///|
pub using @core {type ProjNode, collect_registry}
```

- [ ] **Step 3: Remove lambda re-exports from `projection/flat_proj.mbt`**

Delete this file entirely — it only contained lambda re-exports:

```bash
git rm projection/flat_proj.mbt
```

- [ ] **Step 4: Remove lambda re-exports from `projection/source_map.mbt`**

Replace the entire file with:

```moonbit
// Re-exports so @proj.SourceMap continues to work.

///|
pub using @core {type SourceMap}
```

- [ ] **Step 5: Move `projection/reconcile_ast.mbt` to lambda facade**

```bash
git mv projection/reconcile_ast.mbt lang/lambda/reconcile_ast.mbt
```

Update `lang/lambda/moon.pkg` to add the `@core` import if not already
present (it should be from Task 3). The `reconcile_ast` function uses
`ProjNode[@ast.Term]`, so `lang/lambda/moon.pkg` also needs:

```
"dowdiness/lambda/ast" @ast,
```

Add this import to `lang/lambda/moon.pkg`.

- [ ] **Step 6: Update `projection/moon.pkg`**

Remove `@lambda_edits`, `@lambda_proj` from main imports.
Move `@parser` and `@ast` to test-only imports (test files still use
`@ast.Term` as a concrete type parameter). Remove `@seam` if only
used by test files (check with `grep -r '@seam' projection/*.mbt`
excluding test files).

New `projection/moon.pkg`:

```
import {
  "dowdiness/canopy/core" @core,
  "dowdiness/loom/core" @loomcore,
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/cmp",
  "moonbitlang/core/immut/hashset" @immut/hashset,
}

import {
  "dowdiness/lambda" @parser,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/seam" @seam,
} for "test"

warnings = "-2-6-29"

options(
  is_main: false,
)
```

Run `moon check` immediately after this change. If test files reference
`@parser`/`@ast`/`@seam` outside of `*_test.mbt`/`*_wbtest.mbt` files
(e.g., in benchmark files), move those imports back to the main section
or add `for "bench"`. Adjust until `moon check` passes.

- [ ] **Step 7: Update `lang/lambda/flat/moon.pkg`**

This package currently imports `@proj` (projection) for `FlatProj` and
related types. Since `FlatProj` is no longer in projection, change to
import `lang/lambda/proj` directly:

```
import {
  "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
  "dowdiness/incr" @incr,
}

options(
  is_main: false,
)
```

Then update all `@proj.` references in `lang/lambda/flat/*.mbt` to
`@lambda_proj.`. Use find-and-replace:

```bash
grep -rn '@proj\.' lang/lambda/flat/
```

Replace each `@proj.FlatProj` with `@lambda_proj.FlatProj`, etc.
Run `moon check` to verify.

- [ ] **Step 8: Update `editor/moon.pkg` imports**

Add the facade import and remove the now-redundant direct sub-package
import:

1. Add: `"dowdiness/canopy/lang/lambda" @lambda,`
2. Remove: `"dowdiness/canopy/lang/lambda/flat" @lambda_flat,`

Then update any `@lambda_flat.` references in `editor/*.mbt` to
`@lambda.` (e.g., `@lambda_flat.VersionedFlatProj` →
`@lambda.VersionedFlatProj`).

```bash
grep -rn '@lambda_flat\.' editor/
```

- [ ] **Step 9: Update `@proj.X` → `@lambda.X` in editor files**

The following symbols must change from `@proj.` to `@lambda.`:

| Symbol | New qualifier |
|--------|---------------|
| `FlatProj` | `@lambda.FlatProj` |
| `TreeEditOp` | `@lambda.TreeEditOp` |
| `EditContext` | `@lambda.EditContext` |
| `FocusHint` | `@lambda.FocusHint` |
| `DropPosition` | `@lambda.DropPosition` |
| `to_flat_proj` | `@lambda.to_flat_proj` |
| `to_flat_proj_incremental` | `@lambda.to_flat_proj_incremental` |
| `reconcile_flat_proj` | `@lambda.reconcile_flat_proj` |
| `populate_token_spans` | `@lambda.populate_token_spans` |
| `compute_text_edit` | `@lambda.compute_text_edit` |

These symbols STAY as `@proj.`:
- `NodeId`, `ProjNode`, `SourceMap`, `collect_registry`, `Renderable`

Files to update (9 files, ~60+ replacements):
1. `editor/errors.mbt` — `NodeId` stays as `@proj.NodeId` (generic)
2. `editor/projection_memo.mbt` — heaviest: `FlatProj`, `to_flat_proj`,
   `to_flat_proj_incremental`, `reconcile_flat_proj`,
   `populate_token_spans` → `@lambda.*`; `ProjNode`, `SourceMap`,
   `NodeId` stay `@proj.*`
3. `editor/sync_editor.mbt` — `FlatProj` → `@lambda.`; `ProjNode`,
   `SourceMap` stay
4. `editor/sync_editor_test.mbt` — `ProjNode` stays
5. `editor/sync_editor_tree_edit.mbt` — `TreeEditOp`, `DropPosition`,
   `Renderable`, `compute_text_edit` → check each; `Renderable` stays
6. `editor/sync_editor_tree_edit_wbtest.mbt` — `DropPosition` →
   `@lambda.`
7. `editor/tree_edit_bridge.mbt` — `TreeEditOp`, `EditContext`,
   `FocusHint`, `compute_text_edit` → `@lambda.*`
8. `editor/tree_edit_json.mbt` — all `TreeEditOp` references →
   `@lambda.TreeEditOp`
9. `editor/view_updater.mbt` — check each reference

Strategy: Use `grep -rn '@proj\.' editor/` to find all references.
For each reference, check if the symbol is in the "stays" list or the
"moves" list above. Replace accordingly. Then run `moon check`.

- [ ] **Step 10: Regenerate interfaces**

```bash
moon info && moon fmt
```

- [ ] **Step 11: Verify**

```bash
moon check && moon test
```

- [ ] **Step 12: Commit**

```bash
git add -A && git commit -m "refactor: make projection/ language-agnostic, lambda types to lang/lambda/"
```

---

### Task 6: Move FFI to `ffi/`

**Files:**
- Move: `canopy_lambda.mbt`, `canopy_json.mbt`, `canopy_view.mbt`,
  `canopy_sync.mbt`, `canopy_ephemeral.mbt`, `canopy_test.mbt`,
  `integration_ws_test.mbt` → `ffi/`
- Create: `ffi/moon.pkg`
- Modify: `moon.pkg` (root — strip FFI imports and link exports)
- Modify: `examples/web/vite.config.ts` (update JS output path)

- [ ] **Step 1: Verify MoonBit supports link exports in non-root packages**

Create a minimal test:

```bash
mkdir -p /tmp/moonbit-link-test/src
cat > /tmp/moonbit-link-test/moon.mod.json << 'EOF'
{"name": "test/link", "version": "0.0.1"}
EOF
cat > /tmp/moonbit-link-test/moon.pkg << 'EOF'
{}
EOF
cat > /tmp/moonbit-link-test/src/moon.pkg << 'EOF'
options(link: {"js": {"exports": ["hello"]}})
EOF
cat > /tmp/moonbit-link-test/src/main.mbt << 'EOF'
pub fn hello() -> String { "hello" }
EOF
cd /tmp/moonbit-link-test && moon build --target js 2>&1
```

If this succeeds and produces a JS file with the `hello` export under
`_build/js/...`, proceed. If it fails, **skip this entire task** — FFI
stays at root alongside `top.mbt`.

- [ ] **Step 2: Move FFI files**

```bash
mkdir ffi
git mv canopy_lambda.mbt ffi/
git mv canopy_json.mbt ffi/
git mv canopy_view.mbt ffi/
git mv canopy_sync.mbt ffi/
git mv canopy_ephemeral.mbt ffi/
git mv canopy_test.mbt ffi/
git mv integration_ws_test.mbt ffi/
```

- [ ] **Step 3: Create `ffi/moon.pkg`**

Copy the imports and link exports from root `moon.pkg`:

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/json/edits" @json_edits,
  "dowdiness/canopy/relay",
  "dowdiness/json" @djson,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/event-graph-walker/text",
  "moonbitlang/core/buffer",
  "moonbitlang/core/json",
  "moonbitlang/core/string",
}

options(
  link: {
    "js": {
      "exports": [
        "create_editor",
        "destroy_editor",
        "get_text",
        "set_text",
        "get_ast_dot_resolved",
        "get_ast_pretty",
        "get_errors_json",
        "export_all_json",
        "export_since_json",
        "apply_sync_json",
        "get_version_json",
        "create_editor_with_undo",
        "insert_and_record",
        "delete_and_record",
        "backspace_and_record",
        "set_text_and_record",
        "undo_manager_undo",
        "undo_manager_redo",
        "undo_manager_can_undo",
        "undo_manager_can_redo",
        "undo_manager_set_tracking",
        "undo_manager_clear",
        "ephemeral_encode_all",
        "ephemeral_apply",
        "ephemeral_set_presence",
        "ephemeral_set_presence_with_selection",
        "ephemeral_delete_presence",
        "ephemeral_remove_outdated",
        "ephemeral_get_peer_cursors_json",
        "get_proj_node_json",
        "get_source_map_json",
        "apply_tree_edit_json",
        "insert_at",
        "delete_at",
        "undo_and_export_json",
        "redo_and_export_json",
        "relay_on_connect",
        "relay_on_message",
        "relay_on_disconnect",
        "ws_on_open",
        "ws_on_message",
        "ws_on_close",
        "ws_broadcast_edit",
        "ws_broadcast_cursor",
        "create_json_editor",
        "destroy_json_editor",
        "json_get_text",
        "json_set_text",
        "json_get_errors",
        "json_get_proj_node_json",
        "json_get_source_map_json",
        "json_apply_edit",
        "get_view_tree_json",
        "compute_view_patches_json",
        "json_get_view_tree_json",
        "json_compute_view_patches_json",
        "handle_text_intent",
        "handle_undo",
        "handle_redo",
        "handle_structural_intent",
      ],
    },
  },
)
```

- [ ] **Step 4: Strip FFI concerns from root `moon.pkg`**

Replace root `moon.pkg` with minimal content (no imports, no link
exports — those are now in `ffi/moon.pkg`):

```
{}
```

This will be populated with `pub using` imports in Task 7.

- [ ] **Step 5: Verify MoonBit build**

```bash
moon check && moon test
```

- [ ] **Step 6: Find the new JS output path**

```bash
find _build/js -name '*.js' | head -20
```

The FFI JS output will be at a new path like
`_build/js/release/build/ffi/ffi.js` instead of
`_build/js/release/build/canopy.js`. Note the exact path.

- [ ] **Step 7: Update `examples/web/vite.config.ts`**

Change the `canopy.js` output path in the `moonbitPlugin` modules
config. The exact change depends on Step 6 output. Replace the old
path (e.g., `_build/js/release/build/canopy.js`) with the new one
(e.g., `_build/js/release/build/ffi/ffi.js`).

- [ ] **Step 8: Verify web build**

```bash
moon build --target js --release
cd examples/web && npm run build
```

If the web build fails, check the Vite config path. The JS entry file
name may differ.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "refactor: move JS FFI to ffi/ package"
```

---

### Task 7: Add `top.mbt` at root

**Files:**
- Create: `top.mbt`
- Modify: `moon.pkg` (root — add imports for re-exports)

- [ ] **Step 1: Update root `moon.pkg`**

Add imports for the packages whose types we want to re-export:

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/projection" @proj,
  "dowdiness/canopy/protocol" @protocol,
  "dowdiness/canopy/relay",
}
```

- [ ] **Step 2: Create `top.mbt`**

```moonbit
// Canopy public API — import `dowdiness/canopy` for these types.

///|
pub using @editor {
  type SyncEditor,
  type ViewUpdateState,
}

///|
pub using @core {
  type ProjNode,
  type NodeId,
  type SourceMap,
  type SpanEdit,
  type FocusHint,
}

///|
pub using @proj {
  type TreeEditorState,
}

///|
pub using @relay {
  type RelayRoom,
}

///|
pub using @protocol {
  type ViewPatch,
  type ViewNode,
}
```

Note: `SpanEdit` and `FocusHint` are in `core`. Verify with
`moon ide doc "@core.*"`. If they are defined elsewhere, adjust the
import. Run `moon check` to verify.

- [ ] **Step 3: Verify**

```bash
moon check && moon test
```

- [ ] **Step 4: Commit**

```bash
git add top.mbt moon.pkg
git commit -m "feat: add public MoonBit API via top.mbt"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `AGENTS.md` (package map section)

- [ ] **Step 1: Update the package map in AGENTS.md**

Find the `## Package Map` section and replace the table with:

```markdown
**Main module: `dowdiness/canopy`**

| Package | Path | Purpose |
|---------|------|---------|
| `dowdiness/canopy` | `./` | Public MoonBit API (`top.mbt`), re-exports key types |
| `dowdiness/canopy/ffi` | `ffi/` | JS FFI entry point, 58 link exports |
| `dowdiness/canopy/core` | `core/` | Generic types: NodeId, ProjNode[T], SourceMap, reconcile, helpers |
| `dowdiness/canopy/protocol` | `protocol/` | EditorProtocol: ViewPatch, ViewNode, UserIntent |
| `dowdiness/canopy/editor` | `editor/` | SyncEditor, EphemeralHub, cursor/presence tracking, undo |
| `dowdiness/canopy/projection` | `projection/` | Language-agnostic: TreeEditorState, tree refresh, tree editor ops |
| `dowdiness/canopy/relay` | `relay/` | Relay room, wire protocol (multi-peer sync) |
| `dowdiness/canopy/lang/lambda` | `lang/lambda/` | Lambda language facade (re-exports from sub-packages) |
| `dowdiness/canopy/lang/lambda/proj` | `lang/lambda/proj/` | FlatProj, syntax_to_proj_node, populate_token_spans |
| `dowdiness/canopy/lang/lambda/flat` | `lang/lambda/flat/` | VersionedFlatProj (incr memo wrapper) |
| `dowdiness/canopy/lang/lambda/edits` | `lang/lambda/edits/` | TreeEditOp, text edit handlers, scope, free_vars, actions |
| `dowdiness/canopy/lang/lambda/zipper` | `lang/lambda/zipper/` | Zipper-based tree navigation |
| `dowdiness/canopy/lang/json` | `lang/json/` | JSON language facade (re-exports from sub-packages) |
| `dowdiness/canopy/lang/json/proj` | `lang/json/proj/` | JSON syntax_to_proj_node, populate_token_spans, memo builder |
| `dowdiness/canopy/lang/json/edits` | `lang/json/edits/` | JsonEditOp, edit handlers, bridge, new_json_editor |
| `dowdiness/canopy/cmd/main` | `cmd/main/` | CLI entry point, REPL, demo |
```

If Task 6 was skipped (FFI stays at root), adjust the first two rows:

```markdown
| `dowdiness/canopy` | `./` | Public MoonBit API (`top.mbt`) + JS FFI (`canopy_*.mbt`, 58 link exports) |
```

and remove the `ffi/` row.

- [ ] **Step 2: Verify AGENTS.md is valid**

```bash
moon check
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update package map for reorganized structure"
```

---

## Final Validation

After all tasks are complete, run the full validation suite:

```bash
moon check
moon test
moon build --target js --release
cd examples/web && npm run build
```

Verify:
- No `framework/` directory exists
- `core/` and `protocol/` are top-level
- `lang/lambda/top.mbt` and `lang/json/top.mbt` exist
- `top.mbt` exists at root
- `projection/moon.pkg` has no lambda imports
- All 664+ tests pass
