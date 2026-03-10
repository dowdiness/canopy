// Tree Edit Bridge: Round-trip tree edits through the text CRDT
// TreeEditOp -> CanonicalModel (structural) -> unparse -> set_text -> reparse

///|
/// Apply a tree edit by round-tripping through the text CRDT.
///
/// 1. Apply tree edit structurally to CanonicalModel
/// 2. Unparse modified AST to text
/// 3. Set CRDT text to the new text (generates broadcastable ops)
/// 4. Re-reconcile CanonicalModel from authoritative CRDT text
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  canonical : @proj.CanonicalModel,
  op : @proj.TreeEditOp,
) -> Result[Unit, String] {
  let old_text = self.get_text()
  let old_cursor = self.get_cursor()

  // 1. Apply tree edit structurally to CanonicalModel
  match @proj.tree_lens_apply_edit(canonical, op) {
    Ok(_) => ()
    Err(msg) => return Err(msg)
  }

  // 2. Get text representation of modified AST
  let new_text = match @proj.text_lens_get(canonical) {
    Ok(t) => t
    Err(msg) => return Err("text_lens_get failed: " + msg)
  }

  // 3. Skip CRDT ops if text unchanged (UI-only ops: Select, Collapse, etc.)
  if old_text == new_text {
    return Ok(())
  }

  // 4. Apply text change to CRDT (set_text handles diff internally)
  self.set_text(new_text)
  self.move_cursor(old_cursor)

  // 5. Re-reconcile CanonicalModel from authoritative CRDT text
  // (re-parses to update positions; known double-parse, see TODO.md §6)
  match @proj.text_lens_put(canonical, self.doc.text()) {
    Ok(_) => Ok(())
    Err(msg) => Err("text_lens_put failed: " + msg)
  }
}
