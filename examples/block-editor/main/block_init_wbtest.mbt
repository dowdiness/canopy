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
}

///|
test "destroy_editor removes handle" {
  let h = create_editor("alice")
  destroy_editor(h)
  // get_render_state on destroyed handle returns empty
  inspect(get_render_state(h), content="{\"blocks\":[]}")
}
