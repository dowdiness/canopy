// Text and cursor operations for SyncEditor.

///|
pub fn SyncEditor::insert(self : SyncEditor, text : String) -> Unit raise {
  let old_source = self.doc.text()
  let insert_start = self.cursor
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor = self.cursor + text.length()
  self.apply_local_text_change(
    old_source,
    self.doc.text(),
    Some(@parser.Edit::insert(insert_start, text.length())),
  )
}

///|
pub fn SyncEditor::delete(self : SyncEditor) -> Bool {
  let old_source = self.doc.text()
  try self.doc.delete(@text.Pos::at(self.cursor)) catch {
    _ => false
  } noraise {
    _ => {
      self.apply_local_text_change(
        old_source,
        self.doc.text(),
        Some(@parser.Edit::delete(self.cursor, self.cursor + 1)),
      )
      true
    }
  }
}

///|
pub fn SyncEditor::backspace(self : SyncEditor) -> Bool {
  if self.cursor > 0 {
    let old_source = self.doc.text()
    self.cursor = self.cursor - 1
    try self.doc.delete(@text.Pos::at(self.cursor)) catch {
      _ => {
        self.cursor = self.cursor + 1
        false
      }
    } noraise {
      _ => {
        self.apply_local_text_change(
          old_source,
          self.doc.text(),
          Some(@parser.Edit::delete(self.cursor, self.cursor + 1)),
        )
        true
      }
    }
  } else {
    false
  }
}

///|
pub fn SyncEditor::move_cursor(self : SyncEditor, position : Int) -> Unit {
  let text_len = self.doc.len()
  if position < 0 {
    self.cursor = 0
  } else if position > text_len {
    self.cursor = text_len
  } else {
    self.cursor = position
  }
}

///|
pub fn SyncEditor::get_text(self : SyncEditor) -> String {
  self.doc.text()
}

///|
pub fn SyncEditor::get_cursor(self : SyncEditor) -> Int {
  self.cursor
}

///|
fn SyncEditor::apply_replace_span(
  self : SyncEditor,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
) -> Unit {
  let range = @text.Range::from_ints(start, start + deleted_len)
  if record_undo {
    self.doc.replace_range_and_record(range, inserted, self.undo, timestamp_ms~) catch {
      _ => ()
    }
  } else {
    self.doc.replace_range(range, inserted) catch {
      _ => ()
    }
  }
}

///|
fn SyncEditor::apply_text_edit_internal(
  self : SyncEditor,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
  move_cursor_to_edit_end : Bool,
) -> Unit {
  let old_source = self.doc.text()
  let text_len = self.doc.len()
  let safe_start = if start < 0 {
    0
  } else if start > text_len {
    text_len
  } else {
    start
  }
  let max_delete_len = text_len - safe_start
  let safe_delete_len = if deleted_len < 0 {
    0
  } else if deleted_len > max_delete_len {
    max_delete_len
  } else {
    deleted_len
  }
  // Funnel all bulk text mutation through one helper so CRDT range-edit and
  // undo behavior stay aligned at a single boundary.
  self.apply_replace_span(
    safe_start, safe_delete_len, inserted, timestamp_ms, record_undo,
  )
  if move_cursor_to_edit_end {
    self.cursor = safe_start + inserted.length()
  } else {
    self.adjust_cursor()
  }
  self.apply_local_text_change(
    old_source,
    self.doc.text(),
    Some(@parser.Edit::new(safe_start, safe_delete_len, inserted.length())),
  )
}

///|
pub fn SyncEditor::apply_text_edit(
  self : SyncEditor,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
) -> Unit {
  self.apply_text_edit_internal(
    start, deleted_len, inserted, timestamp_ms, true, true,
  )
}

///|
/// Replace the document text with `new_text` via a single range edit.
///
/// **CRDT position caveat:** `replace_range` inserts all characters as a
/// contiguous batch, so the internal FugueMax tree has no interleaving
/// points between them. A subsequent `insert` / `insert_and_record` at
/// position 0 may resolve to the *end* of the batch rather than prepending,
/// because FugueMax's tie-breaking places the new character after the
/// batch's root. Use `set_text` only for bulk initialization or
/// synchronization; for interactive typing, prefer the per-character
/// `insert` / `insert_and_record` methods which create proper interleaving
/// points. See `resolve_applied_edit` in `sync_editor_parser.mbt` for how
/// the cursor adjustment layer compensates for this divergence.
pub fn SyncEditor::set_text(self : SyncEditor, new_text : String) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let splice = @text_change.compute_text_change(old_text, new_text)
  self.apply_text_edit_internal(
    splice.start,
    splice.delete_len,
    splice.inserted,
    0,
    false,
    true,
  )
}

///|
/// Insert text at a specific position without moving the cursor.
/// Records the operation for undo. Used by ProseMirror bridge.
pub fn SyncEditor::insert_at(
  self : SyncEditor,
  position : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  let text_len = self.doc.len()
  if position < 0 || position > text_len {
    return
  }
  self.apply_text_edit_internal(position, 0, text, timestamp_ms, true, false)
}

///|
/// Delete the character at a specific position without moving the cursor.
/// Records the operation for undo. Returns false if position is out of bounds.
/// Used by ProseMirror bridge.
pub fn SyncEditor::delete_at(
  self : SyncEditor,
  position : Int,
  timestamp_ms : Int,
) -> Bool {
  let text_len = self.doc.len()
  if position < 0 || position >= text_len {
    return false
  }
  self.apply_text_edit_internal(position, 1, "", timestamp_ms, true, false)
  true
}

///|
pub fn SyncEditor::set_text_and_record(
  self : SyncEditor,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let splice = @text_change.compute_text_change(old_text, new_text)
  self.apply_text_edit_internal(
    splice.start,
    splice.delete_len,
    splice.inserted,
    timestamp_ms,
    true,
    false,
  )
}
