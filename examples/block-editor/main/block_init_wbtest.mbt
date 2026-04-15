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
  let key = @container.tree_node_id_key(id)
  let parsed = parse_block_id(key)
  inspect(@container.tree_node_id_agent(parsed), content="alice")
  inspect(
    @container.tree_node_id_counter(parsed) ==
    @container.tree_node_id_counter(id),
    content="true",
  )
}

///|
test "parse_block_id: empty string falls back to root" {
  let parsed = parse_block_id("")
  inspect(
    @container.tree_node_id_eq(parsed, @container.root_id),
    content="true",
  )
}

///|
test "parse_block_id: no colon falls back to root" {
  let parsed = parse_block_id("no-colon-here")
  inspect(
    @container.tree_node_id_eq(parsed, @container.root_id),
    content="true",
  )
}

///|
test "parse_block_id: multiple colons splits on last" {
  let parsed = parse_block_id("agent:with:colons:42")
  inspect(@container.tree_node_id_agent(parsed), content="agent:with:colons")
  inspect(@container.tree_node_id_counter(parsed), content="42")
}

///|
test "parse_block_id: negative counter" {
  let parsed = parse_block_id("root:-1")
  inspect(@container.tree_node_id_agent(parsed), content="root")
  inspect(@container.tree_node_id_counter(parsed), content="-1")
}

///|
test "parse_block_id: zero counter" {
  let parsed = parse_block_id("alice:0")
  inspect(@container.tree_node_id_agent(parsed), content="alice")
  inspect(@container.tree_node_id_counter(parsed), content="0")
}

///|
test "write_json_escaped: special characters" {
  let buf = StringBuilder::new()
  write_json_escaped(buf, "hello \"world\" \\ new\nline\ttab")
  inspect(buf.to_string(), content="hello \\\"world\\\" \\\\ new\\nline\\ttab")
}

///|
test "write_json_escaped: control characters" {
  let buf = StringBuilder::new()
  // ASCII control char 0x01 (SOH)
  write_json_escaped(buf, "\u0001")
  inspect(buf.to_string(), content="\\u0001")
}

///|
test "destroy_editor removes handle" {
  let h = create_editor("alice")
  destroy_editor(h)
  inspect(get_render_state(h), content=(
    #|{"block_count":0,"blocks":[]}
  ))
}

///|
test "get_render_state returns block JSON" {
  let h = create_editor("test_render")
  let doc = docs.get(h).unwrap()
  let id = doc.create_block(Heading(2))
  doc.set_text(id, "Hello")
  let json = get_render_state(h)
  inspect(String::contains(json, "heading"), content="true")
  inspect(String::contains(json, "Hello"), content="true")
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
  inspect(String::contains(json1, "heading"), content="true")
  // Get the first block's id to insert after
  let doc = docs.get(h).unwrap()
  let first_id = @container.tree_node_id_key(doc.children(root_block_id)[0])
  let new_id = editor_insert_block_after(h, first_id, "paragraph")
  inspect(new_id.length() > 0, content="true")
  let json2 = get_render_state(h)
  inspect(String::contains(json2, "heading"), content="true")
  inspect(String::contains(json2, "paragraph"), content="true")
}

///|
test "editor_set_block_type changes type" {
  let h = create_editor("test_type")
  editor_import_markdown(h, "Hello\n")
  let json1 = get_render_state(h)
  inspect(String::contains(json1, "paragraph"), content="true")
  // Change to heading via bridge
  let doc = docs.get(h).unwrap()
  let block_id = @container.tree_node_id_key(doc.children(root_block_id)[0])
  editor_set_block_type(h, block_id, "heading", 2, "")
  let json2 = get_render_state(h)
  inspect(String::contains(json2, "heading"), content="true")
  inspect(String::contains(json2, "Hello"), content="true")
}
