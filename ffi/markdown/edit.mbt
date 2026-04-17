// Markdown editor structural edits

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
