///|
fn string_contains(s : String, sub : String) -> Bool {
  if sub.length() > s.length() {
    return false
  }
  for i = 0; i <= s.length() - sub.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < sub.length(); j = j + 1 {
      if s[i + j] != sub[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}

///|
test "create_editor returns incrementing handles" {
  let h1 = create_editor("alice")
  let h2 = create_editor("bob")
  inspect(h1 != h2, content="true")
}

///|
test "parse_block_id round-trips with id_key" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Paragraph)
  let key = id_key(id)
  let parsed = parse_block_id(key)
  inspect(@tree.tree_node_id_agent(parsed), content="alice")
  inspect(
    @tree.tree_node_id_counter(parsed) == @tree.tree_node_id_counter(id),
    content="true",
  )
}

///|
test "destroy_editor removes handle" {
  let h = create_editor("alice")
  destroy_editor(h)
  inspect(get_render_state(h), content="{\"blocks\":[]}")
}

///|
test "get_render_state returns block JSON" {
  let h = create_editor("test_render")
  with_doc(h, fn(doc) {
    let id = doc.create_block(Heading(2))
    doc.set_text(id, "Hello")
  })
  let json = get_render_state(h)
  inspect(string_contains(json, "heading"), content="true")
  inspect(string_contains(json, "Hello"), content="true")
}

///|
test "editor_import_and_export_markdown round-trips" {
  let h = create_editor("test_md")
  let md = "# Title\n\nSome text\n"
  editor_import_markdown(h, md)
  let out = editor_export_markdown(h)
  inspect(out, content="# Title\n\nSome text\n")
}

///|
test "editor_insert_block_after creates block" {
  let h = create_editor("test_insert")
  editor_import_markdown(h, "# Title\n")
  let json1 = get_render_state(h)
  inspect(string_contains(json1, "Title"), content="true")
  // Extract the block id from JSON and insert after it
  let state1 = get_render_state(h)
  // The id is in format "test_insert:N" — find it
  // Insert a paragraph after the first block
  let children_before = state1
  inspect(string_contains(children_before, "heading"), content="true")
  // Use the bridge to insert — we need the id string
  // Import gives us one block; get its id via render state
  with_doc(h, fn(doc) {
    let kids = doc.children(root_block_id)
    let first_id = id_key(kids[0])
    let new_id = editor_insert_block_after(h, first_id, "paragraph")
    // Verify new block was created
    inspect(new_id.length() > 0, content="true")
  })
  let json2 = get_render_state(h)
  // Should now have 2 blocks: heading + paragraph
  inspect(string_contains(json2, "heading"), content="true")
  inspect(string_contains(json2, "paragraph"), content="true")
}

///|
test "editor_set_block_type changes type" {
  let h = create_editor("test_type")
  editor_import_markdown(h, "Hello\n")
  let json1 = get_render_state(h)
  inspect(string_contains(json1, "paragraph"), content="true")
  // Change to heading via bridge
  with_doc(h, fn(doc) {
    let kids = doc.children(root_block_id)
    let block_id = id_key(kids[0])
    editor_set_block_type(h, block_id, "heading", 2, "")
  })
  let json2 = get_render_state(h)
  inspect(string_contains(json2, "heading"), content="true")
  inspect(string_contains(json2, "Hello"), content="true")
}
