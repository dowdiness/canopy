///| CST → ProjNode[@markdown.Block] projection for Markdown.

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
  match @markdown.SyntaxKind::from_raw(node.kind()) {
    DocumentNode => build_document(node, counter)
    HeadingNode => build_heading(node, counter)
    ParagraphNode => build_leaf(node, counter, @markdown.Block::Paragraph([]))
    UnorderedListNode => build_list(node, counter)
    ListItemNode => build_leaf(node, counter, @markdown.Block::ListItem([]))
    CodeBlockNode => build_code_block(node, counter)
    ErrorNode => {
      let err_text = match node.first_token() {
        Some(tok) => tok.text()
        None => ""
      }
      @core.ProjNode::new(
        @markdown.Block::Error(err_text),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
    _ =>
      @core.ProjNode::new(
        @markdown.Block::Paragraph([]),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
}

///|
fn build_document(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for child in node.children() {
    if is_block_node(@markdown.SyntaxKind::from_raw(child.kind())) {
      children.push(syntax_to_proj_node(child, counter))
    }
  }
  @core.ProjNode::new(
    @markdown.Block::Document([]),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn build_heading(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let level = match
    node.find_token(@markdown.SyntaxKind::HeadingMarkerToken.to_raw()) {
    Some(tok) => {
      let mut n = 0
      for c in tok.text() {
        if c == '#' {
          n = n + 1
        }
      }
      if n > 0 {
        n
      } else {
        1
      }
    }
    None => 1
  }
  @core.ProjNode::new(
    @markdown.Block::Heading(level, []),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
}

///|
fn build_leaf(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
  kind : @markdown.Block,
) -> @core.ProjNode[@markdown.Block] {
  @core.ProjNode::new(
    kind,
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
}

///|
fn build_list(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for child in node.children() {
    if @markdown.SyntaxKind::from_raw(child.kind()) == ListItemNode {
      children.push(syntax_to_proj_node(child, counter))
    }
  }
  @core.ProjNode::new(
    @markdown.Block::UnorderedList([]),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn build_code_block(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let info = match
    node.find_token(@markdown.SyntaxKind::CodeFenceOpenToken.to_raw()) {
    Some(tok) =>
      match tok.text().view() {
        [.. "```", .. rest] =>
          rest
          .trim_end(chars="\n".view())
          .trim_end(chars=" ".view())
          .to_string()
        _ => ""
      }
    None => ""
  }
  @core.ProjNode::new(
    @markdown.Block::CodeBlock(info, ""),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
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
