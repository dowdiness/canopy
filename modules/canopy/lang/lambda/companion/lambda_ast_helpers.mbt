// Lambda-specific AST accessor functions.
// These were previously methods on SyncEditor[@ast.Term].

///|
/// Returns the parsed lambda Term.
pub fn get_lambda_ast(editor : @editor.SyncEditor[@ast.Term]) -> @ast.Term {
  match editor.get_tree() {
    Some(t) => t
    None => @ast.Term::Unit
  }
}

///|
/// Returns pretty-printed AST with debug tree.
pub fn get_lambda_ast_pretty(editor : @editor.SyncEditor[@ast.Term]) -> String {
  let ast = get_lambda_ast(editor)
  let formatted = @pretty.pretty_print(ast, width=60)
  "Expression: " + formatted + "\n\nAST:\n" + @debug.to_string(ast)
}

///|
/// Returns name resolution info.
pub fn get_lambda_resolution(
  editor : @editor.SyncEditor[@ast.Term],
) -> @parser.Resolution {
  let (_, res) = @parser.resolve(get_lambda_ast(editor))
  res
}

///|
/// Returns Graphviz DOT with resolution.
pub fn get_lambda_dot_resolved(
  editor : @editor.SyncEditor[@ast.Term],
) -> String {
  let ast = get_lambda_ast(editor)
  let (resolved_ast, res) = @parser.resolve(ast)
  @parser.term_to_dot_resolved(resolved_ast, res)
}
