// Parser-facing SyncEditor methods.

///|
/// Flag that the projection registry / source map / proj node may be stale.
/// All text-changing paths (insert, backspace, apply_text_edit_internal,
/// undo/redo via mark_dirty, remote sync) converge here after the parser
/// has been updated — the Parser itself batches its own signal updates
/// internally via Runtime::batch.
fn[T] SyncEditor::mark_projection_dirty(self : SyncEditor[T]) -> Unit {
  self.projection_dirty = true
}

///|
fn[T : Eq] SyncEditor::sync_parser_after_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit {
  // Short-circuits mark_projection_dirty; Parser does its own identity check.
  guard old_source != new_source else { return }
  if new_source == "" {
    self.parser.set_source(new_source)
  } else {
    let edit = match known_edit {
      Some(edit) => edit
      None => compute_edit(old_source, new_source)
    }
    self.parser.apply_edit(edit, new_source)
  }
  self.mark_projection_dirty()
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
fn[T : Eq] SyncEditor::apply_local_text_change(
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
pub fn[T : Eq] SyncEditor::mark_dirty(self : SyncEditor[T]) -> Unit {
  self.parser.set_source(self.doc.text())
  self.mark_projection_dirty()
}

///|
pub fn[T] SyncEditor::get_errors(self : SyncEditor[T]) -> Array[String] {
  if self.doc.text() == "" {
    return []
  }
  self.parser.diagnostics().read_or_abort().format()
}

///|
pub fn[T] SyncEditor::is_parse_valid(self : SyncEditor[T]) -> Bool {
  self.get_errors().is_empty()
}

///|
/// The reactive runtime owned by the parser. Exposed so downstream
/// consumers (e.g. the FFI typecheck bundle) can join the same graph
/// and react to edits without a second parse of the editor's text.
pub fn[T] SyncEditor::parser_runtime(self : SyncEditor[T]) -> @incr.Runtime {
  self.parser.runtime()
}

///|
/// Reactive view of the parser's recovered CST. Tracked when `.get_or_abort()`
/// inside a memo closure.
pub fn[T] SyncEditor::parser_syntax_tree(
  self : SyncEditor[T],
) -> @incr.Derived[@seam.SyntaxNode] {
  self.parser.syntax_tree()
}

///|
/// Convert an (old_text, new_text) pair into parser Edits using loom's
/// TextDelta API instead of a bespoke string diff.
///
/// Returns an empty array when old == new (no edit needed).
/// Returns sequential Edits for disjoint insert/delete regions, so callers can
/// preserve cursor positions across multi-edit remote merges.
///
/// This is the fallback path for batch remote merges (Design §1).
/// The direct Op → Edit path (O(1)) will be added in a later phase
/// once event-graph-walker/text exposes lv_to_position and insert_with_op.
fn merge_to_edits(
  old_text : String,
  new_text : String,
) -> Array[@loom_core.Edit] {
  compute_text_edits(old_text, new_text)
}
