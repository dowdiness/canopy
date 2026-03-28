///|
/// Export a BlockDoc to Markdown.
///
/// Rules:
/// - Blank line between all block pairs except consecutive same-style list items
/// - Numbered list items renumbered from 1
/// - Code: ```lang\n…\n```
/// - Divider: ---
/// - Raw: verbatim content
pub fn block_doc_to_markdown(doc : BlockDoc) -> String {
  let buf = StringBuilder::new()
  let children = doc.children(root_block_id)
  let len = children.length()
  let mut numbered_counter = 1
  let mut prev_type : BlockType? = None
  for i = 0; i < len; i = i + 1 {
    let id = children[i]
    let bt = doc.get_type(id)
    let text = doc.get_text(id)
    if i > 0 {
      let need_blank = match (prev_type, bt) {
        (Some(ListItem(a)), ListItem(b)) => a != b
        _ => true
      }
      if need_blank {
        buf.write_string("\n")
      }
    }
    match bt {
      ListItem(Numbered) => ()
      _ => numbered_counter = 1
    }
    match bt {
      Paragraph => {
        buf.write_string(text)
        buf.write_string("\n")
      }
      Heading(n) => {
        for j = 0; j < n; j = j + 1 {
          buf.write_string("#")
        }
        buf.write_string(" ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      ListItem(Bullet) => {
        buf.write_string("- ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      ListItem(Numbered) => {
        buf.write_string(numbered_counter.to_string())
        buf.write_string(". ")
        buf.write_string(text)
        buf.write_string("\n")
        numbered_counter = numbered_counter + 1
      }
      ListItem(Todo) => {
        if doc.get_checked(id) {
          buf.write_string("- [x] ")
        } else {
          buf.write_string("- [ ] ")
        }
        buf.write_string(text)
        buf.write_string("\n")
      }
      Quote => {
        buf.write_string("> ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      Code(lang) => {
        buf.write_string("```")
        buf.write_string(lang)
        buf.write_string("\n")
        buf.write_string(text)
        buf.write_string("\n```\n")
      }
      Divider => buf.write_string("---\n")
      Raw => {
        buf.write_string(text)
        buf.write_string("\n")
      }
    }
    prev_type = Some(bt)
  }
  buf.to_string()
}
