// Undo integration for SyncEditor.

///|
fn AuthorityCore::can_undo(self : AuthorityCore) -> Bool {
  self.undo.can_undo()
}

///|
fn AuthorityCore::can_redo(self : AuthorityCore) -> Bool {
  self.undo.can_redo()
}

///|
fn AuthorityCore::set_tracking(self : AuthorityCore, enabled : Bool) -> Unit {
  self.undo.set_tracking(enabled)
}

///|
fn AuthorityCore::clear_undo(self : AuthorityCore) -> Unit {
  self.undo.clear()
}

///|
fn AuthorityCore::insert_and_record(
  self : AuthorityCore,
  pos : @text.Pos,
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  self.doc.insert_and_record(pos, text, self.undo, timestamp_ms~)
}

///|
fn AuthorityCore::delete_range_and_record(
  self : AuthorityCore,
  range : @text.Range,
  timestamp_ms : Int,
) -> Unit raise {
  self.doc.delete_range_and_record(range, self.undo, timestamp_ms~)
}

///|
fn AuthorityCore::undo_history(self : AuthorityCore) -> Bool raise {
  self.undo.undo(self.doc)
}

///|
fn AuthorityCore::redo_history(self : AuthorityCore) -> Bool raise {
  self.undo.redo(self.doc)
}

///|
pub fn[T : Eq] SyncEditor::insert_and_record(
  self : SyncEditor[T],
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let before_version = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  self.interaction.set_cursor_prev_grapheme_boundary(
    old_source,
    self.interaction.cursor,
  )
  let insert_start = self.interaction.cursor
  let item_start = utf16_offset_to_item_pos(old_source, insert_start)
  self.authority.insert_and_record(
    @text.Pos::at(item_start),
    text,
    timestamp_ms,
  )
  if self.authority.doc.version() != before_version {
    self.observe_authority_acceptance()
  }
  self.interaction.set_cursor_next_grapheme_boundary(
    self.authority.doc.text(),
    insert_start + text.length(),
  )
  self.apply_local_text_change(
    old_source,
    self.authority.doc.text(),
    Some(@loom_core.Edit::insert(insert_start, text.length())),
    before_version~,
  )
}

///|
pub fn[T : Eq] SyncEditor::delete_and_record(
  self : SyncEditor[T],
  timestamp_ms : Int,
) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let before_version = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  if !@moji.is_grapheme_boundary(old_source, self.interaction.cursor) {
    self.interaction.set_cursor_prev_grapheme_boundary(
      old_source,
      self.interaction.cursor,
    )
  }
  if self.interaction.cursor >= old_source.length() {
    return false
  }
  let delete_start = self.interaction.cursor
  let right = @moji.next_grapheme_boundary(
    old_source,
    self.interaction.cursor + 1,
  )
  if right == delete_start {
    return false
  }
  let item_start = utf16_offset_to_item_pos(old_source, delete_start)
  let item_end = utf16_offset_to_item_pos(old_source, right)
  try {
    self.authority.delete_range_and_record(
      @text.Range::from_ints(item_start, item_end),
      timestamp_ms,
    )
    if self.authority.doc.version() != before_version {
      self.observe_authority_acceptance()
    }
    let new_text = self.authority.doc.text()
    self.interaction.set_cursor_next_grapheme_boundary(
      new_text,
      clamp_utf16_offset(new_text, self.interaction.cursor),
    )
    self.apply_local_text_change(
      old_source,
      new_text,
      Some(@loom_core.Edit::delete(delete_start, right)),
      before_version~,
    )
    true
  } catch {
    Failure::Failure(_) as failure => raise failure
    _ => false
  }
}

///|
pub fn[T : Eq] SyncEditor::backspace_and_record(
  self : SyncEditor[T],
  timestamp_ms : Int,
) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let before_version = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  if !@moji.is_grapheme_boundary(old_source, self.interaction.cursor) {
    self.interaction.set_cursor_next_grapheme_boundary(
      old_source,
      self.interaction.cursor,
    )
  }
  if self.interaction.cursor > 0 {
    let delete_end = self.interaction.cursor
    let left = @moji.prev_grapheme_boundary(
      old_source,
      self.interaction.cursor - 1,
    )
    let item_start = utf16_offset_to_item_pos(old_source, left)
    let item_end = utf16_offset_to_item_pos(old_source, delete_end)
    try {
      self.authority.delete_range_and_record(
        @text.Range::from_ints(item_start, item_end),
        timestamp_ms,
      )
      if self.authority.doc.version() != before_version {
        self.observe_authority_acceptance()
      }
      self.interaction.set_cursor(left)
      self.apply_local_text_change(
        old_source,
        self.authority.doc.text(),
        Some(@loom_core.Edit::delete(left, delete_end)),
        before_version~,
      )
      true
    } catch {
      Failure::Failure(_) as failure => raise failure
      _ => false
    }
  } else {
    false
  }
}

///|
pub fn[T : Eq] SyncEditor::undo(self : SyncEditor[T]) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let old_source = self.authority.doc.text()
  try {
    if !self.authority.undo_history() {
      return false
    }
    let new_source = self.authority.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    Failure::Failure(_) as failure => raise failure
    _ => false
  }
}

///|
pub fn[T : Eq] SyncEditor::redo(self : SyncEditor[T]) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let old_source = self.authority.doc.text()
  try {
    if !self.authority.redo_history() {
      return false
    }
    let new_source = self.authority.doc.text()
    self.adjust_cursor()
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.mark_dirty()
    true
  } catch {
    Failure::Failure(_) as failure => raise failure
    _ => false
  }
}

///|
/// Undo and return a SyncMessage containing the inverse ops for peer broadcast.
/// Returns None if undo stack is empty or undo fails.
pub fn[T : Eq] SyncEditor::undo_and_export(
  self : SyncEditor[T],
) -> @text.SyncMessage? raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let ver_before = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  let success = try {
    if !self.authority.undo_history() {
      false
    } else {
      let new_source = self.authority.doc.text()
      self.adjust_cursor()
      self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
      self.mark_dirty()
      true
    }
  } catch {
    Failure::Failure(_) as failure => raise failure
    _ => false
  }
  if !success {
    return None
  }
  Some(self.authority.export_since(ver_before)) catch {
    _ => None
  }
}

///|
/// Redo and return a SyncMessage containing the ops for peer broadcast.
/// Returns None if redo stack is empty or redo fails.
pub fn[T : Eq] SyncEditor::redo_and_export(
  self : SyncEditor[T],
) -> @text.SyncMessage? raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  self.taint_pending_transforms()
  let ver_before = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  let success = try {
    if !self.authority.redo_history() {
      false
    } else {
      let new_source = self.authority.doc.text()
      self.adjust_cursor()
      self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
      self.mark_dirty()
      true
    }
  } catch {
    Failure::Failure(_) as failure => raise failure
    _ => false
  }
  if !success {
    return None
  }
  Some(self.authority.export_since(ver_before)) catch {
    _ => None
  }
}

///|
pub fn[T] SyncEditor::can_undo(self : SyncEditor[T]) -> Bool {
  self.authority.can_undo()
}

///|
pub fn[T] SyncEditor::can_redo(self : SyncEditor[T]) -> Bool {
  self.authority.can_redo()
}

///|
pub fn[T] SyncEditor::set_tracking(
  self : SyncEditor[T],
  enabled : Bool,
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.authority.set_tracking(enabled)
}

///|
pub fn[T] SyncEditor::clear_undo(self : SyncEditor[T]) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.authority.clear_undo()
}
