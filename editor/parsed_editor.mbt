// ParsedEditor: Integration of CRDT text editor with incremental parser
// Combines Editor (CRDT text) and IncrementalParser (AST) using wrapper pattern

///|
/// ParsedEditor wraps both the CRDT editor and incremental parser
/// Keeps them synchronized via lazy evaluation and text diffing
pub struct ParsedEditor {
  editor : Editor // CRDT text editor
  parser : @parser.ImperativeParser[@parser.SyntaxNode] // Incremental parser
  mut ast : @ast.AstNode? // Cached AST (lazy evaluation)
  mut parse_dirty : Bool // Does AST need reparsing?
  mut cached_text : String // Last parsed text (for computing Edit)
  mut cached_errors : Array[String] // Cached errors from last parse
}

///|
/// Create a new ParsedEditor with the given agent ID
pub fn ParsedEditor::new(agent_id : String) -> ParsedEditor {
  let editor = Editor::new(agent_id)
  let parser = @parser.new_imperative_parser("")
  {
    editor,
    parser,
    ast: None,
    parse_dirty: true,
    cached_text: "",
    cached_errors: [],
  }
}

///|
/// Insert text at the current cursor position
/// Marks AST as dirty for lazy reparsing
pub fn ParsedEditor::insert(self : ParsedEditor, text : String) -> Unit raise {
  self.editor.insert(text)
  self.parse_dirty = true
}

///|
/// Delete character at cursor position (forward delete)
/// Returns true if deletion succeeded, false if at end of document
pub fn ParsedEditor::delete(self : ParsedEditor) -> Bool {
  let result = self.editor.delete()
  if result {
    self.parse_dirty = true
  }
  result
}

///|
/// Delete character before cursor (backspace)
/// Returns true if deletion succeeded, false if at start of document
pub fn ParsedEditor::backspace(self : ParsedEditor) -> Bool {
  let result = self.editor.backspace()
  if result {
    self.parse_dirty = true
  }
  result
}

///|
/// Move cursor to specific position
pub fn ParsedEditor::move_cursor(self : ParsedEditor, position : Int) -> Unit {
  self.editor.move_cursor(position)
}

///|
/// Get current cursor position
pub fn ParsedEditor::get_cursor(self : ParsedEditor) -> Int {
  self.editor.get_cursor()
}

///|
/// Get the current text content
pub fn ParsedEditor::get_text(self : ParsedEditor) -> String {
  self.editor.get_text()
}

///|
/// Mark the AST as dirty so it will be reparsed on next access
pub fn ParsedEditor::mark_dirty(self : ParsedEditor) -> Unit {
  self.parse_dirty = true
}

///|
/// Get the AST (lazy evaluation - only reparses if dirty)
/// Raises an error if parsing fails
pub fn ParsedEditor::get_ast(self : ParsedEditor) -> @ast.AstNode {
  if self.parse_dirty {
    self.reparse()
  }
  match self.ast {
    Some(ast) => ast
    None => abort("No valid parse tree")
  }
}

///|
/// Incremental reparse using the Edit Bridge.
/// Converts old→new text via loom's TextDelta API and applies the resulting
/// edits to the incremental parser.
fn ParsedEditor::reparse(self : ParsedEditor) -> Unit {
  let old_text = self.cached_text
  let new_text = self.editor.get_text()
  let edits = merge_to_edits(old_text, new_text)
  // text_to_delta always produces at most one contiguous change, so edits
  // has length 0 (identical strings) or 1.
  let syntax_node = if edits.is_empty() {
    // No textual change (e.g., identical text or failed op).
    // Apply a no-op edit at position 0 to obtain the current SyntaxNode.
    self.parser.edit(@parser.Edit::new(0, 0, 0), new_text)
  } else {
    self.parser.edit(edits[0], new_text)
  }
  let counter = Ref::new(0)
  let ast = @parser.syntax_node_to_ast_node(syntax_node, counter)
  self.ast = Some(ast)
  self.cached_errors = @parser.collect_errors(ast)
  self.cached_text = new_text
  self.parse_dirty = false
}

///|
/// Get cached errors from the last parse
/// Ensures AST is up-to-date before returning errors
pub fn ParsedEditor::get_errors(self : ParsedEditor) -> Array[String] {
  // Ensure the AST is up-to-date (triggers reparse if dirty)
  let _ = self.get_ast()
  // Return the cached errors (collected during reparse)
  self.cached_errors
}

///|
/// Check if the current parse tree is valid (no errors)
pub fn ParsedEditor::is_parse_valid(self : ParsedEditor) -> Bool {
  match self.ast {
    Some(ast) => not(@parser.has_errors(ast))
    None => false
  }
}

///|
/// Apply a sync message from a remote peer and update local state.
/// Marks AST as dirty for reparsing after merge.
pub fn ParsedEditor::apply_sync(
  self : ParsedEditor,
  msg : @text.SyncMessage,
) -> Unit raise {
  self.editor.apply_sync(msg)
  self.parse_dirty = true
}

///|
/// Get the current version (for sync)
pub fn ParsedEditor::get_version(self : ParsedEditor) -> @text.Version {
  self.editor.get_version()
}

///|
/// Export all operations as a SyncMessage (for initial peer sync)
pub fn ParsedEditor::export_all(self : ParsedEditor) -> @text.SyncMessage raise {
  self.editor.export_all()
}

///|
/// Export operations since a peer's version (for delta sync)
pub fn ParsedEditor::export_since(
  self : ParsedEditor,
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.editor.export_since(peer_version)
}
