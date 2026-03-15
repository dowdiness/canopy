// Sync/export operations for SyncEditor.

///|
fn SyncEditor::adjust_cursor(self : SyncEditor) -> Unit {
  let text_len = self.doc.len()
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
pub fn SyncEditor::apply_sync(
  self : SyncEditor,
  msg : @text.SyncMessage,
) -> Unit raise {
  let old_source = self.doc.text()
  self.doc.sync().apply(msg)
  self.adjust_cursor()
  self.sync_parser_after_text_change(old_source, self.doc.text(), None)
}

///|
pub fn SyncEditor::get_version(self : SyncEditor) -> @text.Version {
  self.doc.version()
}

///|
pub fn SyncEditor::export_all(self : SyncEditor) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
pub fn SyncEditor::export_since(
  self : SyncEditor,
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}
