// Public API for applying span-level text edits from structural editing.
// Used by language companions (e.g. LambdaCompanion) to apply tree edits
// through the text CRDT without accessing SyncEditor internals.

///|
/// Apply a list of SpanEdits through the text CRDT, then adjust the cursor
/// per the FocusHint. Edits are applied in reverse document order to avoid
/// position shifts. All edits are recorded for undo.
pub fn[T] SyncEditor::apply_span_edits(
  self : SyncEditor[T],
  edits : Array[@proj.SpanEdit],
  focus_hint : @proj.FocusHint,
  timestamp_ms : Int,
) -> Unit {
  if edits.is_empty() {
    return
  }
  let old_cursor = self.get_cursor()
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  for edit in sorted {
    self.apply_text_edit_internal(
      edit.start,
      edit.delete_len,
      edit.inserted,
      timestamp_ms,
      true, // record_undo — grouped by capture timeout
      false, // move_cursor_to_edit_end
    )
  }
  match focus_hint {
    @proj.FocusHint::RestoreCursor => self.move_cursor(old_cursor)
    @proj.FocusHint::MoveCursor(position~) => self.move_cursor(position)
  }
}
