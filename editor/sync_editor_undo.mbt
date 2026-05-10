// Undo integration for SyncEditor.

///|
pub fn[T : Eq] SyncEditor::insert_and_record(
  self : SyncEditor[T],
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  let old_source = self.doc.text()
  self.cursor = @moji.prev_grapheme_boundary(old_source, self.cursor)
  let insert_start = self.cursor
  let item_start = utf16_offset_to_item_pos(old_source, insert_start)
  self.doc.insert_and_record(
    @text.Pos::at(item_start),
    text,
    self.undo,
    timestamp_ms~,
  )
  self.cursor = @moji.next_grapheme_boundary(
    self.doc.text(),
    insert_start + text.length(),
  )
  self.apply_local_text_change(
    old_source,
    self.doc.text(),
    Some(@loom_core.Edit::insert(insert_start, text.length())),
  )
}

///|
pub fn[T : Eq] SyncEditor::delete_and_record(
  self : SyncEditor[T],
  timestamp_ms : Int,
) -> Bool {
  let old_source = self.doc.text()
  if !@moji.is_grapheme_boundary(old_source, self.cursor) {
    self.cursor = @moji.prev_grapheme_boundary(old_source, self.cursor)
  }
  if self.cursor >= old_source.length() {
    return false
  }
  let delete_start = self.cursor
  let right = @moji.next_grapheme_boundary(old_source, self.cursor + 1)
  if right == delete_start {
    return false
  }
  let item_start = utf16_offset_to_item_pos(old_source, delete_start)
  let item_end = utf16_offset_to_item_pos(old_source, right)
  try {
    self.doc.delete_range_and_record(
      @text.Range::from_ints(item_start, item_end),
      self.undo,
      timestamp_ms~,
    )
    let new_text = self.doc.text()
    self.cursor = @moji.next_grapheme_boundary(
      new_text,
      clamp_utf16_offset(new_text, self.cursor),
    )
    self.apply_local_text_change(
      old_source,
      new_text,
      Some(@loom_core.Edit::delete(delete_start, right)),
    )
    true
  } catch {
    _ => false
  }
}

///|
pub fn[T : Eq] SyncEditor::backspace_and_record(
  self : SyncEditor[T],
  timestamp_ms : Int,
) -> Bool {
  let old_source = self.doc.text()
  if !@moji.is_grapheme_boundary(old_source, self.cursor) {
    self.cursor = @moji.next_grapheme_boundary(old_source, self.cursor)
  }
  if self.cursor > 0 {
    let delete_end = self.cursor
    let left = @moji.prev_grapheme_boundary(old_source, self.cursor - 1)
    let item_start = utf16_offset_to_item_pos(old_source, left)
    let item_end = utf16_offset_to_item_pos(old_source, delete_end)
    try {
      self.doc.delete_range_and_record(
        @text.Range::from_ints(item_start, item_end),
        self.undo,
        timestamp_ms~,
      )
      self.cursor = left
      self.apply_local_text_change(
        old_source,
        self.doc.text(),
        Some(@loom_core.Edit::delete(left, delete_end)),
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
pub fn[T : Eq] SyncEditor::undo(self : SyncEditor[T]) -> Bool {
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
pub fn[T : Eq] SyncEditor::redo(self : SyncEditor[T]) -> Bool {
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
pub fn[T : Eq] SyncEditor::undo_and_export(
  self : SyncEditor[T],
) -> @text.SyncMessage? {
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
  if !success {
    return None
  }
  Some(self.doc.sync().export_since(ver_before)) catch {
    _ => None
  }
}

///|
/// Redo and return a SyncMessage containing the ops for peer broadcast.
/// Returns None if redo stack is empty or redo fails.
pub fn[T : Eq] SyncEditor::redo_and_export(
  self : SyncEditor[T],
) -> @text.SyncMessage? {
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
  if !success {
    return None
  }
  Some(self.doc.sync().export_since(ver_before)) catch {
    _ => None
  }
}

///|
pub fn[T] SyncEditor::can_undo(self : SyncEditor[T]) -> Bool {
  self.undo.can_undo()
}

///|
pub fn[T] SyncEditor::can_redo(self : SyncEditor[T]) -> Bool {
  self.undo.can_redo()
}

///|
pub fn[T] SyncEditor::set_tracking(
  self : SyncEditor[T],
  enabled : Bool,
) -> Unit {
  self.undo.set_tracking(enabled)
}

///|
pub fn[T] SyncEditor::clear_undo(self : SyncEditor[T]) -> Unit {
  self.undo.clear()
}
