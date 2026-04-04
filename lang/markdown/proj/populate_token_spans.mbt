///| Extract token spans from the Markdown CST into the SourceMap.
///
/// Uses `find_token(raw_kind)` because `children()` returns only child nodes,
/// not tokens. `find_token` searches for the first token of the given kind
/// within the node's subtree.

///|
pub fn populate_token_spans(
  source_map : @core.SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : @core.ProjNode[@markdown.Block],
) -> Unit {
  populate_block(source_map, syntax_root, proj_root)
}

///|
fn populate_block(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : @core.ProjNode[@markdown.Block],
) -> Unit {
  match proj_node.kind {
    Document(_) => {
      let syntax_children = collect_block_children(syntax_node)
      let len = proj_node.children.length().min(syntax_children.length())
      for i in 0..<len {
        populate_block(source_map, syntax_children[i], proj_node.children[i])
      }
    }
    Heading(_, _) => {
      match
        syntax_node.find_token(
          @markdown.SyntaxKind::HeadingMarkerToken.to_raw(),
        ) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "marker",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match syntax_node.find_token(@markdown.SyntaxKind::TextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "text",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    }
    Paragraph(_) | ListItem(_) =>
      match syntax_node.find_token(@markdown.SyntaxKind::TextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "text",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    UnorderedList(_) => {
      let syntax_children = collect_syntax_children(
        syntax_node,
        @markdown.SyntaxKind::ListItemNode,
      )
      let len = proj_node.children.length().min(syntax_children.length())
      for i in 0..<len {
        populate_block(source_map, syntax_children[i], proj_node.children[i])
      }
    }
    CodeBlock(_, _) => {
      match
        syntax_node.find_token(
          @markdown.SyntaxKind::CodeFenceOpenToken.to_raw(),
        ) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "fence_open",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match
        syntax_node.find_token(@markdown.SyntaxKind::CodeTextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "code",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match
        syntax_node.find_token(
          @markdown.SyntaxKind::CodeFenceCloseToken.to_raw(),
        ) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "fence_close",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    }
    Error(_) => ()
  }
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
