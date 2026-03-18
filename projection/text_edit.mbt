///|
/// A text span replacement: replace source_text[start : start+delete_len] with inserted.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
/// Translate a TreeEditOp into text span edits using the source map.
/// Returns None for unhandled ops (fall back to old path during migration).
/// Returns Some([]) for no-op ops (Select, Collapse, etc.).
pub fn compute_text_edit(
  op : TreeEditOp,
  source_text : String,
  source_map : SourceMap,
  registry : Map[NodeId, ProjNode],
  flat_proj : FlatProj,
) -> Result[Array[SpanEdit]?, String] {
  let _ = source_text
  let _ = registry
  let _ = flat_proj
  match op {
    // No-op operations — these don't modify source text
    Select(..)
    | SelectRange(..)
    | StartEdit(..)
    | CancelEdit
    | StartDrag(..)
    | DragOver(..)
    | Collapse(..)
    | Expand(..) => Ok(Some([]))
    // CommitEdit: replace node span with new user-provided text
    CommitEdit(node_id~, new_value~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) =>
          Ok(
            Some([
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: new_value,
              },
            ]),
          )
      }
    // Unhandled — fall back to old path
    _ => Ok(None)
  }
}
