///| CST → ProjNode[@markdown.Block] projection for Markdown.
///
/// Uses CstFold to get fully-populated Block values (with inline content,
/// heading levels, code text). The ProjNode tree structure mirrors the
/// CST block structure; Block payloads carry the semantic content.

///|
/// Convenience: parse source and project in one call (for tests and REPL).
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@markdown.Block], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @markdown.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  // CstFold produces a fully-populated Block with inline content
  let fold = @loomcore.CstFold::new(@markdown.markdown_fold_node)
  let block = fold.fold(node)
  build_proj_tree(node, block, counter)
}

///|
fn build_proj_tree(
  syntax_node : @seam.SyntaxNode,
  block : @markdown.Block,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  match block {
    Document(_) =>
      build_container(
        syntax_node,
        block,
        collect_block_children(syntax_node),
        counter,
      )
    UnorderedList(_) =>
      build_container(
        syntax_node,
        block,
        collect_syntax_children(syntax_node, @markdown.SyntaxKind::ListItemNode),
        counter,
      )
    _ =>
      @core.ProjNode::new(
        block,
        syntax_node.start(),
        syntax_node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
}

///|
fn build_container(
  syntax_node : @seam.SyntaxNode,
  block : @markdown.Block,
  syntax_children : Array[@seam.SyntaxNode],
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let block_children = block.children()
  let len = syntax_children.length().min(block_children.length())
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for i in 0..<len {
    children.push(
      build_proj_tree(syntax_children[i], block_children[i], counter),
    )
  }
  @core.ProjNode::new(
    block,
    syntax_node.start(),
    syntax_node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn collect_block_children(node : @seam.SyntaxNode) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if is_block_node(@markdown.SyntaxKind::from_raw(child.kind())) {
      result.push(child)
    }
  }
  result
}

///|
fn collect_syntax_children(
  node : @seam.SyntaxNode,
  kind : @markdown.SyntaxKind,
) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if @markdown.SyntaxKind::from_raw(child.kind()) == kind {
      result.push(child)
    }
  }
  result
}

///|
fn is_block_node(kind : @markdown.SyntaxKind) -> Bool {
  match kind {
    HeadingNode
    | ParagraphNode
    | UnorderedListNode
    | ListItemNode
    | CodeBlockNode
    | ErrorNode => true
    _ => false
  }
}
