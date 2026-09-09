///|
/// Provisional, positive output budgets for a DocumentLead.
///
/// Budgets count Unicode scalar values. They bound the retained strings, not
/// parser work: extraction still parses the complete source.
pub struct DocumentLeadLimits {
  primary : Int
  description : Int
} derive(Eq, Debug)

///|
pub fn DocumentLeadLimits::try_new(
  primary~ : Int,
  description~ : Int,
) -> Result[DocumentLeadLimits, Unit] {
  if primary <= 0 || description <= 0 {
    Err(())
  } else {
    Ok({ primary, description })
  }
}

///|
pub enum DocumentLeadForm {
  Heading
  Task(Bool)
  Quote
  Code
  List(String)
  Plain
  Empty
} derive(Eq, Debug)

///|
/// A task checkbox marker displayed in `description`.
///
/// `start` is inclusive and `end` is exclusive. Both are UTF-16 code-unit
/// offsets into `DocumentLead::description()`, matching MoonBit `String`
/// slicing (and JavaScript string indices). The range covers the rendered
/// list marker and checkbox prefix, not task content. Ranges are emitted only
/// for task items represented by the Markdown IR; literal text and code are
/// never inferred as tasks. A range is omitted when truncation would cut its
/// prefix.
pub struct DocumentLeadTaskMarkerRange {
  start : Int
  end : Int
  checked : Bool
} derive(Eq, Debug)

///|
pub fn DocumentLeadTaskMarkerRange::start(
  self : DocumentLeadTaskMarkerRange,
) -> Int {
  self.start
}

///|
pub fn DocumentLeadTaskMarkerRange::end(
  self : DocumentLeadTaskMarkerRange,
) -> Int {
  self.end
}

///|
pub fn DocumentLeadTaskMarkerRange::checked(
  self : DocumentLeadTaskMarkerRange,
) -> Bool {
  self.checked
}

///|
pub struct DocumentLead {
  form : DocumentLeadForm
  primary : String
  description : String
  primary_truncated : Bool
  description_truncated : Bool
  priv task_marker_ranges : Array[DocumentLeadTaskMarkerRange]
} derive(Eq, Debug)

///|
pub fn DocumentLead::form(self : DocumentLead) -> DocumentLeadForm {
  self.form
}

///|
pub fn DocumentLead::primary(self : DocumentLead) -> String {
  self.primary
}

///|
pub fn DocumentLead::description(self : DocumentLead) -> String {
  self.description
}

///|
/// Return task-marker provenance for the retained description.
///
/// The returned array is a defensive copy and may be freely mutated by the
/// caller without changing the lead.
pub fn DocumentLead::task_marker_ranges(
  self : DocumentLead,
) -> Array[DocumentLeadTaskMarkerRange] {
  self.task_marker_ranges.copy()
}

///|
pub fn DocumentLead::primary_truncated(self : DocumentLead) -> Bool {
  self.primary_truncated
}

///|
pub fn DocumentLead::description_truncated(self : DocumentLead) -> Bool {
  self.description_truncated
}

///|
/// private
fn bound_text(text : String, limit : Int) -> (String, Bool) {
  let length = text.char_length()
  if length <= limit {
    (text, false)
  } else {
    let end = text.offset_of_nth_char(limit).unwrap()
    (text.view(end_offset=end).to_owned(), true)
  }
}

///|
/// private
fn readable_text(node : @markdown.MarkdownIR, source : String) -> String? {
  let builder = StringBuilder()
  if append_lead_readable_text(node, builder, source) {
    Some(builder.to_string())
  } else {
    None
  }
}

///|
/// Keep source-backed recovery nodes readable instead of silently dropping them.
fn append_lead_readable_text(
  node : @markdown.MarkdownIR,
  builder : StringBuilder,
  source : String,
) -> Bool {
  match node.view() {
    @markdown.Text(value~)
    | @markdown.InlineCode(value~)
    | @markdown.Autolink(display=value, ..)
    | @markdown.CodeBlock(value~, ..) => builder.write_string(value)
    @markdown.SoftBreak | @markdown.HardBreak(..) => builder.write_char('\n')
    @markdown.Unsupported(..) => {
      let origin = node.origin()
      builder.write_string(source[origin.start():origin.end()].to_owned())
    }
    @markdown.Document
    | @markdown.BlockQuote
    | @markdown.UnorderedList(..)
    | @markdown.OrderedList(..)
    | @markdown.ListItem(..)
    | @markdown.OrderedListItem(..) => {
      let mut first = true
      for child in node.children() {
        if !first {
          builder.write_char('\n')
        }
        guard append_lead_readable_text(child, builder, source) else {
          return false
        }
        first = false
      }
    }
    @markdown.Heading(..)
    | @markdown.Paragraph
    | @markdown.Bold
    | @markdown.Italic
    | @markdown.Link(..)
    | @markdown.Image(..) =>
      for child in node.children() {
        guard append_lead_readable_text(child, builder, source) else {
          return false
        }
      }
    @markdown.Raw(value~) | @markdown.Recovered(value~) =>
      builder.write_string(value)
    @markdown.ThematicBreak
    | @markdown.HtmlBlock(..)
    | @markdown.InlineHtml(..) => ()
  }
  true
}

///|
/// private
fn marker_text(node : @markdown.MarkdownIR) -> String {
  match node.view() {
    @markdown.UnorderedList(marker~, ..) | @markdown.ListItem(marker~, ..) =>
      match marker {
        Some(@markdown.UnorderedListMarker::Dash) => "-"
        Some(@markdown.UnorderedListMarker::Star) => "*"
        Some(@markdown.UnorderedListMarker::Plus) => "+"
        None => "-"
      }
    @markdown.OrderedList(marker~, ..)
    | @markdown.OrderedListItem(marker~, ..) =>
      marker.map(m => m.text()).unwrap_or("1.")
    _ => "-"
  }
}

///|
priv struct DescriptionRender {
  text : String
  markers : Array[DocumentLeadTaskMarkerRange]
}

///|
fn render_description(
  node : @markdown.MarkdownIR,
  source : String,
) -> DescriptionRender {
  let builder = StringBuilder::StringBuilder()
  let markers = []
  append_rendered_description(node, source, builder, markers, None)
  { text: builder.to_string(), markers }
}

///|
fn append_rendered_description(
  node : @markdown.MarkdownIR,
  source : String,
  builder : StringBuilder,
  markers : Array[DocumentLeadTaskMarkerRange],
  marker_start : Int?,
) -> Unit {
  let write = text => builder.write_string(text)
  match node.view() {
    @markdown.BlockQuote =>
      for i, child in node.children() {
        if i > 0 {
          write("\n")
        }
        let rendered = render_description(child, source)
        append_rendered_fragment(
          builder,
          markers,
          rendered,
          "> ",
          builder.to_string().length(),
        )
      }
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
      for i, child in node.children() {
        if i > 0 {
          write("\n")
        }
        let start = builder.to_string().length()
        write(marker_text(child) + " ")
        append_rendered_description(
          child,
          source,
          builder,
          markers,
          Some(start),
        )
      }
    @markdown.ListItem(..) | @markdown.OrderedListItem(..) => {
      let task_prefix = match node.view() {
        @markdown.ListItem(task=Some(task), ..)
        | @markdown.OrderedListItem(task=Some(task), ..) =>
          Some((if task.checked() { "[x] " } else { "[ ] " }, task.checked()))
        _ => None
      }
      match task_prefix {
        Some((prefix, checked)) => {
          let start = marker_start.unwrap_or(builder.to_string().length())
          write(prefix)
          markers.push({ start, end: builder.to_string().length(), checked })
        }
        None => ()
      }
      for i, child in node.children() {
        if i > 0 {
          write("\n")
        }
        match child.view() {
          @markdown.UnorderedList(..) | @markdown.OrderedList(..) => {
            let rendered = render_description(child, source)
            let base = builder.to_string().length()
            append_rendered_fragment(builder, markers, rendered, "  ", base)
          }
          _ => {
            let rendered = render_description(child, source)
            write(rendered.text)
          }
        }
      }
    }
    _ => write(readable_text(node, source).unwrap_or(""))
  }
}

///|
/// The first readable item is the primary for a list; later items retain
/// their own markers in the description. Nested content of the primary item
/// remains in the description before those later items.
fn list_lead_text(
  node : @markdown.MarkdownIR,
  source : String,
) -> (String, DocumentLeadForm) {
  let items = node.children()
  let first_readable = items.search_by(item => {
    readable_text(item, source).unwrap_or("").trim().is_empty() == false
  })
  match first_readable {
    None => ("", DocumentLeadForm::List(marker_text(node)))
    Some(index) => {
      let item = items.get(index).unwrap()
      let primary = item
        .children()
        .filter(child => {
          match child.view() {
            @markdown.MarkdownIRView::UnorderedList(..)
            | @markdown.MarkdownIRView::OrderedList(..) => false
            _ => true
          }
        })
        .map(child => readable_text(child, source).unwrap_or(""))
        .join("\n")
        .trim()
        .to_owned()
      let nested = item
        .children()
        .filter(child => {
          match child.view() {
            @markdown.MarkdownIRView::UnorderedList(..)
            | @markdown.MarkdownIRView::OrderedList(..) => true
            _ => false
          }
        })
      let primary = if primary.is_empty() {
        nested
        .get(0)
        .map(child => list_lead_text(child, source).0)
        .unwrap_or("")
      } else {
        primary
      }
      let form = match item.view() {
        @markdown.MarkdownIRView::ListItem(task=Some(task), ..)
        | @markdown.MarkdownIRView::OrderedListItem(task=Some(task), ..) =>
          DocumentLeadForm::Task(task.checked())
        _ => DocumentLeadForm::List(marker_text(node))
      }
      (primary, form)
    }
  }
}

///|
/// private
fn lead_from_node(
  node : @markdown.MarkdownIR,
  source : String,
  limits : DocumentLeadLimits,
) -> DocumentLead? {
  let (primary_source, description_source, list_form) = match node.view() {
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) => {
      let (primary, form) = list_lead_text(node, source)
      (primary, "", Some(form))
    }
    @markdown.CodeBlock(..) =>
      (readable_text(node, source).unwrap_or(""), "", None)
    _ => (readable_text(node, source).unwrap_or("").trim().to_owned(), "", None)
  }
  guard !primary_source.is_empty() else { return None }
  let (primary, primary_truncated) = bound_text(primary_source, limits.primary)
  let description = description_source
  let description_truncated = false
  let form = match node.view() {
    @markdown.Heading(..) => DocumentLeadForm::Heading
    @markdown.BlockQuote => DocumentLeadForm::Quote
    @markdown.CodeBlock(..) => DocumentLeadForm::Code
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
      list_form.unwrap()
    @markdown.ListItem(task=Some(task), ..)
    | @markdown.OrderedListItem(task=Some(task), ..) =>
      DocumentLeadForm::Task(task.checked())
    _ => DocumentLeadForm::Plain
  }
  Some({
    form,
    primary,
    description,
    primary_truncated,
    description_truncated,
    task_marker_ranges: [],
  })
}

///|
/// private
fn fallback_lead(source : String, limits : DocumentLeadLimits) -> DocumentLead {
  let normalized = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let lines = normalized.split("\n").to_array()
  let first = lines.search_by(line => !line.trim().is_empty())
  let primary_source = match first {
    Some(index) => lines[index].trim().to_owned()
    None => ""
  }
  let description_source = match first {
    Some(index) => {
      let rest = lines[index + 1:]
      match rest.search_by(line => !line.trim().is_empty()) {
        Some(start) =>
          rest[start:].join("\n").trim_end(chars="\n".view()).to_owned()
        None => ""
      }
    }
    None => ""
  }
  let (primary, primary_truncated) = bound_text(primary_source, limits.primary)
  let (description, description_truncated) = bound_text(
    description_source,
    limits.description,
  )
  {
    form: if primary.is_empty() {
      DocumentLeadForm::Empty
    } else {
      DocumentLeadForm::Plain
    },
    primary,
    description,
    primary_truncated,
    description_truncated,
    task_marker_ranges: [],
  }
}

///|
/// Select the first block with readable text. Kept separate so the benchmark
/// measures the exact selection operation used by `extract`.
fn first_readable_index(
  document : @markdown.MarkdownIR,
  source : String,
) -> Int? {
  document
  .children()
  .search_by(child => {
    match readable_text(child, source) {
      Some(text) => !text.trim().is_empty()
      None => false
    }
  })
}

///|
/// Find marker lines with one linear scan of the rendered text, rather than
/// slicing and splitting once per marker.
fn rendered_marker_line(text : String, offset : Int) -> Int {
  let lines = text.split("\n")
  let starts : Array[Int] = [0]
  let mut position = 0
  for i, line in lines {
    position += line.length()
    if i + 1 < lines.length() {
      position += 1
      starts.push(position)
    }
  }
  starts
  .search_by(start => start > offset)
  .map(i => i - 1)
  .unwrap_or(starts.length() - 1)
}

///|
fn append_rendered_fragment(
  builder : StringBuilder,
  markers : Array[DocumentLeadTaskMarkerRange],
  rendered : DescriptionRender,
  prefix : String,
  base : Int,
) -> Unit {
  let lines = rendered.text.split("\n")
  for i, line in lines {
    if i > 0 {
      builder.write_char('\n')
    }
    builder.write_string(prefix)
    builder.write_string(line.to_owned())
  }
  for marker in rendered.markers {
    // `prefix` is written before every line, including the first one.
    let line = rendered_marker_line(rendered.text, marker.start())
    let shift = base + prefix.length() * (line + 1)
    markers.push({
      start: marker.start() + shift,
      end: marker.end() + shift,
      checked: marker.checked(),
    })
  }
}

///|
/// Add a rendered item marker only to its first line. Continuation lines are
/// already indented by the item renderer.
fn append_rendered_first_line(
  builder : StringBuilder,
  markers : Array[DocumentLeadTaskMarkerRange],
  rendered : DescriptionRender,
  prefix : String,
  base : Int,
) -> Unit {
  let lines = rendered.text.split("\n")
  for i, line in lines {
    if i > 0 {
      builder.write_char('\n')
    }
    if i == 0 {
      builder.write_string(prefix)
    }
    builder.write_string(line.to_owned())
  }
  for marker in rendered.markers {
    let line = rendered_marker_line(rendered.text, marker.start())
    let extra = if line == 0 && marker.start() != 0 {
      prefix.length()
    } else {
      0
    }
    let shift = base + extra
    let end_extra = if line == 0 && marker.start() == 0 {
      prefix.length()
    } else {
      0
    }
    markers.push({
      start: marker.start() + shift,
      end: marker.end() + shift + end_extra,
      checked: marker.checked(),
    })
  }
}

///|
/// Render exactly the description retained for the selected lead. Text and
/// marker ranges are assembled together, so no provenance reconstruction can
/// drift from the displayed string.
fn description_render_for_lead(
  lead : DocumentLead,
  children : Array[@markdown.MarkdownIR],
  index : Int,
  source : String,
) -> DescriptionRender {
  ignore(lead)
  let builder = StringBuilder::StringBuilder()
  let markers : Array[DocumentLeadTaskMarkerRange] = []
  let append = (rendered : DescriptionRender, prefix : String) => {
    let base = builder.to_string().length()
    append_rendered_fragment(builder, markers, rendered, prefix, base)
  }
  match children[index].view() {
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) => {
      let items = children[index].children()
      let selected = items.search_by(item => {
        readable_text(item, source).unwrap_or("").trim().is_empty() == false
      })
      match selected {
        Some(selected_index) => {
          let item = items[selected_index]
          let item_has_primary = item
            .children()
            .any(child => {
              match child.view() {
                @markdown.UnorderedList(..) | @markdown.OrderedList(..) => false
                _ =>
                  !readable_text(child, source).unwrap_or("").trim().is_empty()
              }
            })
          let mut skipped_primary_nested = false
          for child in item.children() {
            match child.view() {
              @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
                if !item_has_primary && !skipped_primary_nested {
                  skipped_primary_nested = true
                  let remaining = description_render_for_lead(
                    lead,
                    [child],
                    0,
                    source,
                  )
                  if !remaining.text.is_empty() {
                    if !builder.is_empty() {
                      builder.write_char('\n')
                    }
                    append(remaining, "  ")
                  }
                } else {
                  if !builder.is_empty() {
                    builder.write_char('\n')
                  }
                  append(render_description(child, source), "  ")
                }
              _ => ()
            }
          }
          for item in items[selected_index + 1:] {
            if !builder.is_empty() {
              builder.write_char('\n')
            }
            append_rendered_first_line(
              builder,
              markers,
              render_description(item, source),
              marker_text(item) + " ",
              builder.to_string().length(),
            )
          }
        }
        None => ()
      }
    }
    _ =>
      for child in children[index + 1:] {
        if !builder.is_empty() {
          builder.write_char('\n')
        }
        append(render_description(child, source), "")
      }
  }
  { text: builder.to_string(), markers }
}

///|
/// Construct the final bounded result from the already selected lead.
fn result_from_bounded_description(
  lead : DocumentLead,
  description : String,
  description_truncated : Bool,
  task_marker_ranges : Array[DocumentLeadTaskMarkerRange],
) -> DocumentLead {
  {
    form: lead.form,
    primary: lead.primary,
    description,
    primary_truncated: lead.primary_truncated,
    description_truncated: lead.description_truncated || description_truncated,
    task_marker_ranges,
  }
}

///|
fn finish_lead(
  lead : DocumentLead,
  children : Array[@markdown.MarkdownIR],
  index : Int,
  source : String,
  limits : DocumentLeadLimits,
) -> DocumentLead {
  let rendered = description_render_for_lead(lead, children, index, source)
  let (description, description_truncated) = bound_text(
    rendered.text,
    limits.description,
  )
  let marker_end = description.length()
  let markers = rendered.markers.filter(marker => marker.end() <= marker_end)
  result_from_bounded_description(
    lead, description, description_truncated, markers,
  )
}

///|
/// Extract a bounded, equality-bearing lead from the complete Markdown source.
pub fn extract(source : String, limits~ : DocumentLeadLimits) -> DocumentLead {
  let parsed = @markdown.parse_cst(name_source_id, source) catch {
    _ => return fallback_lead(source, limits)
  }
  let (cst, diagnostics) = parsed
  let root = @seam.SyntaxNode::from_cst(cst)
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  let children = document.children()
  match first_readable_index(document, source) {
    Some(index) => {
      let first = children.get(index).unwrap()
      match lead_from_node(first, source, limits) {
        Some(lead) => finish_lead(lead, children, index, source, limits)
        None => fallback_lead(source, limits)
      }
    }
    None => fallback_lead(source, limits)
  }
}
