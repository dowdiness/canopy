///|
let name_source_id : @loom.SourceId = @loom.SourceId(
  "loomark-source-repository-name",
)

///|
pub struct DerivedName {
  priv text : String
  priv reusable_prefix : String?
}

///|
pub impl Eq for DerivedName with fn equal(self, other) -> Bool {
  self.text == other.text
}

///|
pub impl Debug for DerivedName with fn to_repr(self) {
  @debug.Repr::string(self.text)
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
  let prefix = source.view(end_offset=end).to_owned()
  guard !prefix.contains("[") else { return None }
  let terminator = source.view(start_offset=end - 1, end_offset=end)
  if terminator.equal_to_string("\n") || terminator.equal_to_string("\r") {
    Some(end)
  } else {
    None
  }
}

///|
fn derive_name_with_certificate(source : String) -> DerivedName {
  let (cst, diagnostics) = @markdown.parse_cst(name_source_id, source) catch {
    _ => return { text: "", reusable_prefix: None, }
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  match first_name_candidate(document, source) {
    None => { text: "", reusable_prefix: None, }
    Some((candidate, name)) =>
      {
        text: name,
        reusable_prefix: if name.is_empty() {
          None
        } else {
          certify_reusable_name_prefix(source, root, diagnostics, candidate).map(end => {
              source.view(end_offset=end).to_owned()
            },
          )
        },
      }
  }
}

///|
pub fn derive_name(source : String) -> DerivedName {
  derive_name_with_certificate(source)
}

///|
pub fn DerivedName::update(self : Self, source : String) -> Self {
  match self.reusable_prefix {
    Some(prefix) if source.has_prefix(prefix.view()) => self
    _ => derive_name(source)
  }
}

///|
pub fn DerivedName::text(self : Self) -> String {
  self.text
}
