// Regression test for the legacy init-only ModuleProjection compat shape.
//
// `ModuleProjection::from_proj_node` (lang/lambda/proj/module_projection.mbt)
// accepts two def-child shapes: the production LetDef row (`LetDef(_, _)` whose
// `children[0]` is the init) AND a legacy fallback where the def child IS the
// init node directly (no LetDef wrapper), recorded with `def.3 = init_child.id()`.
// The scope builder then sets that decl's `node_id` to the init node, so
// `def_view_from_decl` sees an init node — not a LetDef — at `decl.node_id`.
//
// The helper must mirror from_proj_node's discriminator (key on the `LetDef`
// KIND, not mere child presence): a compound init like `App(f, x)` HAS children,
// so a child-presence fallback would mis-read its first child `f` as the init.

///|
test "def_view_from_decl: legacy init-only compound def keeps the whole init, not its first child" {
  // Legacy shape: the Module's def child is the App init directly (no LetDef
  // row). from_proj_node's `_ =>` arm records `decl.node_id = app_init.id()`.
  let f = @core.ProjNode::new(@ast.Term::Var("f"), 8, 9, 10, [])
  let x = @core.ProjNode::new(@ast.Term::Var("x"), 10, 11, 11, [])
  let app_init = @core.ProjNode::new(
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x")),
    8,
    11,
    12,
    [f, x],
  )
  let body = @core.ProjNode::new(@ast.Term::Var("g"), 12, 13, 13, [])
  let root = @core.ProjNode::new(
    @ast.Term::Module(
      [("g", @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x")))],
      @ast.Term::Var("g"),
    ),
    0,
    13,
    1,
    [app_init, body],
  )
  let source_map = SourceMap::from_ast(root)
  let registry = text_edit_test_registry(root)
  let fp = ModuleProjection::from_proj_node(root)
  let g = @scope.build(fp, registry, source_map)
  guard decl_for_binding_node(g, app_init.id()) is Some(decl) else {
    fail(
      "expected a ModuleDef decl whose node is the legacy init-only def child",
    )
  }
  match def_view_from_decl(registry, source_map, decl) {
    Ok((name, init, _start, letdef_id)) => {
      inspect(name, content="g")
      // The init must be the App node ITSELF (id 12), never its first child
      // `f` (id 10) — the bug current HEAD exhibits (wrong output, not Err).
      inspect(init.id() == app_init.id(), content="true")
      inspect(init.kind is @ast.Term::App(_, _), content="true")
      inspect(letdef_id == app_init.id(), content="true")
    }
    Err(e) => fail("expected def-view for legacy init-only def, got Err: " + e)
  }
}
