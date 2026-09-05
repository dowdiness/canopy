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
pub struct DocumentLead {
  form : DocumentLeadForm
  primary : String
  description : String
  primary_truncated : Bool
  description_truncated : Bool
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
/// private
fn structured_description(
  node : @markdown.MarkdownIR,
  source : String,
) -> String {
  match node.view() {
    @markdown.BlockQuote =>
      node
      .children()
      .map(child => structured_description(child, source))
      .join("\n")
      .split("\n")
      .map(line => "> " + line.to_owned())
      .join("\n")
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
      node
      .children()
      .map(child => {
        let marker = marker_text(child)
        let text = structured_description(child, source)
        if text.is_empty() {
          marker
        } else {
          marker + " " + text
        }
      })
      .join("\n")
    @markdown.ListItem(..) | @markdown.OrderedListItem(..) => {
      let text = node
        .children()
        .map(child => {
          match child.view() {
            @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
              "  " +
              structured_description(child, source).replace(
                old="\n",
                new="\n  ",
              )
            _ => readable_text(child, source).unwrap_or("")
          }
        })
        .join("\n")
      match node.view() {
        @markdown.ListItem(task=Some(task), ..)
        | @markdown.OrderedListItem(task=Some(task), ..) =>
          (if task.checked() { "[x] " } else { "[ ] " }) + text
        _ => text
      }
    }
    _ => readable_text(node, source).unwrap_or("")
  }
}

///|
/// The first readable item is the primary for a list; later items retain
/// their own markers in the description. Nested content of the primary item
/// remains in the description before those later items.
fn list_lead_text(
  node : @markdown.MarkdownIR,
  source : String,
) -> (String, String, DocumentLeadForm) {
  let items = node.children()
  let first_readable = items.search_by(item => {
    readable_text(item, source).unwrap_or("").trim().is_empty() == false
  })
  match first_readable {
    None => ("", "", DocumentLeadForm::List(marker_text(node)))
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
      let (primary, primary_nested) = if primary.is_empty() {
        let nested_primary = nested
          .get(0)
          .map(child => {
            readable_text(child, source).unwrap_or("").trim().to_owned()
          })
          .unwrap_or("")
        (nested_primary, "")
      } else {
        let nested_description = nested
          .map(child => {
            "  " +
            structured_description(child, source).replace(old="\n", new="\n  ")
          })
          .join("\n")
        (primary, nested_description)
      }
      let later = items[index + 1:]
        .map(item => {
          let marker = marker_text(item)
          let text = structured_description(item, source)
          if text.is_empty() {
            marker
          } else {
            marker + " " + text
          }
        })
        .join("\n")
      let description = [primary_nested, later]
        .filter(text => !text.is_empty())
        .join("\n")
      let form = match item.view() {
        @markdown.MarkdownIRView::ListItem(task=Some(task), ..)
        | @markdown.MarkdownIRView::OrderedListItem(task=Some(task), ..) =>
          DocumentLeadForm::Task(task.checked())
        _ => DocumentLeadForm::List(marker_text(node))
      }
      (primary, description, form)
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
      let (primary, description, form) = list_lead_text(node, source)
      (primary, description, Some(form))
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
  Some({ form, primary, description, primary_truncated, description_truncated })
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
/// Construct the unbounded description from the selected lead and siblings.
fn description_for_lead(
  lead : DocumentLead,
  children : Array[@markdown.MarkdownIR],
  index : Int,
  source : String,
) -> String {
  let later = children[index + 1:]
    .map(child => structured_description(child, source))
    .filter(text => !text.is_empty())
  if lead.description.is_empty() {
    later.join("\n")
  } else if later.is_empty() {
    lead.description
  } else {
    lead.description + "\n" + later.join("\n")
  }
}

///|
/// Construct the final bounded result from the already selected lead.
fn result_from_bounded_description(
  lead : DocumentLead,
  description : String,
  description_truncated : Bool,
) -> DocumentLead {
  {
    form: lead.form,
    primary: lead.primary,
    description,
    primary_truncated: lead.primary_truncated,
    description_truncated: lead.description_truncated || description_truncated,
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
  let combined = description_for_lead(lead, children, index, source)
  let (description, description_truncated) = bound_text(
    combined,
    limits.description,
  )
  result_from_bounded_description(lead, description, description_truncated)
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
