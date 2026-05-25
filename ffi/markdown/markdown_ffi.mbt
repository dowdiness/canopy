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
