# §P0b Phase 1b WS2 — Markdown + JSON FFI Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `assemble_<lang>_handle` + `<Lang>ProtectedCells` + coordinator-routed destroy to the Markdown and JSON FFI surfaces, co-migrating one production accessor per language through `coordinator.read_protected` so the cells bundles ship live, not as dead code.

**Architecture:** Each FFI surface (`ffi/markdown/`, `ffi/json/`) gets its own module-scope `@workspace.Coordinator`, a private `<Lang>Handle` struct, a private `<Lang>ProtectedCells` 7-cell bundle, an atomic `assemble_<lang>_handle` ctor, and a coordinator-routed `destroy_<lang>_editor`. The Markdown accessor `markdown_compute_view_patches_json` is rewritten to read three protected cells + raw text and produce patches via a locally-duplicated `diff_view_nodes` helper. The JSON accessor `json_get_errors` is rewritten to read `parser_diagnostics` through the coordinator with an empty-doc guard. Per-language coordinators are intentionally independent at this phase (no shared runtime, no cross-language registry — see spec §4 for the JS-bundle empirical justification).

**Tech Stack:** MoonBit (workspace via `moon.work`, JS target via `moon build --target js`), `@workspace.Coordinator` API, `@editor.SyncEditor[T]`, `@protocol.proj_to_view_node`. `NEW_MOON_MOD=0` is required by a hook for `moon check` / `moon test` invocations.

**Spec:** `docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md`. Read it before starting — this plan executes the spec, it does not replace it.

**Reference pattern:** `ffi/lambda/lifecycle.mbt`, `ffi/lambda/protected_cells.mbt`, `ffi/lambda/diagnostics.mbt`, `ffi/lambda/lifecycle_phase1_wbtest.mbt` (PR4 + WS1). The Markdown/JSON files in this plan mirror those Lambda files structurally, omitting Lambda-only fields (`companion`, `typecheck`, `proj_memo`, `escalation_memo`, `typecheck_output`, `last_created_handle`, `pretty_view_states`).

---

## PR Decomposition

Two **independent** PRs. Either order. Neither requires the other to merge first. Neither touches Lambda or any package outside `ffi/<lang>/`.

- **PR-B (Markdown)** — Tasks B1..B9. Co-migrates `markdown_compute_view_patches_json`.
- **PR-C (JSON)** — Tasks C1..C8. Co-migrates `json_get_errors`.

Each PR is self-contained: at the end of its task list, `moon check` is clean, `moon test` is green, and the FFI exposes the same JS surface to consumers.

---

## File Structure

### PR-B (Markdown) files

| File | Action | Responsibility |
|------|--------|----------------|
| `ffi/markdown/protected_cells.mbt` | **Create** | `MarkdownProtectedCells` priv struct (7 fields) + ctor + `to_protected_reads`. Mirrors `ffi/lambda/protected_cells.mbt:18-101` for the 7-cell SyncEditor-generic subset (no companion/typecheck fields). |
| `ffi/markdown/markdown_ffi.mbt` | **Modify** | Replace `markdown_editors` map + `markdown_next_handle` counter with `markdown_handles : Map[Int, MarkdownHandle]` + module-scope `coordinator`. Add `MarkdownHandle` priv struct + `assemble_markdown_handle`. Rewrite `create_markdown_editor`, `destroy_markdown_editor`, `markdown_compute_view_patches_json`. Update `markdown_get_text`, `markdown_export_text`, `markdown_set_text`, `markdown_apply_edit` lookups from `markdown_editors` → `markdown_handles` (cosmetic — they read `h.editor` instead of the old `ed` directly). |
| `ffi/markdown/diff_view.mbt` | **Create** | Local `diff_view_nodes` helper duplicated from `editor/view_updater.mbt:77-143` (private to editor pkg → cannot be imported, per Codex round-2 #2 / spec §3.3 / §6.2 step 6). |
| `ffi/markdown/lifecycle_phase1_wbtest.mbt` | **Create** | Spec §12 tests 1–4 (read-all-7-cells, destroy-while-depended-upon, read-after-destroy, cross-editor-cell-rejection) + behavior-equivalence + destroyed-editor regression for `markdown_compute_view_patches_json`. Mirrors `ffi/lambda/lifecycle_phase1_wbtest.mbt:36-156` structurally. |
| `ffi/markdown/moon.pkg` | **Modify** | Add imports for `@workspace`, `@protocol`, `@loom_core`, `@core_json`. Add `warnings = "-7"` carve-out + header comment (spec §5.4). Add `"dowdiness/incr/cells" @cells` import for `parent_runtime` typing. |
| `ffi/markdown/pkg.generated.mbti` | **Regenerated** | Updated automatically by `moon info` after the source changes. |

### PR-C (JSON) files

| File | Action | Responsibility |
|------|--------|----------------|
| `ffi/json/protected_cells.mbt` | **Create** | `JsonProtectedCells` priv struct (7 fields) + ctor + `to_protected_reads`. Same 7-cell subset as Markdown, parameterised on `@djson.JsonValue`. |
| `ffi/json/json_ffi.mbt` | **Modify** | Replace `json_editors` map + `json_next_handle` counter with `json_handles : Map[Int, JsonHandle]` + module-scope `coordinator`. Add `JsonHandle` priv struct + `assemble_json_handle`. Rewrite `create_json_editor`, `destroy_json_editor`, `json_get_errors`. Update remaining lookups (`json_get_text`, `json_set_text`, `json_get_proj_node_json`, `json_get_source_map_json`, `json_get_view_tree_json`, `json_compute_view_patches_json`) to read `h.editor`. |
| `ffi/json/edit.mbt` | **Modify** | Update `json_apply_edit` lookup from `json_editors` → `json_handles` (cosmetic). |
| `ffi/json/lifecycle_phase1_wbtest.mbt` | **Create** | Spec §12 tests 1–4 + behavior-equivalence + destroyed-editor regression for `json_get_errors`. Same structure as Markdown's wbtest. |
| `ffi/json/moon.pkg` | **Modify** | Add imports for `@workspace`, `@loom_core`. Add `warnings = "-7"` carve-out + header comment. Add `"dowdiness/incr/cells" @cells` import. |
| `ffi/json/pkg.generated.mbti` | **Regenerated** | Updated by `moon info`. |

### What stays untouched

- `ffi/lambda/*` — Lambda already shipped through PR4 + WS1.
- `ffi/markdown/README.md`, `ffi/json/README.md` — no docs changes in this workstream (followup if PR-C surfaces a doc gap).
- `editor/view_updater.mbt:77` `diff_view_nodes` — stays `priv` to editor pkg (spec §3.3). Spec §9 records the future-extraction followup.
- All language companion packages — `new_markdown_editor` and `new_json_editor` already accept `parent_runtime~` (verified in `lang/markdown/companion/pkg.generated.mbti:16` and `lang/json/companion/pkg.generated.mbti:14`).
- `@workspace.Coordinator` — its API is already at the surface this plan consumes.

---

## Required disciplines (apply throughout both PRs)

- **Incremental Edit Rule.** Run `NEW_MOON_MOD=0 moon check` after every file edit. If errors appear, fix them before continuing. (Enforced by hook; rerun is cheap.)
- **TDD.** Every new test in the wbtest files is written **before** the source change it covers, run to confirm it fails, then made to pass.
- **Frequent commits.** Each task ends with a commit. Commits use the conventional-commit style of recent canopy history: `feat(ffi/markdown): §P0b Phase 1b WS2 — <one-line summary>`.
- **Byte-equivalent moves where the spec demands.** The 7-cell bundle ctor and the §12 tests are mechanically symmetric to Lambda; copy verbatim with only `lambda` → `markdown`/`json` and the `T` type parameter changes. No "while I'm here" tweaks.
- **No paste-in code drift.** Code blocks below are the actual text to write. If a later task references a symbol from an earlier task, that symbol's name and signature match exactly.
- **Verify branch before committing.** `git branch --show-current` — work happens on a feature branch (e.g. `feat/ws2-markdown`, `feat/ws2-json`), not `main`.

---

# PR-B — Markdown FFI

### Task B1: Create the worktree / feature branch

**Files:** none modified; branch state only.

- [ ] **Step 1: Create branch from main**

```bash
git fetch origin
git checkout -b feat/ws2-markdown origin/main
git branch --show-current
```

Expected output: `feat/ws2-markdown`.

- [ ] **Step 2: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean` (untracked files outside `ffi/markdown/` are fine).

---

### Task B2: Add Markdown FFI imports + warnings carve-out

**Files:**
- Modify: `ffi/markdown/moon.pkg`

- [ ] **Step 1: Add new imports + `warnings` carve-out**

Replace the entire file with:

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/core",
  "dowdiness/canopy/lang/markdown/edits" @md_edits,
  "dowdiness/canopy/lang/markdown/companion" @md_companion,
  "dowdiness/canopy/lang/markdown/sentinel" @md_sentinel,
  "dowdiness/canopy/protocol",
  "dowdiness/canopy/workspace/coordinator" @workspace,
  "dowdiness/incr/cells",
  "dowdiness/loom/core" @loom,
  "dowdiness/markdown" @md,
  "moonbitlang/core/json",
}

// `cells` field of MarkdownHandle is read in production by
// `markdown_compute_view_patches_json` (parser_diagnostics + cached_proj_node
// + source_map_memo, via Phase 1b workstream 2) and by whitebox tests
// (`lifecycle_phase1_wbtest.mbt`) for the remaining 4 cells. Until additional
// Phase 1b workstreams migrate the other production accessors, per-field
// unused warnings still fire on the rest of `MarkdownProtectedCells`.

warnings = "-7"

options(
  link: {
    "js": {
      "exports": [
        "create_markdown_editor",
        "destroy_markdown_editor",
        "markdown_get_text",
        "markdown_export_text",
        "markdown_set_text",
        "markdown_compute_view_patches_json",
        "markdown_apply_edit",
        "markdown_empty_paragraph_sentinel",
      ],
    },
  },
)
```

- [ ] **Step 2: Verify check still compiles (no source-side users yet)**

Run: `NEW_MOON_MOD=0 moon check ffi/markdown`

Expected: PASS. Any "unused import" warnings on the new imports are silenced by `warnings = "-7"` (variant `7` covers unused-imports; matches Lambda's carve-out at `ffi/lambda/moon.pkg:29`). If `moon check` complains about an unknown variant number, run `NEW_MOON_MOD=0 moon check ffi/markdown 2>&1 | head -20` and adjust the warnings line to match the Lambda comment's intent (silence per-field unused warnings until all 7 cells are read by production accessors).

- [ ] **Step 3: Commit**

```bash
git add ffi/markdown/moon.pkg
git commit -m "chore(ffi/markdown): §P0b Phase 1b WS2 — add workspace/protocol imports + warnings carve-out"
```

---

### Task B3: Create `MarkdownProtectedCells` bundle

**Files:**
- Create: `ffi/markdown/protected_cells.mbt`

- [ ] **Step 1: Create the file**

```
// Markdown protected-cell bundle — typed view onto the editor surface that
// participates in workspace coordination.
//
// Each field wraps an editor `Derived[T]` in a long-lived `Watch` (the GC
// root) via `ProtectedCell::from_derived`. The bundle is constructed from a
// freshly-built editor inside `assemble_markdown_handle` (markdown_ffi.mbt)
// and erased to `Array[ProtectedRead]` for registration with the coordinator.
//
// 7-cell SyncEditor-generic subset (no language companion + no typecheck
// pipeline). See docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md
// §5.1.

///|
priv struct MarkdownProtectedCells {
  parser_syntax_tree : @workspace.ProtectedCell[@seam.SyntaxNode]
  parser_ast : @workspace.ProtectedCell[@md.Block]
  parser_source : @workspace.ProtectedCell[String]
  parser_diagnostics : @workspace.ProtectedCell[@loom.DiagnosticSet]
  cached_proj_node : @workspace.ProtectedCell[@core.ProjNode[@md.Block]?]
  registry_memo : @workspace.ProtectedCell[
    Map[@core.NodeId, @core.ProjNode[@md.Block]],
  ]
  source_map_memo : @workspace.ProtectedCell[@core.SourceMap]
}

///|
fn MarkdownProtectedCells::MarkdownProtectedCells(
  editor : @editor.SyncEditor[@md.Block],
) -> MarkdownProtectedCells {
  {
    parser_syntax_tree: @workspace.ProtectedCell::from_derived(
      "parser_syntax_view",
      editor.parser_syntax_tree(),
    ),
    parser_ast: @workspace.ProtectedCell::from_derived(
      "parser_ast_view",
      editor.parser_ast(),
    ),
    parser_source: @workspace.ProtectedCell::from_derived(
      "parser_source_view",
      editor.parser_source(),
    ),
    parser_diagnostics: @workspace.ProtectedCell::from_derived(
      "parser_diagnostics_view",
      editor.parser_diagnostics(),
    ),
    cached_proj_node: @workspace.ProtectedCell::from_derived(
      "cached_proj_node",
      editor.cached_proj_node(),
    ),
    registry_memo: @workspace.ProtectedCell::from_derived(
      "proj_registry",
      editor.registry_memo(),
    ),
    source_map_memo: @workspace.ProtectedCell::from_derived(
      "source_map",
      editor.source_map_memo(),
    ),
  }
}

///|
fn MarkdownProtectedCells::to_protected_reads(
  self : MarkdownProtectedCells,
) -> Array[@workspace.ProtectedRead] {
  [
    self.parser_syntax_tree.erase(),
    self.parser_ast.erase(),
    self.parser_source.erase(),
    self.parser_diagnostics.erase(),
    self.cached_proj_node.erase(),
    self.registry_memo.erase(),
    self.source_map_memo.erase(),
  ]
}
```

- [ ] **Step 2: Add `@seam` import if `moon check` complains**

Run: `NEW_MOON_MOD=0 moon check ffi/markdown`

Expected: PASS (the file is syntactically valid and `@seam.SyntaxNode` is already transitively imported via `@editor`, but if `moon check` reports `unknown package "seam"`, append `"dowdiness/seam"` to the imports block in `ffi/markdown/moon.pkg` to make the type explicit and re-run).

- [ ] **Step 3: Commit**

```bash
git add ffi/markdown/protected_cells.mbt ffi/markdown/moon.pkg
git commit -m "feat(ffi/markdown): §P0b Phase 1b WS2 — add MarkdownProtectedCells 7-cell bundle"
```

---

### Task B4: Add local `diff_view_nodes` helper

**Files:**
- Create: `ffi/markdown/diff_view.mbt`

The editor-pkg `diff_view_nodes` (`editor/view_updater.mbt:77`) is `priv` to that package and cannot be imported (spec §3.3, Codex round-2 #2). Duplicate verbatim.

- [ ] **Step 1: Create the helper file**

```
// Local duplicate of `diff_view_nodes` from `editor/view_updater.mbt:77`.
// The editor-pkg helper is private; this Markdown FFI accessor cannot import
// it. Duplicated byte-for-byte — when WS3+ migrates a second view-patch
// accessor (e.g. JSON), promote the helper to a shared package and remove
// this copy. Tracked as a §9 followup in the WS2 design spec.

///|
fn diff_view_nodes(
  prev : @protocol.ViewNode,
  curr : @protocol.ViewNode,
  patches : Array[@protocol.ViewPatch],
) -> Unit {
  if prev.id != curr.id {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.kind_tag != curr.kind_tag {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.token_spans != curr.token_spans {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.annotations != curr.annotations {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.label != curr.label ||
    prev.css_class != curr.css_class ||
    prev.text != curr.text {
    patches.push(
      @protocol.ViewPatch::UpdateNode(
        node_id=curr.id,
        label=curr.label,
        css_class=curr.css_class,
        text=curr.text,
      ),
    )
  }
  let prev_len = prev.children.length()
  let curr_len = curr.children.length()
  let min_len = if prev_len < curr_len { prev_len } else { curr_len }
  for i = 0; i < min_len; i = i + 1 {
    diff_view_nodes(prev.children[i], curr.children[i], patches)
  }
  if curr_len > prev_len {
    for i = prev_len; i < curr_len; i = i + 1 {
      patches.push(
        @protocol.ViewPatch::InsertChild(
          parent_id=curr.id,
          index=i,
          child=curr.children[i],
        ),
      )
    }
  }
  if prev_len > curr_len {
    for i = prev_len - 1; i >= curr_len; i = i - 1 {
      patches.push(
        @protocol.ViewPatch::RemoveChild(
          parent_id=curr.id,
          index=i,
          child_id=prev.children[i].id,
        ),
      )
    }
  }
}
```

- [ ] **Step 2: Verify it compiles standalone**

Run: `NEW_MOON_MOD=0 moon check ffi/markdown`

Expected: PASS. The `for ... { ... }` C-style loop is current MoonBit (see `editor/view_updater.mbt:117-141` — same syntax). The `diff_view_nodes` symbol is unused so far; it'll wire into `markdown_compute_view_patches_json` in B6. The `warnings = "-7"` carve-out covers unused-function warnings.

- [ ] **Step 3: Commit**

```bash
git add ffi/markdown/diff_view.mbt
git commit -m "feat(ffi/markdown): §P0b Phase 1b WS2 — local diff_view_nodes helper (editor-pkg copy)"
```

---

### Task B5: Rewrite Markdown lifecycle (handles + coordinator + assemble + destroy)

This is the structural core of PR-B. Replaces the registry, adds the handle struct, adds the assemble ctor, routes destroy through the coordinator. Existing simple accessors (`markdown_get_text`, `markdown_set_text`, `markdown_export_text`, `markdown_apply_edit`) get their lookup updated from `markdown_editors[handle]` → `markdown_handles.get(handle).map(h => h.editor)`. `markdown_compute_view_patches_json` is rewritten in B6 — for this task, leave its body calling `@editor.compute_view_patches(state, h.editor)` against the new struct so the file still compiles.

**Files:**
- Modify: `ffi/markdown/markdown_ffi.mbt`

- [ ] **Step 1: Replace the entire file**

Replace the entire contents with:

```
///| FFI surface for the Markdown editor: lifecycle, text I/O, structural
/// edits, and view patches. Editor construction funnels through
/// `assemble_markdown_handle` so the FFI ctor shares one `@incr.Runtime`,
/// one atomic registration boundary, and one destroy gateway with the
/// workspace coordinator. See docs/superpowers/specs/2026-05-25-p0b-
/// phase1b-ws2-design.md §5.

///|
priv struct MarkdownHandle {
  editor : @editor.SyncEditor[@md.Block]
  editor_id : @workspace.EditorId
  cells : MarkdownProtectedCells
}

///|
/// Process-global coordinator for the Markdown FFI bundle. Per-language
/// (not shared with Lambda/JSON) — see spec §4 for the JS-bundle
/// empirical justification. Cross-language sharing is a Phase 2 concern.
let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()

///|
let markdown_handles : Map[Int, MarkdownHandle] = Map::default()

///|
let markdown_view_states : Map[Int, @editor.ViewUpdateState] = Map::default()

// ── Lifecycle ────────────────────────────────────────────────────────────

///|
/// Build a Markdown editor on the shared runtime, then atomically register
/// its protected cells with the coordinator. Returns the freshly-allocated
/// `EditorId`. Aborting at any step leaves `markdown_handles` untouched
/// (atomic-boundary observation, spec §3.6).
fn assemble_markdown_handle(agent_id : String) -> @workspace.EditorId {
  let editor = @md_companion.new_markdown_editor(
    agent_id,
    parent_runtime=coordinator.runtime(),
  )
  let cells = MarkdownProtectedCells::MarkdownProtectedCells(editor)
  let editor_id = coordinator.register_editor(
    agent_id,
    cells.to_protected_reads(),
  )
  markdown_handles[editor_id.0] = { editor, editor_id, cells }
  editor_id
}

///|
pub fn create_markdown_editor(agent_id : String) -> Int {
  assemble_markdown_handle(agent_id).0
}

///|
/// Destroy a Markdown editor and free its resources. The coordinator gateway
/// refuses if workspace deps still reference the editor; in that case the
/// FFI-side bookkeeping (markdown_handles entry, view_states entry) is
/// intentionally left intact so reads of cached state remain valid. Phase 1
/// behavior matches Lambda's `destroy_editor` (spec §5.3).
pub fn destroy_markdown_editor(handle : Int) -> Unit {
  let h = match markdown_handles.get(handle) {
    Some(v) => v
    None => return
  }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => {
      println("destroy_markdown_editor refused: \{report}")
      return
    }
  }
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
}

///|
pub fn markdown_get_text(handle : Int) -> String {
  match markdown_handles.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Return markdown text with ZWSP placeholder paragraphs stripped structurally.
/// Delegates to the companion helper which walks the projection tree, identifies
/// sentinel paragraphs (AST `Paragraph([Text("​")])`), and removes only the
/// ZWSP character itself — leaving ZWSP inside other content (code blocks,
/// paragraphs with mixed text) untouched.
pub fn markdown_export_text(handle : Int) -> String {
  match markdown_handles.get(handle) {
    Some(h) => @md_companion.export_markdown_text(h.editor)
    None => ""
  }
}

///|
pub fn markdown_set_text(handle : Int, text : String) -> Unit {
  match markdown_handles.get(handle) {
    Some(h) => h.editor.set_text(text)
    None => ()
  }
}

///|
/// JS-side accessor for the empty-paragraph sentinel codepoint. Returns the
/// same value as `@md_sentinel.EMPTY_PARAGRAPH_SENTINEL` (which itself
/// aliases `@moji.ZERO_WIDTH_SPACE`). Exposed as a function so TS consumers
/// import a single source of truth from the build artifact rather than
/// hardcoding the literal.
pub fn markdown_empty_paragraph_sentinel() -> String {
  @md_sentinel.EMPTY_PARAGRAPH_SENTINEL
}

// ── Structural edits ─────────────────────────────────────────────────────

///|
pub fn markdown_apply_edit(
  handle : Int,
  op_type : String,
  node_id : Int,
  param1 : String,
  param2 : Int,
  timestamp_ms : Int,
) -> String {
  match markdown_handles.get(handle) {
    Some(h) => {
      let nid = @core.NodeId::from_int(node_id)
      let op : @md_edits.MarkdownEditOp = match op_type {
        "commit_edit" =>
          @md_edits.MarkdownEditOp::CommitEdit(node_id=nid, new_text=param1)
        "change_heading_level" =>
          @md_edits.MarkdownEditOp::ChangeHeadingLevel(
            node_id=nid,
            level=param2,
          )
        "toggle_list_item" =>
          @md_edits.MarkdownEditOp::ToggleListItem(node_id=nid)
        "delete" => @md_edits.MarkdownEditOp::Delete(node_id=nid)
        "insert_block_after" =>
          @md_edits.MarkdownEditOp::InsertBlockAfter(node_id=nid)
        "split_block" =>
          @md_edits.MarkdownEditOp::SplitBlock(node_id=nid, offset=param2)
        "merge_with_previous" =>
          @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=nid)
        _ =>
          return Json::object({
            "status": Json::string("error"),
            "message": Json::string("unknown op: " + op_type),
          }).stringify()
      }
      match @md_companion.apply_markdown_edit(h.editor, op, timestamp_ms) {
        Ok(_) => Json::object({ "status": Json::string("ok") }).stringify()
        Err(msg) =>
          Json::object({
            "status": Json::string("error"),
            "message": Json::string(msg),
          }).stringify()
      }
    }
    None =>
      Json::object({
        "status": Json::string("error"),
        "message": Json::string("invalid handle"),
      }).stringify()
  }
}

// ── View patches ─────────────────────────────────────────────────────────

///|
/// Stub still calling the editor-pkg helper; rewritten in WS2 task B6 to
/// route through `coordinator.read_protected`.
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_handles.get(handle) {
    Some(h) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::ViewUpdateState()
          markdown_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
```

`h.editor_id` is used in the `coordinator.destroy_editor` call above, so the matched binding is consumed — no discard line needed (unlike the Lambda version, which additionally calls `h.typecheck.scope.dispose()`).

- [ ] **Step 2: Run `moon check`**

Run: `NEW_MOON_MOD=0 moon check ffi/markdown`

Expected: PASS. If you get errors, do not proceed. Common pitfalls:
- `markdown_editors` referenced anywhere — search `git grep markdown_editors -- ffi/markdown` and replace each site with the new `markdown_handles`-based lookup.
- `markdown_next_handle` referenced anywhere — same fix.
- `let _ = h` rejected because `h` is already used — remove the line.

- [ ] **Step 3: Run `moon test` (workspace)**

Run: `NEW_MOON_MOD=0 moon test`

Expected: green. The existing Markdown tests (none in `ffi/markdown/` yet — first tests arrive in B7) shouldn't regress. If a workspace-wide test exercises Markdown FFI through a downstream package, it should still pass because the JS surface is unchanged.

- [ ] **Step 4: Commit**

```bash
git add ffi/markdown/markdown_ffi.mbt
git commit -m "feat(ffi/markdown): §P0b Phase 1b WS2 — assemble_markdown_handle + MarkdownHandle + coordinator-routed destroy"
```

---

### Task B6: Rewrite `markdown_compute_view_patches_json` through `coordinator.read_protected`

This co-migrates the accessor so the cells bundle ships live (not as dead code under `warnings = "-7"`). Per spec §6.2: read three protected cells + raw text, assemble `ViewNode?` manually via `@protocol.proj_to_view_node`, diff with the local `diff_view_nodes` helper, emit `SetDiagnostics` like the editor-pkg `compute_view_patches`.

**Files:**
- Modify: `ffi/markdown/markdown_ffi.mbt:124-142` (the `markdown_compute_view_patches_json` stub from B5)

- [ ] **Step 1: Replace the function body**

Find the existing stub:

```
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_handles.get(handle) {
    Some(h) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::ViewUpdateState()
          markdown_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
```

Replace with the migrated version:

```
///|
/// Compute incremental view patches by reading the editor's projection +
/// source-map + diagnostics through the coordinator's protected surface.
/// Mirrors `@editor.compute_view_patches` shape but routes Derived reads
/// through `coordinator.read_protected`; on any Err (EditorDestroyed,
/// CellNotInProtectedSurface, etc.) collapses to "[]" rather than exposing
/// partial/stale patches. Text state is read raw (`h.editor.get_text()`):
/// per spec §3.4 / Codex round-2 #3 it backs the parser inputs, is not a
/// Derived cell, and reading it raw doesn't violate any cell-protection
/// invariant.
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  let h = match markdown_handles.get(handle) {
    Some(v) => v
    None => return "[]"
  }
  let state = match markdown_view_states.get(handle) {
    Some(s) => s
    None => {
      let s = @editor.ViewUpdateState::ViewUpdateState()
      markdown_view_states[handle] = s
      s
    }
  }
  let proj_opt = match
    coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
    Ok(p) => p
    Err(report) => {
      println("markdown_compute_view_patches_json proj read: \{report}")
      return "[]"
    }
  }
  let source_map = match
    coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
    Ok(m) => m
    Err(report) => {
      println("markdown_compute_view_patches_json source_map read: \{report}")
      return "[]"
    }
  }
  let parse_errors : Array[String] = if h.editor.get_text() == "" {
    []
  } else {
    match coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
      Ok(d) => d.format()
      Err(report) => {
        println(
          "markdown_compute_view_patches_json diagnostics read: \{report}",
        )
        return "[]"
      }
    }
  }
  let source_text = h.editor.get_text()
  let current : @protocol.ViewNode? = match proj_opt {
    Some(proj) =>
      Some(
        @protocol.proj_to_view_node(
          proj,
          source_map,
          source_text=Some(source_text),
          annotations={},
        ),
      )
    None => None
  }
  let patches : Array[@protocol.ViewPatch] = []
  match (state.previous, current) {
    (None, None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) => diff_view_nodes(prev, curr, patches)
  }
  if parse_errors.length() > 0 {
    let diagnostics : Array[@protocol.Diagnostic] = []
    for error in parse_errors {
      diagnostics.push(
        @protocol.Diagnostic(
          from=0,
          to=0,
          severity=@protocol.SevError,
          message=error,
        ),
      )
    }
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics~))
    state.had_errors = true
  } else if state.had_errors {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
    state.had_errors = false
  }
  state.previous = current
  Json::array(patches.map(fn(p) { p.to_json() })).stringify()
}
```

Notes on construction:
- The `annotations={}` value is correct under current Markdown configuration (spec §6.2 final paragraph + §9 followup). Markdown's `new_markdown_editor` passes no `LanguageCapabilities`. If a future workstream adds capabilities, this accessor will silently emit empty annotations until the followup lands.
- The empty-doc guard around `parser_diagnostics` mirrors `SyncEditor::get_errors` at `editor/sync_editor_parser.mbt:107-110` (Codex round-2 #1 — applied here too because the same parser produces the same spurious empty-doc diagnostics).
- The `diff_view_nodes` helper is the local one defined in B4.

- [ ] **Step 2: Run `moon check`**

Run: `NEW_MOON_MOD=0 moon check ffi/markdown`

Expected: PASS. Likely errors and fixes:
- `proj_to_view_node` argument order — verify against `protocol/pkg.generated.mbti:13`. Current signature: `proj_to_view_node(proj, source_map, annotations? : Map[...], source_text? : String?)`. The call above passes `source_text=Some(source_text), annotations={}` as labelled args after the positionals — verify against the .mbti, swap order if needed.
- `state.had_errors` access on `ViewUpdateState` — confirmed `mut had_errors : Bool` at `editor/view_updater.mbt:5`, so direct field assignment compiles when the struct is constructed via the named ctor `ViewUpdateState::ViewUpdateState()` in the same package boundary. If MoonBit rejects cross-package field assignment, change to call a public setter (none exists today; would require an editor-pkg addition — flag this as a blocker and stop, do **not** add a setter speculatively).

- [ ] **Step 3: Run `moon test`**

Run: `NEW_MOON_MOD=0 moon test`

Expected: green. No behavior regressions in any downstream consumer.

- [ ] **Step 4: Commit**

```bash
git add ffi/markdown/markdown_ffi.mbt
git commit -m "feat(ffi/markdown): §P0b Phase 1b WS2 — route markdown_compute_view_patches_json through coordinator.read_protected"
```

---

### Task B7: Add structural §12 tests 1–4 for Markdown

**Files:**
- Create: `ffi/markdown/lifecycle_phase1_wbtest.mbt`

Mirrors `ffi/lambda/lifecycle_phase1_wbtest.mbt:1-156` for the 7-cell subset. Tests 1–4 only; test 5 (`ProtectedCellDisposed`) is workspace-generic, covered by `workspace/coordinator/coordinator_wbtest.mbt:33` (spec §7.1 / Codex round-2 Q4).

- [ ] **Step 1: Create the file with the four structural tests**

```
// Whitebox integration tests for §P0b Phase 1b WS2: Markdown FFI editors
// driven through the workspace coordinator. Covers spec §12 tests 1–4
// (7-cell symmetric subset) — these need access to package-private
// symbols (`markdown_handles`, `coordinator`, `MarkdownHandle` fields), so
// they live in a `_wbtest.mbt`.
//
// §12 #5 (`ProtectedCellDisposed`) is workspace-generic and covered by
// `workspace/coordinator/coordinator_wbtest.mbt:33`.

///|
fn reset_markdown_coordinator_for_phase1_tests() -> Unit {
  // Force-clear FFI-side bookkeeping. Going through public
  // `destroy_markdown_editor` would route through
  // `coordinator.destroy_editor`, which can refuse
  // (DestroyWhileDependedUpon) and leave the entry behind — fragile if a
  // prior test panicked mid-flow and left a stale dep. Coordinator-side
  // registrations stay around with alive=true; each new test gets a fresh
  // EditorId from the monotonic counter so leakage cannot affect
  // correctness, only memory.
  let keys = markdown_handles.keys().to_array()
  for k in keys {
    markdown_handles.remove(k)
  }
  let vkeys = markdown_view_states.keys().to_array()
  for k in vkeys {
    markdown_view_states.remove(k)
  }
}

///|
test "spec §12 #1 (md): each protected cell reads through read_protected" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_one")
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.read_protected(id, h.cells.parser_syntax_tree) {
    Ok(_) => ()
    Err(report) => fail("parser_syntax_tree: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_ast) {
    Ok(_) => ()
    Err(report) => fail("parser_ast: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_source) {
    Ok(s) => assert_eq(s, "")
    Err(report) => fail("parser_source: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_diagnostics) {
    Ok(_) => ()
    Err(report) => fail("parser_diagnostics: \{report}")
  }
  match coordinator.read_protected(id, h.cells.cached_proj_node) {
    Ok(_) => ()
    Err(report) => fail("cached_proj_node: \{report}")
  }
  match coordinator.read_protected(id, h.cells.registry_memo) {
    Ok(_) => ()
    Err(report) => fail("registry_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.source_map_memo) {
    Ok(_) => ()
    Err(report) => fail("source_map_memo: \{report}")
  }
  destroy_markdown_editor(handle)
}

///|
test "spec §12 #2 (md): destroy refused while depended-upon; succeeds after unregister_dep" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_two")
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_ast_id = h.cells.parser_ast.cell_id()
  let synth_id = parser_ast_id
  coordinator.register_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon")
    Err(report) => assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
  }
  coordinator.unregister_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("expected Ok after unregister_dep, got \{report}")
  }
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
}

///|
test "spec §12 #3 (md): read_protected after destroy returns EditorDestroyed" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_three")
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_markdown_editor(handle)
  match coordinator.read_protected(id, parser_source_cell) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(report) => {
      assert_eq(report.kind, @workspace.EditorDestroyed)
      assert_eq(report.agent_id, "md_test_agent_three")
    }
  }
}

///|
test "spec §12 #4 (md): read_protected rejects cells from a different editor" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle_a = create_markdown_editor("md_agent_alpha")
  let handle_b = create_markdown_editor("md_agent_beta")
  let h_a = markdown_handles.get(handle_a).unwrap()
  let h_b = markdown_handles.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_markdown_editor(handle_a)
  destroy_markdown_editor(handle_b)
}
```

- [ ] **Step 2: Run the tests — expect them to PASS immediately**

Run: `NEW_MOON_MOD=0 moon test ffi/markdown`

Expected: 4 new tests pass (the structural infrastructure is already in place from B5; these tests verify it). Test count delta: +4.

If any test fails, the failure points at a concrete defect in B5 (e.g. cells not registered, wrong order in `to_protected_reads`, missing `editor_id` field on the handle). Do not "fix" the test — fix B5's source until the test passes against the spec contract.

- [ ] **Step 3: Verify test count delta against the report**

Run: `NEW_MOON_MOD=0 moon test ffi/markdown 2>&1 | tail -5`

Look for the summary like `Total tests: N, passed: N, failed: 0`. The 4 new tests must appear in the count — per `[[feedback-test-count-delta]]`, "moon test passes" is not the same as "tests ran".

- [ ] **Step 4: Commit**

```bash
git add ffi/markdown/lifecycle_phase1_wbtest.mbt
git commit -m "test(ffi/markdown): §P0b Phase 1b WS2 — spec §12 tests 1-4 (read-all-7-cells, destroy-while-depended, read-after-destroy, cross-editor-rejection)"
```

---

### Task B8: Add behavior-equivalence + destroyed-editor regression tests for `markdown_compute_view_patches_json`

Per spec §7.2 + `[[feedback-verify-test-for-flagged-risk]]`: each behavioral risk in the rewrite gets its own explicit test. Three risks: initial-render emits `FullTree`, incremental-diff emits non-FullTree patches matching the change, post-destroy collapses to `"[]"`.

**Files:**
- Modify: `ffi/markdown/lifecycle_phase1_wbtest.mbt` (append three tests)

- [ ] **Step 1: Write the initial-render test FIRST (TDD), confirm it passes**

Append to `ffi/markdown/lifecycle_phase1_wbtest.mbt`:

```
///|
/// Phase 1b workstream 2 — `markdown_compute_view_patches_json` migration
/// regressions. Each test corresponds to one behavioral risk called out in
/// spec §7.2.
///
/// Initial-render path: a fresh editor with non-empty source should emit a
/// FullTree patch carrying a non-null root. Regression check that the
/// `coordinator.read_protected(cached_proj_node)` → assemble manually →
/// FullTree pipeline produces the same Some-root shape that the
/// pre-migration `@editor.compute_view_patches` did.
test "workstream 2 (md): compute_view_patches initial render emits FullTree with root" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_initial_agent")
  markdown_set_text(handle, "# Hello\n\nWorld\n")
  let out = markdown_compute_view_patches_json(handle)
  if !out.contains("\"FullTree\"") {
    fail(
      "expected initial render to emit FullTree patch, got \{out}",
    )
  }
  // The root should not be null — a populated markdown document projects to
  // a ViewNode. (Empty doc would be {"FullTree":{"root":null}}; we just
  // wrote two blocks.)
  if out.contains("\"root\":null") {
    fail("expected non-null root on initial render of non-empty doc, got \{out}")
  }
  destroy_markdown_editor(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/markdown`

Expected: PASS. If it fails, the failure isolates which side of the pipeline diverges from baseline.

- [ ] **Step 2: Write the incremental-diff test**

Append:

```
///|
/// Incremental-diff path: a second call after a structural change must emit
/// targeted patches (`UpdateNode` / `ReplaceNode` / `InsertChild` /
/// `RemoveChild`), not a fresh `FullTree`. The `state.previous` carry-over
/// from the first call is what makes this possible; if the rewrite ever
/// loses the carry-over, this test catches it.
test "workstream 2 (md): compute_view_patches second call emits incremental patches" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_incr_agent")
  markdown_set_text(handle, "# Hello\n")
  let _ = markdown_compute_view_patches_json(handle)
  markdown_set_text(handle, "# Hello world\n")
  let second = markdown_compute_view_patches_json(handle)
  // Second call must NOT be a FullTree — that would mean the diff path
  // didn't trigger.
  if second.contains("\"FullTree\"") {
    fail(
      "expected incremental patch on second call after edit, got FullTree: \{second}",
    )
  }
  // At least one of the incremental patch tags must appear.
  let has_incremental = second.contains("\"UpdateNode\"") ||
    second.contains("\"ReplaceNode\"") ||
    second.contains("\"InsertChild\"") ||
    second.contains("\"RemoveChild\"")
  if !has_incremental {
    fail(
      "expected UpdateNode / ReplaceNode / InsertChild / RemoveChild patch, got \{second}",
    )
  }
  destroy_markdown_editor(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/markdown`

Expected: PASS.

- [ ] **Step 3: Write the post-destroy collapse test**

Append:

```
///|
/// Post-destroy path: after `coordinator.destroy_editor`, the accessor must
/// collapse to "[]" via the Err arm of every `read_protected` call. The
/// pre-migration body called `@editor.compute_view_patches` directly on
/// `ed`, bypassing the coordinator — destroyed-editor reads would have
/// returned stale Derived state. This test pins the new behavior.
test "workstream 2 (md): compute_view_patches collapses to [] after coordinator destroy" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_destroy_agent")
  markdown_set_text(handle, "# Pre-destroy\n")
  let alive = markdown_compute_view_patches_json(handle)
  // Sanity-check that we got something pre-destroy (FullTree from initial
  // render); confirms the test setup is wired correctly.
  if !alive.contains("\"FullTree\"") {
    fail(
      "expected pre-destroy initial render to emit FullTree, got \{alive}",
    )
  }
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  // FFI bookkeeping retained — coordinator side is destroyed, but the
  // handle entry stays so subsequent calls still hit the protected-read
  // path (and that path's Err arm produces "[]").
  match markdown_handles.get(handle) {
    Some(_) => ()
    None =>
      fail(
        "expected markdown_handles to retain handle after direct coordinator destroy",
      )
  }
  assert_eq(markdown_compute_view_patches_json(handle), "[]")
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/markdown`

Expected: PASS. Test count delta from B7 + B8 combined: +7 in `ffi/markdown/lifecycle_phase1_wbtest.mbt`.

- [ ] **Step 4: Commit**

```bash
git add ffi/markdown/lifecycle_phase1_wbtest.mbt
git commit -m "test(ffi/markdown): §P0b Phase 1b WS2 — initial-render, incremental-diff, post-destroy regression for markdown_compute_view_patches_json"
```

---

### Task B9: Format, regenerate `.mbti`, verify, push

**Files:**
- Modify: `ffi/markdown/pkg.generated.mbti` (regenerated)

- [ ] **Step 1: Format + regenerate interface**

Run: `NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info`

This updates `ffi/markdown/pkg.generated.mbti` to reflect the new public surface (the JS exports list is unchanged; only the underlying types/handle struct shape changed and those are `priv`, so the .mbti delta should be minimal).

- [ ] **Step 2: Check the .mbti delta**

Run: `git diff ffi/markdown/pkg.generated.mbti`

Expected: minimal changes — possibly nothing public changed at all (the JS exports list at `ffi/markdown/moon.pkg:10-23` is unchanged from the original file). Per the project's `feedback_api_diff_check` discipline: any unexpected widening of a public signature is a regression. Verify no public function lost or gained generic params, type bounds, or labelled args.

- [ ] **Step 3: Final workspace check + test**

Run:

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
```

Expected: both green across the workspace.

- [ ] **Step 4: Build JS to verify the FFI surface still compiles for the web target**

Run: `bash scripts/build-js.sh`

Expected: produces `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js` (~1.2 MB, ESM module). If it fails with a missing-import error, the FFI's JS export list is fine but a transitive dependency needs adjustment — check the error message before assuming the lifecycle/cells changes are at fault.

- [ ] **Step 5: Verify commit history is clean**

Run: `git log --oneline origin/main..feat/ws2-markdown`

Expected: 7 commits, one per task (B2..B8). B1 created the branch but didn't commit. B9 hasn't committed yet — the format+mbti delta gets committed in step 6.

- [ ] **Step 6: Commit the format + mbti regen**

```bash
git add ffi/markdown/pkg.generated.mbti
git diff --cached --stat
git commit -m "chore(ffi/markdown): §P0b Phase 1b WS2 — moon fmt + moon info"
```

If `git diff --cached` shows no changes, skip the commit — the .mbti was already correct.

- [ ] **Step 7: Push and open the PR**

Run:

```bash
git push -u origin feat/ws2-markdown
gh pr create --title "feat(ffi/markdown): §P0b Phase 1b WS2 — coordinator-routed handle + compute_view_patches migration" --body "$(cat <<'EOF'
## Summary
- Adds per-package `@workspace.Coordinator`, `MarkdownHandle`, `MarkdownProtectedCells` (7-cell SyncEditor-generic bundle), atomic `assemble_markdown_handle` ctor, and coordinator-routed `destroy_markdown_editor` to the Markdown FFI surface.
- Co-migrates `markdown_compute_view_patches_json` through `coordinator.read_protected` (three protected reads + raw text + local `diff_view_nodes` duplicate). The pre-migration body bypassed the coordinator entirely; the migrated version proves the cells bundle ships live.
- Per spec §4 (empirical JS-bundle verification): per-language coordinator only, no cross-language runtime sharing in WS2.

## Test plan
- [x] `NEW_MOON_MOD=0 moon check ffi/markdown` — clean
- [x] `NEW_MOON_MOD=0 moon test ffi/markdown` — 4 structural + 3 regression tests, all green
- [x] `NEW_MOON_MOD=0 moon test` — workspace-wide green
- [x] `bash scripts/build-js.sh` — `markdown.js` artifact still produced
- [ ] Codex scoped review of WS2 PR-B (pre-merge)
- [ ] Codex broad pre-merge pass (pair with scoped per `[[feedback-codex-broad-vs-scoped-review]]`)

Spec: docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md
Plan: docs/superpowers/plans/2026-05-26-p0b-phase1b-ws2-implementation.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Do NOT merge yet.** PR-B and PR-C each need a pre-merge Codex review pair (scoped + broad) per `[[feedback-codex-broad-vs-scoped-review]]`. The merge step happens after both reviews PASS and CI is fully green per `[[feedback-ci-merge-policy]]`.

---

# PR-C — JSON FFI

PR-C is structurally simpler than PR-B (no `diff_view_nodes` duplicate; the migrated accessor `json_get_errors` is a tight 4-line rewrite around one protected read). Most tasks are direct mirrors of PR-B's structural tasks.

### Task C1: Create the worktree / feature branch

- [ ] **Step 1: Create branch from main**

```bash
git fetch origin
git checkout -b feat/ws2-json origin/main
git branch --show-current
```

Expected: `feat/ws2-json`.

- [ ] **Step 2: Verify clean tree**

```bash
git status
```

---

### Task C2: Add JSON FFI imports + warnings carve-out

**Files:**
- Modify: `ffi/json/moon.pkg`

- [ ] **Step 1: Replace the entire file**

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/core",
  "dowdiness/canopy/lang/json/edits" @json_edits,
  "dowdiness/canopy/lang/json/companion" @json_companion,
  "dowdiness/canopy/workspace/coordinator" @workspace,
  "dowdiness/incr/cells",
  "dowdiness/json" @djson,
  "dowdiness/loom/core" @loom,
  "moonbitlang/core/json" @core_json,
}

// `cells` field of JsonHandle is read in production by `json_get_errors`
// (parser_diagnostics, via Phase 1b workstream 2) and by whitebox tests
// (`lifecycle_phase1_wbtest.mbt`) for the remaining 6 cells. Until additional
// Phase 1b workstreams migrate the other production accessors, per-field
// unused warnings still fire on the rest of `JsonProtectedCells`.

warnings = "-7"

options(
  link: {
    "js": {
      "exports": [
        "create_json_editor",
        "destroy_json_editor",
        "json_get_text",
        "json_set_text",
        "json_get_errors",
        "json_get_proj_node_json",
        "json_get_source_map_json",
        "json_apply_edit",
        "json_get_view_tree_json",
        "json_compute_view_patches_json",
      ],
    },
  },
)
```

- [ ] **Step 2: Verify check passes**

Run: `NEW_MOON_MOD=0 moon check ffi/json`

Expected: PASS (with `warnings = "-7"` silencing any unused-import warning on the just-added imports).

- [ ] **Step 3: Commit**

```bash
git add ffi/json/moon.pkg
git commit -m "chore(ffi/json): §P0b Phase 1b WS2 — add workspace imports + warnings carve-out"
```

---

### Task C3: Create `JsonProtectedCells` bundle

**Files:**
- Create: `ffi/json/protected_cells.mbt`

Identical shape to `MarkdownProtectedCells`, parameterised on `@djson.JsonValue`.

- [ ] **Step 1: Create the file**

```
// JSON protected-cell bundle — typed view onto the editor surface that
// participates in workspace coordination.
//
// Each field wraps an editor `Derived[T]` in a long-lived `Watch` (the GC
// root) via `ProtectedCell::from_derived`. The bundle is constructed from a
// freshly-built editor inside `assemble_json_handle` (json_ffi.mbt) and
// erased to `Array[ProtectedRead]` for registration with the coordinator.
//
// 7-cell SyncEditor-generic subset (no language companion + no typecheck
// pipeline). See docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md
// §5.1.

///|
priv struct JsonProtectedCells {
  parser_syntax_tree : @workspace.ProtectedCell[@seam.SyntaxNode]
  parser_ast : @workspace.ProtectedCell[@djson.JsonValue]
  parser_source : @workspace.ProtectedCell[String]
  parser_diagnostics : @workspace.ProtectedCell[@loom.DiagnosticSet]
  cached_proj_node : @workspace.ProtectedCell[@core.ProjNode[@djson.JsonValue]?]
  registry_memo : @workspace.ProtectedCell[
    Map[@core.NodeId, @core.ProjNode[@djson.JsonValue]],
  ]
  source_map_memo : @workspace.ProtectedCell[@core.SourceMap]
}

///|
fn JsonProtectedCells::JsonProtectedCells(
  editor : @editor.SyncEditor[@djson.JsonValue],
) -> JsonProtectedCells {
  {
    parser_syntax_tree: @workspace.ProtectedCell::from_derived(
      "parser_syntax_view",
      editor.parser_syntax_tree(),
    ),
    parser_ast: @workspace.ProtectedCell::from_derived(
      "parser_ast_view",
      editor.parser_ast(),
    ),
    parser_source: @workspace.ProtectedCell::from_derived(
      "parser_source_view",
      editor.parser_source(),
    ),
    parser_diagnostics: @workspace.ProtectedCell::from_derived(
      "parser_diagnostics_view",
      editor.parser_diagnostics(),
    ),
    cached_proj_node: @workspace.ProtectedCell::from_derived(
      "cached_proj_node",
      editor.cached_proj_node(),
    ),
    registry_memo: @workspace.ProtectedCell::from_derived(
      "proj_registry",
      editor.registry_memo(),
    ),
    source_map_memo: @workspace.ProtectedCell::from_derived(
      "source_map",
      editor.source_map_memo(),
    ),
  }
}

///|
fn JsonProtectedCells::to_protected_reads(
  self : JsonProtectedCells,
) -> Array[@workspace.ProtectedRead] {
  [
    self.parser_syntax_tree.erase(),
    self.parser_ast.erase(),
    self.parser_source.erase(),
    self.parser_diagnostics.erase(),
    self.cached_proj_node.erase(),
    self.registry_memo.erase(),
    self.source_map_memo.erase(),
  ]
}
```

- [ ] **Step 2: Check compiles (add `"dowdiness/seam"` import if needed, same as B3)**

Run: `NEW_MOON_MOD=0 moon check ffi/json`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add ffi/json/protected_cells.mbt ffi/json/moon.pkg
git commit -m "feat(ffi/json): §P0b Phase 1b WS2 — add JsonProtectedCells 7-cell bundle"
```

---

### Task C4: Rewrite JSON lifecycle (handles + coordinator + assemble + destroy)

**Files:**
- Modify: `ffi/json/json_ffi.mbt`

- [ ] **Step 1: Replace the entire file**

```
// FFI surface for the JSON editor: lifecycle, text I/O, diagnostics, and
// view patches. Editor construction funnels through `assemble_json_handle`
// so the FFI ctor shares one `@incr.Runtime`, one atomic registration
// boundary, and one destroy gateway with the workspace coordinator. See
// docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md §5.
// Structural edits live in edit.mbt.

///|
priv struct JsonHandle {
  editor : @editor.SyncEditor[@djson.JsonValue]
  editor_id : @workspace.EditorId
  cells : JsonProtectedCells
}

///|
/// Process-global coordinator for the JSON FFI bundle. Per-language (not
/// shared with Lambda/Markdown) — see spec §4 for the JS-bundle empirical
/// justification.
let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()

///|
let json_handles : Map[Int, JsonHandle] = Map::default()

///|
let json_view_states : Map[Int, @editor.ViewUpdateState] = Map::default()

// ── Lifecycle ────────────────────────────────────────────────────────────

///|
/// Build a JSON editor on the shared runtime, then atomically register its
/// protected cells with the coordinator. Returns the freshly-allocated
/// `EditorId`. Aborting at any step leaves `json_handles` untouched
/// (atomic-boundary observation, spec §3.6).
fn assemble_json_handle(agent_id : String) -> @workspace.EditorId {
  let editor = @json_companion.new_json_editor(
    agent_id,
    parent_runtime=coordinator.runtime(),
  )
  let cells = JsonProtectedCells::JsonProtectedCells(editor)
  let editor_id = coordinator.register_editor(
    agent_id,
    cells.to_protected_reads(),
  )
  json_handles[editor_id.0] = { editor, editor_id, cells }
  editor_id
}

///|
/// Create a new JSON SyncEditor instance. Returns a unique handle.
pub fn create_json_editor(agent_id : String) -> Int {
  assemble_json_handle(agent_id).0
}

///|
/// Destroy a JSON editor and free its resources. The coordinator gateway
/// refuses if workspace deps still reference the editor; in that case the
/// FFI-side bookkeeping (json_handles entry, view_states entry) is
/// intentionally left intact so reads of cached state remain valid.
pub fn destroy_json_editor(handle : Int) -> Unit {
  let h = match json_handles.get(handle) {
    Some(v) => v
    None => return
  }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => {
      println("destroy_json_editor refused: \{report}")
      return
    }
  }
  json_handles.remove(handle)
  json_view_states.remove(handle)
}

///|
/// Get current text content of the JSON editor.
pub fn json_get_text(handle : Int) -> String {
  match json_handles.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire JSON document).
pub fn json_set_text(handle : Int, new_text : String) -> Unit {
  match json_handles.get(handle) {
    Some(h) => h.editor.set_text(new_text)
    None => ()
  }
}

// ── Diagnostics ──────────────────────────────────────────────────────────

///|
/// Get parse errors as JSON array of strings. Reads
/// `parser_diagnostics` through the coordinator's protected surface; on
/// Err collapses to "[]". Mirrors `SyncEditor::get_errors` empty-doc
/// short-circuit (`editor/sync_editor_parser.mbt:107-110`) at the FFI
/// boundary — pre-migration, that suppression lived inside the unmigrated
/// `ed.get_errors()` call. Without this guard the migration would surface
/// spurious empty-doc parser diagnostics that consumers were never
/// previously exposed to (Codex round-2 #1).
pub fn json_get_errors(handle : Int) -> String {
  let h = match json_handles.get(handle) {
    Some(v) => v
    None => return "[]"
  }
  if h.editor.get_text() == "" {
    return "[]"
  }
  match coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
    Ok(d) => d.format().to_json().stringify()
    Err(report) => {
      println("json_get_errors parser read: \{report}")
      "[]"
    }
  }
}

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available.
pub fn json_get_proj_node_json(handle : Int) -> String {
  match json_handles.get(handle) {
    Some(h) =>
      match h.editor.get_proj_node() {
        Some(proj) => proj.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Get the SourceMap as JSON string.
/// Returns an array of {node_id, start, end} entries.
pub fn json_get_source_map_json(handle : Int) -> String {
  match json_handles.get(handle) {
    Some(h) => h.editor.get_source_map().to_json().stringify()
    None => "[]"
  }
}

// ── View patches ─────────────────────────────────────────────────────────

///|
/// Get the ViewNode tree as JSON for a JSON editor.
/// Returns "null" if no projection is available.
pub fn json_get_view_tree_json(handle : Int) -> String {
  match json_handles.get(handle) {
    Some(h) =>
      match h.editor.get_view_tree() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a JSON editor.
/// Returns a JSON array of ViewPatch objects. NOT migrated to
/// `coordinator.read_protected` in WS2 — see spec §9 followup table; will
/// land in WS3+ alongside the rest of the unmigrated JSON accessors.
pub fn json_compute_view_patches_json(handle : Int) -> String {
  match json_handles.get(handle) {
    Some(h) => {
      let state = match json_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::ViewUpdateState()
          json_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
```

- [ ] **Step 2: Run `moon check`**

Run: `NEW_MOON_MOD=0 moon check ffi/json`

Expected: PASS. Likely errors:
- `json_editors` or `json_next_handle` referenced elsewhere — search `git grep json_editors -- ffi/json && git grep json_next_handle -- ffi/json` and fix.
- Note `d.format().to_json().stringify()` — `.format()` returns `Array[String]` (verified at `editor/sync_editor_parser.mbt:111`); `Array[String]::to_json()` is provided by the moonbit JSON derive. The chain matches the pre-migration shape `ed.get_errors().to_json().stringify()` exactly.

- [ ] **Step 3: Run `moon test`**

Run: `NEW_MOON_MOD=0 moon test`

Expected: green. Pre-existing JSON consumers (e.g. examples/web/src/json-editor.ts) call the FFI through the JS bundle, not via MoonBit tests, so the only test coverage that exercises the JSON FFI is what we'll add in C6.

- [ ] **Step 4: Commit**

```bash
git add ffi/json/json_ffi.mbt
git commit -m "feat(ffi/json): §P0b Phase 1b WS2 — assemble_json_handle + JsonHandle + coordinator-routed destroy + json_get_errors migration"
```

---

### Task C5: Update `edit.mbt` lookups to use `json_handles`

**Files:**
- Modify: `ffi/json/edit.mbt`

- [ ] **Step 1: Read the file**

Run: `cat ffi/json/edit.mbt` (or read via the Read tool) and note every reference to `json_editors`. Each must be replaced with `json_handles.get(handle).map(h => h.editor)` or equivalent pattern.

- [ ] **Step 2: Apply the replacement**

For each `match json_editors.get(handle)` block, replace with:

```
match json_handles.get(handle) {
  Some(h) => {
    // body that previously bound `ed` now binds `h.editor`; substitute `ed` → `h.editor`
  }
  None => ...
}
```

Concretely, if the old body was:

```
match json_editors.get(handle) {
  Some(ed) => @json_companion.apply_json_edit(ed, op, ts) ...
  None => ...
}
```

Rewrite as:

```
match json_handles.get(handle) {
  Some(h) => @json_companion.apply_json_edit(h.editor, op, ts) ...
  None => ...
}
```

Do **not** introduce a new `let ed = h.editor` binding — keep the call sites simple.

- [ ] **Step 3: Check and test**

```bash
NEW_MOON_MOD=0 moon check ffi/json
NEW_MOON_MOD=0 moon test
```

Both green.

- [ ] **Step 4: Commit**

```bash
git add ffi/json/edit.mbt
git commit -m "refactor(ffi/json): §P0b Phase 1b WS2 — route json_apply_edit lookups through json_handles"
```

---

### Task C6: Add structural §12 tests 1–4 for JSON

**Files:**
- Create: `ffi/json/lifecycle_phase1_wbtest.mbt`

Identical structure to PR-B's task B7 but parameterised on JSON-side names (`json_handles`, `create_json_editor`, etc.). The expected `Ok(s) => assert_eq(s, "")` for `parser_source` on a fresh editor holds for JSON identically (the empty-doc starting state is shared across all SyncEditor instances).

- [ ] **Step 1: Create the file with all four §12 tests**

```
// Whitebox integration tests for §P0b Phase 1b WS2: JSON FFI editors driven
// through the workspace coordinator. Covers spec §12 tests 1–4 (7-cell
// symmetric subset) — these need access to package-private symbols
// (`json_handles`, `coordinator`, `JsonHandle` fields), so they live in a
// `_wbtest.mbt`.
//
// §12 #5 (`ProtectedCellDisposed`) is workspace-generic and covered by
// `workspace/coordinator/coordinator_wbtest.mbt:33`.

///|
fn reset_json_coordinator_for_phase1_tests() -> Unit {
  let keys = json_handles.keys().to_array()
  for k in keys {
    json_handles.remove(k)
  }
  let vkeys = json_view_states.keys().to_array()
  for k in vkeys {
    json_view_states.remove(k)
  }
}

///|
test "spec §12 #1 (json): each protected cell reads through read_protected" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_one")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.read_protected(id, h.cells.parser_syntax_tree) {
    Ok(_) => ()
    Err(report) => fail("parser_syntax_tree: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_ast) {
    Ok(_) => ()
    Err(report) => fail("parser_ast: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_source) {
    Ok(s) => assert_eq(s, "")
    Err(report) => fail("parser_source: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_diagnostics) {
    Ok(_) => ()
    Err(report) => fail("parser_diagnostics: \{report}")
  }
  match coordinator.read_protected(id, h.cells.cached_proj_node) {
    Ok(_) => ()
    Err(report) => fail("cached_proj_node: \{report}")
  }
  match coordinator.read_protected(id, h.cells.registry_memo) {
    Ok(_) => ()
    Err(report) => fail("registry_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.source_map_memo) {
    Ok(_) => ()
    Err(report) => fail("source_map_memo: \{report}")
  }
  destroy_json_editor(handle)
}

///|
test "spec §12 #2 (json): destroy refused while depended-upon; succeeds after unregister_dep" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_two")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_ast_id = h.cells.parser_ast.cell_id()
  let synth_id = parser_ast_id
  coordinator.register_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon")
    Err(report) => assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
  }
  coordinator.unregister_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("expected Ok after unregister_dep, got \{report}")
  }
  json_handles.remove(handle)
  json_view_states.remove(handle)
}

///|
test "spec §12 #3 (json): read_protected after destroy returns EditorDestroyed" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_three")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_json_editor(handle)
  match coordinator.read_protected(id, parser_source_cell) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(report) => {
      assert_eq(report.kind, @workspace.EditorDestroyed)
      assert_eq(report.agent_id, "json_test_agent_three")
    }
  }
}

///|
test "spec §12 #4 (json): read_protected rejects cells from a different editor" {
  reset_json_coordinator_for_phase1_tests()
  let handle_a = create_json_editor("json_agent_alpha")
  let handle_b = create_json_editor("json_agent_beta")
  let h_a = json_handles.get(handle_a).unwrap()
  let h_b = json_handles.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_json_editor(handle_a)
  destroy_json_editor(handle_b)
}
```

- [ ] **Step 2: Run tests, expect 4 new passing**

```bash
NEW_MOON_MOD=0 moon test ffi/json
```

Expected: 4 tests pass.

- [ ] **Step 3: Confirm test count delta via summary**

Run: `NEW_MOON_MOD=0 moon test ffi/json 2>&1 | tail -5`

Verify 4 new tests in the report — not just "passes".

- [ ] **Step 4: Commit**

```bash
git add ffi/json/lifecycle_phase1_wbtest.mbt
git commit -m "test(ffi/json): §P0b Phase 1b WS2 — spec §12 tests 1-4 (read-all-7-cells, destroy-while-depended, read-after-destroy, cross-editor-rejection)"
```

---

### Task C7: Add behavior-equivalence + destroyed-editor regression tests for `json_get_errors`

Three risks per spec §7.2: empty-doc returns `"[]"`, parse-error path produces non-empty output, post-destroy collapses to `"[]"`.

**Files:**
- Modify: `ffi/json/lifecycle_phase1_wbtest.mbt` (append three tests)

- [ ] **Step 1: Empty-doc test (TDD — write first, run, expect PASS)**

Append:

```
///|
/// Phase 1b workstream 2 — `json_get_errors` migration regressions. Each
/// test corresponds to one behavioral risk called out in spec §7.2.
///
/// Empty-doc guard: pre-migration, `SyncEditor::get_errors` short-circuited
/// to `[]` on empty source (editor/sync_editor_parser.mbt:108-110) before
/// reading parser diagnostics — the parser produces spurious diagnostics
/// on "" source that must be suppressed. The migration must preserve that
/// semantic at the FFI boundary; calling `parser_diagnostics.format()`
/// unconditionally would surface those spurious errors.
test "workstream 2 (json): json_get_errors returns [] for empty source" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_empty_agent")
  // `create_json_editor` produces an editor with empty source — no set_text.
  assert_eq(json_get_errors(handle), "[]")
  destroy_json_editor(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/json`

Expected: PASS.

- [ ] **Step 2: Parse-error path test**

Append:

```
///|
/// Parse-error path: malformed JSON input produces a non-empty array of
/// diagnostic strings via the migrated `coordinator.read_protected(parser_
/// diagnostics).format()` chain. Output must still be a valid JSON array
/// (consumers parse it).
test "workstream 2 (json): json_get_errors returns non-empty array for parse error" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_parse_agent")
  // Unclosed object — guaranteed parse error.
  json_set_text(handle, "{ invalid")
  let out = json_get_errors(handle)
  // Must be a JSON array (starts with `[`, ends with `]`).
  if !out.has_prefix("[") || !out.has_suffix("]") {
    fail("expected JSON array shape, got \{out}")
  }
  // Must be non-empty (not "[]").
  if out == "[]" {
    fail("expected non-empty diagnostics for parse-error input, got []")
  }
  destroy_json_editor(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/json`

Expected: PASS. If `has_prefix` / `has_suffix` aren't on String in current MoonBit, substitute with `out.get(0) == Some('[')` and length-based suffix checks, or use `out.contains("[") && out.contains("]")` as the looser fallback. (Same shape as the workspace-wide pattern; verify against the workspace stdlib version in scope.)

- [ ] **Step 3: Post-destroy collapse test**

Append:

```
///|
/// Post-destroy path: after `coordinator.destroy_editor`, the accessor must
/// collapse to "[]" via the Err arm of `read_protected`. Pre-migration the
/// accessor read `ed.get_errors()` directly (bypassing the coordinator), so
/// a destroyed editor would have produced stale diagnostics from the
/// Derived cell rather than failing closed. This test pins the new
/// behavior.
test "workstream 2 (json): json_get_errors collapses to [] after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_destroy_agent")
  json_set_text(handle, "{ invalid")
  let alive = json_get_errors(handle)
  if alive == "[]" {
    fail("expected non-empty diagnostics pre-destroy, got []")
  }
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  // FFI bookkeeping retained — coordinator side is destroyed.
  match json_handles.get(handle) {
    Some(_) => ()
    None =>
      fail(
        "expected json_handles to retain handle after direct coordinator destroy",
      )
  }
  assert_eq(json_get_errors(handle), "[]")
  json_handles.remove(handle)
  json_view_states.remove(handle)
}
```

Run: `NEW_MOON_MOD=0 moon test ffi/json`

Expected: PASS. Test count delta C6 + C7 combined: +7 in `ffi/json/lifecycle_phase1_wbtest.mbt`.

- [ ] **Step 4: Commit**

```bash
git add ffi/json/lifecycle_phase1_wbtest.mbt
git commit -m "test(ffi/json): §P0b Phase 1b WS2 — empty-doc, parse-error, post-destroy regression for json_get_errors"
```

---

### Task C8: Format, regenerate `.mbti`, verify, push

Identical structure to PR-B's task B9.

- [ ] **Step 1: Format + regenerate**

```bash
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
```

- [ ] **Step 2: Check .mbti delta**

```bash
git diff ffi/json/pkg.generated.mbti
```

Expected: minimal. The JS exports list is unchanged from the original `ffi/json/moon.pkg:13-25`.

- [ ] **Step 3: Workspace check + test**

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
```

Both green.

- [ ] **Step 4: Build JS**

```bash
bash scripts/build-js.sh
```

Expected: produces `_build/js/release/build/dowdiness/canopy/ffi/json/json.js`.

- [ ] **Step 5: Commit format + mbti**

```bash
git add ffi/json/pkg.generated.mbti
git diff --cached --stat
git commit -m "chore(ffi/json): §P0b Phase 1b WS2 — moon fmt + moon info"
```

Skip the commit if `git diff --cached` shows no changes.

- [ ] **Step 6: Push and open the PR**

```bash
git push -u origin feat/ws2-json
gh pr create --title "feat(ffi/json): §P0b Phase 1b WS2 — coordinator-routed handle + json_get_errors migration" --body "$(cat <<'EOF'
## Summary
- Adds per-package `@workspace.Coordinator`, `JsonHandle`, `JsonProtectedCells` (7-cell SyncEditor-generic bundle), atomic `assemble_json_handle` ctor, and coordinator-routed `destroy_json_editor` to the JSON FFI surface.
- Co-migrates `json_get_errors` through `coordinator.read_protected(parser_diagnostics).format()`, with an explicit empty-doc guard mirroring `SyncEditor::get_errors`'s pre-existing short-circuit (Codex round-2 #1).
- Per spec §4: per-language coordinator only, no cross-language runtime sharing in WS2.

## Test plan
- [x] `NEW_MOON_MOD=0 moon check ffi/json` — clean
- [x] `NEW_MOON_MOD=0 moon test ffi/json` — 4 structural + 3 regression tests, all green
- [x] `NEW_MOON_MOD=0 moon test` — workspace-wide green
- [x] `bash scripts/build-js.sh` — `json.js` artifact still produced
- [ ] Codex scoped review of WS2 PR-C (pre-merge)
- [ ] Codex broad pre-merge pass (pair with scoped per `[[feedback-codex-broad-vs-scoped-review]]`)

Spec: docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md
Plan: docs/superpowers/plans/2026-05-26-p0b-phase1b-ws2-implementation.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Do NOT merge yet.** Apply the same scoped + broad Codex review pair as PR-B.

---

## Cross-PR notes

- **No dependency between PR-B and PR-C.** They can land in either order. Each one shipping alone reduces dead-code surface on its FFI bundle; both together complete WS2.
- **Merge sequencing.** Even though the PRs are independent, each must individually pass: (1) Codex scoped review, (2) Codex broad review, (3) fully green CI per `[[feedback-ci-merge-policy]]` (skipped checks are NOT passing). After both reviews + green CI, merge via `gh pr merge --squash --delete-branch`. Per `[[feedback-gh-delete-branch-worktree]]`: if a worktree still holds the branch, the `--delete-branch` step fails — clean up the worktree first.
- **Followups (spec §9).** Five known followups intentionally NOT in scope: migrate ~12 remaining accessors (WS3+), first cross-language workspace memo, shared coordinator across all three FFI surfaces, Markdown `LanguageCapabilities` annotations wiring, extract the duplicated `diff_view_nodes`. None of these block WS2 merging.
- **What this plan does NOT change.** Lambda's FFI, any language companion package, `@workspace.Coordinator`, `@editor`, `@protocol`. Greatest blast radius is two FFI directories totalling ~400 new lines + ~80-line `diff_view_nodes` duplicate.

---

## Self-review checklist

Run mentally before declaring the plan complete:

1. **Spec coverage:**
   - §3.1 (per-language coordinator) → B5 + C4 (module-scope `let coordinator`)
   - §3.2 (empty-doc behavior) → B6 step 1 (md guard) + C4 (`json_get_errors`) + C7 step 1 (test)
   - §3.3 (private `diff_view_nodes`) → B4 (local duplicate)
   - §3.4 (raw `get_text`) → B6 step 1 (`let source_text = h.editor.get_text()`)
   - §3.5 (destroy ordering) → B5 step 1 + C4 step 1
   - §3.6 (atomic ctor) → B5 step 1 + C4 step 1
   - §3.7 (symmetric 7-cell shape) → B3 + C3
   - §4 (per-language justification) → B5 + C4 module-scope comments
   - §5.1 (cells table) → B3 + C3 (field-by-field)
   - §5.1.1 (handle namespace) → B5 + C4 (counters removed)
   - §5.2 (`<Lang>Handle` + assemble) → B5 + C4
   - §5.3 (destroy_<lang>_editor) → B5 + C4
   - §5.4 (warnings carve-out) → B2 + C2
   - §6.1 (`json_get_errors`) → C4
   - §6.2 (`markdown_compute_view_patches_json`) → B6
   - §7.1 (structural §12 tests 1–4) → B7 + C6
   - §7.2 (regression tests per accessor) → B8 + C7
   - §7.3 (test count +14 expected) → B7+B8 contribute +7, C6+C7 contribute +7, total +14 ✓
   - §8 (PR decomposition) → PR-B / PR-C split

2. **Placeholder scan:** no `TBD`, no "implement appropriate", no "similar to Task N", no symbol references without definition. Every code block is the full body the engineer types.

3. **Type consistency:**
   - `MarkdownProtectedCells` field types (B3) match the read sites (B6, B7) — `cached_proj_node : ProtectedCell[ProjNode[@md.Block]?]`, used as `Ok(proj_opt) => match proj_opt { Some(proj) => ... }` ✓
   - `JsonProtectedCells` field types (C3) match the read sites (C4, C6, C7) ✓
   - `assemble_<lang>_handle` returns `@workspace.EditorId`; `create_<lang>_editor` returns `Int` via `.0` projection — symmetric to Lambda's `lifecycle.mbt:118-120` ✓
   - `diff_view_nodes` signature in B4 matches the call site in B6 ✓
   - `@protocol.proj_to_view_node` call in B6 step 1 — argument order verified against `protocol/pkg.generated.mbti:13` (positional `proj`, `source_map`; labelled `annotations?`, `source_text?`); the call passes both labelled args after positionals which is current MoonBit-correct ✓
