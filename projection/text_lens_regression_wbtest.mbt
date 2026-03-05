///|
// Regression: ProjNode.kind must be rebuilt from reconciled children so that
// text_lens_get renders the updated term, not the stale pre-edit kind.
test "text_lens_put should update rendered text after same-shape edit" {
  let (ast, _) = parse_to_proj_node("x + 1")
  let model = CanonicalModel::from_ast(ast)
  let _ = text_lens_put(model, "x + 2")
  let text = match text_lens_get(model) {
    Ok(t) => t
    Err(msg) => abort(msg)
  }
  inspect(text, content="(x + 2)")
}
