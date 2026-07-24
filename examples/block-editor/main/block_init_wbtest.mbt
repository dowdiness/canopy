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
  let key = id.key()
  let parsed = parse_block_id(key)
  inspect(parsed.replica_id(), content="alice")
  inspect(parsed.sequence() == id.sequence(), content="true")
}

///|
test "parse_block_id: empty string falls back to root" {
  let parsed = parse_block_id("")
  inspect(parsed == @container.root_id, content="true")
}

///|
test "parse_block_id: no colon falls back to root" {
  let parsed = parse_block_id("no-colon-here")
  inspect(parsed == @container.root_id, content="true")
}

///|
test "parse_block_id: length prefix preserves colons" {
  let parsed = parse_block_id("17:agent:with:colons:42")
  inspect(parsed.replica_id(), content="agent:with:colons")
  inspect(parsed.sequence(), content="42")
}

///|
test "parse_block_id: virtual root key falls back to root" {
  let parsed = parse_block_id(@container.root_id.key())
  inspect(parsed == @container.root_id, content="true")
}

///|
test "parse_block_id: zero counter" {
  let parsed = parse_block_id("5:alice:0")
  inspect(parsed.replica_id(), content="alice")
  inspect(parsed.sequence(), content="0")
}

///|
test "write_json_escaped: special characters" {
  let buf = StringBuilder()
  buf.write_json_escaped("hello \"world\" \\ new\nline\ttab")
  inspect(buf.to_string(), content="hello \\\"world\\\" \\\\ new\\nline\\ttab")
}

///|
test "write_json_escaped: control characters" {
  let buf = StringBuilder()
  buf.write_json_escaped("\u0001")
  inspect(buf.to_string(), content="\\u0001")
}

///|
test "destroy_editor removes handle" {
  let h = create_editor("alice")
  destroy_editor(h)
  inspect(
    get_render_state(h),
    content=(
      #|{"block_count":0,"blocks":[]}
    ),
  )
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
  let first_id = doc.children(root_block_id)[0].key()
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
  let block_id = doc.children(root_block_id)[0].key()
  editor_set_block_type(h, block_id, "heading", 2, "")
  let json2 = get_render_state(h)
  inspect(String::contains(json2, "heading"), content="true")
  inspect(String::contains(json2, "Hello"), content="true")
}

///|
test "get_render_state includes depth and child_count" {
  let h = create_editor("test_depth")
  let doc = docs.get(h).unwrap()
  let parent = doc.create_block(Paragraph)
  doc.set_text(parent, "parent")
  let child = doc.create_block(Paragraph, parent~)
  doc.set_text(child, "child")
  let json = get_render_state(h)
  inspect(String::contains(json, "\"depth\":0"), content="true")
  inspect(String::contains(json, "\"depth\":1"), content="true")
  inspect(String::contains(json, "\"child_count\":1"), content="true")
  inspect(String::contains(json, "\"is_alive\":true"), content="true")
  let parent_key = parent.key()
  inspect(
    String::contains(json, "\"parent_id\":\"\{parent_key}\""),
    content="true",
  )
}
