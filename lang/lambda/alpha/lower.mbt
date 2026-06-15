///|
pub fn lower_root(
  root : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
) -> AlphaTerm {
  let binders = source_binders(graph)
  lower_node(root, graph, binders)
}

///|
fn source_binders(graph : @scope.ScopeGraph) -> Map[@core.NodeId, Binder] {
  let binders : Map[@core.NodeId, Binder] = {}
  for i, decl in graph.decls {
    binders[decl.node_id] = {
      id: BinderId(i),
      hint: decl.name,
      origin: SourceDecl(node_id=decl.node_id, hint=decl.name),
    }
  }
  binders
}

///|
fn generated_binder(hint : String, salt : Int) -> Binder {
  { id: BinderId(-1 - salt), hint, origin: Generated(salt) }
}

///|
fn binder_for_node(
  binders : Map[@core.NodeId, Binder],
  node_id : @core.NodeId,
  hint : String,
) -> Binder {
  match binders.get(node_id) {
    Some(binder) => binder
    None => generated_binder(hint, 0)
  }
}

///|
fn lower_ref(
  node : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
  binders : Map[@core.NodeId, Binder],
  name : String,
) -> AlphaTerm {
  match @scope.declaration(graph, node.id()) {
    Some(decl) =>
      match binders.get(decl.node_id) {
        Some(binder) => Var(Bound(binder.id))
        None => Error("resolved reference without lowered binder: " + decl.name)
      }
    None => Var(Free({ name, origin: SourceVar }))
  }
}

///|
fn lower_child_or_error(
  node : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
  binders : Map[@core.NodeId, Binder],
  index : Int,
  label : String,
) -> AlphaTerm {
  match node.children.get(index) {
    Some(child) => lower_node(child, graph, binders)
    None => Error("missing " + label)
  }
}

///|
fn lower_let_def_child(
  node : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
  binders : Map[@core.NodeId, Binder],
  hint : String,
) -> (Binder, AlphaTerm) {
  let binder = binder_for_node(binders, node.id(), hint)
  let init = lower_child_or_error(
    node, graph, binders, 0, "let definition init",
  )
  (binder, init)
}

///|
fn lower_module(
  node : @core.ProjNode[@ast.Term],
  defs : Array[(String, @ast.Term)],
  graph : @scope.ScopeGraph,
  binders : Map[@core.NodeId, Binder],
) -> AlphaTerm {
  let lowered_defs : Array[(Binder, AlphaTerm)] = []
  for i, def in defs {
    match node.children.get(i) {
      Some(child) =>
        lowered_defs.push(lower_let_def_child(child, graph, binders, def.0))
      None =>
        lowered_defs.push(
          (generated_binder(def.0, i), Error("missing module definition child")),
        )
    }
  }
  let body = lower_child_or_error(
    node,
    graph,
    binders,
    defs.length(),
    "module body",
  )
  Module(lowered_defs, body)
}

///|
fn lower_node(
  node : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
  binders : Map[@core.NodeId, Binder],
) -> AlphaTerm {
  match node.kind {
    @ast.Term::Int(value) => Int(value)
    @ast.Term::Unit => Unit
    @ast.Term::Var(name) => lower_ref(node, graph, binders, name)
    @ast.Term::Unbound(name) => Var(Free({ name, origin: SourceUnbound }))
    @ast.Term::Lam(name, _) => {
      let binder = binder_for_node(binders, node.id(), name)
      Lam(binder, lower_child_or_error(node, graph, binders, 0, "lambda body"))
    }
    @ast.Term::App(_, _) =>
      App(
        lower_child_or_error(node, graph, binders, 0, "application function"),
        lower_child_or_error(node, graph, binders, 1, "application argument"),
      )
    @ast.Term::Bop(op, _, _) =>
      Bop(
        op,
        lower_child_or_error(node, graph, binders, 0, "binary lhs"),
        lower_child_or_error(node, graph, binders, 1, "binary rhs"),
      )
    @ast.Term::If(_, _, _) =>
      If(
        lower_child_or_error(node, graph, binders, 0, "if condition"),
        lower_child_or_error(node, graph, binders, 1, "if then branch"),
        lower_child_or_error(node, graph, binders, 2, "if else branch"),
      )
    @ast.Term::LetDef(name, _) => {
      let binder = binder_for_node(binders, node.id(), name)
      LetDef(
        binder,
        lower_child_or_error(node, graph, binders, 0, "let definition init"),
      )
    }
    @ast.Term::Module(defs, _) => lower_module(node, defs, graph, binders)
    @ast.Term::Error(message) => Error(message)
    @ast.Term::Hole(index) => Hole(index)
  }
}
