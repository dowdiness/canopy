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
    item_pos += 1
    if next_utf16_pos == target {
      return item_pos
    }
    utf16_pos = next_utf16_pos
  }
  item_pos
}

///|
fn AuthorityCore::insert_text(
  self : AuthorityCore,
  pos : @text.Pos,
  text : String,
) -> Unit raise {
  self.doc.insert(pos, text)
}

///|
fn AuthorityCore::delete_range(
  self : AuthorityCore,
  range : @text.Range,
) -> Unit raise {
  self.doc.delete_range(range)
}

///|
fn AuthorityCore::replace_range(
  self : AuthorityCore,
  range : @text.Range,
  inserted : String,
) -> Unit raise {
  self.doc.replace_range(range, inserted)
}

///|
fn AuthorityCore::replace_range_and_record(
  self : AuthorityCore,
  range : @text.Range,
  inserted : String,
  timestamp_ms : Int,
) -> Unit raise {
  self.doc.replace_range_and_record(range, inserted, self.undo, timestamp_ms~)
}

///|
fn AuthorityCore::stop_capturing(self : AuthorityCore) -> Unit {
  self.undo.stop_capturing()
}

///|
pub fn[T : Eq] SyncEditor::insert(
  self : SyncEditor[T],
  text : String,
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
  self.authority.insert_text(@text.Pos::at(item_start), text)
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
pub fn[T : Eq] SyncEditor::delete(self : SyncEditor[T]) -> Bool raise Failure {
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
  try
    self.authority.delete_range(@text.Range::from_ints(item_start, item_end))
  catch {
    _ => false
  } noraise {
    _ => {
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
    }
  }
}

///|
pub fn[T : Eq] SyncEditor::backspace(
  self : SyncEditor[T],
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
    try
      self.authority.delete_range(@text.Range::from_ints(item_start, item_end))
    catch {
      _ => false
    } noraise {
      _ => {
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
      }
    }
  } else {
    false
  }
}

///|
pub fn[T] SyncEditor::move_cursor(self : SyncEditor[T], position : Int) -> Unit {
  let text = self.authority.doc.text()
  self.interaction.set_cursor_prev_grapheme_boundary(
    text,
    clamp_utf16_offset(text, position),
  )
}

///|
pub fn[T] SyncEditor::move_cursor_left_grapheme(self : SyncEditor[T]) -> Unit {
  if self.interaction.cursor == 0 {
    return
  }
  self.interaction.set_cursor_prev_grapheme_boundary(
    self.authority.doc.text(),
    self.interaction.cursor - 1,
  )
}

///|
pub fn[T] SyncEditor::move_cursor_right_grapheme(self : SyncEditor[T]) -> Unit {
  let text = self.authority.doc.text()
  if self.interaction.cursor == text.length() {
    return
  }
  self.interaction.set_cursor_next_grapheme_boundary(
    text,
    self.interaction.cursor + 1,
  )
}

///|
/// Word-navigation policy (VS Code-style) over moji's raw UAX #29
/// boundaries: left lands at word start, right at word end, whitespace is
/// skipped, punctuation runs are single units. See `word_nav.mbt`.
pub fn[T] SyncEditor::move_cursor_left_word(self : SyncEditor[T]) -> Unit {
  self.interaction.set_cursor(
    prev_word_stop(self.authority.doc.text(), self.interaction.cursor),
  )
}

///|
pub fn[T] SyncEditor::move_cursor_right_word(self : SyncEditor[T]) -> Unit {
  self.interaction.set_cursor(
    next_word_stop(self.authority.doc.text(), self.interaction.cursor),
  )
}

///|
pub fn[T] SyncEditor::get_text(self : SyncEditor[T]) -> String {
  self.authority.get_text()
}

///|
pub fn[T] SyncEditor::get_cursor(self : SyncEditor[T]) -> Int {
  self.interaction.cursor
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
  // The Raw append path already validated an end insertion. TextState.len()
  // is the exact item position and avoids scanning the whole UTF-16 source
  // twice just to convert the same endpoint.
  let (item_start, item_end) = if start == old_source.length() &&
    deleted_len == 0 {
    let end = self.authority.doc.len()
    (end, end)
  } else {
    (
      utf16_offset_to_item_pos(old_source, start),
      utf16_offset_to_item_pos(old_source, start + deleted_len),
    )
  }
  let range = @text.Range::from_ints(item_start, item_end) catch {
    _ => return false
  }
  if record_undo {
    self.authority.replace_range_and_record(range, inserted, timestamp_ms) catch {
      _ => return false
    }
  } else {
    self.authority.replace_range(range, inserted) catch {
      _ => return false
    }
  }
  true
}

///|
/// Commit one prevalidated Loom fix as a single externally observable source
/// transition. The fix owns source/range validation; this shell records its
/// replacements end-to-start, then reconciles cursors and the parser once.
fn[T : Eq] SyncEditor::apply_diagnostic_fix_candidate(
  self : SyncEditor[T],
  source_id : @loom_core.SourceId,
  fix : @loom_core.DiagnosticFix,
  timestamp_ms : Int,
) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  let before_version = self.authority.doc.version()
  let old_source = self.authority.doc.text()
  let expected_source = fix.apply(source_id, old_source) catch {
    _ => return false
  }
  let edits = fix.edits()
  self.taint_pending_transforms()
  self.authority.stop_capturing()
  let mut applied = true
  edits.rev_each(edit => {
    if applied {
      let range = edit.span().range()
      applied = self.apply_replace_span(
        self.authority.doc.text(),
        range.start().value(),
        range.length(),
        edit.replacement(),
        timestamp_ms,
        true,
      )
    }
  })
  self.authority.stop_capturing()
  let after_version = self.authority.doc.version()
  if after_version != before_version {
    self.observe_authority_acceptance()
  }
  let new_source = self.authority.doc.text()
  self.interaction.set_cursor_next_grapheme_boundary(
    new_source,
    clamp_utf16_offset(new_source, self.interaction.cursor),
  )
  if after_version == before_version {
    self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
    self.sync_parser_after_text_change(old_source, new_source, None)
  } else {
    self.settle_committed_text_change(
      old_source,
      new_source,
      before_version,
      classify_projection_continuation(old_source, new_source, None),
      None,
    )
  }
  applied && new_source == expected_source
}

///|
fn[T] SyncEditor::apply_text_edit_mutation_only(
  self : SyncEditor[T],
  old_source : String,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
  policy : SplicePolicy,
) -> @loom_core.Edit? raise Failure {
  let text_len = old_source.length()
  editor_perf_begin("applyEditPolicy")
  let resolved : (Int, Int)? = match policy {
    ExactBoundaries =>
      if start < 0 ||
        deleted_len < 0 ||
        start > text_len ||
        start + deleted_len > text_len {
        None
      } else {
        let boundaries = @moji.grapheme_boundaries(old_source)
        if boundaries.binary_search(start) is Err(_) ||
          boundaries.binary_search(start + deleted_len) is Err(_) {
          None
        } else {
          Some((start, deleted_len))
        }
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
        Some((@moji.prev_grapheme_boundary(old_source, clamped_start), 0))
      } else {
        let new_start = @moji.prev_grapheme_boundary(old_source, clamped_start)
        let new_end = @moji.next_grapheme_boundary(
          old_source,
          clamped_start + clamped_delete_len,
        )
        Some((new_start, new_end - new_start))
      }
    }
  }
  editor_perf_end("applyEditPolicy")
  guard resolved is Some((safe_start, safe_delete_len)) else { return None }
  guard editor_perf_measure("crdtReplace", () => {
    self.apply_replace_span(
      old_source, safe_start, safe_delete_len, inserted, timestamp_ms, record_undo,
    )
  }) else {
    return None
  }
  Some(@loom_core.Edit::new(safe_start, safe_delete_len, inserted.length()))
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
) -> Bool raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  let before_version = self.authority.doc.version()
  let old_source = editor_perf_measure("applyEditOldSnapshot", () => {
    self.authority.doc.text()
  })
  guard self.apply_text_edit_mutation_only(
      old_source, start, deleted_len, inserted, timestamp_ms, record_undo, policy,
    )
    is Some(applied_edit) else {
    return false
  }
  if self.authority.doc.version() != before_version {
    self.observe_authority_acceptance()
  }
  let new_text = editor_perf_measure("applyEditNewSnapshot", () => {
    self.authority.doc.text()
  })
  if move_cursor_to_edit_end {
    self.interaction.set_cursor_next_grapheme_boundary(
      new_text,
      applied_edit.start() + applied_edit.new_len(),
    )
  } else {
    self.interaction.set_cursor_next_grapheme_boundary(
      new_text,
      clamp_utf16_offset(new_text, self.interaction.cursor),
    )
  }
  editor_perf_measure("localTextChange", () => {
    self.apply_local_text_change(
      old_source,
      new_text,
      Some(applied_edit),
      before_version~,
    )
  })
  true
}

///|
/// Implementation-detail funnel for all text-changing paths (insert, delete,
/// backspace, apply_text_edit_with_policy, structural edits). The `_internal`
/// suffix marks it as private API per the Canopy library API boundary decision
/// (`docs/decisions/2026-06-11-library-api-boundary.md`). External library
/// consumers should call the higher-level `apply_text_edit_*` / `insert` /
/// `delete` methods instead.
fn[T : Eq] SyncEditor::apply_text_edit_internal(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
  record_undo : Bool,
  move_cursor_to_edit_end : Bool,
) -> Bool raise Failure {
  self.apply_text_edit_with_policy(
    start,
    deleted_len,
    inserted,
    timestamp_ms,
    record_undo,
    move_cursor_to_edit_end,
    SnapToGrapheme,
  )
}

///|
pub fn[T : Eq] SyncEditor::apply_text_edit(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.taint_pending_transforms()
  ignore(
    self.apply_text_edit_internal(
      start, deleted_len, inserted, timestamp_ms, true, true,
    ),
  )
}

///|
pub fn[T : Eq] SyncEditor::apply_text_edit_exact(
  self : SyncEditor[T],
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int,
) -> Bool raise Failure {
  editor_perf_scope(() => {
    self.ensure_parser_healthy()
    self.taint_pending_transforms()
    self.apply_text_edit_with_policy(
      start,
      deleted_len,
      inserted,
      timestamp_ms,
      true,
      true,
      ExactBoundaries,
    )
  })
}

///|
/// Fast path for the common Raw-input shape: an ASCII suffix appended at the
/// current end of the source. ASCII cannot join the preceding grapheme except
/// for CRLF, which is deliberately left to the shared Unicode-aware diff.
fn fast_append_text_change(
  old_text : String,
  new_text : String,
) -> @text_change.TextChange? {
  if old_text == new_text {
    return Some(
      @text_change.TextChange::ReplaceRange(
        start=old_text.length(),
        delete_len=0,
        inserted="",
      ),
    )
  }
  guard new_text.has_prefix(old_text) else { return None }
  let suffix = new_text[old_text.length():]
  let mut ascii = true
  for ch in suffix {
    if !ch.is_ascii() {
      ascii = false
      break
    }
  }
  guard ascii else { return None }
  guard !(old_text.has_suffix("\r") && suffix.has_prefix("\n")) else {
    return None
  }
  Some(
    @text_change.TextChange::ReplaceRange(
      start=old_text.length(),
      delete_len=0,
      inserted=suffix.to_owned(),
    ),
  )
}

///|
/// Replace the document text with `new_text` and return the exact splice used
/// together with whether the edit was accepted.
///
/// Like `set_text`, this is a bulk synchronization operation: it does not
/// record undo history and moves the cursor to the end of the replacement.
/// Returning the splice lets façade callers reuse the text-diff result when
/// they need to publish a transform alongside the edit.
pub fn[T : Eq] SyncEditor::set_text_with_change(
  self : SyncEditor[T],
  new_text : String,
) -> (@text_change.TextChange, Bool) raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  let old_text = self.authority.doc.text()
  let splice = match fast_append_text_change(old_text, new_text) {
    Some(splice) => splice
    None => @text_change.compute_text_change(old_text, new_text)
  }
  if splice.is_noop() {
    return (splice, true)
  }
  self.taint_pending_transforms()
  let accepted = match splice {
    @text_change.TextChange::ReplaceRange(start~, delete_len~, inserted~) =>
      self.apply_text_edit_internal(start, delete_len, inserted, 0, false, true)
    @text_change.TextChange::ReplaceAll(_) =>
      abort("text diff unexpectedly returned ReplaceAll")
  }
  (splice, accepted)
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
) -> Unit raise Failure {
  ignore(self.set_text_with_change(new_text))
}

///|
/// Insert text at a specific position without moving the cursor.
/// Records the operation for undo. Used by ProseMirror bridge.
pub fn[T : Eq] SyncEditor::insert_at(
  self : SyncEditor[T],
  position : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  let text_len = self.authority.doc.len()
  if position < 0 || position > text_len {
    return
  }
  self.taint_pending_transforms()
  ignore(
    self.apply_text_edit_internal(position, 0, text, timestamp_ms, true, false),
  )
}

///|
/// Delete the character at a specific position without moving the cursor.
/// Records the operation for undo. Returns false if position is out of bounds.
/// Used by ProseMirror bridge.
pub fn[T : Eq] SyncEditor::delete_at(
  self : SyncEditor[T],
  position : Int,
  timestamp_ms : Int,
) -> Bool raise Failure {
  self.ensure_parser_healthy()
  let text_len = self.authority.doc.len()
  if position < 0 || position >= text_len {
    return false
  }
  self.taint_pending_transforms()
  ignore(
    self.apply_text_edit_internal(position, 1, "", timestamp_ms, true, false),
  )
  true
}

///|
pub fn[T : Eq] SyncEditor::set_text_and_record(
  self : SyncEditor[T],
  new_text : String,
  timestamp_ms : Int,
) -> Unit raise Failure {
  editor_perf_scope(() => self.set_text_and_record_impl(new_text, timestamp_ms))
}

///|
fn[T : Eq] SyncEditor::set_text_and_record_impl(
  self : SyncEditor[T],
  new_text : String,
  timestamp_ms : Int,
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  let old_text = editor_perf_measure("setTextOldSnapshot", () => {
    self.authority.doc.text()
  })
  if old_text == new_text {
    return
  }
  self.taint_pending_transforms()
  let splice = editor_perf_measure("setTextFullDiff", () => {
    @text_change.compute_text_change(old_text, new_text)
  })
  ignore(
    editor_perf_measure("setTextApply", () => {
      match splice {
        @text_change.TextChange::ReplaceRange(start~, delete_len~, inserted~) =>
          self.apply_text_edit_internal(
            start, delete_len, inserted, timestamp_ms, true, false,
          )
        @text_change.TextChange::ReplaceAll(_) =>
          abort("compute_text_change unexpectedly returned ReplaceAll")
      }
    }),
  )
}
