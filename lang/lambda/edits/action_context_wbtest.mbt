// Whitebox tests for action_context.mbt — action domain logic extracted
// from examples/ideal/main.

///|
fn test_ctx() -> ActionContext {
  {
    node_id: @core.NodeId::from_int(1),
    kind: @ast.Term::Unit,
    is_let_binding: false,
    binding_node_id: None,
    binding_def_index: None,
    module_node_id: None,
  }
}

///|
fn test_binding_ctx() -> ActionContext {
  {
    node_id: @core.NodeId::from_int(2),
    kind: @ast.Term::Int(0),
    is_let_binding: true,
    binding_node_id: Some(@core.NodeId::from_int(10)),
    binding_def_index: Some(0),
    module_node_id: Some(@core.NodeId::from_int(0)),
  }
}

// ── get_submenu_choices ────────────────────────────────────────────

///|
test "get_submenu_choices: change_op returns operator choices" {
  let choices = get_submenu_choices("change_op", @ast.Term::Unit)
  inspect(choices.length(), content="2")
  inspect(choices[0].0, content="+ (plus)")
  inspect(choices[0].1, content="Plus")
  inspect(choices[1].0, content="- (minus)")
  inspect(choices[1].1, content="Minus")
}

///|
test "get_submenu_choices: wrap_bop returns operator choices" {
  let choices = get_submenu_choices("wrap_bop", @ast.Term::Unit)
  inspect(choices.length(), content="2")
}

///|
test "get_submenu_choices: unwrap Bop returns keep-left/keep-right" {
  let choices = get_submenu_choices(
    "unwrap",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2)),
  )
  inspect(choices.length(), content="2")
  inspect(choices[0].0, content="Keep left operand")
  inspect(choices[1].0, content="Keep right operand")
}

///|
test "get_submenu_choices: unwrap If returns three choices" {
  let choices = get_submenu_choices(
    "unwrap",
    @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
  )
  inspect(choices.length(), content="3")
  inspect(choices[2].0, content="Keep else branch")
}

///|
test "get_submenu_choices: unwrap App returns keep-func/keep-arg" {
  let choices = get_submenu_choices(
    "unwrap",
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Int(1)),
  )
  inspect(choices.length(), content="2")
  inspect(choices[0].0, content="Keep function")
  inspect(choices[1].0, content="Keep argument")
}

///|
test "get_submenu_choices: unwrap generic returns single keep-body" {
  let choices = get_submenu_choices("unwrap", @ast.Term::Unit)
  inspect(choices.length(), content="1")
  inspect(choices[0].0, content="Keep body")
}

///|
test "get_submenu_choices: unknown action returns empty" {
  let choices = get_submenu_choices("nonexistent", @ast.Term::Unit)
  inspect(choices.length(), content="0")
}

///|
test "get_submenu_choices: delete returns empty" {
  let choices = get_submenu_choices("delete", @ast.Term::Unit)
  inspect(choices.length(), content="0")
}

// ── parse_bop ───────────────────────────────────────────────────────

///|
test "parse_bop: Plus" {
  inspect(parse_bop("Plus"), content="Some(Plus)")
}

///|
test "parse_bop: Minus" {
  inspect(parse_bop("Minus"), content="Some(Minus)")
}

///|
test "parse_bop: unknown returns None" {
  inspect(parse_bop("Times") is None, content="true")
  inspect(parse_bop("") is None, content="true")
  inspect(parse_bop("plus") is None, content="true")
}

// ── to_node_context ─────────────────────────────────────────────────

///|
test "to_node_context: non-binding context returns default" {
  let nc = to_node_context(test_ctx())
  inspect(nc.is_let_binding, content="false")
  inspect(nc.binding_node_id is None, content="true")
  inspect(nc.binding_def_index is None, content="true")
  inspect(nc.module_node_id is None, content="true")
}

///|
test "to_node_context: binding context produces new_binding" {
  let nc = to_node_context(test_binding_ctx())
  inspect(nc.is_let_binding, content="true")
  inspect(nc.binding_node_id, content="Some(NodeId(10))")
  inspect(nc.binding_def_index, content="Some(0)")
  inspect(nc.module_node_id, content="Some(NodeId(0))")
}

// ── build_action_context ────────────────────────────────────────────

///|
test "build_action_context: non-binding node" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("1")
  let di = @lambda_proj.DefinitionIndex::from_proj_node(proj)
  let ctx = build_action_context(
    node_id=proj.id(),
    kind=proj.kind,
    definition_index=di,
    module_node_id=None,
  )
  inspect(ctx.is_let_binding, content="false")
  inspect(ctx.binding_node_id is None, content="true")
}

///|
test "build_action_context: let-binding node via parse" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("let x = 1\nx")
  let di = @lambda_proj.DefinitionIndex::from_proj_node(proj)
  // The first child (index 0) is the LetDef init: Int(1)
  let init_child = proj.children[0]
  let ctx = build_action_context(
    node_id=init_child.id(),
    kind=init_child.kind,
    definition_index=di,
    module_node_id=Some(proj.id()),
  )
  inspect(ctx.is_let_binding, content="true")
  inspect(ctx.binding_node_id is Some(_), content="true")
  inspect(ctx.binding_def_index is Some(_), content="true")
  inspect(ctx.module_node_id is Some(_), content="true")
}

// ── build_tree_edit_op ──────────────────────────────────────────────

///|
test "build_tree_edit_op: delete" {
  let result = build_tree_edit_op("delete", test_ctx(), "", "")
  inspect(result is Ok(Some(Delete(_))), content="true")
}

///|
test "build_tree_edit_op: delete uses ctx node_id" {
  let ctx = test_ctx()
  match build_tree_edit_op("delete", ctx, "", "") {
    Ok(Some(Delete(node_id~))) =>
      inspect(node_id == ctx.node_id, content="true")
    _ => inspect("unexpected", content="Delete")
  }
}

///|
test "build_tree_edit_op: extract_to_let needs name" {
  let result = build_tree_edit_op("extract_to_let", test_ctx(), "", "")
  inspect(result is Ok(None), content="true")
}

///|
test "build_tree_edit_op: extract_to_let with name" {
  let result = build_tree_edit_op("extract_to_let", test_ctx(), "", "foo")
  match result {
    Ok(Some(ExtractToLet(node_id~, var_name~))) =>
      inspect(var_name, content="foo")
    _ => inspect("unexpected", content="ExtractToLet")
  }
}

///|
test "build_tree_edit_op: inline" {
  let result = build_tree_edit_op("inline", test_ctx(), "", "")
  inspect(result is Ok(Some(InlineDefinition(_))), content="true")
}

///|
test "build_tree_edit_op: rename needs name" {
  let result = build_tree_edit_op("rename", test_ctx(), "", "")
  inspect(result is Ok(None), content="true")
}

///|
test "build_tree_edit_op: rename with name" {
  let result = build_tree_edit_op("rename", test_ctx(), "", "bar")
  match result {
    Ok(Some(Rename(node_id~, new_name~))) => inspect(new_name, content="bar")
    _ => inspect("unexpected", content="Rename")
  }
}

///|
test "build_tree_edit_op: unwrap with valid choice" {
  let result = build_tree_edit_op("unwrap", test_ctx(), "1", "")
  match result {
    Ok(Some(Unwrap(node_id~, keep_child_index=1))) =>
      inspect("ok", content="ok")
    _ => inspect("unexpected", content="Unwrap")
  }
}

///|
test "build_tree_edit_op: unwrap with invalid choice errors" {
  let result = build_tree_edit_op("unwrap", test_ctx(), "abc", "")
  inspect(result is Err(_), content="true")
}

///|
test "build_tree_edit_op: swap" {
  let result = build_tree_edit_op("swap", test_ctx(), "", "")
  inspect(result is Ok(Some(SwapChildren(_))), content="true")
}

///|
test "build_tree_edit_op: change_op with valid choice" {
  let result = build_tree_edit_op("change_op", test_ctx(), "Plus", "")
  inspect(
    result is Ok(Some(ChangeOperator(node_id=_, new_op=Plus))),
    content="true",
  )
}

///|
test "build_tree_edit_op: change_op with invalid choice errors" {
  let result = build_tree_edit_op("change_op", test_ctx(), "Times", "")
  inspect(result is Err(_), content="true")
}

///|
test "build_tree_edit_op: wrap_lambda needs name" {
  let result = build_tree_edit_op("wrap_lambda", test_ctx(), "", "")
  inspect(result is Ok(None), content="true")
}

///|
test "build_tree_edit_op: wrap_lambda with name" {
  let result = build_tree_edit_op("wrap_lambda", test_ctx(), "", "x")
  match result {
    Ok(Some(WrapInLambda(node_id~, var_name~))) =>
      inspect(var_name, content="x")
    _ => inspect("unexpected", content="WrapInLambda")
  }
}

///|
test "build_tree_edit_op: wrap_if" {
  let result = build_tree_edit_op("wrap_if", test_ctx(), "", "")
  inspect(result is Ok(Some(WrapInIf(_))), content="true")
}

///|
test "build_tree_edit_op: wrap_bop with valid choice" {
  let result = build_tree_edit_op("wrap_bop", test_ctx(), "Minus", "")
  inspect(result is Ok(Some(WrapInBop(node_id=_, op=Minus))), content="true")
}

///|
test "build_tree_edit_op: wrap_bop with invalid choice errors" {
  let result = build_tree_edit_op("wrap_bop", test_ctx(), "Times", "")
  inspect(result is Err(_), content="true")
}

///|
test "build_tree_edit_op: wrap_app" {
  let result = build_tree_edit_op("wrap_app", test_ctx(), "", "")
  inspect(result is Ok(Some(WrapInApp(_))), content="true")
}

///|
test "build_tree_edit_op: binding_duplicate with binding" {
  let result = build_tree_edit_op(
    "binding_duplicate",
    test_binding_ctx(),
    "",
    "",
  )
  match result {
    Ok(Some(DuplicateBinding(binding_node_id~))) =>
      inspect(binding_node_id == @core.NodeId::from_int(10), content="true")
    _ => inspect("unexpected", content="DuplicateBinding")
  }
}

///|
test "build_tree_edit_op: binding_duplicate without binding errors" {
  let result = build_tree_edit_op("binding_duplicate", test_ctx(), "", "")
  inspect(result is Err(_), content="true")
}

///|
test "build_tree_edit_op: binding_move_up" {
  let result = build_tree_edit_op("binding_move_up", test_binding_ctx(), "", "")
  inspect(result is Ok(Some(MoveBindingUp(_))), content="true")
}

///|
test "build_tree_edit_op: binding_move_down" {
  let result = build_tree_edit_op(
    "binding_move_down",
    test_binding_ctx(),
    "",
    "",
  )
  inspect(result is Ok(Some(MoveBindingDown(_))), content="true")
}

///|
test "build_tree_edit_op: binding_inline_all" {
  let result = build_tree_edit_op(
    "binding_inline_all",
    test_binding_ctx(),
    "",
    "",
  )
  inspect(result is Ok(Some(InlineAllUsages(_))), content="true")
}

///|
test "build_tree_edit_op: binding_delete" {
  let result = build_tree_edit_op("binding_delete", test_binding_ctx(), "", "")
  inspect(result is Ok(Some(DeleteBinding(_))), content="true")
}

///|
test "build_tree_edit_op: binding_rename needs name" {
  let result = build_tree_edit_op("binding_rename", test_binding_ctx(), "", "")
  inspect(result is Ok(None), content="true")
}

///|
test "build_tree_edit_op: binding_rename with name" {
  let result = build_tree_edit_op(
    "binding_rename",
    test_binding_ctx(),
    "",
    "bar",
  )
  match result {
    Ok(Some(Rename(node_id~, new_name~))) => inspect(new_name, content="bar")
    _ => inspect("unexpected", content="Rename")
  }
}

///|
test "build_tree_edit_op: add_binding with module" {
  let result = build_tree_edit_op("add_binding", test_binding_ctx(), "", "")
  inspect(result is Ok(Some(AddBinding(_))), content="true")
}

///|
test "build_tree_edit_op: add_binding without module errors" {
  let result = build_tree_edit_op("add_binding", test_ctx(), "", "")
  inspect(result is Err(_), content="true")
}

///|
test "build_tree_edit_op: unknown action errors" {
  let result = build_tree_edit_op("nonexistent", test_ctx(), "", "")
  inspect(result is Err(_), content="true")
}
