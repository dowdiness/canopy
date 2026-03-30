///|
/// Import Markdown text into a BlockDoc.
///
/// Line-by-line parser recognising:
/// - `# ` … `###### ` → Heading(n)
/// - `- ` or `* ` → ListItem(Bullet)
/// - `- [ ] ` / `- [x] ` / `- [X] ` → ListItem(Todo)
/// - `N. ` → ListItem(Numbered)
/// - `> ` → Quote
/// - ` ``` ` … ` ``` ` → Code(lang)
/// - `---` / `***` / `___` → Divider
/// - consecutive non-blank lines → single Paragraph (joined with space)
/// - blank lines → block separator
pub fn block_doc_from_markdown(
  md : String,
  replica_id : String,
) -> BlockDoc raise @tree.TreeError {
  let doc = BlockDoc::new(replica_id)
  let lines = split_lines(md)
  let len = lines.length()
  let para_buf : Array[String] = []
  let mut i = 0
  while i < len {
    let line = lines[i]
    if starts_with(line, "```") {
      flush_paragraph(doc, para_buf)
      let lang = line[3:].to_string()
      let code_buf = StringBuilder::new()
      i = i + 1
      let mut first = true
      while i < len && !(starts_with(lines[i], "```")) {
        if !(first) {
          code_buf.write_string("\n")
        }
        code_buf.write_string(lines[i])
        first = false
        i = i + 1
      }
      if i < len {
        i = i + 1
      }
      let id = doc.create_block(Code(lang))
      doc.set_text(id, code_buf.to_string())
      continue
    }
    if line == "" {
      flush_paragraph(doc, para_buf)
      i = i + 1
      continue
    }
    if is_divider(line) {
      flush_paragraph(doc, para_buf)
      let _ = doc.create_block(Divider)
      i = i + 1
      continue
    }
    let heading_level = count_heading_hashes(line)
    if heading_level > 0 && heading_level <= 6 {
      flush_paragraph(doc, para_buf)
      let text = line[heading_level + 1:].to_string()
      let id = doc.create_block(Heading(heading_level))
      doc.set_text(id, text)
      i = i + 1
      continue
    }
    // Todo must be checked before bullet (both start with "- ")
    if starts_with(line, "- [ ] ") ||
      starts_with(line, "- [x] ") ||
      starts_with(line, "- [X] ") {
      flush_paragraph(doc, para_buf)
      let checked = !(starts_with(line, "- [ ] "))
      let text = line[6:].to_string()
      let id = doc.create_block(ListItem(Todo))
      doc.set_text(id, text)
      if checked {
        doc.set_checked(id, true)
      }
      i = i + 1
      continue
    }
    if starts_with(line, "- ") || starts_with(line, "* ") {
      flush_paragraph(doc, para_buf)
      let text = line[2:].to_string()
      let id = doc.create_block(ListItem(Bullet))
      doc.set_text(id, text)
      i = i + 1
      continue
    }
    let num_prefix = count_numbered_prefix(line)
    if num_prefix > 0 {
      flush_paragraph(doc, para_buf)
      let text = line[num_prefix:].to_string()
      let id = doc.create_block(ListItem(Numbered))
      doc.set_text(id, text)
      i = i + 1
      continue
    }
    if starts_with(line, "> ") {
      flush_paragraph(doc, para_buf)
      let text = line[2:].to_string()
      let id = doc.create_block(Quote)
      doc.set_text(id, text)
      i = i + 1
      continue
    }
    para_buf.push(line)
    i = i + 1
  }
  flush_paragraph(doc, para_buf)
  doc
}

// ── Private helpers ────────────────────────────────────────────────────────

///|
fn flush_paragraph(
  doc : BlockDoc,
  buf : Array[String],
) -> Unit raise @tree.TreeError {
  if buf.length() > 0 {
    let text = buf.join(" ")
    let id = doc.create_block(Paragraph)
    doc.set_text(id, text)
    buf.clear()
  }
}

///|
/// Split a string into lines. Handles \n, \r\n, and bare \r.
/// Drops trailing empty line from trailing newline.
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < s.length() {
    if s[i] == '\r' {
      lines.push(s[start:i].to_string())
      if i + 1 < s.length() && s[i + 1] == '\n' {
        i = i + 2
      } else {
        i = i + 1
      }
      start = i
    } else if s[i] == '\n' {
      lines.push(s[start:i].to_string())
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  if start < s.length() {
    lines.push(s[start:].to_string())
  }
  lines
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  if prefix.length() > s.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// Count leading '#' characters. Returns the heading level if followed by a space,
/// otherwise 0.
fn count_heading_hashes(line : String) -> Int {
  let mut count = 0
  while count < line.length() && line[count] == '#' {
    count = count + 1
  }
  if count > 0 && count < line.length() && line[count] == ' ' {
    count
  } else {
    0
  }
}

///|
/// Check if a line is a thematic break: 3+ of the same marker char ('-', '*', '_'),
/// optionally separated by spaces, with nothing else on the line.
fn is_divider(line : String) -> Bool {
  if line.length() < 3 {
    return false
  }
  let mut marker : UInt16 = 0
  let mut count = 0
  for i = 0; i < line.length(); i = i + 1 {
    let ch = line[i]
    if ch == ' ' {
      continue
    }
    if marker == 0 {
      if ch != '-' && ch != '*' && ch != '_' {
        return false
      }
      marker = ch
    }
    if ch != marker {
      return false
    }
    count = count + 1
  }
  count >= 3
}

///|
/// If line matches `N. text`, return the offset past "N. " (the length of the prefix).
/// Returns 0 if not a numbered list item.
fn count_numbered_prefix(line : String) -> Int {
  let mut i = 0
  while i < line.length() && line[i] >= '0' && line[i] <= '9' {
    i = i + 1
  }
  if i > 0 && i + 1 < line.length() && line[i] == '.' && line[i + 1] == ' ' {
    i + 2
  } else {
    0
  }
}
