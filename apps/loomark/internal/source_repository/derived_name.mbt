///|
let name_source_id : @loom.SourceId = @loom.SourceId(
  "loomark-source-repository-name",
)

///|
priv struct NameDerivation {
  name : String?
  reusable_prefix_end : Int?
}

///|
fn reusable_node_prefix_end(source : String, node : @seam.SyntaxNode) -> Int? {
  let end = node.end()
  guard node.start() == 0 && end > 0 && end <= source.length() else {
    return None
  }
  let terminator = source.view(start_offset=end - 1, end_offset=end)
  if terminator.equal_to_string("\n") || terminator.equal_to_string("\r") {
    Some(end)
  } else {
    None
  }
}

///|
fn derive_name_with_certificate(
  source : String,
) -> Result[NameDerivation, Unit] {
  let (cst, _) = @markdown.parse_cst(name_source_id, source) catch {
    _ => return Err(())
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  match first_atx_h1(root) {
    None => Ok({ name: None, reusable_prefix_end: None })
    Some((node, inlines)) => {
      let builder = StringBuilder()
      guard append_inlines(inlines, builder) else { return Err(()) }
      let name = builder.to_string().trim().to_owned()
      if name == "" {
        Ok({ name: None, reusable_prefix_end: None })
      } else {
        Ok({
          name: Some(name),
          reusable_prefix_end: reusable_node_prefix_end(source, node),
        })
      }
    }
  }
}

///|
fn derive_name(source : String) -> Result[String?, Unit] {
  derive_name_with_certificate(source).map(derivation => derivation.name)
}

///|
fn first_line_end(source : String) -> Int? {
  let terminator_start = match (source.find("\n"), source.find("\r")) {
    (None, None) => return None
    (Some(lf), None) => lf
    (None, Some(cr)) => cr
    (Some(lf), Some(cr)) => lf.min(cr)
  }
  let after_cr = (terminator_start + 2).min(source.length())
  if source
    .view(start_offset=terminator_start, end_offset=after_cr)
    .equal_to_string("\r\n") {
    Some(terminator_start + 2)
  } else {
    Some(terminator_start + 1)
  }
}

///|
fn certified_name_prefix_end(source : String, expected_name : String?) -> Int? {
  guard first_line_end(source) is Some(end) else { return None }
  let prefix = source.view(end_offset=end).to_owned()
  guard derive_name_with_certificate(prefix) is Ok(derivation) &&
    derivation.name == expected_name &&
    derivation.reusable_prefix_end == Some(end) else {
    return None
  }
  Some(end)
}

///|
fn first_atx_h1(
  node : @seam.SyntaxNode,
) -> (@seam.SyntaxNode, Array[@markdown.Inline])? {
  let kind : @markdown.SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  if kind is HeadingNode &&
    node.has_direct_token_of_kind(
      @seam.ToRawKind::to_raw(@markdown.SyntaxKind::AtxHeadingMarkerToken),
    ) {
    let fold = @loom.CstFold::new(@markdown.markdown_fold_node)
    match fold.fold(node) {
      Heading(1, inlines) => return Some((node, inlines))
      _ => ()
    }
  }
  for child in node.children() {
    match first_atx_h1(child) {
      Some(result) => return Some(result)
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
