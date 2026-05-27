///|
test "get_semantic_projection_json exposes free-variable overlay" {
  let handle = create_editor("semantic-ffi")
  set_text(handle, "λx. y")
  let json = get_semantic_projection_json(handle)
  assert_true(json.contains("\"semantic-free\""))
  assert_true(json.contains("Free variable 'y'"))
  destroy_editor(handle)
}

///|
test "rename_semantic_node rejects free references" {
  let handle = create_editor("semantic-free-rename-ffi")
  set_text(handle, "λx. y")
  let body_id = match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_proj_node() {
        Some(root) =>
          match root.children[0].id().to_json() {
            Json::Number(n, ..) => n.to_int()
            _ => fail("expected numeric node id")
          }
        None => fail("expected projection")
      }
    None => fail("expected handle")
  }
  inspect(
    rename_semantic_node(handle, body_id, "z", 0),
    content="error: node is not a semantic binder or reference",
  )
  inspect(get_text(handle), content="λx. y")
  destroy_editor(handle)
}

///|
test "rename_semantic_node renames let binder through flat binding id" {
  let handle = create_editor("semantic-let-rename-ffi")
  set_text(handle, "let x = 1\nx")
  let binding_id = match lambda_handles.get(handle) {
    Some(h) =>
      match h.companion.get_flat_proj() {
        Some(flat_proj) =>
          match flat_proj.defs[0].3.to_json() {
            Json::Number(n, ..) => n.to_int()
            _ => fail("expected numeric binding node id")
          }
        None => fail("expected flat projection")
      }
    None => fail("expected handle")
  }
  inspect(rename_semantic_node(handle, binding_id, "y", 0), content="ok")
  inspect(get_text(handle), content="let y = 1\ny")
  destroy_editor(handle)
}

///|
test "rename_semantic_node renames binder and usages through text edits" {
  let handle = create_editor("semantic-rename-ffi")
  set_text(handle, "λx. x")
  let body_id = match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_proj_node() {
        Some(root) =>
          match root.children[0].id().to_json() {
            Json::Number(n, ..) => n.to_int()
            _ => fail("expected numeric node id")
          }
        None => fail("expected projection")
      }
    None => fail("expected handle")
  }
  inspect(rename_semantic_node(handle, body_id, "y", 0), content="ok")
  inspect(get_text(handle), content="λy.y")
  destroy_editor(handle)
}
