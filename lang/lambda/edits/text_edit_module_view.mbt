///|
/// Edit-local view of the root module shape, derived from the current
/// `ProjNode` registry. It replaces `ModuleProjection` as edit context: edit
/// handlers only need the structural `LetDef` children, their source ranges,
/// and the current body node.
priv struct EditModuleBinding {
  name : String
  init : ProjNode[@ast.Term]
  start : Int
  binding_id : NodeId
}

///|
priv struct EditModuleView {
  defs : Array[EditModuleBinding]
  final_expr : ProjNode[@ast.Term]?
}

///|
fn edit_root_node(
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> ProjNode[@ast.Term]? {
  let parents : Map[NodeId, NodeId] = {}
  for _id, node in registry {
    for child in node.children {
      parents[child.id()] = node.id()
    }
  }
  registry.values().find_first(fn(node) { parents.get(node.id()) is None })
}

///|
fn edit_binding_from_child(
  name : String,
  child : ProjNode[@ast.Term],
) -> EditModuleBinding {
  match child.kind {
    @ast.Term::LetDef(_, _) if child.children.length() > 0 =>
      {
        name,
        init: child.children[0],
        start: child.start,
        binding_id: child.id(),
      }
    _ => { name, init: child, start: child.start, binding_id: child.id() }
  }
}

///|
fn edit_binding_by_id(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> Result[EditModuleBinding, String] {
  match ctx.registry.get(binding_node_id) {
    Some(node) =>
      match node.kind {
        @ast.Term::LetDef(name, _) => Ok(edit_binding_from_child(name, node))
        _ => Err("Binding not found: " + binding_node_id.to_string())
      }
    None => {
      let module_view = edit_module_view(ctx)
      match
        module_view.defs
        .iter()
        .find_first(fn(def) { def.binding_id == binding_node_id }) {
        Some(def) => Ok(def)
        None => Err("Binding not found: " + binding_node_id.to_string())
      }
    }
  }
}

///|
fn edit_binding_for_decl(
  ctx : EditContext[@ast.Term],
  decl : @scope.Decl,
) -> Result[EditModuleBinding, String] {
  match decl.kind {
    @scope.DeclKind::ModuleDef(_) => edit_binding_by_id(ctx, decl.node_id)
    @scope.DeclKind::LamParam(_) => Err("Expected module binding")
  }
}

///|
fn EditModuleView::from_root(root : ProjNode[@ast.Term]) -> EditModuleView {
  match root.kind {
    @ast.Term::Module(defs, _) => {
      let bindings : Array[EditModuleBinding] = []
      let child_count = root.children.length()
      for i, def in defs {
        if i + 1 < child_count {
          bindings.push(edit_binding_from_child(def.0, root.children[i]))
        }
      }
      let final_expr = if defs.length() < child_count {
        let body = root.children[defs.length()]
        match body.kind {
          @ast.Term::Unit => None
          _ => Some(body)
        }
      } else {
        None
      }
      { defs: bindings, final_expr }
    }
    @ast.Term::Unit => { defs: [], final_expr: None }
    _ => { defs: [], final_expr: Some(root) }
  }
}

///|
fn edit_module_view(ctx : EditContext[@ast.Term]) -> EditModuleView {
  match edit_root_node(ctx.registry) {
    Some(root) => EditModuleView::from_root(root)
    None => { defs: [], final_expr: None }
  }
}
