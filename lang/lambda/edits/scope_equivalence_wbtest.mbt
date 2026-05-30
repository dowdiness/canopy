///|
/// Normalize a scope-graph Decl to (tag, node_id, def_index); def_index = -1
/// for lambda params.
fn norm_decl(decl : @scope.Decl) -> (String, NodeId, Int) {
  match decl.kind {
    DeclKind::LamParam(lam_id~) => ("lam", lam_id, -1)
    DeclKind::ModuleDef(def_index~) => ("module", decl.node_id, def_index)
  }
}

///|
/// Normalize an edits BindingSite to the same shape.
fn norm_binder(b : BindingSite) -> (String, NodeId, Int) {
  match b {
    LamBinder(lam_id~) => ("lam", lam_id, -1)
    ModuleBinder(binding_node_id~, def_index~) =>
      ("module", binding_node_id, def_index)
  }
}

///|
/// One equivalence check: declaration() must agree with resolve_binder on the
/// chosen Var node. Returns true if both sides normalize to the same value
/// (including both-None).
fn agree(
  text : String,
  locate : (@core.ProjNode[@ast.Term]) -> NodeId,
) -> Bool raise {
  let (proj, _errs) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let sm = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, sm)
  let var_id = locate(proj)
  let new_site = match @scope.declaration(g, var_id) {
    Some(d) => Some(norm_decl(d))
    None => None
  }
  let old_site = match
    resolve_binder(var_id, var_name_of(proj, var_id), fp, registry, sm) {
    Some(b) => Some(norm_binder(b))
    None => None
  }
  new_site == old_site
}

///|
/// Look up the Var name at a NodeId (resolve_binder needs the name string).
fn var_name_of(root : @core.ProjNode[@ast.Term], id : NodeId) -> String {
  let mut out = ""
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if n.id() == id {
      match n.kind {
        @ast.Term::Var(x) => out = x
        @ast.Term::Unbound(x) => out = x
        _ => ()
      }
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  out
}

///|
/// Find first Var named `name` (helper for locators).
fn find_var(root : @core.ProjNode[@ast.Term], name : String) -> NodeId {
  let mut found : NodeId? = None
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if found is Some(_) {
      return
    }
    if n.kind is @ast.Term::Var(x) && x == name {
      found = Some(n.id())
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  found.unwrap()
}

///|
test "equivalence: declaration() matches resolve_binder across all binding rules" {
  // (description, source, locator)
  inspect(agree("λx. x", root => root.children[0].id()), content="true") // lam param
  inspect(agree("let x = 0\nx", root => find_var(root, "x")), content="true") // module body
  inspect(agree("let x = x\nx", root => find_var(root, "x")), content="true") // self-ref (first x is init → unbound)
  inspect(
    agree("let x = 1\nlet x = 2\nx", root => find_var(root, "x")),
    content="true",
  ) // shadowing / latest
  inspect(
    agree("let a = b\nlet b = 1\na", root => find_var(root, "b")),
    content="true",
  ) // earlier can't see later (free)
  inspect(agree("λx. λx. x", root => find_var(root, "x")), content="true") // nested lam shadow
  inspect(
    agree("let x = 0\nλx. x", root => find_var(root, "x")),
    content="true",
  ) // lam param shadows same-name module def
  inspect(
    agree("let x = 1\nlet x = x\nx", root => find_var(root, "x")),
    content="true",
  ) // later def init resolves to earlier same-name def (not itself)
}
