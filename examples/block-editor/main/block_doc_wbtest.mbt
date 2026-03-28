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
