///|
fn parse_fixture(
  text : String,
) -> (@core.ProjNode[@ast.Term], @core.SourceMap) raise {
  let (cst, _) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let root = @lambda_proj.to_proj_node(syntax, Ref(0))
  let source_map = @core.SourceMap::from_ast(root)
  @lambda_proj.populate_token_spans(source_map, syntax, root)
  (root, source_map)
}

///|
fn parse_flat_fixture(
  text : String,
) -> (@core.ProjNode[@ast.Term], @core.SourceMap, @lambda_proj.FlatProj) raise {
  let (cst, _) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  let flat_proj = @lambda_proj.to_flat_proj(syntax, counter)
  let root = flat_proj.to_proj_node(counter)
  let source_map = @core.SourceMap::from_ast(root)
  @lambda_proj.populate_token_spans(source_map, syntax, root)
  (root, source_map, flat_proj)
}

///|
fn has_annotation(
  projection : SemanticProjection,
  node_id : @core.NodeId,
  label : String,
) -> Bool {
  match projection.annotations.get(node_id) {
    Some(anns) => anns.iter().any(fn(ann) { ann.label == label })
    None => false
  }
}

///|
test "semantic projection annotates lambda binder and bound use" {
  let (root, source_map) = parse_fixture("λx. x")
  let projection = build_semantic_projection(root, source_map)
  assert_true(has_annotation(projection, root.id(), "λx"))
  assert_true(has_annotation(projection, root.children[0].id(), "bound x"))
  inspect(projection.diagnostics.length(), content="0")
  assert_true(
    projection.decorations
    .iter()
    .any(fn(d) { d.css_class == "semantic-binder" }),
  )
  assert_true(
    projection.decorations.iter().any(fn(d) { d.css_class == "semantic-bound" }),
  )
}

///|
test "semantic projection reports free variable" {
  let (root, source_map) = parse_fixture("λx. y")
  let projection = build_semantic_projection(root, source_map)
  let body = root.children[0]
  assert_true(has_annotation(projection, body.id(), "free y"))
  inspect(projection.diagnostics.length(), content="1")
  assert_true(
    projection.decorations.iter().any(fn(d) { d.css_class == "semantic-free" }),
  )
}

///|
test "semantic projection respects sequential module bindings" {
  let (root, source_map, flat_proj) = parse_flat_fixture(
    "let x = 1\nlet y = x\nx + y",
  )
  let projection = build_semantic_projection_with_flat_proj(
    root,
    source_map,
    Some(flat_proj),
  )
  assert_true(has_annotation(projection, flat_proj.defs[0].3, "let x"))
  assert_true(has_annotation(projection, flat_proj.defs[1].3, "let y"))
  assert_false(has_annotation(projection, root.id(), "let x"))
  assert_false(has_annotation(projection, root.id(), "let y"))
  inspect(projection.diagnostics.length(), content="0")
}
