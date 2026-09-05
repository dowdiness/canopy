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
fn first_readable_line(text : String) -> String? {
  text
  .replace_all(old="\r\n", new="\n")
  .replace_all(old="\r", new="\n")
  .split("\n")
  .map(line => line.trim())
  .find_first(line => !line.is_empty())
  .map(line => line.to_owned())
}

///|
fn append_readable_children(
  node : @markdown.MarkdownIR,
  builder : StringBuilder,
  separate : Bool,
) -> Bool {
  let mut first = true
  for child in node.children() {
    if separate && !first {
      builder.write_char('\n')
    }
    guard append_readable_text(child, builder) else { return false }
    first = false
  }
  true
}

///|
fn append_readable_text(
  node : @markdown.MarkdownIR,
  builder : StringBuilder,
) -> Bool {
  match node.view() {
    @markdown.Text(value~)
    | @markdown.InlineCode(value~)
    | @markdown.Autolink(display=value, ..)
    | @markdown.CodeBlock(value~, ..) => builder.write_string(value)
    @markdown.SoftBreak | @markdown.HardBreak(..) => builder.write_char('\n')
    @markdown.Document
    | @markdown.BlockQuote
    | @markdown.UnorderedList(..)
    | @markdown.OrderedList(..)
    | @markdown.ListItem(..)
    | @markdown.OrderedListItem(..) => {
      guard append_readable_children(node, builder, true) else { return false }
    }
    @markdown.Heading(..)
    | @markdown.Paragraph
    | @markdown.Bold
    | @markdown.Italic
    | @markdown.Link(..)
    | @markdown.Image(..) => {
      guard append_readable_children(node, builder, false) else { return false }
    }
    @markdown.ThematicBreak
    | @markdown.HtmlBlock(..)
    | @markdown.InlineHtml(..) => ()
    @markdown.Raw(value~) | @markdown.Recovered(value~) =>
      builder.write_string(value)
    @markdown.Unsupported(..) => return false
  }
  true
}

///|
fn readable_name(node : @markdown.MarkdownIR) -> Result[String?, Unit] {
  let builder = StringBuilder()
  guard append_readable_text(node, builder) else { return Err(()) }
  Ok(first_readable_line(builder.to_string()))
}

///|
fn first_name_candidate(
  document : @markdown.MarkdownIR,
) -> Result[(@markdown.MarkdownIR, String)?, Unit] {
  guard document.view() is @markdown.Document else { return Err(()) }
  for child in document.children() {
    match readable_name(child) {
      Err(_) => return Err(())
      Ok(Some(name)) => return Ok(Some((child, name)))
      Ok(None) => ()
    }
  }
  Ok(None)
}

///|
fn certify_reusable_name_prefix(
  source : String,
  root : @seam.SyntaxNode,
  diagnostics : @loom.DiagnosticSet,
  candidate : @markdown.MarkdownIR,
) -> Int? {
  let origin = candidate.origin()
  guard diagnostics.is_empty() &&
    candidate.diagnostics().is_empty() &&
    root.first_child() is Some(first) &&
    first.start() == origin.start() &&
    first.end() == origin.end() &&
    !first.cst_node().has_any_error() else {
    return None
  }
  let start = origin.start()
  let end = origin.end()
  guard start == 0 && end > 0 && end <= source.length() else { return None }
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
  let (cst, diagnostics) = @markdown.parse_cst(name_source_id, source) catch {
    _ => return Err(())
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  match first_name_candidate(document) {
    Err(_) => Err(())
    Ok(None) => Ok({ name: None, reusable_prefix_end: None })
    Ok(Some((candidate, name))) =>
      Ok({
        name: Some(name),
        reusable_prefix_end: certify_reusable_name_prefix(
          source, root, diagnostics, candidate,
        ),
      })
  }
}

///|
pub fn derive_name(source : String) -> Result[String?, Unit] {
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
pub fn derived_name_survives_edit(
  previous_source : String,
  source : String,
  expected_name : String?,
) -> Bool {
  guard certified_name_prefix_end(previous_source, expected_name) is Some(end) else {
    return false
  }
  end <= source.length() &&
  previous_source.view(end_offset=end).equal(source.view(end_offset=end))
}
