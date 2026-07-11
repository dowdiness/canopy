///| Extract token spans from the JSX CST into the SourceMap.
///
/// Role conventions: "tag_name", "attr_name"/"attr_value" (index-suffixed,
/// see populate_attrs), "text", "expr_raw" (opaque `{...}` content, no
/// braces), "open_bracket"/"close_bracket" for element/fragment
/// delimiters. Not consumed by anything in Phase 2 (read-only) — populated
/// now for Phase 3's eventual editor, per the plan.

///|
pub fn populate_token_spans(
  source_map : @core.SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : @core.ProjNode[@jsx.JsxNode],
) -> Unit {
  populate_node(source_map, syntax_root, proj_root)
}

///|
fn populate_node(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : @core.ProjNode[@jsx.JsxNode],
) -> Unit {
  let id = proj_node.id()
  match proj_node.kind {
    Root(..) =>
      populate_children(source_map, syntax_node.children(), proj_node.children)
    Element(..) => {
      populate_element_delimiters(source_map, syntax_node, id)
      populate_attrs(source_map, syntax_node, id)
      populate_children(
        source_map,
        element_content_children(syntax_node),
        proj_node.children,
      )
    }
    Fragment(..) => {
      populate_fragment_delimiters(source_map, syntax_node, id)
      populate_children(source_map, syntax_node.children(), proj_node.children)
    }
    Text(_) =>
      source_map.set_token_span(
        id,
        "text",
        @loomcore.Range::new(syntax_node.start(), syntax_node.end()),
      )
    ExprSpan(..) => populate_expr_raw(source_map, syntax_node, id, "expr_raw")
    Error(_) => ()
  }
}

///|
fn populate_children(
  source_map : @core.SourceMap,
  syntax_children : Array[@seam.SyntaxNode],
  proj_children : Array[@core.ProjNode[@jsx.JsxNode]],
) -> Unit {
  let len = syntax_children.length().min(proj_children.length())
  for i in 0..<len {
    populate_node(source_map, syntax_children[i], proj_children[i])
  }
}

///|
/// "open_bracket" = the open tag's leading `<`; "close_bracket" = the
/// self-close `/>` if present, else the close tag's trailing `>` if
/// present (an unclosed element per Design B case 2 has neither).
fn populate_element_delimiters(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  id : @core.NodeId,
) -> Unit {
  set_optional_token_span(
    source_map,
    syntax_node,
    id,
    "open_bracket",
    @syntax.SyntaxKind::OpenTagStartToken,
  )
  // `find_token`'s first-match default is exactly what "tag_name" needs:
  // the open tag's TagNameToken is always emitted before any close tag's
  // (emit_close_tag in cst_parser.mbt also emits one for `</name>`), so
  // the first direct match is always the opening tag's own name.
  set_optional_token_span(
    source_map,
    syntax_node,
    id,
    "tag_name",
    @syntax.SyntaxKind::TagNameToken,
  )
  match
    syntax_node.direct_token_of_kind(
      @syntax.SyntaxKind::SelfCloseEndToken.to_raw(),
    ) {
    Some(tok) =>
      source_map.set_token_span(
        id,
        "close_bracket",
        @loomcore.Range::new(tok.start(), tok.end()),
      )
    None =>
      // A direct TagEndToken always includes the open tag's own `>`
      // (parse_content is only reached after emitting it) — a real close
      // tag contributes a second one via emit_close_tag. One match means
      // the element is unclosed (Design B case 2): no close_bracket.
      match
        syntax_node.tokens_of_kind(@syntax.SyntaxKind::TagEndToken.to_raw()) {
        [_, ..] as toks if toks.length() >= 2 => {
          let last = toks[toks.length() - 1]
          source_map.set_token_span(
            id,
            "close_bracket",
            @loomcore.Range::new(last.start(), last.end()),
          )
        }
        _ => ()
      }
  }
}

///|
fn populate_fragment_delimiters(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  id : @core.NodeId,
) -> Unit {
  set_optional_token_span(
    source_map,
    syntax_node,
    id,
    "open_bracket",
    @syntax.SyntaxKind::FragmentOpenToken,
  )
  set_optional_token_span(
    source_map,
    syntax_node,
    id,
    "close_bracket",
    @syntax.SyntaxKind::FragmentCloseToken,
  )
}

///|
fn set_optional_token_span(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  id : @core.NodeId,
  role : String,
  kind : @syntax.SyntaxKind,
) -> Unit {
  match syntax_node.find_token(kind.to_raw()) {
    Some(tok) =>
      source_map.set_token_span(
        id,
        role,
        @loomcore.Range::new(tok.start(), tok.end()),
      )
    None => ()
  }
}

///|
/// Attributes aren't separate ProjNodes (TreeNode::children excludes
/// them), so their spans attach to the owning Element's id. A plain
/// "attr_name"/"attr_value" role would collide across multiple
/// attributes on one element (SourceMap holds one Range per (id, role));
/// index-suffix each role instead.
///
/// Caveat: the index is positional within the element's current attribute
/// list, not a stable per-attribute identity — inserting, removing, or
/// reordering an attribute shifts every later index's role key even
/// though the owning Element's NodeId doesn't change. Fine for Phase 2
/// (read-only), but a future editor consuming these roles must not treat
/// "attr_name:N" as a durable handle across edits.
fn populate_attrs(
  source_map : @core.SourceMap,
  element_syntax_node : @seam.SyntaxNode,
  id : @core.NodeId,
) -> Unit {
  let attr_kind = @syntax.SyntaxKind::AttrNode.to_raw()
  let attrs = element_syntax_node.direct_children_of_kind(attr_kind)
  for i, attr_node in attrs.iter2() {
    set_optional_token_span(
      source_map,
      attr_node,
      id,
      "attr_name:" + i.to_string(),
      @syntax.SyntaxKind::AttrNameToken,
    )
    let value_role = "attr_value:" + i.to_string()
    match
      attr_node.direct_token_of_kind(
        @syntax.SyntaxKind::AttrStringLitToken.to_raw(),
      ) {
      Some(tok) =>
        source_map.set_token_span(
          id,
          value_role,
          @loomcore.Range::new(tok.start(), tok.end()),
        )
      None =>
        match
          attr_node.direct_token_of_kind(
            @syntax.SyntaxKind::AttrStringLitUnterminatedToken.to_raw(),
          ) {
          Some(tok) =>
            source_map.set_token_span(
              id,
              value_role,
              @loomcore.Range::new(tok.start(), tok.end()),
            )
          None =>
            match
              attr_node.direct_child_of_kind(
                @syntax.SyntaxKind::ExprSpanNode.to_raw(),
              ) {
              Some(expr_node) =>
                source_map.set_token_span(
                  id,
                  value_role,
                  @loomcore.Range::new(expr_node.start(), expr_node.end()),
                )
              None => ()
            }
        }
    }
  }
}

///|
/// Content span between the braces, excluding them — the raw
/// unparsed expression text (Design B case 4's ExprRawText/
/// ExprStringUnterminated chunks, concatenated by span rather than text).
fn populate_expr_raw(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  id : @core.NodeId,
  role : String,
) -> Unit {
  let content_start = match
    syntax_node.find_token(@syntax.SyntaxKind::BraceOpenToken.to_raw()) {
    Some(tok) => tok.end()
    None => syntax_node.start()
  }
  let content_end = match
    syntax_node.find_token(@syntax.SyntaxKind::BraceCloseToken.to_raw()) {
    Some(tok) => tok.start()
    None => syntax_node.end()
  }
  if content_start <= content_end {
    source_map.set_token_span(
      id,
      role,
      @loomcore.Range::new(content_start, content_end),
    )
  }
}
