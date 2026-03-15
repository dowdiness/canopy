// Text and cursor operations for SyncEditor.

///|
pub fn SyncEditor::insert(self : SyncEditor, text : String) -> Unit raise {
  let old_source = self.doc.text()
  let insert_start = self.cursor
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor = self.cursor + text.length()
  self.sync_parser_after_text_change(
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
      self.sync_parser_after_text_change(
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
        self.sync_parser_after_text_change(
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
fn SyncEditor::apply_delete_span(
  self : SyncEditor,
  start : Int,
  deleted_len : Int,
  timestamp_ms : Int,
  record_undo : Bool,
) -> Unit {
  // TextDoc only exposes single-character delete today. Keep the span-delete
  // workaround isolated here until event-graph-walker adds a range delete API.
  // Do not duplicate this loop in more editor call sites; pay the debt in the
  // owning CRDT package when the API is extended.
  for _i = 0; _i < deleted_len; _i = _i + 1 {
    if record_undo {
      self.doc.delete_and_record(@text.Pos::at(start), self.undo, timestamp_ms~) catch {
        _ => ()
      }
    } else {
      self.doc.delete(@text.Pos::at(start)) catch {
        _ => ()
      }
    }
  }
}

///|
fn SyncEditor::apply_insert_span(
  self : SyncEditor,
  start : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
) -> Unit {
  if inserted.length() == 0 {
    return
  }
  if record_undo {
    self.doc.insert_and_record(
      @text.Pos::at(start),
      inserted,
      self.undo,
      timestamp_ms~,
    ) catch {
      _ => ()
    }
  } else {
    self.doc.insert(@text.Pos::at(start), inserted) catch {
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
  // Funnel all bulk text mutation through one helper so temporary CRDT API
  // workarounds stay localized and are easy to remove later.
  self.apply_delete_span(safe_start, safe_delete_len, timestamp_ms, record_undo)
  self.apply_insert_span(safe_start, inserted, timestamp_ms, record_undo)
  if move_cursor_to_edit_end {
    self.cursor = safe_start + inserted.length()
  } else {
    self.adjust_cursor()
  }
  self.sync_parser_after_text_change(
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
pub fn SyncEditor::set_text(self : SyncEditor, new_text : String) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let splice = compute_text_splice(old_text, new_text)
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
pub fn SyncEditor::set_text_and_record(
  self : SyncEditor,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let splice = compute_text_splice(old_text, new_text)
  self.apply_text_edit_internal(
    splice.start,
    splice.delete_len,
    splice.inserted,
    timestamp_ms,
    true,
    false,
  )
}
