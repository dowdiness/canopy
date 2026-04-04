///| Extract token spans from the Markdown CST into the SourceMap.

///|
pub fn populate_token_spans(
  source_map : @core.SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : @core.ProjNode[@markdown.Block],
) -> Unit {
  populate_block(source_map, syntax_root, proj_root)
}

///|
/// Set a token span from a single specific token.
fn set_token_span(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_id : @core.NodeId,
  role : String,
  kind : @markdown.SyntaxKind,
) -> Unit {
  match syntax_node.find_token(kind.to_raw()) {
    Some(tok) =>
      source_map.set_token_span(
        proj_id,
        role,
        @loomcore.Range::new(tok.start(), tok.end()),
      )
    None => ()
  }
}

///|
/// Set a "text" span covering all inline content after a structural prefix.
/// For headings: content starts after HeadingMarkerToken, ends at node end.
/// For paragraphs/list items: content starts after ListMarkerToken (if any),
/// ends at node end. This captures all inline tokens (text, bold, italic, etc.)
/// as a single contiguous span.
fn set_content_span(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_id : @core.NodeId,
  role : String,
  prefix_kind : @markdown.SyntaxKind?,
) -> Unit {
  // Content starts after the prefix token (if any), otherwise at node start
  let content_start = match prefix_kind {
    Some(kind) =>
      match syntax_node.find_token(kind.to_raw()) {
        Some(tok) => tok.end() // content starts right after the prefix token
        None => syntax_node.start()
      }
    None => syntax_node.start()
  }
  // Content ends at node end, trimmed of trailing newlines
  let mut content_end = syntax_node.end()
  // Don't include trailing NewlineToken — check if the node has one
  match syntax_node.find_token(@markdown.SyntaxKind::NewlineToken.to_raw()) {
    Some(tok) => if tok.end() == content_end { content_end = tok.start() }
    None => ()
  }
  if content_start < content_end {
    source_map.set_token_span(
      proj_id,
      role,
      @loomcore.Range::new(content_start, content_end),
    )
  }
}

///|
fn populate_block(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : @core.ProjNode[@markdown.Block],
) -> Unit {
  let id = proj_node.id()
  match proj_node.kind {
    Document(_) => {
      let syntax_children = collect_block_children(syntax_node)
      let len = proj_node.children.length().min(syntax_children.length())
      for i in 0..<len {
        populate_block(source_map, syntax_children[i], proj_node.children[i])
      }
    }
    Heading(_, _) => {
      set_token_span(source_map, syntax_node, id, "marker", HeadingMarkerToken)
      // Full inline content after the heading marker
      set_content_span(
        source_map,
        syntax_node,
        id,
        "text",
        Some(HeadingMarkerToken),
      )
    }
    Paragraph(_) =>
      // Full inline content (no prefix to skip)
      set_content_span(source_map, syntax_node, id, "text", None)
    ListItem(_) =>
      // Full inline content after the list marker
      set_content_span(
        source_map,
        syntax_node,
        id,
        "text",
        Some(ListMarkerToken),
      )
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
      set_token_span(
        source_map,
        syntax_node,
        id,
        "fence_open",
        CodeFenceOpenToken,
      )
      // Full code content between fences
      set_content_span(
        source_map,
        syntax_node,
        id,
        "code",
        Some(CodeFenceOpenToken),
      )
      set_token_span(
        source_map,
        syntax_node,
        id,
        "fence_close",
        CodeFenceCloseToken,
      )
    }
    Error(_) => ()
  }
}
