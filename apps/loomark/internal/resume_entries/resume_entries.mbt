///|
let resume_source_id : @loom.SourceId = @loom.SourceId("loomark-resume-entries")

///|
/// The kind named by an explicit `###` heading. A kind records what the text
/// says it is; it does not mean the statement is confirmed or complete.
pub(all) enum EntryKind {
  Observation
  Decision
  NextStep
} derive(Eq, Debug)

///|
/// One top-level list item under a kind heading. `start` and `end` are a
/// half-open UTF-16 range into the document source it was extracted from, and
/// `text` is that exact slice. `project` is the exact text of the enclosing
/// `##` heading, or `None` when no project heading applies.
pub struct ResumeEntry {
  kind : EntryKind
  project : String?
  start : Int
  end : Int
  text : String
} derive(Eq, Debug)

///|
/// The extraction result for one selected document. `entries` is `None` when
/// the source could not be parsed; such a document has no checkable entries.
pub struct ResumeDocument[K] {
  key : K
  source : String
  entries : Array[ResumeEntry]?
}

///|
/// Whether entries of this document still describe `text` for `key`. A range
/// is only meaningful for the exact source it was extracted from.
pub fn[K : Eq] ResumeDocument::is_current(
  self : ResumeDocument[K],
  key : K,
  text : String,
) -> Bool {
  self.key == key && self.source == text
}

///|
/// Extract entries from each selected document in order. A key that appears
/// more than once is used only at its first occurrence.
pub fn[K : Eq + Hash] extract(
  documents : Array[(K, String)],
) -> Array[ResumeDocument[K]] {
  let seen : Set[K] = Set([])
  documents.filter_map(document => {
    let (key, source) = document
    guard !seen.contains(key) else { None }
    seen.add(key)
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
    Some("試したこと") => Some(Observation)
    Some("判断") => Some(Decision)
    Some("次にやること") => Some(NextStep)
    _ => None
  }
}

///|
priv struct Context {
  project : String?
  kind : EntryKind?
  entries : Array[ResumeEntry]
}

///|
/// Walk only top-level blocks, so headings and lists inside block quotes and
/// code blocks are never read. `#` clears the context, `##` sets the project
/// and clears the kind, `###` sets the kind (or clears it for another title),
/// and deeper headings clear the kind. Other blocks leave the context as is.
fn extract_entries(source : String) -> Array[ResumeEntry]? {
  let (cst, diagnostics) = @markdown.parse_cst(resume_source_id, source) catch {
    _ => return None
  }
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    resume_source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  let initial = { project: None, kind: None, entries: [], }
  let context = document
    .children()
    .fold(init=initial, (context, node) => {
      match node.view() {
        Heading(depth=1) => { ..context, project: None, kind: None, }
        Heading(depth=2) => {
          let project = heading_text(node, source).filter(text => {
            !text.is_empty()
          })
          { ..context, project, kind: None, }
        }
        Heading(depth=3) =>
          { ..context, kind: kind_of(heading_text(node, source)), }
        Heading(..) => { ..context, kind: None, }
        UnorderedList(..) | OrderedList(..) =>
          match context.kind {
            Some(kind) => {
              let entries = node
                .children()
                .map(item => {
                  let origin = item.origin()
                  // An item with nested content can end after its final line
                  // ending; ranges end at the item's last character instead.
                  let text = source[origin.start():origin.end()]
                    .trim_end(chars="\r\n")
                    .to_owned()
                  {
                    kind,
                    project: context.project,
                    start: origin.start(),
                    end: origin.start() + text.length(),
                    text,
                  }
                })
              { ..context, entries: [..context.entries, ..entries], }
            }
            None => context
          }
        _ => context
      }
    })
  Some(context.entries)
}

///|
pub extend EntryKind with Eq::{equal, not_equal}

///|
pub extend EntryKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ResumeEntry with Eq::{equal, not_equal}

///|
pub extend ResumeEntry with @moonbitlang/core/debug.Debug::{to_repr}
