///|
/// Edit-local view of the root module shape, derived from the current
/// `ProjNode` registry. Edit handlers only need the structural `LetDef`
/// children, their source ranges, and the current body node.
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
  let parents : Map[NodeId, NodeId] = Map([])
  for _id, node in registry {
    for child in node.children {
      parents[child.id()] = node.id()
    }
  }
  registry.values().find_first(fn(node) { parents.get(node.id()) is None })
}

///|
fn edit_binding_from_let_def(
  name : String,
  let_def : ProjNode[@ast.Term],
) -> EditModuleBinding {
  {
    name,
    init: let_def.children[0],
    start: let_def.start,
    binding_id: let_def.id(),
  }
}

///|
fn edit_binding_by_id(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> EditModuleBinding raise EditError {
  guard ctx.registry.get(binding_node_id) is Some(node) else {
    raise BindingNotFound(action="Find edit binding", node_id=binding_node_id)
  }
  guard node.kind is @ast.Term::LetDef(name, _) && node.children.length() > 0 else {
    raise BindingNotFound(action="Find edit binding", node_id=binding_node_id)
  }
  edit_binding_from_let_def(name, node)
}

///|
fn edit_binding_for_decl(
  ctx : EditContext[@ast.Term],
  decl : @scope.Decl,
) -> EditModuleBinding raise EditError {
  match decl.kind {
    @scope.DeclKind::ModuleDef(_) => edit_binding_by_id(ctx, decl.node_id)
    @scope.DeclKind::LamParam(_) =>
      raise InvalidTarget(detail="Expected module binding")
  }
}

///|
fn EditModuleView::from_root(root : ProjNode[@ast.Term]) -> EditModuleView {
  match root.kind {
    @ast.Term::Module(defs, _) => {
      let bindings : Array[EditModuleBinding] = []
      let child_count = root.children.length()
      for i, def in defs {
        if i + 1 < child_count &&
          root.children[i].kind is @ast.Term::LetDef(_, _) &&
          root.children[i].children.length() > 0 {
          bindings.push(edit_binding_from_let_def(def.0, root.children[i]))
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
