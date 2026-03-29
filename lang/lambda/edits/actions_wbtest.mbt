///|
test "actions for Int node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Int(0), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("delete"), content="true")
  inspect(ids.contains("wrap_lambda"), content="true")
  inspect(ids.contains("wrap_if"), content="true")
  inspect(ids.contains("wrap_bop"), content="true")
  inspect(ids.contains("wrap_app"), content="true")
  inspect(ids.contains("inline"), content="false")
  inspect(ids.contains("rename"), content="false")
  inspect(ids.contains("unwrap"), content="false")
}

///|
test "actions for Var node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Var("x"), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("inline"), content="true")
  inspect(ids.contains("rename"), content="true")
}

///|
test "actions for Bop: no self-wrapping" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(0), @ast.Term::Int(0)),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("swap"), content="true")
  inspect(ids.contains("change_op"), content="true")
  inspect(ids.contains("unwrap"), content="true")
  inspect(ids.contains("wrap_bop"), content="false") // No self-wrapping
  inspect(ids.contains("wrap_if"), content="true")
  inspect(ids.contains("wrap_lambda"), content="true")
}

///|
test "actions for If: no self-wrapping" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::If(@ast.Term::Int(0), @ast.Term::Int(0), @ast.Term::Int(0)),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("swap"), content="true")
  inspect(ids.contains("wrap_if"), content="false") // No self-wrapping
  inspect(ids.contains("wrap_bop"), content="true")
}

///|
test "actions for Error: only delete" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Error("bad"), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.length(), content="1")
  inspect(ids[0], content="delete")
}

///|
test "binding context adds binding actions" {
  let ctx = NodeContext::new_binding(
    binding_node_id=NodeId::from_int(99),
    binding_def_index=0,
    module_node_id=NodeId::from_int(1),
  )
  let actions = get_actions_for_node(@ast.Term::Int(0), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("binding_rename"), content="true")
  inspect(ids.contains("binding_duplicate"), content="true")
  inspect(ids.contains("binding_delete"), content="true")
  inspect(ids.contains("binding_inline_all"), content="true")
  inspect(ids.contains("binding_move_up"), content="true")
  inspect(ids.contains("binding_move_down"), content="true")
}

///|
test "actions for Lam node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("rename"), content="true")
  inspect(ids.contains("unwrap"), content="true")
  inspect(ids.contains("wrap_lambda"), content="true")
  inspect(ids.contains("wrap_if"), content="true")
  inspect(ids.contains("wrap_bop"), content="true")
  inspect(ids.contains("wrap_app"), content="true")
  inspect(ids.contains("delete"), content="true")
  inspect(ids.contains("inline"), content="false")
}

///|
test "actions for App node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Int(1)),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("unwrap"), content="true")
  inspect(ids.contains("wrap_lambda"), content="true")
  inspect(ids.contains("delete"), content="true")
  inspect(ids.contains("rename"), content="false")
  inspect(ids.contains("inline"), content="false")
}

///|
test "actions for Module node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::Module([], @ast.Term::Unit),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.length(), content="1")
  inspect(ids[0], content="add_binding")
}

///|
test "actions for Unit node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Unit, ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("wrap_lambda"), content="true")
  inspect(ids.contains("wrap_if"), content="true")
  inspect(ids.contains("wrap_bop"), content="true")
  inspect(ids.contains("wrap_app"), content="true")
  inspect(ids.contains("delete"), content="true")
  inspect(ids.contains("extract_to_let"), content="false")
}
