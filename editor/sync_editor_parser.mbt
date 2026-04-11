// Parser-facing SyncEditor methods.

///|
fn[T] SyncEditor::set_parser_signals(
  self : SyncEditor[T],
  source : String,
  syntax? : @seam.SyntaxNode? = None,
) -> Unit {
  self.parser_rt.batch(fn() {
    self.source_text.set(source)
    self.syntax_tree.set(syntax)
  })
  // All text-changing paths (insert, backspace, apply_text_edit_internal,
  // undo/redo via mark_dirty, remote sync) converge here.
  self.projection_dirty = true
}

///|
fn[T] SyncEditor::sync_parser_after_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit {
  if old_source == new_source {
    return
  }
  if new_source == "" {
    let _ = self.parser.reset(new_source)
    self.set_parser_signals(new_source)
    return
  }
  let edit = match known_edit {
    Some(edit) => edit
    None => compute_edit(old_source, new_source)
  }
  let _ = self.parser.edit(edit, new_source)
  self.set_parser_signals(new_source, syntax=self.parser.get_syntax_tree())
}

///|
fn[T] SyncEditor::adjust_peer_cursors_after_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit {
  if old_source == new_source {
    return
  }
  match known_edit {
    Some(edit) =>
      self.cursor_view.adjust_for_edit(
        edit.start(),
        edit.old_len(),
        edit.new_len(),
      )
    None =>
      for edit in merge_to_edits(old_source, new_source) {
        self.cursor_view.adjust_for_edit(
          edit.start(),
          edit.old_len(),
          edit.new_len(),
        )
      }
  }
}

///|
/// The CRDT may place inserts at different positions than the cursor indicates
/// (e.g. after set_text, position semantics can diverge). Verify the known edit
/// against the actual text change so cursor adjustments use the real positions.
fn resolve_applied_edit(
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> @loom_core.Edit? {
  match known_edit {
    None => None
    Some(edit) => {
      let actual = compute_edit(old_source, new_source)
      if edit.start() == actual.start() &&
        edit.old_len() == actual.old_len() &&
        edit.new_len() == actual.new_len() {
        Some(edit)
      } else {
        Some(actual)
      }
    }
  }
}

///|
fn[T] SyncEditor::apply_local_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit {
  let applied_edit = resolve_applied_edit(old_source, new_source, known_edit)
  self.adjust_peer_cursors_after_text_change(
    old_source, new_source, applied_edit,
  )
  self.sync_parser_after_text_change(old_source, new_source, applied_edit)
}

///|
fn[T] SyncEditor::force_parser_reset(self : SyncEditor[T]) -> @seam.SyntaxNode? {
  let source = self.doc.text()
  let _ = self.parser.reset(source)
  let syntax = self.parser.get_syntax_tree()
  self.set_parser_signals(source, syntax~)
  syntax
}

///|
pub fn[T] SyncEditor::mark_dirty(self : SyncEditor[T]) -> Unit {
  let _ = self.force_parser_reset()
}

///|
pub fn[T] SyncEditor::get_errors(self : SyncEditor[T]) -> Array[String] {
  if self.doc.text() == "" {
    return []
  }
  self.parser.diagnostics()
}

///|
pub fn[T] SyncEditor::is_parse_valid(self : SyncEditor[T]) -> Bool {
  self.get_errors().is_empty()
}
