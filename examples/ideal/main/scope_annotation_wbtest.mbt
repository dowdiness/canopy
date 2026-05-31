// Whitebox tests for scope annotation.

///|
test "color_index is stable across calls" {
  let idx1 = binder_color_index("x")
  let idx2 = binder_color_index("x")
  inspect(idx1 == idx2, content="true")
  let idx3 = binder_color_index("add")
  inspect(idx1 >= 0 && idx1 < 8, content="true")
  inspect(idx3 >= 0 && idx3 < 8, content="true")
}

///|
test "compute_highlight_set for variable returns binder + usages" {
  let scope_map : Map[@canopy_core.NodeId, ScopeAnnotation] = {}
  let var_id = @canopy_core.NodeId::from_int(10)
  let binder_id = @canopy_core.NodeId::from_int(1)
  let usage1 = @canopy_core.NodeId::from_int(10)
  let usage2 = @canopy_core.NodeId::from_int(20)
  scope_map[var_id] = {
    binder_id: Some(binder_id),
    is_definition: false,
    color_index: 0,
    usage_ids: [],
  }
  scope_map[binder_id] = {
    binder_id: Some(binder_id),
    is_definition: true,
    color_index: 0,
    usage_ids: [usage1, usage2],
  }
  let hs = compute_highlight_set(var_id, scope_map)
  inspect(hs.contains(binder_id), content="true")
  inspect(hs.contains(usage1), content="true")
  inspect(hs.contains(usage2), content="true")
}

///|
test "compute_highlight_set for non-identifier returns empty set" {
  let scope_map : Map[@canopy_core.NodeId, ScopeAnnotation] = {}
  let unknown_id = @canopy_core.NodeId::from_int(99)
  let hs = compute_highlight_set(unknown_id, scope_map)
  inspect(hs.length(), content="0")
}

///|
test "clicking f does not highlight apply var (no module/lambda scope confusion)" {
  let (editor, companion) = @lambda.new_lambda_editor("test")
  editor.set_text(
    "let id = \\x. { x }\nlet apply = \\f. \\x. { f x }\napply id 42",
  )
  let scope_map = build_scope_map(editor, companion)
  let proj_root = editor.get_proj_node().unwrap()
  let f_var_id = find_var_node_id(proj_root, "f")
  let apply_var_id = find_var_node_id(proj_root, "apply")
  // f should resolve to a binder (λf)
  let f_ann = scope_map.get(f_var_id).unwrap()
  inspect(f_ann.binder_id is None, content="false")
  // apply should also resolve to a binder (module def)
  let apply_ann = scope_map.get(apply_var_id).unwrap()
  inspect(apply_ann.binder_id is None, content="false")
  // Highlight set for f should NOT contain apply_var_id
  let hs_f = compute_highlight_set(f_var_id, scope_map)
  inspect(hs_f.contains(f_var_id), content="true")
  inspect(hs_f.contains(apply_var_id), content="false")
  // Highlight set for apply should contain apply but NOT f
  let hs_apply = compute_highlight_set(apply_var_id, scope_map)
  inspect(hs_apply.contains(apply_var_id), content="true")
  inspect(hs_apply.contains(f_var_id), content="false")
}

///|
test "nested block: inner x does not highlight outer x" {
  let (editor, companion) = @lambda.new_lambda_editor("test")
  editor.set_text("let x = 0\nlet y = { let x = 1\n  x }\nx")
  let scope_map = build_scope_map(editor, companion)
  let proj_root = editor.get_proj_node().unwrap()
  // There are two Var("x") nodes — inner (inside block) and outer (body)
  let x_vars = find_all_var_node_ids(proj_root, "x")
  // Should have at least 2 Var("x") usages
  inspect(x_vars.length() >= 2, content="true")
  // Each x should resolve to a different binder
  let x0_ann = scope_map.get(x_vars[0])
  let x1_ann = scope_map.get(x_vars[1])
  inspect(x0_ann is None, content="false")
  inspect(x1_ann is None, content="false")
  // Their binder_ids should be different (inner x → inner def, outer x → outer def)
  let bid0 = x0_ann.unwrap().binder_id.unwrap()
  let bid1 = x1_ann.unwrap().binder_id.unwrap()
  inspect(bid0 == bid1, content="false")
  // Clicking one x should NOT highlight the other
  let hs0 = compute_highlight_set(x_vars[0], scope_map)
  inspect(hs0.contains(x_vars[1]), content="false")
  let hs1 = compute_highlight_set(x_vars[1], scope_map)
  inspect(hs1.contains(x_vars[0]), content="false")
}

///|
test "nested block: inner module can reference enclosing block binder" {
  let (editor, companion) = @lambda.new_lambda_editor("test")
  editor.set_text("let x = 0\nlet y = { let x = 1\n  { let z = x\n    z } }\nx")
  let scope_map = build_scope_map(editor, companion)
  let proj_root = editor.get_proj_node().unwrap()
  let x_vars = find_all_var_node_ids(proj_root, "x")
  inspect(x_vars.length() >= 2, content="true")
  let inner_x_ann = scope_map.get(x_vars[0]).unwrap()
  let outer_x_ann = scope_map.get(x_vars[x_vars.length() - 1]).unwrap()
  inspect(inner_x_ann.binder_id == outer_x_ann.binder_id, content="false")
  let hs_inner = compute_highlight_set(x_vars[0], scope_map)
  inspect(hs_inner.contains(x_vars[x_vars.length() - 1]), content="false")
  let hs_outer = compute_highlight_set(x_vars[x_vars.length() - 1], scope_map)
  inspect(hs_outer.contains(x_vars[0]), content="false")
}

///|
test "scope_map keys module references by canonical @scope declaration" {
  let (editor, companion) = @lambda.new_lambda_editor("test")
  editor.set_text("let x = 0\nlet f = \\x. { x }\nx")
  let scope_map = build_scope_map(editor, companion)
  let proj_root = editor.get_proj_node().unwrap()
  let x_vars = find_all_var_node_ids(proj_root, "x")
  let inner_x_id = x_vars[0]
  let module_x_id = x_vars[x_vars.length() - 1]
  let graph = @scope.build(
    companion.get_flat_proj().unwrap(),
    editor.get_registry(),
    editor.get_source_map(),
  )
  let module_decl = @scope.declaration(graph, module_x_id).unwrap()
  let inner_decl = @scope.declaration(graph, inner_x_id).unwrap()
  inspect(module_decl.id == inner_decl.id, content="false")
  let is_module_decl = match module_decl.kind {
    @scope.DeclKind::ModuleDef(def_index=_) => true
    _ => false
  }
  inspect(is_module_decl, content="true")
  let module_binder_key = scope_binder_ui_key(graph, module_decl)
  let ann = scope_map.get(module_x_id).unwrap()
  inspect(ann.binder_id == Some(module_binder_key), content="true")
  let binder_ann = scope_map.get(module_binder_key).unwrap()
  inspect(
    binder_ann.usage_ids == @scope.references(graph, module_decl.id),
    content="true",
  )
  let hs_inner = compute_highlight_set(inner_x_id, scope_map)
  inspect(hs_inner.contains(module_x_id), content="false")
}

///|
fn find_var_node_id(
  node : @canopy_core.ProjNode[@ast.Term],
  name : String,
) -> @canopy_core.NodeId {
  match node.kind {
    Var(n) => if n == name { return node.id() }
    _ => ()
  }
  for child in node.children {
    let result = find_var_node_id(child, name)
    if result != @canopy_core.NodeId::from_int(-1) {
      return result
    }
  }
  @canopy_core.NodeId::from_int(-1)
}

///|
fn find_all_var_node_ids(
  node : @canopy_core.ProjNode[@ast.Term],
  name : String,
) -> Array[@canopy_core.NodeId] {
  let results : Array[@canopy_core.NodeId] = []
  collect_var_ids(node, name, results)
  results
}

///|
fn collect_var_ids(
  node : @canopy_core.ProjNode[@ast.Term],
  name : String,
  results : Array[@canopy_core.NodeId],
) -> Unit {
  match node.kind {
    Var(n) => if n == name { results.push(node.id()) }
    _ => ()
  }
  for child in node.children {
    collect_var_ids(child, name, results)
  }
}
