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
/// Reject parser and projection work after Loom has raised Failure. The stored
/// value is re-raised unchanged so callers can quarantine the owning editor.
fn[T] SyncEditor::ensure_parser_healthy(
  self : SyncEditor[T],
) -> Unit raise Failure {
  match self.parser_failure {
    Some(failure) => raise failure
    None => ()
  }
}

///|
/// Whether parser-derived operations are still safe on this editor. Canonical
/// CRDT text/version/history access remains available after this becomes false.
pub fn[T] SyncEditor::is_parser_healthy(self : SyncEditor[T]) -> Bool {
  self.parser_failure is None
}

///|
fn[T : Eq] SyncEditor::sync_parser_after_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  editor_perf_measure("documentVersionUpdate", () => {
    self.document_version.set(self.doc.version())
  })
  // Short-circuits mark_projection_dirty; Parser does its own identity check.
  guard old_source != new_source else { return }
  editor_perf_measure("parserApply", () => {
    try {
      if new_source == "" {
        self.parser.set_source(new_source)
      } else {
        let edit = match known_edit {
          Some(edit) => edit
          None => compute_edit(old_source, new_source)
        }
        self.parser.apply_edit(edit, new_source)
      }
    } catch {
      Failure::Failure(_) as failure => {
        self.parser_failure = Some(failure)
        raise failure
      }
    }
  })
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
/// Return true only for ASCII text without a CRLF grapheme. The local state is
/// limited to the previous code unit so the ASCII and CRLF checks share one
/// source pass; non-ASCII and CRLF transitions remain on the canonical diff.
fn is_ascii_without_crlf(text : String) -> Bool {
  let mut previous_was_cr = false
  for ch in text {
    if !ch.is_ascii() || (previous_was_cr && ch == '\n') {
      return false
    }
    previous_was_cr = ch == '\r'
  }
  true
}

///|
/// A known edit is safe to reuse when it describes the same minimal UTF-16
/// range as the source transition. Prefix/suffix equality proves the changed
/// window is in the right place; the edge checks conservatively reject ranges
/// that could be shrunk or shifted across repeated code units. Matching edge
/// characters intentionally reduce the fast-path hit rate and use the
/// canonical grapheme-aware diff instead of weakening this proof.
fn known_edit_matches_source_change(
  old_source : String,
  new_source : String,
  edit : @loom_core.Edit,
) -> Bool {
  let start = edit.start()
  let old_len = edit.old_len()
  let new_len = edit.new_len()
  if start < 0 ||
    old_len < 0 ||
    new_len < 0 ||
    start > old_source.length() ||
    start > new_source.length() ||
    old_len > old_source.length() - start ||
    new_len > new_source.length() - start {
    return false
  }
  if !is_ascii_without_crlf(old_source) || !is_ascii_without_crlf(new_source) {
    return false
  }
  let old_end = start + old_len
  let new_end = start + new_len
  if old_len == 0 && new_len == 0 && start != old_source.length() {
    return false
  }
  if old_source[:start] != new_source[:start] ||
    old_source[old_end:] != new_source[new_end:] {
    return false
  }
  if old_len == 0 {
    if new_len > 0 &&
      start < old_source.length() &&
      new_source.at(start) == old_source.at(start) {
      return false
    }
    if new_len > 0 &&
      start > 0 &&
      new_source.at(new_end - 1) == old_source.at(start - 1) {
      return false
    }
  } else if new_len == 0 {
    if old_end < old_source.length() &&
      old_source.at(start) == old_source.at(old_end) {
      return false
    }
    if start > 0 && old_source.at(old_end - 1) == old_source.at(start - 1) {
      return false
    }
  } else if old_source.at(start) == new_source.at(start) ||
    old_source.at(old_end - 1) == new_source.at(new_end - 1) {
    return false
  }
  true
}

///|
/// The CRDT may place inserts at different positions than the cursor indicates
/// (e.g. after set_text, position semantics can diverge). Verify the known edit
/// against the actual text change so cursor adjustments use the real positions.
fn resolve_applied_edit(
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> @loom_core.Edit? raise Failure {
  match known_edit {
    None => None
    Some(edit) =>
      if known_edit_matches_source_change(old_source, new_source, edit) {
        Some(edit)
      } else {
        let actual = editor_perf_measure("resolveAppliedEditDiff", () => {
          compute_edit(old_source, new_source)
        })
        Some(actual)
      }
  }
}

///|
fn[T : Eq] SyncEditor::apply_local_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit raise Failure {
  let applied_edit = resolve_applied_edit(old_source, new_source, known_edit)
  editor_perf_measure("peerCursorAdjust", () => {
    self.adjust_peer_cursors_after_text_change(
      old_source, new_source, applied_edit,
    )
  })
  editor_perf_measure("parserSync", () => {
    self.sync_parser_after_text_change(old_source, new_source, applied_edit)
  })
}

///|
pub fn[T : Eq] SyncEditor::mark_dirty(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.document_version.set(self.doc.version())
  self.parser.set_source(self.doc.text())
  self.mark_projection_dirty()
}

///|
pub fn[T] SyncEditor::get_errors(
  self : SyncEditor[T],
) -> Array[String] raise Failure {
  self.ensure_parser_healthy()
  if self.doc.text() == "" {
    return []
  }
  self.parser.diagnostics().read_or_abort().format()
}

///|
pub fn[T] SyncEditor::is_parse_valid(
  self : SyncEditor[T],
) -> Bool raise Failure {
  self.get_errors().is_empty()
}

///|
/// The reactive runtime owned by the parser. Exposed so downstream
/// consumers (e.g. the FFI typecheck bundle) can join the same graph
/// and react to edits without a second parse of the editor's text.
pub fn[T] SyncEditor::parser_runtime(
  self : SyncEditor[T],
) -> @incr.Runtime raise Failure {
  self.ensure_parser_healthy()
  self.parser.runtime()
}

///|
/// Stable source identity owned by this editor's parser.
pub fn[T] SyncEditor::parser_source_id(
  self : SyncEditor[T],
) -> @loom_core.SourceId {
  self.parser.source_id()
}

///|
/// Reactive view of the parser's complete coherent snapshot.
pub fn[T] SyncEditor::parser_snapshot(
  self : SyncEditor[T],
) -> @incr.Derived[@loom.ParseSnapshot[T]] raise Failure {
  self.ensure_parser_healthy()
  self.parser.snapshot()
}

///|
/// Reactive view of the parser's recovered CST. Tracked when `.get_or_abort()`
/// inside a memo closure.
pub fn[T] SyncEditor::parser_syntax_tree(
  self : SyncEditor[T],
) -> @incr.Derived[@seam.SyntaxNode] raise Failure {
  self.ensure_parser_healthy()
  self.parser.syntax_tree()
}

///|
/// Reactive view of the parser's recovered AST. Tracked when read via
/// `.get_or_abort()` inside a memo closure.
pub fn[T] SyncEditor::parser_ast(
  self : SyncEditor[T],
) -> @incr.Derived[T] raise Failure {
  self.ensure_parser_healthy()
  self.parser.ast()
}

///|
/// Reactive view of the parser's source text.
pub fn[T] SyncEditor::parser_source(
  self : SyncEditor[T],
) -> @incr.Derived[String] raise Failure {
  self.ensure_parser_healthy()
  self.parser.source()
}

///|
/// Reactive view of the parser's diagnostic set.
pub fn[T] SyncEditor::parser_diagnostics(
  self : SyncEditor[T],
) -> @incr.Derived[@loom.DiagnosticSet] raise Failure {
  self.ensure_parser_healthy()
  self.parser.diagnostics()
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
