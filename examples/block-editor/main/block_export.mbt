///|
/// Export a BlockDoc to Markdown.
///
/// Rules:
/// - Blank line before/after: headings, dividers, quotes, code blocks
/// - No blank lines between consecutive list items of the same style
/// - Different list styles get a blank line between
/// - Numbered list items renumbered from 1
/// - Code: ```lang\n…\n```
/// - Divider: ---
/// - Raw: verbatim content
pub fn block_doc_to_markdown(doc : BlockDoc) -> String {
  let buf = StringBuilder::new()
  let children = doc.children(root_block_id)
  let len = children.length()
  let mut numbered_counter = 1
  for i = 0; i < len; i = i + 1 {
    let id = children[i]
    let bt = doc.get_type(id)
    let text = doc.get_text(id)
    let prev_type : BlockType? = if i > 0 {
      Some(doc.get_type(children[i - 1]))
    } else {
      None
    }
    // Blank line logic: before headings, dividers, quotes, code blocks,
    // and when switching between list styles or from list to non-list.
    if i > 0 {
      let need_blank = match (prev_type, bt) {
        // Same list style: no blank line
        (Some(ListItem(a)), ListItem(b)) => not(list_style_eq(a, b))
        // Everything else gets a blank line between blocks
        _ => true
      }
      if need_blank {
        buf.write_string("\n")
      }
    }
    // Reset numbered counter when not in a numbered run
    match bt {
      ListItem(Numbered) => ()
      _ => numbered_counter = 1
    }
    // Write the block
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
  }
  buf.to_string()
}

// ── Private helpers ────────────────────────────────────────────────────────

///|
fn list_style_eq(a : ListStyle, b : ListStyle) -> Bool {
  match (a, b) {
    (Bullet, Bullet) => true
    (Numbered, Numbered) => true
    (Todo, Todo) => true
    _ => false
  }
}
