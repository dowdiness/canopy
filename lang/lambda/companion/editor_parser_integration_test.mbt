// Lambda-grammar parse-tree assertions for the lambda editor.
// Moved here from editor/sync_editor_parser_test.mbt as part of the
// editor-neutral-test-grammar work (#599): these verify lambda's specific
// parse trees / pretty output / resolution, which are lang/lambda's
// responsibility, not the (language-agnostic) editor's.

///|
test "parser: get_ast_pretty contains expression" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("42")
  let pretty = get_lambda_ast_pretty(se)
  inspect(pretty.contains("42"), content="true")
  inspect(pretty.contains("Expression:"), content="true")
}

///|
test "parser: complex expression parses correctly" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("(f, x) => f x")
  inspect(
    @ast.print_term(get_lambda_ast(se)),
    content=(
      #|(f) => (x) => f x
    ),
  )
}

///|
test "parser: let binding with body" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("let x = 1\nx + 2")
  let ast = get_lambda_ast(se)
  inspect(
    @ast.print_term(ast),
    content=(
      #|{ let x = 1
      #|x + 2 }
    ),
  )
}

///|
test "parser: if-then-else expression" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("if x then 1 else 2")
  inspect(@ast.print_term(get_lambda_ast(se)), content="if x then 1 else 2")
}

///|
test "parser: arithmetic addition" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("1 + 2 + 3")
  let ast = get_lambda_ast(se)
  inspect(
    @ast.print_term(ast),
    content=(
      #|1 + 2 + 3
    ),
  )
}

///|
test "parser: resolution tracks bound and free variables" {
  let se = (try! new_lambda_editor("agent1")).0
  se.set_text("(x) => x + y")
  let res = get_lambda_resolution(se)
  // Verify resolution is populated (bound x, free y)
  inspect(res.vars.length() > 0, content="true")
}
