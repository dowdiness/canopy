///|
let resume_source_id : @loom.SourceId = @loom.SourceId("loomark-resume-entries")

///|
/// The kind named by a `###` heading.
#derive(Eq, Debug)
pub(all) enum EntryKind {
  Observation
  Decision
  NextStep
}

///|
/// A top-level list item under a kind heading: a half-open UTF-16 range in
/// its document's source, and the enclosing `##` heading text, if any.
#derive(Eq, Debug)
pub struct ResumeEntry {
  kind : EntryKind
  project : String?
  start : Int32
  end : Int32
}

///|
/// One selected document. `entries` is `None` when parsing failed.
pub struct ResumeDocument[K] {
  key : K
  source : String
  entries : Array[ResumeEntry]?
}

///|
/// Whether the entries still apply to `text` for `key`.
pub fn[K : Eq] ResumeDocument::is_current(
  self : ResumeDocument[K],
  key : K,
  text : String,
) -> Bool {
  self.key == key && self.source == text
}

///|
/// Extract entries from each document in order; a repeated key is skipped.
pub fn[K : Eq + Hash] extract(
  documents : Array[(K, String)],
) -> Array[ResumeDocument[K]] {
  let seen : Set[K] = Set([])
  documents.filter_map(document => {
    let (key, source) = document
    guard !seen.contains(key) else { None }
    seen.insert(key)
    Some({ key, source, entries: extract_entries(source), })
  })
}

///|
fn heading_text(node : @markdown.MarkdownIR, source : String) -> String? {
  node
  .content_origin()
  .map(origin => source[origin.start():origin.end()].trim().to_owned())
}

///|
fn kind_of(title : String?) -> EntryKind? {
  match title {
    Some("試したこと" | "Observations") => Some(Observation)
    Some("判断" | "Decisions") => Some(Decision)
    Some("次にやること" | "Next steps") => Some(NextStep)
    _ => None
  }
}

///|
/// Read only top-level blocks, so quotes and code blocks are skipped.
fn extract_entries(source : String) -> Array[ResumeEntry]? {
  let (cst, diagnostics) = @markdown.parse_cst(resume_source_id, source) catch {
    _ => return None
  }
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    resume_source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let entries = []
  let mut project = None
  let mut kind = None
  for node in document.children() {
    match node.view() {
      Heading(depth=1) => {
        project = None
        kind = None
      }
      Heading(depth=2) => {
        project = heading_text(node, source).filter(text => !text.is_empty())
        kind = None
      }
      Heading(depth=3) => kind = kind_of(heading_text(node, source))
      Heading(..) => kind = None
      UnorderedList(..) | OrderedList(..) =>
        if kind is Some(kind) {
          for item in node.children() {
            let origin = item.origin()
            // An item with a nested list can end after a line ending.
            let text = source[origin.start():origin.end()].trim_end(
              chars="\r\n",
            )
            let start = origin.start()
            entries.push({ kind, project, start, end: start + text.length(), })
          }
        }
      _ => ()
    }
  }
  Some(entries)
}

///|
pub extend EntryKind with Eq::{equal, not_equal}

///|
pub extend EntryKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ResumeEntry with Eq::{equal, not_equal}

///|
pub extend ResumeEntry with @moonbitlang/core/debug.Debug::{to_repr}
