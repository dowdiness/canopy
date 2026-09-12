///|
/// Document leads retain bounded Unicode scalar-value prefixes.
let primary_limit = 80

///|
let description_limit = 160

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
struct DocumentLead {
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
            _ => readable_text(child, Some(source)).unwrap_or("")
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
    _ => readable_text(node, Some(source)).unwrap_or("")
  }
}

///|
priv struct UnboundedLead {
  form : DocumentLeadForm
  primary : String
  description : String
}

///|
/// The first readable item is the primary for a list; later items retain
/// their own markers in the description. Nested content of the primary item
/// remains in the description before those later items.
fn list_lead_text(
  node : @markdown.MarkdownIR,
  source : String,
) -> UnboundedLead {
  let items = node.children()
  let first_readable = items.search_by(item => {
    readable_text(item, Some(source)).unwrap_or("").trim().is_empty() == false
  })
  match first_readable {
    None =>
      {
        form: DocumentLeadForm::List(marker_text(node)),
        primary: "",
        description: "",
      }
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
        .map(child => readable_text(child, Some(source)).unwrap_or(""))
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
        let nested_lead = match nested.get(0) {
          Some(child) => lead_from_node(child, source)
          None => None
        }
        match nested_lead {
          Some(lead) => {
            let description = if lead.description.is_empty() {
              ""
            } else {
              "  " + lead.description.replace(old="\n", new="\n  ")
            }
            (lead.primary, description)
          }
          None => ("", "")
        }
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
      { form, primary, description, }
    }
  }
}

///|
fn lead_from_node(
  node : @markdown.MarkdownIR,
  source : String,
) -> UnboundedLead? {
  let lead = match node.view() {
    @markdown.UnorderedList(..) | @markdown.OrderedList(..) =>
      list_lead_text(node, source)
    @markdown.CodeBlock(..) =>
      {
        form: DocumentLeadForm::Code,
        primary: readable_text(node, Some(source)).unwrap_or(""),
        description: "",
      }
    view => {
      let form = match view {
        @markdown.Heading(..) => DocumentLeadForm::Heading
        @markdown.BlockQuote => DocumentLeadForm::Quote
        @markdown.ListItem(task=Some(task), ..)
        | @markdown.OrderedListItem(task=Some(task), ..) =>
          DocumentLeadForm::Task(task.checked())
        _ => DocumentLeadForm::Plain
      }
      {
        form,
        primary: readable_text(node, Some(source))
        .unwrap_or("")
        .trim()
        .to_owned(),
        description: "",
      }
    }
  }
  guard !lead.primary.is_empty() else { return None }
  Some(lead)
}

///|
fn fallback_lead(source : String) -> DocumentLead {
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
  let (primary, primary_truncated) = bound_text(primary_source, primary_limit)
  let (description, description_truncated) = bound_text(
    description_source, description_limit,
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
/// Select the first block with readable text.
fn first_readable_index(
  document : @markdown.MarkdownIR,
  source : String,
) -> Int? {
  document
  .children()
  .search_by(child => {
    match readable_text(child, Some(source)) {
      Some(text) => !text.trim().is_empty()
      None => false
    }
  })
}

///|
/// Extract a bounded, equality-bearing lead from the complete Markdown source.
pub fn extract(source : String) -> DocumentLead {
  let parsed = @markdown.parse_cst(name_source_id, source) catch {
    _ => return fallback_lead(source)
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
      match lead_from_node(first, source) {
        Some(lead) => {
          let later = children[index + 1:]
            .map(child => structured_description(child, source))
            .filter(text => !text.is_empty())
          let description_source = [lead.description, later.join("\n")]
            .filter(text => !text.is_empty())
            .join("\n")
          let (primary, primary_truncated) = bound_text(
            lead.primary,
            primary_limit,
          )
          let (description, description_truncated) = bound_text(
            description_source, description_limit,
          )
          {
            form: lead.form,
            primary,
            description,
            primary_truncated,
            description_truncated,
          }
        }
        None => fallback_lead(source)
      }
    }
    None => fallback_lead(source)
  }
}
