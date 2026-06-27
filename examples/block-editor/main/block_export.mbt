///| Export a BlockDoc to Markdown.
///|
///| Rules:
///| - Blank line between all block pairs except consecutive same-style list items
///| - Numbered list items renumbered from 1 per container
///| - Code: ```lang\n…\n```
///| - Divider: ---
///| - Raw: verbatim content
///| - Nested blocks indented by 2 spaces per depth level
pub fn block_doc_to_markdown(doc : BlockDoc) -> String {
  let buf = StringBuilder()
  emit_children(buf, doc, root_block_id, 0)
  buf.to_string()
}

fn emit_children(
  buf : StringBuilder,
  doc : BlockDoc,
  parent_id : @container.TreeNodeId,
  depth : Int,
) -> Unit {
  let children = doc.children(parent_id)
  let len = children.length()
  let mut numbered_counter = 1
  let mut prev_type : BlockType? = None
  let indent = if depth > 0 {
    let s = StringBuilder()
    for _ in 0..<depth {
      s.write_string("  ")
    }
    s.to_string()
  } else {
    ""
  }
  for i in 0..<len {
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
        buf.write_string(indent)
        buf.write_string(text)
        buf.write_string("\n")
      }
      Heading(n) => {
        buf.write_string(indent)
        for _ in 0..<n {
          buf.write_string("#")
        }
        buf.write_string(" ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      ListItem(Bullet) => {
        buf.write_string(indent)
        buf.write_string("- ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      ListItem(Numbered) => {
        buf.write_string(indent)
        buf.write_string(numbered_counter.to_string())
        buf.write_string(". ")
        buf.write_string(text)
        buf.write_string("\n")
        numbered_counter = numbered_counter + 1
      }
      ListItem(Todo) => {
        buf.write_string(indent)
        if doc.get_checked(id) {
          buf.write_string("- [x] ")
        } else {
          buf.write_string("- [ ] ")
        }
        buf.write_string(text)
        buf.write_string("\n")
      }
      Quote => {
        buf.write_string(indent)
        buf.write_string("> ")
        buf.write_string(text)
        buf.write_string("\n")
      }
      Code(lang) => {
        buf.write_string(indent)
        buf.write_string("```")
        buf.write_string(lang)
        buf.write_string("\n")
        buf.write_string(indent)
        buf.write_string(text)
        buf.write_string("\n")
        buf.write_string(indent)
        buf.write_string("```\n")
      }
      Divider => {
        buf.write_string(indent)
        buf.write_string("---\n")
      }
      Raw => {
        buf.write_string(indent)
        buf.write_string(text)
        buf.write_string("\n")
      }
    }
    // Recurse into children (nested blocks)
    emit_children(buf, doc, id, depth + 1)
    prev_type = Some(bt)
  }
}
