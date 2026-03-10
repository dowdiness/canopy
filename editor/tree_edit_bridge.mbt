// Tree Edit Bridge: Round-trip tree edits through the text CRDT
// TreeEditOp -> CanonicalModel (structural) -> unparse -> diff -> CRDT ops

///|
/// Apply a tree edit by round-tripping through the text CRDT.
///
/// 1. Apply tree edit structurally to CanonicalModel
/// 2. Unparse modified AST to text
/// 3. Diff against current CRDT text
/// 4. Apply diff as CRDT text ops (broadcastable to peers)
/// 5. Re-reconcile CanonicalModel from authoritative CRDT text
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  canonical : @proj.CanonicalModel,
  op : @proj.TreeEditOp,
) -> Result[Unit, String] {
  let old_text = self.get_text()

  // 1. Apply tree edit structurally to CanonicalModel
  match @proj.tree_lens_apply_edit(canonical, op) {
    Ok(_) => ()
    Err(msg) => return Err(msg)
  }

  // 2. Get text representation of modified AST
  let new_text = match @proj.text_lens_get(canonical) {
    Ok(t) => t
    Err(_) => ""
  }

  // 3. Skip CRDT ops if text unchanged (UI-only ops: Select, Collapse, etc.)
  if old_text == new_text {
    return Ok(())
  }

  // 4. Diff and apply as CRDT text ops
  let edits = @proj.text_lens_diff(old_text, new_text)
  apply_projection_edits(self, edits)

  // 5. Trigger reparse
  self.parser.set_source(self.doc.text())

  // 6. Re-reconcile CanonicalModel from authoritative CRDT text
  let _ = @proj.text_lens_put(canonical, self.doc.text())

  Ok(())
}

///|
/// Apply ProjectionEdits as CRDT text operations.
/// Edits from text_lens_diff are ordered: insert first (at original position),
/// then delete (with positions adjusted for the preceding insert).
fn apply_projection_edits(
  editor : SyncEditor,
  edits : Array[@proj.ProjectionEdit],
) -> Unit {
  for edit in edits {
    match edit {
      TextInsert(position~, text~) =>
        editor.doc.insert(@text.Pos::at(position), text) catch {
          _ => ()
        }
      TextDelete(start~, end~) => {
        let count = end - start
        for _j = 0; _j < count; _j = _j + 1 {
          editor.doc.delete(@text.Pos::at(start)) catch {
            _ => ()
          }
        }
      }
      _ => () // NodeSelect, NodeValueChange, StructuralChange — UI-only
    }
  }
}
