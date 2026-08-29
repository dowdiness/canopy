///|
let name_source_id : @loom.SourceId = @loom.SourceId(
  "loomark-source-repository-name",
)

///|
fn derive_name(source : String) -> Result[String?, Unit] {
  let (cst, _) = @markdown.parse_cst(name_source_id, source) catch {
    _ => return Err(())
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  match first_atx_h1(root) {
    None => Ok(None)
    Some(inlines) => {
      let builder = StringBuilder()
      guard append_inlines(inlines, builder) else { return Err(()) }
      let name = builder.to_string().trim().to_owned()
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(name))
      }
    }
  }
}

///|
fn first_atx_h1(node : @seam.SyntaxNode) -> Array[@markdown.Inline]? {
  let kind : @markdown.SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  if kind is HeadingNode &&
    node.has_direct_token_of_kind(
      @seam.ToRawKind::to_raw(@markdown.SyntaxKind::AtxHeadingMarkerToken),
    ) {
    let fold = @loom.CstFold::new(@markdown.markdown_fold_node)
    match fold.fold(node) {
      Heading(1, inlines) => return Some(inlines)
      _ => ()
    }
  }
  for child in node.children() {
    match first_atx_h1(child) {
      Some(inlines) => return Some(inlines)
      None => ()
    }
  }
  None
}

///|
fn append_inlines(
  inlines : Array[@markdown.Inline],
  builder : StringBuilder,
) -> Bool {
  for inline in inlines {
    match inline {
      Text(value) | InlineCode(value) => builder.write_string(value)
      Bold(children) | Italic(children) | Link(children, _) =>
        if !append_inlines(children, builder) {
          return false
        }
      Error(_) => return false
    }
  }
  true
}
