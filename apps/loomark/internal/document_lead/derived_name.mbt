///|
let name_source_id : @loom.SourceId = @loom.SourceId(
  "loomark-source-repository-name",
)

///|
priv struct NameDerivation {
  name : String
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
fn readable_name(node : @markdown.MarkdownIR, source : String) -> String {
  readable_text(node, Some(source))
  .map(text => first_readable_line(text).unwrap_or(""))
  .unwrap_or("")
}

///|
fn first_name_candidate(
  document : @markdown.MarkdownIR,
  source : String,
) -> (@markdown.MarkdownIR, String)? {
  guard document.view() is @markdown.Document else { return None }
  for child in document.children() {
    let name = readable_name(child, source)
    if !name.is_empty() {
      return Some((child, name))
    }
  }
  None
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
fn derive_name_with_certificate(source : String) -> NameDerivation {
  let (cst, diagnostics) = @markdown.parse_cst(name_source_id, source) catch {
    _ => return { name: "", reusable_prefix_end: None }
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  match first_name_candidate(document, source) {
    None => { name: "", reusable_prefix_end: None }
    Some((candidate, name)) =>
      {
        name,
        reusable_prefix_end: certify_reusable_name_prefix(
          source, root, diagnostics, candidate,
        ),
      }
  }
}

///|
pub fn derive_name(source : String) -> String {
  derive_name_with_certificate(source).name
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
fn certified_name_prefix_end(source : String, expected_name : String) -> Int? {
  guard first_line_end(source) is Some(end) else { return None }
  let prefix = source.view(end_offset=end).to_owned()
  let derivation = derive_name_with_certificate(prefix)
  guard derivation.name == expected_name &&
    derivation.reusable_prefix_end == Some(end) else {
    return None
  }
  Some(end)
}

///|
pub fn derived_name_survives_edit(
  previous_source : String,
  source : String,
  expected_name : String,
) -> Bool {
  guard certified_name_prefix_end(previous_source, expected_name) is Some(end) else {
    return false
  }
  end <= source.length() &&
  previous_source.view(end_offset=end).equal(source.view(end_offset=end))
}
