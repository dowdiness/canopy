// Whitebox tests for compute_text_edit

///|
/// Build a registry from a ProjNode tree.
fn text_edit_test_registry(root : ProjNode) -> Map[NodeId, ProjNode] {
  let registry : Map[NodeId, ProjNode] = {}
  fn register(node : ProjNode) {
    registry[node.id()] = node
    for child in node.children {
      register(child)
    }
  }
  register(root)
  registry
}

///|
/// Apply span edits to text (in reverse document order) and return the result.
fn apply_edits(text : String, edits : Array[SpanEdit]) -> String {
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  let mut result = text
  for edit in sorted {
    result = result[:edit.start].to_string() +
      edit.inserted +
      result[edit.start + edit.delete_len:].to_string()
  }
  result
}

///|
test "compute_text_edit: CommitEdit replaces single expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    CommitEdit(node_id=root_id, new_value="99"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].start, content="0")
      inspect(edits[0].delete_len, content="2")
      inspect(apply_edits(text, edits), content="99")
    }
    _ => abort("expected Some edits")
  }
}

///|
test "compute_text_edit: CommitEdit replaces left operand in binary expr" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // children[0] is the left operand (Var("x")), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=lhs.id(), new_value="y"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].start, content="0")
      inspect(edits[0].delete_len, content="1")
      inspect(apply_edits(text, edits), content="y + 1")
    }
    _ => abort("expected Some edits")
  }
}

///|
test "compute_text_edit: no-op ops return empty array" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    Select(node_id=NodeId(0)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result, content="Ok(Some([]))")
}

///|
test "compute_text_edit: unhandled ops return None" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    Delete(node_id=NodeId(0)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result, content="Ok(None)")
}

///|
test "compute_text_edit: CommitEdit with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    CommitEdit(node_id=NodeId(9999), new_value="x"),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}
