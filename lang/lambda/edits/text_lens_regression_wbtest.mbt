///|
// Regression: ProjNode.kind must be rebuilt from reconciled children so that
// rendering reflects the updated tree after a same-shape edit.
test "reconcile_ast rebuilds rendered text after same-shape edit" {
  let (old_root, _) = parse_to_proj_node("x + 1")
  let (new_root, _) = parse_to_proj_node("x + 2")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(100))
  inspect(@ast.print_term(reconciled.kind), content="(x + 2)")
}
