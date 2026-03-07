// SyncEditor: Unified facade composing TextDoc + UndoManager + ReactiveParser
// Replaces ParsedEditor + separate UndoManager global

///|
pub struct SyncEditor {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ReactiveParser[@parser.SyntaxNode]
  priv mut cursor : Int
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
pub fn SyncEditor::get_resolution(self : SyncEditor) -> @parser.Resolution {
  @parser.resolve(self.get_ast())
}

///|
pub fn SyncEditor::get_dot_resolved(self : SyncEditor) -> String {
  let ast = self.get_ast()
  let res = @parser.resolve(ast)
  @parser.term_to_dot_resolved(ast, res)
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

// --- Bulk text methods ---

///|
pub fn SyncEditor::set_text(self : SyncEditor, new_text : String) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let old_len = old_text.length()
  self.cursor = 0
  for _i = 0; _i < old_len; _i = _i + 1 {
    self.doc.delete(@text.Pos::at(0)) catch {
      _ => ()
    }
  }
  if new_text.length() > 0 {
    self.doc.insert(@text.Pos::at(0), new_text) catch {
      _ => ()
    }
    self.cursor = new_text.length()
  }
  self.parser.set_source(self.doc.text())
}

///|
pub fn SyncEditor::set_text_and_record(
  self : SyncEditor,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  let old_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let old_len = old_text.length()
  let new_len = new_text.length()
  let mut prefix = 0
  while prefix < old_len &&
        prefix < new_len &&
        old_text[prefix] == new_text[prefix] {
    prefix = prefix + 1
  }
  let mut suffix = 0
  while suffix < old_len - prefix &&
        suffix < new_len - prefix &&
        old_text[old_len - 1 - suffix] == new_text[new_len - 1 - suffix] {
    suffix = suffix + 1
  }
  let del_count = old_len - prefix - suffix
  let ins_len = new_len - prefix - suffix
  for _i = 0; _i < del_count; _i = _i + 1 {
    self.doc.delete_and_record(@text.Pos::at(prefix), self.undo, timestamp_ms~) catch {
      _ => ()
    }
  }
  if ins_len > 0 {
    try {
      let ins_text = new_text[prefix:prefix + ins_len].to_string()
      self.doc.insert_and_record(
        @text.Pos::at(prefix),
        ins_text,
        self.undo,
        timestamp_ms~,
      )
    } catch {
      _ => ()
    }
  }
  self.adjust_cursor()
  self.parser.set_source(self.doc.text())
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
    self.adjust_cursor()
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
    self.adjust_cursor()
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
