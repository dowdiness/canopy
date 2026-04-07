///|
test "create paragraph and read text" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Paragraph)
  doc.set_text(id, "hello world")
  inspect(doc.get_text(id), content="hello world")
  inspect(doc.get_type(id), content="Paragraph")
}

///|
test "create heading with level" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Heading(2))
  inspect(doc.get_type(id), content="Heading(2)")
  doc.set_text(id, "Title")
  inspect(doc.get_text(id), content="Title")
}

///|
test "children order is insertion order" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(Paragraph)
  let b = doc.create_block(Paragraph)
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(id_eq(children[0], a), content="true")
  inspect(id_eq(children[1], b), content="true")
}

///|
test "delete block removes from children" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(Paragraph)
  let b = doc.create_block(Paragraph)
  doc.delete_block(a)
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(id_eq(children[0], b), content="true")
  inspect(doc.is_alive(a), content="false")
}

///|
test "change block type preserves text" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Paragraph)
  doc.set_text(id, "some text")
  doc.set_type(id, Heading(3))
  inspect(doc.get_type(id), content="Heading(3)")
  inspect(doc.get_text(id), content="some text")
}

///|
test "list item style and checked" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(ListItem(Todo))
  inspect(doc.get_type(id), content="ListItem(Todo)")
  inspect(doc.get_checked(id), content="false")
  doc.set_checked(id, true)
  inspect(doc.get_checked(id), content="true")
}

///|
test "create_block_after inserts at correct position" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(Paragraph)
  let b = doc.create_block(Paragraph)
  let c = doc.create_block_after(a, Paragraph)
  let children = doc.children(root_block_id)
  inspect(children.length(), content="3")
  inspect(id_eq(children[0], a), content="true")
  inspect(id_eq(children[1], c), content="true")
  inspect(id_eq(children[2], b), content="true")
}

///|
test "create_block_after appends when after_id is last" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(Paragraph)
  let b = doc.create_block(Paragraph)
  let c = doc.create_block_after(b, Paragraph)
  let children = doc.children(root_block_id)
  inspect(children.length(), content="3")
  inspect(id_eq(children[0], a), content="true")
  inspect(id_eq(children[1], b), content="true")
  inspect(id_eq(children[2], c), content="true")
}

// ── Markdown export tests ─────────────────────────────────────────────────

///|
test "export: paragraph" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Paragraph)
  doc.set_text(id, "Hello world")
  inspect(block_doc_to_markdown(doc), content="Hello world\n")
}

///|
test "export: heading" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Heading(2))
  doc.set_text(id, "Title")
  inspect(block_doc_to_markdown(doc), content="## Title\n")
}

///|
test "export: mixed blocks" {
  let doc = BlockDoc::new("alice")
  let h = doc.create_block(Heading(1))
  doc.set_text(h, "Welcome")
  let p = doc.create_block(Paragraph)
  doc.set_text(p, "Some text here.")
  let b1 = doc.create_block(ListItem(Bullet))
  doc.set_text(b1, "item one")
  let b2 = doc.create_block(ListItem(Bullet))
  doc.set_text(b2, "item two")
  let expected =
    #|# Welcome
    #|
    #|Some text here.
    #|
    #|- item one
    #|- item two
    #|
  inspect(block_doc_to_markdown(doc), content=expected)
}

///|
test "export: numbered list" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(ListItem(Numbered))
  doc.set_text(a, "first")
  let b = doc.create_block(ListItem(Numbered))
  doc.set_text(b, "second")
  let expected =
    #|1. first
    #|2. second
    #|
  inspect(block_doc_to_markdown(doc), content=expected)
}

///|
test "export: todo list" {
  let doc = BlockDoc::new("alice")
  let a = doc.create_block(ListItem(Todo))
  doc.set_text(a, "unchecked task")
  let b = doc.create_block(ListItem(Todo))
  doc.set_text(b, "checked task")
  doc.set_checked(b, true)
  let expected =
    #|- [ ] unchecked task
    #|- [x] checked task
    #|
  inspect(block_doc_to_markdown(doc), content=expected)
}

///|
test "export: code block" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Code("moonbit"))
  doc.set_text(id, "fn main() { }")
  let expected =
    #|```moonbit
    #|fn main() { }
    #|```
    #|
  inspect(block_doc_to_markdown(doc), content=expected)
}

///|
test "export: divider" {
  let doc = BlockDoc::new("alice")
  let _ = doc.create_block(Divider)
  inspect(block_doc_to_markdown(doc), content="---\n")
}

// ── Markdown import tests ─────────────────────────────────────────────────

///|
test "import: paragraph" {
  let doc = block_doc_from_markdown("Hello world\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Paragraph")
  inspect(doc.get_text(children[0]), content="Hello world")
}

///|
test "import: heading levels" {
  let doc = block_doc_from_markdown("# H1\n## H2\n### H3\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="3")
  inspect(doc.get_type(children[0]), content="Heading(1)")
  inspect(doc.get_type(children[1]), content="Heading(2)")
  inspect(doc.get_type(children[2]), content="Heading(3)")
  inspect(doc.get_text(children[0]), content="H1")
  inspect(doc.get_text(children[1]), content="H2")
  inspect(doc.get_text(children[2]), content="H3")
}

///|
test "import: bullet list" {
  let doc = block_doc_from_markdown("- alpha\n- beta\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="ListItem(Bullet)")
  inspect(doc.get_type(children[1]), content="ListItem(Bullet)")
  inspect(doc.get_text(children[0]), content="alpha")
  inspect(doc.get_text(children[1]), content="beta")
}

///|
test "import: numbered list" {
  let doc = block_doc_from_markdown("1. first\n2. second\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="ListItem(Numbered)")
  inspect(doc.get_type(children[1]), content="ListItem(Numbered)")
  inspect(doc.get_text(children[0]), content="first")
  inspect(doc.get_text(children[1]), content="second")
}

///|
test "import: todo list" {
  let doc = block_doc_from_markdown("- [ ] todo\n- [x] done\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="ListItem(Todo)")
  inspect(doc.get_type(children[1]), content="ListItem(Todo)")
  inspect(doc.get_checked(children[0]), content="false")
  inspect(doc.get_checked(children[1]), content="true")
  inspect(doc.get_text(children[0]), content="todo")
  inspect(doc.get_text(children[1]), content="done")
}

///|
test "import: code block" {
  let doc = block_doc_from_markdown("```moonbit\nfn main() { }\n```\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Code(\"moonbit\")")
  inspect(doc.get_text(children[0]), content="fn main() { }")
}

///|
test "import: multi-line paragraph accumulated" {
  let doc = block_doc_from_markdown(
    "first line\nsecond line\n\nnew para\n", "alice",
  )
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="Paragraph")
  inspect(doc.get_text(children[0]), content="first line second line")
  inspect(doc.get_type(children[1]), content="Paragraph")
  inspect(doc.get_text(children[1]), content="new para")
}

// ── Round-trip test ───────────────────────────────────────────────────────

///|
test "round-trip: heading + paragraph + bullet list" {
  let md =
    #|# Welcome
    #|
    #|Some text here.
    #|
    #|- item one
    #|- item two
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

// ── Edge-case tests ───────────────────────────────────────────────────────

///|
test "import: empty input" {
  let doc = block_doc_from_markdown("", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="0")
}

///|
test "export: empty document" {
  let doc = BlockDoc::new("alice")
  inspect(block_doc_to_markdown(doc), content="")
}

///|
test "round-trip: two adjacent paragraphs" {
  let md =
    #|first paragraph
    #|
    #|second paragraph
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_text(children[0]), content="first paragraph")
  inspect(doc.get_text(children[1]), content="second paragraph")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "import: consecutive blank lines collapse" {
  let doc = block_doc_from_markdown("aaa\n\n\n\nbbb\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_text(children[0]), content="aaa")
  inspect(doc.get_text(children[1]), content="bbb")
}

///|
test "import: unclosed code fence consumes to EOF" {
  let doc = block_doc_from_markdown("```js\nlet x = 1\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Code(\"js\")")
  inspect(doc.get_text(children[0]), content="let x = 1")
}

///|
test "import: heading-like lines inside code fence stay as code" {
  let md =
    #|```
    #|# not a heading
    #|--- not a divider
    #|```
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Code(\"\")")
  let expected =
    #|# not a heading
    #|--- not a divider
  inspect(doc.get_text(children[0]), content=expected)
}

///|
test "round-trip: numbered list" {
  let md =
    #|1. first
    #|2. second
    #|3. third
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "round-trip: todo list" {
  let md =
    #|- [ ] unchecked
    #|- [x] checked
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "round-trip: code block" {
  let md =
    #|```js
    #|console.log("hello")
    #|```
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "round-trip: blockquote" {
  let md =
    #|> quoted text
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "round-trip: divider" {
  let md =
    #|---
    #|
  let doc = block_doc_from_markdown(md, "alice")
  let out = block_doc_to_markdown(doc)
  inspect(out, content=md)
}

///|
test "import: CRLF line endings" {
  let doc = block_doc_from_markdown("# Title\r\n\r\nSome text\r\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="Heading(1)")
  inspect(doc.get_text(children[0]), content="Title")
  inspect(doc.get_type(children[1]), content="Paragraph")
  inspect(doc.get_text(children[1]), content="Some text")
}

///|
test "import: uppercase todo checkbox" {
  let doc = block_doc_from_markdown("- [X] done\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="ListItem(Todo)")
  inspect(doc.get_checked(children[0]), content="true")
  inspect(doc.get_text(children[0]), content="done")
}

///|
test "import: divider with spaces" {
  let doc = block_doc_from_markdown("- - -\n", "alice")
  let children = doc.children(root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Divider")
}

///|
test "sync: full message converges two block docs" {
  let doc_a = BlockDoc::new("alice")
  let heading = doc_a.create_block(Heading(2))
  doc_a.set_text(heading, "Shared title")
  let todo = doc_a.create_block(ListItem(Todo))
  doc_a.set_text(todo, "ship sync")
  doc_a.set_checked(todo, true)

  let doc_b = BlockDoc::new("bob")
  doc_b.apply_remote_sync_message(doc_a.export_sync_message())

  inspect(block_doc_to_markdown(doc_b), content=block_doc_to_markdown(doc_a))
  let children = doc_b.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc_b.get_type(children[0]), content="Heading(2)")
  inspect(doc_b.get_type(children[1]), content="ListItem(Todo)")
  inspect(doc_b.get_checked(children[1]), content="true")
}

///|
test "sync: incremental message sends only missing block history" {
  let doc_a = BlockDoc::new("alice")
  let first = doc_a.create_block(Paragraph)
  doc_a.set_text(first, "first")

  let doc_b = BlockDoc::new("bob")
  doc_b.apply_remote_sync_message(doc_a.export_sync_message())
  let vv = doc_b.get_version_vector()

  let second = doc_a.create_block_after(first, Heading(3))
  doc_a.set_text(second, "later")
  doc_a.set_type(first, ListItem(Bullet))
  doc_a.set_text(first, "updated")

  doc_b.apply_remote_sync_message(doc_a.export_sync_message_since(vv))

  inspect(block_doc_to_markdown(doc_b), content=block_doc_to_markdown(doc_a))
  let children = doc_b.children(root_block_id)
  inspect(children.length(), content="2")
  inspect(doc_b.get_type(children[0]), content="ListItem(Bullet)")
  inspect(doc_b.get_text(children[0]), content="updated")
  inspect(doc_b.get_type(children[1]), content="Heading(3)")
  inspect(doc_b.get_text(children[1]), content="later")
}
