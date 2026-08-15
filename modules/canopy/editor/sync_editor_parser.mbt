// Parser-facing SyncEditor methods.

///|
/// Flag that the projection registry / source map / proj node may be stale.
/// All text-changing paths (insert, backspace, apply_text_edit_internal,
/// undo/redo via mark_dirty, remote sync) converge here after the parser
/// has been updated — the Parser itself batches its own signal updates
/// internally via Runtime::batch.
fn[T] ProjectionState::mark_projection_dirty(self : ProjectionState[T]) -> Unit {
  self.projection_dirty = true
}

///|
/// Reject parser and projection work after Loom has raised Failure. The stored
/// value is re-raised unchanged so callers can quarantine the owning editor.
fn[T] ProjectionState::ensure_parser_healthy(
  self : ProjectionState[T],
) -> Unit raise Failure {
  match self.parser_failure {
    Some(failure) => raise failure
    None => ()
  }
}

///|
fn[T] SyncEditor::ensure_parser_healthy(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.projection.ensure_parser_healthy()
}

///|
/// Whether parser-derived operations are still safe on this editor. Canonical
/// CRDT text/version/history access remains available after this becomes false.
fn[T] ProjectionState::is_parser_healthy(self : ProjectionState[T]) -> Bool {
  self.parser_failure is None
}

///|
pub fn[T] SyncEditor::is_parser_healthy(self : SyncEditor[T]) -> Bool {
  self.projection.is_parser_healthy()
}

///|
fn[T] ProjectionState::set_document_version(
  self : ProjectionState[T],
  version : @text.Version,
) -> Unit {
  self.document_version.set(version)
}

///|
fn[T : Eq] ProjectionState::apply_parser_text_change(
  self : ProjectionState[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit raise Failure {
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
}

///|
fn[T : Eq] SyncEditor::sync_parser_after_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
) -> Unit raise Failure {
  self.projection.ensure_parser_healthy()
  editor_perf_measure("documentVersionUpdate", () => {
    self.projection.set_document_version(self.authority.doc.version())
  })
  // Short-circuits mark_projection_dirty; Parser does its own identity check,
  // but projection mirrors still observe the causal document-version advance.
  guard old_source != new_source else {
    self.observe_parser_synchronized()
    return
  }
  editor_perf_measure("parserApply", () => {
    self.projection.apply_parser_text_change(old_source, new_source, known_edit)
  })
  self.projection.mark_projection_dirty()
  self.observe_parser_synchronized()
}

///|
fn[T : Eq] ProjectionState::set_parser_source(
  self : ProjectionState[T],
  source : String,
) -> Unit raise Failure {
  self.parser.set_source(source) catch {
    Failure::Failure(_) as failure => {
      self.parser_failure = Some(failure)
      raise failure
    }
  }
}

///|
fn[T : Eq] SyncEditor::sync_parser_from_coherent_seed(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.projection.ensure_parser_healthy()
  editor_perf_measure("documentVersionUpdate", () => {
    self.projection.set_document_version(self.authority.doc.version())
  })
  editor_perf_measure("parserSeed", () => {
    let seed = self.authority.doc.text()
    self.projection.set_parser_source(seed)
  })
  self.projection.mark_projection_dirty()
  self.observe_parser_synchronized()
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
    Some(edit) => self.interaction.adjust_cursor_view_for_edit(edit)
    None =>
      for edit in merge_to_edits(old_source, new_source) {
        self.interaction.adjust_cursor_view_for_edit(edit)
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
priv struct ProjectionReplaySpan {
  edit : @loom_core.Edit
  inserted : String
} derive(Eq, Debug)

///|
priv enum ProjectionReplay {
  Single(@loom_core.Edit)
  Spans(Array[ProjectionReplaySpan])
} derive(Eq, Debug)

///|
priv enum ProjectionContinuation {
  Replay(ProjectionReplay)
  SourceUnchanged
  NeedsSeed
} derive(Eq, Debug)

///|
fn classify_projection_continuation(
  old_source : String,
  new_source : String,
  replay_edit : @loom_core.Edit?,
) -> ProjectionContinuation {
  if old_source == new_source {
    ProjectionContinuation::SourceUnchanged
  } else {
    match replay_edit {
      Some(edit) =>
        ProjectionContinuation::Replay(ProjectionReplay::Single(edit))
      None => ProjectionContinuation::NeedsSeed
    }
  }
}

///|
#warnings("-unused_value")
priv suberror CommittedTransitionRejection {
  NoCausalAdvance
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv struct CommittedTransition {
  before_version : @text.Version
  after_version : @text.Version
  continuation : ProjectionContinuation
} derive(Eq, Debug)

///|
fn CommittedTransition::CommittedTransition(
  before_version~ : @text.Version,
  after_version~ : @text.Version,
  continuation~ : ProjectionContinuation,
) -> CommittedTransition raise CommittedTransitionRejection {
  guard before_version != after_version else {
    raise CommittedTransitionRejection::NoCausalAdvance
  }
  { before_version, after_version, continuation }
}

///|
fn[T : Eq] ProjectionState::replay_parser_spans(
  self : ProjectionState[T],
  spans : Array[ProjectionReplaySpan],
  expected_source : String,
) -> Unit raise Failure {
  let mut source = self.parser.source().read_or_abort()
  try {
    for span in spans {
      let start = span.edit.start()
      let old_end = start + span.edit.old_len()
      let next_source = source[:start].to_owned() +
        span.inserted +
        source[old_end:].to_owned()
      self.parser.apply_edit(span.edit, next_source)
      source = next_source
    }
    guard source == expected_source else {
      fail("multi-span replay did not reconstruct committed source")
    }
  } catch {
    Failure::Failure(_) as failure => {
      self.parser_failure = Some(failure)
      raise failure
    }
  }
}

///|
fn[T : Eq] SyncEditor::sync_parser_from_replay_spans(
  self : SyncEditor[T],
  spans : Array[ProjectionReplaySpan],
  expected_source : String,
) -> Unit raise Failure {
  self.projection.ensure_parser_healthy()
  editor_perf_measure("documentVersionUpdate", () => {
    self.projection.set_document_version(self.authority.doc.version())
  })
  editor_perf_measure("parserReplaySpans", () => {
    self.projection.replay_parser_spans(spans, expected_source)
  })
  self.projection.mark_projection_dirty()
  self.observe_parser_synchronized()
}

///|
fn[T : Eq] SyncEditor::interpret_committed_transition(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  transition : CommittedTransition,
  interaction_edit : @loom_core.Edit?,
) -> Unit raise Failure {
  editor_perf_measure("peerCursorAdjust", () => {
    self.adjust_peer_cursors_after_text_change(
      old_source, new_source, interaction_edit,
    )
  })
  editor_perf_measure("parserSync", () => {
    match transition.continuation {
      Replay(Single(edit)) =>
        self.sync_parser_after_text_change(old_source, new_source, Some(edit))
      Replay(Spans(spans)) =>
        self.sync_parser_from_replay_spans(spans, new_source)
      SourceUnchanged =>
        self.sync_parser_after_text_change(old_source, new_source, None)
      NeedsSeed => self.sync_parser_from_coherent_seed()
    }
  })
}

///|
fn[T : Eq] SyncEditor::settle_committed_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  before_version : @text.Version,
  continuation : ProjectionContinuation,
  interaction_edit : @loom_core.Edit?,
) -> Unit raise Failure {
  let transition = editor_perf_measure("committedTransition", () => {
    try! CommittedTransition(
      before_version~,
      after_version=self.authority.doc.version(),
      continuation~,
    )
  })
  self.observe_committed_transition_settled()
  self.interpret_committed_transition(
    old_source, new_source, transition, interaction_edit,
  )
}

///|
fn[T : Eq] SyncEditor::apply_local_text_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  known_edit : @loom_core.Edit?,
  before_version? : @text.Version,
) -> Unit raise Failure {
  let applied_edit = resolve_applied_edit(old_source, new_source, known_edit)
  match before_version {
    Some(before_version) => {
      let after_version = self.authority.doc.version()
      if after_version == before_version {
        editor_perf_measure("peerCursorAdjust", () => {
          self.adjust_peer_cursors_after_text_change(
            old_source, new_source, applied_edit,
          )
        })
        editor_perf_measure("parserSync", () => {
          self.sync_parser_after_text_change(
            old_source, new_source, applied_edit,
          )
        })
      } else {
        let continuation = classify_projection_continuation(
          old_source, new_source, applied_edit,
        )
        self.settle_committed_text_change(
          old_source, new_source, before_version, continuation, applied_edit,
        )
      }
    }
    None => {
      editor_perf_measure("peerCursorAdjust", () => {
        self.adjust_peer_cursors_after_text_change(
          old_source, new_source, applied_edit,
        )
      })
      editor_perf_measure("parserSync", () => {
        self.sync_parser_after_text_change(old_source, new_source, applied_edit)
      })
    }
  }
}

///|
fn[T : Eq] SyncEditor::settle_committed_span_change(
  self : SyncEditor[T],
  old_source : String,
  new_source : String,
  before_version : @text.Version,
  replay_spans : Array[ProjectionReplaySpan],
) -> Unit raise Failure {
  let continuation = if old_source == new_source {
    ProjectionContinuation::SourceUnchanged
  } else {
    ProjectionContinuation::Replay(ProjectionReplay::Spans(replay_spans))
  }
  let transition = editor_perf_measure("committedTransition", () => {
    try! CommittedTransition(
      before_version~,
      after_version=self.authority.doc.version(),
      continuation~,
    )
  })
  self.observe_committed_transition_settled()
  editor_perf_measure("peerCursorAdjust", () => {
    for span in replay_spans {
      self.adjust_peer_cursors_after_text_change(
        old_source,
        new_source,
        Some(span.edit),
      )
    }
  })
  editor_perf_measure("parserSync", () => {
    match transition.continuation {
      SourceUnchanged =>
        self.sync_parser_after_text_change(old_source, new_source, None)
      Replay(Spans(spans)) =>
        self.sync_parser_from_replay_spans(spans, new_source)
      Replay(Single(_)) | NeedsSeed => abort("invalid multi-span continuation")
    }
  })
}

///|
pub fn[T : Eq] SyncEditor::mark_dirty(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.projection.ensure_parser_healthy()
  self.projection.set_document_version(self.authority.doc.version())
  self.projection.set_parser_source(self.authority.doc.text())
  self.projection.mark_projection_dirty()
}

///|
pub fn[T] SyncEditor::get_errors(
  self : SyncEditor[T],
) -> Array[String] raise Failure {
  self.projection.ensure_parser_healthy()
  if self.authority.doc.text() == "" {
    return []
  }
  self.projection.formatted_parser_diagnostics()
}

///|
pub fn[T] SyncEditor::is_parse_valid(
  self : SyncEditor[T],
) -> Bool raise Failure {
  self.get_errors().is_empty()
}

///|
fn[T] ProjectionState::parser_runtime(
  self : ProjectionState[T],
) -> @incr.Runtime raise Failure {
  self.ensure_parser_healthy()
  self.parser.runtime()
}

///|
fn[T] ProjectionState::parser_source_id(
  self : ProjectionState[T],
) -> @loom_core.SourceId {
  self.parser.source_id()
}

///|
fn[T] ProjectionState::parser_snapshot(
  self : ProjectionState[T],
) -> @incr.Derived[@loom.ParseSnapshot[T]] raise Failure {
  self.ensure_parser_healthy()
  self.parser.snapshot()
}

///|
fn[T] ProjectionState::parser_syntax_tree(
  self : ProjectionState[T],
) -> @incr.Derived[@seam.SyntaxNode] raise Failure {
  self.ensure_parser_healthy()
  self.parser.syntax_tree()
}

///|
fn[T] ProjectionState::parser_ast(
  self : ProjectionState[T],
) -> @incr.Derived[T] raise Failure {
  self.ensure_parser_healthy()
  self.parser.ast()
}

///|
fn[T] ProjectionState::parser_source(
  self : ProjectionState[T],
) -> @incr.Derived[String] raise Failure {
  self.ensure_parser_healthy()
  self.parser.source()
}

///|
fn[T] ProjectionState::parser_diagnostics(
  self : ProjectionState[T],
) -> @incr.Derived[@loom.DiagnosticSet] raise Failure {
  self.ensure_parser_healthy()
  self.parser.diagnostics()
}

///|
fn[T] ProjectionState::formatted_parser_diagnostics(
  self : ProjectionState[T],
) -> Array[String] {
  self.parser.diagnostics().read_or_abort().format()
}

///|
/// The reactive runtime owned by the parser. Exposed so downstream
/// consumers (e.g. the FFI typecheck bundle) can join the same graph
/// and react to edits without a second parse of the editor's text.
pub fn[T] SyncEditor::parser_runtime(
  self : SyncEditor[T],
) -> @incr.Runtime raise Failure {
  self.projection.parser_runtime()
}

///|
/// Stable source identity owned by this editor's parser.
pub fn[T] SyncEditor::parser_source_id(
  self : SyncEditor[T],
) -> @loom_core.SourceId {
  self.projection.parser_source_id()
}

///|
/// Reactive view of the parser's complete coherent snapshot.
pub fn[T] SyncEditor::parser_snapshot(
  self : SyncEditor[T],
) -> @incr.Derived[@loom.ParseSnapshot[T]] raise Failure {
  self.projection.parser_snapshot()
}

///|
/// Reactive view of the parser's recovered CST. Tracked when `.get_or_abort()`
/// inside a memo closure.
pub fn[T] SyncEditor::parser_syntax_tree(
  self : SyncEditor[T],
) -> @incr.Derived[@seam.SyntaxNode] raise Failure {
  self.projection.parser_syntax_tree()
}

///|
/// Reactive view of the parser's recovered AST. Tracked when read via
/// `.get_or_abort()` inside a memo closure.
pub fn[T] SyncEditor::parser_ast(
  self : SyncEditor[T],
) -> @incr.Derived[T] raise Failure {
  self.projection.parser_ast()
}

///|
/// Reactive view of the parser's source text.
pub fn[T] SyncEditor::parser_source(
  self : SyncEditor[T],
) -> @incr.Derived[String] raise Failure {
  self.projection.parser_source()
}

///|
/// Reactive view of the parser's diagnostic set.
pub fn[T] SyncEditor::parser_diagnostics(
  self : SyncEditor[T],
) -> @incr.Derived[@loom.DiagnosticSet] raise Failure {
  self.projection.parser_diagnostics()
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
