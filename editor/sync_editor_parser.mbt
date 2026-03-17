// Parser-facing SyncEditor methods.

///|
fn SyncEditor::set_parser_signals(
  self : SyncEditor,
  source : String,
  syntax : @seam.SyntaxNode?,
) -> Unit {
  self.parser_rt.batch(fn() {
    self.source_text.set(source)
    self.syntax_tree.set(syntax)
  })
}

///|
fn SyncEditor::sync_parser_after_text_change(
  self : SyncEditor,
  old_source : String,
  new_source : String,
  known_edit : @parser.Edit?,
) -> Unit {
  if old_source == new_source {
    return
  }
  if new_source == "" {
    ignore(self.parser.reset(new_source))
    self.set_parser_signals(new_source, None)
    return
  }
  let edit = match known_edit {
    Some(edit) => edit
    None => compute_edit(old_source, new_source)
  }
  let syntax = self.parser.edit(edit, new_source)
  self.set_parser_signals(new_source, Some(syntax))
}

///|
fn SyncEditor::adjust_peer_cursors_after_text_change(
  self : SyncEditor,
  old_source : String,
  new_source : String,
  known_edit : @parser.Edit?,
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
  known_edit : @parser.Edit?,
) -> @parser.Edit? {
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
fn SyncEditor::apply_local_text_change(
  self : SyncEditor,
  old_source : String,
  new_source : String,
  known_edit : @parser.Edit?,
) -> Unit {
  let applied_edit = resolve_applied_edit(old_source, new_source, known_edit)
  self.adjust_peer_cursors_after_text_change(
    old_source, new_source, applied_edit,
  )
  self.sync_parser_after_text_change(old_source, new_source, applied_edit)
}

///|
fn SyncEditor::force_parser_reset(self : SyncEditor) -> @seam.SyntaxNode {
  let source = self.doc.text()
  let syntax = self.parser.reset(source)
  if source == "" {
    self.set_parser_signals(source, None)
  } else {
    self.set_parser_signals(source, Some(syntax))
  }
  syntax
}

///|
fn SyncEditor::current_syntax_tree(self : SyncEditor) -> @seam.SyntaxNode {
  match self.syntax_tree.get() {
    Some(tree) => tree
    None => self.force_parser_reset()
  }
}

///|
pub fn SyncEditor::mark_dirty(self : SyncEditor) -> Unit {
  ignore(self.force_parser_reset())
}

///|
pub fn SyncEditor::get_ast(self : SyncEditor) -> @ast.Term {
  let syntax_node = self.current_syntax_tree()
  @parser.syntax_node_to_term(syntax_node)
}

///|
pub fn SyncEditor::get_ast_pretty(self : SyncEditor) -> String {
  let ast = self.get_ast()
  "Expression: " + @ast.print_term(ast) + "\n\nAST:\n" + @debug.to_string(ast)
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
  if self.doc.text() == "" {
    return []
  }
  self.parser.diagnostics()
}

///|
pub fn SyncEditor::is_parse_valid(self : SyncEditor) -> Bool {
  self.get_errors().is_empty()
}
