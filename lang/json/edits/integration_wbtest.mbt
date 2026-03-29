// End-to-end integration tests for JSON editor pipeline.

///|
test "new_json_editor — create and get text" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  inspect(editor.get_text(), content="{\"a\": 1}")
}

///|
test "new_json_editor — projection pipeline works" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": true}")
  let proj = editor.get_proj_node()
  inspect(proj is Some(_), content="true")
  match proj {
    Some(p) => {
      inspect(p.kind is @json.Object(_), content="true")
      inspect(p.children.length(), content="2")
    }
    None => fail("expected projection")
  }
}

///|
test "new_json_editor — source map positions" {
  let editor = new_json_editor("test")
  editor.set_text("[1, 2, 3]")
  let sm = editor.get_source_map()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => inspect(sm.get_range(p.id()) is Some(_), content="true")
    None => fail("expected projection")
  }
}

///|
test "new_json_editor — reconcile preserves IDs" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": 2}")
  let id1 = match editor.get_proj_node() {
    Some(p) => p.node_id
    None => {
      fail("expected projection")
      return
    }
  }
  editor.set_text("{\"a\": 99, \"b\": 2}")
  let id2 = match editor.get_proj_node() {
    Some(p) => p.node_id
    None => {
      fail("expected projection")
      return
    }
  }
  inspect(id1 == id2, content="true")
}

///|
test "new_json_editor — get_flat_proj returns None" {
  let editor = new_json_editor("test")
  editor.set_text("{}")
  inspect(editor.get_flat_proj() is None, content="true")
}

///|
test "apply WrapInArray" {
  let editor = new_json_editor("test")
  editor.set_text("42")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(editor, WrapInArray(node_id=p.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="[42]")
    }
    None => fail("expected projection")
  }
}

///|
test "apply WrapInObject" {
  let editor = new_json_editor("test")
  editor.set_text("42")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        WrapInObject(node_id=p.id(), key="value"),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="{\"value\": 42}")
    }
    None => fail("expected projection")
  }
}

///|
test "apply AddMember to empty object" {
  let editor = new_json_editor("test")
  editor.set_text("{}")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        AddMember(object_id=p.id(), key="name"),
        0,
      )
      inspect(result is Ok(_), content="true")
      let text = editor.get_text()
      inspect(text.contains("\"name\""), content="true")
      inspect(text.contains("null"), content="true")
    }
    None => fail("expected projection")
  }
}

///|
test "apply AddMember to non-empty object" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        AddMember(object_id=p.id(), key="b"),
        0,
      )
      inspect(result is Ok(_), content="true")
      let text = editor.get_text()
      inspect(text.contains("\"b\""), content="true")
      inspect(text.contains("null"), content="true")
    }
    None => fail("expected projection")
  }
}

///|
test "apply AddElement to empty array" {
  let editor = new_json_editor("test")
  editor.set_text("[]")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(editor, AddElement(array_id=p.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="[null]")
    }
    None => fail("expected projection")
  }
}

///|
test "apply AddElement to non-empty array" {
  let editor = new_json_editor("test")
  editor.set_text("[1]")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(editor, AddElement(array_id=p.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="[1, null]")
    }
    None => fail("expected projection")
  }
}

///|
test "apply ChangeType" {
  let editor = new_json_editor("test")
  editor.set_text("null")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        ChangeType(node_id=p.id(), new_type=JArray),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="[]")
    }
    None => fail("expected projection")
  }
}

///|
test "apply ChangeType to object" {
  let editor = new_json_editor("test")
  editor.set_text("123")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        ChangeType(node_id=p.id(), new_type=JObject),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="{}")
    }
    None => fail("expected projection")
  }
}

///|
test "apply CommitEdit" {
  let editor = new_json_editor("test")
  editor.set_text("42")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        CommitEdit(node_id=p.id(), new_value="99"),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="99")
    }
    None => fail("expected projection")
  }
}

///|
test "error recovery — malformed JSON still produces projection" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": }")
  inspect(editor.get_proj_node() is Some(_), content="true")
}

///|
test "CommitEdit on value inside object preserves key" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      // p is the Object, p.children[0] is the value node for member "a"
      let value_node = p.children[0]
      let result = apply_json_edit(
        editor,
        CommitEdit(node_id=value_node.id(), new_value="99"),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(
        editor.get_text(),
        content=(
          #|{"a":99}
        ),
      )
    }
    None => fail("expected projection")
  }
}

///|
test "ChangeType on value inside object preserves key" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      let value_node = p.children[0]
      let result = apply_json_edit(
        editor,
        ChangeType(node_id=value_node.id(), new_type=JArray),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(
        editor.get_text(),
        content=(
          #|{"a":[]}
        ),
      )
    }
    None => fail("expected projection")
  }
}

///|
test "WrapInArray on value inside object preserves key" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      let value_node = p.children[0]
      let result = apply_json_edit(
        editor,
        WrapInArray(node_id=value_node.id()),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(
        editor.get_text(),
        content=(
          #|{"a":[ 1]}
        ),
      )
    }
    None => fail("expected projection")
  }
}

///|
test "WrapInObject on value inside object preserves key" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      let value_node = p.children[0]
      let result = apply_json_edit(
        editor,
        WrapInObject(node_id=value_node.id(), key="inner"),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(
        editor.get_text(),
        content=(
          #|{"a":{"inner":  1}}
        ),
      )
    }
    None => fail("expected projection")
  }
}

///|
test "Delete member from object with two members" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": 2}")
  match editor.get_proj_node() {
    Some(p) => {
      // Delete the first member (value node for "a")
      let value_a = p.children[0]
      let result = apply_json_edit(editor, Delete(node_id=value_a.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="{\"b\": 2}")
    }
    None => fail("expected projection")
  }
}

///|
test "Delete second member from object" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": 2}")
  match editor.get_proj_node() {
    Some(p) => {
      // Delete the second member (value node for "b")
      let value_b = p.children[1]
      let result = apply_json_edit(editor, Delete(node_id=value_b.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="{\"a\": 1}")
    }
    None => fail("expected projection")
  }
}

///|
test "RenameKey on object" {
  let editor = new_json_editor("test")
  editor.set_text("{\"old\": 1}")
  match editor.get_proj_node() {
    Some(p) => {
      let result = apply_json_edit(
        editor,
        RenameKey(object_id=p.id(), key_index=0, new_key="new"),
        0,
      )
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="{\"new\": 1}")
    }
    None => fail("expected projection")
  }
}
