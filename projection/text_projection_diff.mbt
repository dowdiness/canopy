// Text/projection diff adapter for legacy projection edit consumers.
// Shared diff logic stays in dowdiness/crdt/text_change; this file only maps it
// into the compatibility-era ProjectionEdit surface.

///|
pub fn text_lens_diff(
  old_text : String,
  new_text : String,
) -> Array[ProjectionEdit] {
  // Delete this adapter when ProjectionEdit-based consumers are retired.
  let change = @text_change.compute_text_change(old_text, new_text)
  let edits : Array[ProjectionEdit] = []
  if change.inserted.length() > 0 {
    edits.push(TextInsert(position=change.start, text=change.inserted))
  }
  if change.delete_len > 0 {
    let delete_start = change.start + change.inserted.length()
    edits.push(
      TextDelete(start=delete_start, end=delete_start + change.delete_len),
    )
  }
  edits
}
