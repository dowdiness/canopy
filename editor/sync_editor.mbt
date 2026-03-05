// SyncEditor: Unified facade composing TextDoc + UndoManager + ReactiveParser
// Replaces ParsedEditor + separate UndoManager global

///|
pub struct SyncEditor {
  doc : @text.TextDoc
  undo : @undo.UndoManager
  parser : @loom.ReactiveParser[@parser.SyntaxNode]
  mut cursor : Int
}

///|
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor {
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser: @loom.new_reactive_parser("", @parser.lambda_grammar),
    cursor: 0,
  }
}

// --- Editing methods ---

///|
pub fn SyncEditor::insert(self : SyncEditor, text : String) -> Unit raise {
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor = self.cursor + text.length()
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::delete(self : SyncEditor) -> Bool {
  try self.doc.delete(@text.Pos::at(self.cursor)) catch {
    _ => false
  } noraise {
    _ => {
      self.parser.set_source(self.doc.text())
      true
    }
  }
}

///|
pub fn SyncEditor::backspace(self : SyncEditor) -> Bool {
  if self.cursor > 0 {
    self.cursor = self.cursor - 1
    try self.doc.delete(@text.Pos::at(self.cursor)) catch {
      _ => {
        self.cursor = self.cursor + 1
        false
      }
    } noraise {
      _ => {
        self.parser.set_source(self.doc.text())
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

// --- Query methods ---

///|
pub fn SyncEditor::get_text(self : SyncEditor) -> String {
  self.doc.text()
}

///|
pub fn SyncEditor::get_cursor(self : SyncEditor) -> Int {
  self.cursor
}

///|
pub fn SyncEditor::mark_dirty(self : SyncEditor) -> Unit {
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::get_ast(self : SyncEditor) -> @ast.Term {
  let syntax_node = self.parser.term()
  @parser.syntax_node_to_term(syntax_node)
}

///|
pub fn SyncEditor::get_errors(self : SyncEditor) -> Array[String] {
  self.parser.diagnostics()
}

///|
pub fn SyncEditor::is_parse_valid(self : SyncEditor) -> Bool {
  self.get_errors().is_empty()
}

// --- Sync methods ---

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
  self.doc.sync().apply(msg)
  self.adjust_cursor()
  self.parser.set_source(self.doc.text())
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

// --- Undo methods ---

///|
pub fn SyncEditor::insert_and_record(
  self : SyncEditor,
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  self.doc.insert_and_record(
    @text.Pos::at(self.cursor),
    text,
    self.undo,
    timestamp_ms~,
  )
  self.cursor = self.cursor + text.length()
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::delete_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  try {
    self.doc.delete_and_record(
      @text.Pos::at(self.cursor),
      self.undo,
      timestamp_ms~,
    )
    self.parser.set_source(self.doc.text())
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::backspace_and_record(
  self : SyncEditor,
  timestamp_ms : Int,
) -> Bool {
  if self.cursor > 0 {
    let new_pos = self.cursor - 1
    try {
      self.doc.delete_and_record(
        @text.Pos::at(new_pos),
        self.undo,
        timestamp_ms~,
      )
      self.cursor = new_pos
      self.parser.set_source(self.doc.text())
      true
    } catch {
      _ => false
    }
  } else {
    false
  }
}

///|
pub fn SyncEditor::undo(self : SyncEditor) -> Bool {
  try {
    self.undo.undo(self.doc)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::redo(self : SyncEditor) -> Bool {
  try {
    self.undo.redo(self.doc)
    self.mark_dirty()
    true
  } catch {
    _ => false
  }
}

///|
pub fn SyncEditor::can_undo(self : SyncEditor) -> Bool {
  self.undo.can_undo()
}

///|
pub fn SyncEditor::can_redo(self : SyncEditor) -> Bool {
  self.undo.can_redo()
}

///|
pub fn SyncEditor::set_tracking(self : SyncEditor, enabled : Bool) -> Unit {
  self.undo.set_tracking(enabled)
}

///|
pub fn SyncEditor::clear_undo(self : SyncEditor) -> Unit {
  self.undo.clear()
}
