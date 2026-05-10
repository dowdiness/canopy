// Text and cursor operations for SyncEditor.

///|
priv enum SplicePolicy {
  SnapToGrapheme
  ExactBoundaries
}

///|
fn clamp_utf16_offset(text : String, position : Int) -> Int {
  if position < 0 {
    0
  } else if position > text.length() {
    text.length()
  } else {
    position
  }
}

///|
fn utf16_offset_to_item_pos(text : String, offset : Int) -> Int {
  let target = clamp_utf16_offset(text, offset)
  let mut utf16_pos = 0
  let mut item_pos = 0
  for ch in text {
    let next_utf16_pos = utf16_pos + ch.to_string().length()
    if next_utf16_pos > target {
      return item_pos
    }
    item_pos = item_pos + 1
    if next_utf16_pos == target {
      return item_pos
    }
    utf16_pos = next_utf16_pos
  }
  item_pos
}

///|
pub fn[T : Eq] SyncEditor::insert(
  self : SyncEditor[T],
  text : String,
) -> Unit raise {
  let old_source = self.doc.text()
  self.cursor = @moji.prev_grapheme_boundary(old_source, self.cursor)
  let insert_start = self.cursor
  let item_start = utf16_offset_to_item_pos(old_source, insert_start)
  self.doc.insert(@text.Pos::at(item_start), text)
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
pub fn[T : Eq] SyncEditor::delete(self : SyncEditor[T]) -> Bool {
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
  try
    self.doc.delete_range(@text.Range::from_ints(item_start, item_end))
  catch {
    _ => false
  } noraise {
    _ => {
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
    }
  }
}

///|
pub fn[T : Eq] SyncEditor::backspace(self : SyncEditor[T]) -> Bool {
  let old_source = self.doc.text()
  if !@moji.is_grapheme_boundary(old_source, self.cursor) {
    self.cursor = @moji.next_grapheme_boundary(old_source, self.cursor)
  }
  if self.cursor > 0 {
    let delete_end = self.cursor
    let left = @moji.prev_grapheme_boundary(old_source, self.cursor - 1)
    let item_start = utf16_offset_to_item_pos(old_source, left)
    let item_end = utf16_offset_to_item_pos(old_source, delete_end)
    try
      self.doc.delete_range(@text.Range::from_ints(item_start, item_end))
    catch {
      _ => false
    } noraise {
      _ => {
        self.cursor = left
        self.apply_local_text_change(
          old_source,
          self.doc.text(),
          Some(@loom_core.Edit::delete(left, delete_end)),
        )
        true
      }
    }
  } else {
    false
  }
}

///|
pub fn[T] SyncEditor::move_cursor(self : SyncEditor[T], position : Int) -> Unit {
  let text = self.doc.text()
  self.cursor = @moji.prev_grapheme_boundary(
    text,
    clamp_utf16_offset(text, position),
  )
}

///|
pub fn[T] SyncEditor::move_cursor_left_grapheme(self : SyncEditor[T]) -> Unit {
  if self.cursor == 0 {
    return
  }
  self.cursor = @moji.prev_grapheme_boundary(self.doc.text(), self.cursor - 1)
}

///|
pub fn[T] SyncEditor::move_cursor_right_grapheme(self : SyncEditor[T]) -> Unit {
  let text = self.doc.text()
  if self.cursor == text.length() {
    return
  }
  self.cursor = @moji.next_grapheme_boundary(text, self.cursor + 1)
}

///|
pub fn[T] SyncEditor::move_cursor_left_word(self : SyncEditor[T]) -> Unit {
  if self.cursor == 0 {
    return
  }
  self.cursor = @moji.prev_word_boundary(self.doc.text(), self.cursor - 1)
}

///|
pub fn[T] SyncEditor::move_cursor_right_word(self : SyncEditor[T]) -> Unit {
  let text = self.doc.text()
  if self.cursor == text.length() {
    return
  }
  self.cursor = @moji.next_word_boundary(text, self.cursor + 1)
}

///|
pub fn[T] SyncEditor::get_text(self : SyncEditor[T]) -> String {
  self.doc.text()
}

///|
pub fn[T] SyncEditor::get_cursor(self : SyncEditor[T]) -> Int {
  self.cursor
}

///|
fn[T] SyncEditor::apply_replace_span(
  self : SyncEditor[T],
  old_source : String,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
) -> Bool {
  let item_start = utf16_offset_to_item_pos(old_source, start)
  let item_end = utf16_offset_to_item_pos(old_source, start + deleted_len)
  let range = @text.Range::from_ints(item_start, item_end)
  if record_undo {
    self.doc.replace_range_and_record(range, inserted, self.undo, timestamp_ms~) catch {
      _ => return false
    }
  } else {
    self.doc.replace_range(range, inserted) catch {
      _ => return false
    }
  }
  true
}

///|
fn[T : Eq] SyncEditor::apply_text_edit_with_policy(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
  move_cursor_to_edit_end : Bool,
  policy : SplicePolicy,
) -> Bool {
  let old_source = self.doc.text()
  let text_len = old_source.length()
  let (safe_start, safe_delete_len) = match policy {
    ExactBoundaries => {
      if start < 0 ||
        deleted_len < 0 ||
        start > text_len ||
        start + deleted_len > text_len ||
        !@moji.is_grapheme_boundary(old_source, start) ||
        !@moji.is_grapheme_boundary(old_source, start + deleted_len) {
        return false
      }
      (start, deleted_len)
    }
    SnapToGrapheme => {
      let clamped_start = clamp_utf16_offset(old_source, start)
      let max_delete_len = text_len - clamped_start
      let clamped_delete_len = if deleted_len < 0 {
        0
      } else if deleted_len > max_delete_len {
        max_delete_len
      } else {
        deleted_len
      }
      if clamped_delete_len == 0 {
        (@moji.prev_grapheme_boundary(old_source, clamped_start), 0)
      } else {
        let new_start = @moji.prev_grapheme_boundary(old_source, clamped_start)
        let new_end = @moji.next_grapheme_boundary(
          old_source,
          clamped_start + clamped_delete_len,
        )
        (new_start, new_end - new_start)
      }
    }
  }
  // Funnel all bulk text mutation through one helper so CRDT range-edit and
  // undo behavior stay aligned at a single boundary.
  guard self.apply_replace_span(
    old_source, safe_start, safe_delete_len, inserted, timestamp_ms, record_undo,
  ) else {
    return false
  }
  let new_text = self.doc.text()
  if move_cursor_to_edit_end {
    self.cursor = @moji.next_grapheme_boundary(
      new_text,
      safe_start + inserted.length(),
    )
  } else {
    self.cursor = @moji.next_grapheme_boundary(
      new_text,
      clamp_utf16_offset(new_text, self.cursor),
    )
  }
  self.apply_local_text_change(
    old_source,
    new_text,
    Some(@loom_core.Edit::new(safe_start, safe_delete_len, inserted.length())),
  )
  true
}

///|
pub fn[T : Eq] SyncEditor::apply_text_edit_internal(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
  move_cursor_to_edit_end : Bool,
) -> Unit {
  ignore(
    self.apply_text_edit_with_policy(
      start,
      deleted_len,
      inserted,
      timestamp_ms,
      record_undo,
      move_cursor_to_edit_end,
      SnapToGrapheme,
    ),
  )
}

///|
pub fn[T : Eq] SyncEditor::apply_text_edit(
  self : SyncEditor[T],
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
pub fn[T : Eq] SyncEditor::apply_text_edit_exact(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
) -> Bool {
  self.apply_text_edit_with_policy(
    start,
    deleted_len,
    inserted,
    timestamp_ms,
    true,
    true,
    ExactBoundaries,
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
pub fn[T : Eq] SyncEditor::set_text(
  self : SyncEditor[T],
  new_text : String,
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
    0,
    false,
    true,
  )
}

///|
/// Insert text at a specific position without moving the cursor.
/// Records the operation for undo. Used by ProseMirror bridge.
pub fn[T : Eq] SyncEditor::insert_at(
  self : SyncEditor[T],
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
pub fn[T : Eq] SyncEditor::delete_at(
  self : SyncEditor[T],
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
pub fn[T : Eq] SyncEditor::set_text_and_record(
  self : SyncEditor[T],
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
