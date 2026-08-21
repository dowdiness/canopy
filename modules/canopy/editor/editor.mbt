///| Editor - User-facing editor with cursor tracking

///|

///|
/// Wraps a TextState and maintains cursor position
pub struct Editor {
  doc : @text.TextState
  mut cursor : Int // Unicode-scalar position, 0-based
} derive(Debug)

///|
/// Create a new editor for a non-empty agent identifier.
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
pub fn Editor::new(agent_id : String) -> Editor raise @text.TextError {
  { doc: @text.TextState::new(agent_id), cursor: 0 }
}

///|
/// Get the current text content
pub fn Editor::get_text(self : Editor) -> String {
  self.doc.text()
}

///|
/// Get the current cursor position
pub fn Editor::get_cursor(self : Editor) -> Int {
  self.cursor
}

///|
/// Move cursor to a specific position
pub fn Editor::move_cursor(self : Editor, position : Int) -> Unit {
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
fn unicode_scalar_length(text : String) -> Int {
  let mut length = 0
  for _ in text {
    length += 1
  }
  length
}

///| Insert text at current cursor position

///|

///|
/// After insertion, cursor moves to after the inserted text
pub fn Editor::insert(self : Editor, text : String) -> Unit raise {
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor += unicode_scalar_length(text)
}

///| Insert text at a specific position

///|

///|
/// Cursor does not move
pub fn Editor::insert_at(
  self : Editor,
  position : Int,
  text : String,
) -> Unit raise {
  self.doc.insert(@text.Pos::at(position), text)
}

///| Delete character at current cursor position

///|

///|
/// Returns true if successful, false if nothing to delete
pub fn Editor::delete(self : Editor) -> Bool {
  try self.doc.delete(@text.Pos::at(self.cursor)) catch {
    @text.TextError::InvalidPosition(..) => false
    _ => false
  } noraise {
    _ => true
  }
}

///| Delete character before cursor (backspace)

///|

///|
/// Returns true if successful, false if at start
pub fn Editor::backspace(self : Editor) -> Bool {
  if self.cursor > 0 {
    self.cursor -= 1
    try self.doc.delete(@text.Pos::at(self.cursor)) catch {
      @text.TextError::InvalidPosition(..) => {
        // Restore cursor if delete failed
        self.cursor += 1
        false
      }
      _ => {
        self.cursor += 1
        false
      }
    } noraise {
      _ => true
    }
  } else {
    false
  }
}

///|
/// Adjust cursor to stay within valid range after merge
fn Editor::adjust_cursor(self : Editor) -> Unit {
  let text_len = self.doc.len()
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
/// Get the current version (for sync)
pub fn Editor::get_version(self : Editor) -> @text.Version {
  self.doc.version()
}

///|
/// Sync: Export all operations as a SyncMessage
pub fn Editor::export_all(self : Editor) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
/// Sync: Export operations since a peer's version
pub fn Editor::export_since(
  self : Editor,
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}

///|
/// Sync: take a peer's operations into this document, reporting what landed.
///
/// Operations whose causal prerequisites are absent are retained rather than
/// rejected, and counted in the returned report. That is a state, not a
/// failure: a caller that cannot tell a document waiting for prerequisites
/// from a broken one cannot decide what to do next. Callers that require a
/// message to be complete apply that policy themselves — `apply_sync` is the
/// one that does.
pub fn Editor::admit(
  self : Editor,
  msg : @text.SyncMessage,
) -> @text.SyncReport raise @text.TextError {
  let report_result : Result[@text.SyncReport, @text.TextError] = Ok(
    self.doc.sync().apply(msg),
  ) catch {
    error => Err(error)
  }
  // EGW may apply ready operations before reporting an error or retaining
  // causal orphans, so repair shell state before propagating either outcome.
  self.adjust_cursor()
  match report_result {
    Ok(report) => report
    Err(error) => raise error
  }
}

///|
/// Sync: apply a SyncMessage from a peer, requiring it to be complete.
///
/// This is `admit` plus a completeness policy. The name does not say so; it
/// predates the distinction and is kept because its callers depend on the
/// raise.
pub fn Editor::apply_sync(self : Editor, msg : @text.SyncMessage) -> Unit raise {
  if self.admit(msg).pending_operations() > 0 {
    raise @text.TextError::VersionNotFound
  }
}
