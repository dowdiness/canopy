// Undo integration for SyncEditor.

///|
pub fn SyncEditor::insert_and_record(
  self : SyncEditor,
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  let old_source = self.doc.text()
  let insert_start = self.cursor
  self.doc.insert_and_record(
    @text.Pos::at(self.cursor),
    text,
    self.undo,
    timestamp_ms~,
  )
  self.cursor = self.cursor + text.length()
  self.apply_local_text_change(
    old_source,
    self.doc.text(),
    Some(@parser.Edit::insert(insert_start, text.length())),
  )
}

///|
pub fn SyncEditor::delete_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  let old_source = self.doc.text()
  try {
    self.doc.delete_and_record(
      @text.Pos::at(self.cursor),
      self.undo,
      timestamp_ms~,
    )
    self.apply_local_text_change(
      old_source,
      self.doc.text(),
      Some(@parser.Edit::delete(self.cursor, self.cursor + 1)),
    )
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::backspace_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  if self.cursor > 0 {
    let old_source = self.doc.text()
    let new_pos = self.cursor - 1
    try {
      self.doc.delete_and_record(
        @text.Pos::at(new_pos),
        self.undo,
        timestamp_ms~,
      )
      self.cursor = new_pos
      self.apply_local_text_change(
        old_source,
        self.doc.text(),
        Some(@parser.Edit::delete(new_pos, new_pos + 1)),
      )
      true
    } catch {
      _ => false
    }
  } else {
    false
  }
}

///|
pub fn SyncEditor::undo(self : SyncEditor) -> Bool {
  let old_source = self.doc.text()
  try {
    self.undo.undo(self.doc)
    let new_source = self.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::redo(self : SyncEditor) -> Bool {
  let old_source = self.doc.text()
  try {
    self.undo.redo(self.doc)
    let new_source = self.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
/// Undo and return a SyncMessage containing the inverse ops for peer broadcast.
/// Returns None if undo stack is empty or undo fails.
pub fn SyncEditor::undo_and_export(self : SyncEditor) -> @text.SyncMessage? {
  let ver_before = self.doc.version()
  let old_source = self.doc.text()
  let success = try {
    self.undo.undo(self.doc)
    let new_source = self.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
  if not(success) {
    return None
  }
  try {
    Some(self.doc.sync().export_since(ver_before))
  } catch {
    _ => None
  }
}

///|
/// Redo and return a SyncMessage containing the ops for peer broadcast.
/// Returns None if redo stack is empty or redo fails.
pub fn SyncEditor::redo_and_export(self : SyncEditor) -> @text.SyncMessage? {
  let ver_before = self.doc.version()
  let old_source = self.doc.text()
  let success = try {
    self.undo.redo(self.doc)
    let new_source = self.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
  if not(success) {
    return None
  }
  try {
    Some(self.doc.sync().export_since(ver_before))
  } catch {
    _ => None
  }
}

///|
pub fn SyncEditor::can_undo(self : SyncEditor) -> Bool {
  self.undo.can_undo()
}

///|
pub fn SyncEditor::can_redo(self : SyncEditor) -> Bool {
  self.undo.can_redo()
}

///|
pub fn SyncEditor::set_tracking(self : SyncEditor, enabled : Bool) -> Unit {
  self.undo.set_tracking(enabled)
}

///|
pub fn SyncEditor::clear_undo(self : SyncEditor) -> Unit {
  self.undo.clear()
}
