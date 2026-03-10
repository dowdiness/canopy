// Tree Edit Bridge: Apply structural projection edits through the text CRDT.
// TreeEditOp -> ProjNode -> unparse -> set_text_and_record -> memo reconcile

///|
/// Apply a tree edit by round-tripping through the text CRDT.
///
/// 1. Apply tree edit structurally to the current ProjNode
/// 2. Unparse modified AST to text
/// 3. Set CRDT text to the new text (generates broadcastable ops + undo history)
/// 4. Memo chain re-derives ProjNode from authoritative text on next access
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  op : @proj.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let old_text = self.get_text()
  let old_cursor = self.get_cursor()

  let proj = match self.get_proj_node() {
    Some(p) => p
    None => return Err("No ProjNode available")
  }
  let new_proj = match
    @proj.apply_edit_to_proj(
      proj,
      op,
      self.registry_memo.get(),
      self.next_node_id,
    ) {
    Ok(updated) => updated
    Err(msg) => return Err(msg)
  }
  let new_text = @ast.print_term(new_proj.kind)

  // 3. Skip CRDT ops if text unchanged (UI-only ops: Select, Collapse, etc.)
  if old_text == new_text {
    return Ok(())
  }

  // Seed memo reconciliation with the structurally edited tree so the
  // subsequent reparse preserves node identities from the edit result.
  self.seed_proj_node(Some(new_proj))
  self.set_text_and_record(new_text, timestamp_ms)
  self.move_cursor(old_cursor)
  Ok(())
}
