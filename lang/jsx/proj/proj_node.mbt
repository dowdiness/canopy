///| CST → ProjNode[@jsx.JsxNode] projection for JSX.
///
/// Uses CstFold to get a fully-populated JsxNode (element tags, attrs,
/// text, opaque expression spans). The ProjNode tree mirrors the AST's
/// own container/leaf split (see loom/examples/jsx/proj_traits.mbt
/// TreeNode::children): Root/Fragment/Element are containers, Text/
/// ExprSpan/Error are leaves.

///|
/// Convenience: parse source and project in one call (for tests and REPL).
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@jsx.JsxNode], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @jsx.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref(0))
  (root, errors)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  // CstFold produces a fully-populated JsxNode (tags, attrs, text, expr
  // spans already folded in).
  let fold = @loomcore.CstFold::new(@jsx.jsx_grammar.fold_node)
  let ast = fold.fold(node)
  build_proj_tree(node, ast, counter)
}

///|
fn build_proj_tree(
  syntax_node : @seam.SyntaxNode,
  ast : @jsx.JsxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  match ast {
    Root(..) | Fragment(..) =>
      build_container(syntax_node, ast, syntax_node.children(), counter)
    Element(..) =>
      build_container(
        syntax_node,
        ast,
        element_content_children(syntax_node),
        counter,
      )
    Text(_) | ExprSpan(..) | Error(_) =>
      @core.ProjNode::leaf(ast, syntax_node, counter)
  }
}

///|
/// An Element's CST children interleave AttrNodes with its content
/// children (child elements/text/expr spans) — AttrNodes fold into the
/// AST's `attrs` field, not `children`, so they must be excluded here to
/// keep the parallel walk aligned with `ast.children()`.
fn element_content_children(node : @seam.SyntaxNode) -> Array[@seam.SyntaxNode] {
  let attr_kind = @syntax.SyntaxKind::AttrNode.to_raw()
  node.children().filter(c => c.kind() != attr_kind)
}

///|
/// Whitespace-only Text nodes (newlines, indentation between elements) are
/// skipped in the projection tree — they have no visual rendering.
fn is_whitespace_text(node : @jsx.JsxNode) -> Bool {
  match node {
    @jsx.JsxNode::Text(s) => s.trim().is_empty()
    _ => false
  }
}

///|
fn build_container(
  syntax_node : @seam.SyntaxNode,
  ast : @jsx.JsxNode,
  syntax_children : Array[@seam.SyntaxNode],
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  let ast_children = ast.children()
  let len = syntax_children.length().min(ast_children.length())
  let children : Array[@core.ProjNode[@jsx.JsxNode]] = []
  for i in 0..<len {
    let ast_child = ast_children[i]
    if is_whitespace_text(ast_child) { continue }
    children.push(build_proj_tree(syntax_children[i], ast_child, counter))
  }
  @core.ProjNode::branch(
    ast,
    syntax_node.start(),
    syntax_node.end(),
    children,
    counter,
  )
}

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the JSX
/// projection. Delegates to @core.build_projection_memos exactly per
/// ADDING_A_LANGUAGE.md Step 4 — no hand-rolled reconciliation.
pub fn build_jsx_projection_memos(
  parser : @loom.Parser[@jsx.JsxNode],
) -> (
  @incr.Derived[@core.ProjNode[@jsx.JsxNode]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@jsx.JsxNode]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="jsx",
  )
}
