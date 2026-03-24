// Sync/export operations for SyncEditor.

///|
fn[T] SyncEditor::adjust_cursor(self : SyncEditor[T]) -> Unit {
  let text_len = self.doc.len()
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
pub fn[T] SyncEditor::apply_sync(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
) -> Unit raise {
  let old_source = self.doc.text()
  self.undo.set_tracking(false)
  self.doc.sync().apply(msg) catch {
    e => {
      self.undo.set_tracking(true)
      // Reconcile derived state in case apply partially mutated the doc
      let new_source = self.doc.text()
      self.adjust_cursor()
      self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
      self.sync_parser_after_text_change(old_source, new_source, None)
      raise e
    }
  }
  self.undo.set_tracking(true)
  let new_source = self.doc.text()
  self.adjust_cursor()
  self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
  self.sync_parser_after_text_change(old_source, new_source, None)
}

///|
pub fn[T] SyncEditor::get_version(self : SyncEditor[T]) -> @text.Version {
  self.doc.version()
}

///|
pub fn[T] SyncEditor::export_all(
  self : SyncEditor[T],
) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
pub fn[T] SyncEditor::export_since(
  self : SyncEditor[T],
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}
