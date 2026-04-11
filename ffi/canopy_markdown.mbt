///| FFI exports for the Markdown editor.
/// Handles start at 20000 to avoid collisions with lambda (0+) and JSON (10000+).

///|
let markdown_editors : Map[Int, @editor.SyncEditor[@markdown.Block]] = Map::new()

///|
let markdown_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
let markdown_next_handle : Ref[Int] = { val: 20000 }

///|
pub fn create_markdown_editor(agent_id : String) -> Int {
  let handle = markdown_next_handle.val
  markdown_next_handle.val = handle + 1
  markdown_editors[handle] = @md_edits.new_markdown_editor(agent_id)
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
/// Return markdown text with ZWSP placeholders stripped.
/// Use for export, clipboard, raw-mode display — not for internal position math.
pub fn markdown_export_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text().replace_all(old="\u200B", new="")
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
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
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
      match @md_edits.apply_markdown_edit(ed, op, timestamp_ms) {
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
