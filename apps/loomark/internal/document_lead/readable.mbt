///|
/// Read the Markdown text represented by a node. When source is provided,
/// source-backed recovery nodes retain their original spelling; otherwise they
/// make the traversal fail closed.
fn readable_text(node : @markdown.MarkdownIR, source : String?) -> String? {
  let builder = StringBuilder()
  if append_readable_text(node, builder, source) {
    Some(builder.to_string())
  } else {
    None
  }
}

///|
fn append_readable_text(
  node : @markdown.MarkdownIR,
  builder : StringBuilder,
  source : String?,
) -> Bool {
  match node.view() {
    @markdown.Text(value~)
    | @markdown.InlineCode(value~)
    | @markdown.Autolink(display=value, ..)
    | @markdown.CodeBlock(value~, ..) => builder.write_string(value)
    @markdown.SoftBreak | @markdown.HardBreak(..) => builder.write_char('\n')
    @markdown.Unsupported(..) =>
      match source {
        Some(source) => {
          let origin = node.origin()
          builder.write_string(source[origin.start():origin.end()].to_owned())
        }
        None => return false
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
        guard append_readable_text(child, builder, source) else { return false }
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
        guard append_readable_text(child, builder, source) else { return false }
      }
    @markdown.Raw(value~) | @markdown.Recovered(value~) =>
      builder.write_string(value)
    @markdown.ThematicBreak
    | @markdown.HtmlBlock(..)
    | @markdown.InlineHtml(..) => ()
  }
  true
}
