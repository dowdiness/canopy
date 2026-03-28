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
  let doc = docs.get(h).unwrap()
  let id = doc.create_block(Heading(2))
  doc.set_text(id, "Hello")
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
  inspect(string_contains(json1, "heading"), content="true")
  // Get the first block's id to insert after
  let doc = docs.get(h).unwrap()
  let first_id = id_key(doc.children(root_block_id)[0])
  let new_id = editor_insert_block_after(h, first_id, "paragraph")
  inspect(new_id.length() > 0, content="true")
  let json2 = get_render_state(h)
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
  let doc = docs.get(h).unwrap()
  let block_id = id_key(doc.children(root_block_id)[0])
  editor_set_block_type(h, block_id, "heading", 2, "")
  let json2 = get_render_state(h)
  inspect(string_contains(json2, "heading"), content="true")
  inspect(string_contains(json2, "Hello"), content="true")
}
