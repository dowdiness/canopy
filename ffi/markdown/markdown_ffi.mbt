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
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("markdown_export_text proj read: \{report}")
          return ""
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("markdown_export_text source_map read: \{report}")
          return ""
        }
      }
      @md_companion.export_markdown_text(h.editor)
    }
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
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("markdown_apply_edit proj read: \{report}")
          return Json::object({
            "status": Json::string("error"),
            "message": Json::string("editor unavailable"),
          }).stringify()
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("markdown_apply_edit source_map read: \{report}")
          return Json::object({
            "status": Json::string("error"),
            "message": Json::string("editor unavailable"),
          }).stringify()
        }
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
    state.set_had_errors(true)
  } else if state.had_errors {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
    state.set_had_errors(false)
  }
  state.set_previous(current)
  Json::array(patches.map(fn(p) { p.to_json() })).stringify()
}
