///| FFI surface for the Markdown editor: lifecycle, text I/O, structural
/// edits, and view patches. Handles start at 20000 to avoid collisions
/// with lambda (0+) and JSON (10000+).

///|
let markdown_editors : Map[Int, @editor.SyncEditor[@md.Block]] = Map::default()

///|
let markdown_next_handle : Ref[Int] = { val: 20000 }

///|
let markdown_view_states : Map[Int, @editor.ViewUpdateState] = Map::default()

// ── Lifecycle ────────────────────────────────────────────────────────────

///|
pub fn create_markdown_editor(agent_id : String) -> Int {
  let handle = markdown_next_handle.val
  markdown_next_handle.val = handle + 1
  markdown_editors[handle] = @md_companion.new_markdown_editor(agent_id)
  handle
}

///|
pub fn destroy_markdown_editor(handle : Int) -> Unit {
  markdown_editors.remove(handle)
  markdown_view_states.remove(handle)
}

///|
pub fn markdown_get_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
/// Return markdown text with ZWSP placeholder paragraphs stripped structurally.
/// Delegates to the companion helper which walks the projection tree, identifies
/// sentinel paragraphs (AST `Paragraph([Text("\u200B")])`), and removes only the
/// ZWSP character itself \u2014 leaving ZWSP inside other content (code blocks,
/// paragraphs with mixed text) untouched.
pub fn markdown_export_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => @md_companion.export_markdown_text(ed)
    None => ""
  }
}

///|
pub fn markdown_set_text(handle : Int, text : String) -> Unit {
  match markdown_editors.get(handle) {
    Some(ed) => ed.set_text(text)
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
  match markdown_editors.get(handle) {
    Some(ed) => {
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
      match @md_companion.apply_markdown_edit(ed, op, timestamp_ms) {
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
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::ViewUpdateState()
          markdown_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, ed)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
