// Whitebox tests for TreeEditorState using ProjNode + SourceMap directly.

///|
fn tree_editor_test_state(
  source : String,
) -> (ProjNode, SourceMap, TreeEditorState) {
  let (root, _) = parse_to_proj_node(source)
  let source_map = SourceMap::from_ast(root)
  (root, source_map, TreeEditorState::from_projection(Some(root), source_map))
}

///|
fn tree_editor_test_ids(tree : InteractiveTreeNode?) -> Array[NodeId] {
  let result : Array[NodeId] = []
  match tree {
    None => ()
    Some(node) => tree_editor_test_collect(node, result)
  }
  result
}

///|
fn tree_editor_test_collect(
  node : InteractiveTreeNode,
  result : Array[NodeId],
) -> Unit {
  result.push(node.id)
  for child in node.children {
    tree_editor_test_collect(child, result)
  }
}

///|
test "TreeEditorState::new creates empty state" {
  let state = TreeEditorState::new()
  inspect(state.tree is None, content="true")
  inspect(state.selection.length(), content="0")
  inspect(state.editing_node is None, content="true")
  inspect(state.dragging is None, content="true")
  inspect(state.drop_target is None, content="true")
}

///|
test "Collapse sets collapsed state on node" {
  let (_, _, state) = tree_editor_test_state("λx.x + 1")
  let root_id = tree_editor_test_ids(state.tree)[0]
  let collapsed = state.apply_edit(Collapse(node_id=root_id))
  inspect(collapsed.collapsed_nodes.contains(root_id), content="true")
  match find_node(collapsed.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="true")
    None => abort("Node not found")
  }
}

///|
test "Expand clears collapsed state on node" {
  let (_, _, state) = tree_editor_test_state("λx.x + 1")
  let root_id = tree_editor_test_ids(state.tree)[0]
  let expanded = state
    .apply_edit(Collapse(node_id=root_id))
    .apply_edit(Expand(node_id=root_id))
  inspect(expanded.collapsed_nodes.contains(root_id), content="false")
  match find_node(expanded.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="false")
    None => abort("Node not found")
  }
}

///|
test "Collapse state survives refresh" {
  let (root, source_map, state) = tree_editor_test_state("λx.x + 1")
  let root_id = tree_editor_test_ids(state.tree)[0]
  let refreshed = state
    .apply_edit(Collapse(node_id=root_id))
    .refresh(Some(root), source_map)
  inspect(refreshed.collapsed_nodes.contains(root_id), content="true")
  match find_node(refreshed.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="true")
    None => abort("Node not found")
  }
}

///|
test "SelectRange collects nodes in preorder" {
  let (_, _, state) = tree_editor_test_state("1 + 2")
  let ids = tree_editor_test_ids(state.tree)
  let selected = state.apply_edit(SelectRange(start=ids[0], end=ids[2]))
  inspect(selected.selection.length(), content="3")
  inspect(selected.selection[0] == ids[0], content="true")
  inspect(selected.selection[2] == ids[2], content="true")
}

///|
test "Delete clears selection editing dragging and collapsed state" {
  let (_, _, state) = tree_editor_test_state("λx.x + 1")
  let ids = tree_editor_test_ids(state.tree)
  let target = ids[1]
  let deleted = state
    .apply_edit(Select(node_id=target))
    .apply_edit(StartEdit(node_id=target))
    .apply_edit(Collapse(node_id=target))
    .apply_edit(StartDrag(node_id=target))
    .apply_edit(Delete(node_id=target))
  inspect(deleted.selection.length(), content="0")
  inspect(deleted.editing_node is None, content="true")
  inspect(deleted.edit_value, content="")
  inspect(deleted.dragging is None, content="true")
  inspect(deleted.collapsed_nodes.contains(target), content="false")
}

///|
test "Delete clears drop target for removed node" {
  let (_, _, state) = tree_editor_test_state("1 + 2")
  let ids = tree_editor_test_ids(state.tree)
  let deleted = state
    .apply_edit(StartDrag(node_id=ids[1]))
    .apply_edit(DragOver(target=ids[2], position=After))
    .apply_edit(Delete(node_id=ids[2]))
  inspect(deleted.drop_target is None, content="true")
  inspect(deleted.drop_position is None, content="true")
}

///|
test "DragOver rejects self as drop target" {
  let (_, _, state) = tree_editor_test_state("1 + 2")
  let ids = tree_editor_test_ids(state.tree)
  let dragover = state
    .apply_edit(StartDrag(node_id=ids[1]))
    .apply_edit(DragOver(target=ids[1], position=After))
  inspect(dragover.drop_target is None, content="true")
}

///|
test "WrapInLambda keeps wrapped node selected" {
  let (_, _, state) = tree_editor_test_state("x")
  let root_id = tree_editor_test_ids(state.tree)[0]
  let updated = state.apply_edit(WrapInLambda(node_id=root_id, var_name="y"))
  inspect(updated.selection.length(), content="1")
  inspect(updated.selection[0] == root_id, content="true")
}

///|
test "refresh prunes stale ids from UI state" {
  let (root, source_map, state) = tree_editor_test_state("1 + 2")
  let ids = tree_editor_test_ids(state.tree)
  let stale_id = NodeId(9999)
  let stale_state = {
    ..state,
    selection: [ids[0], stale_id],
    editing_node: Some(stale_id),
    edit_value: "stale",
    dragging: Some(stale_id),
    drop_target: Some(stale_id),
    drop_position: Some(After),
    collapsed_nodes: state.collapsed_nodes.add(ids[0]).add(stale_id),
  }
  let refreshed = stale_state.refresh(Some(root), source_map)
  inspect(refreshed.selection.length(), content="1")
  inspect(refreshed.selection[0] == ids[0], content="true")
  inspect(refreshed.editing_node is None, content="true")
  inspect(refreshed.edit_value, content="")
  inspect(refreshed.dragging is None, content="true")
  inspect(refreshed.drop_target is None, content="true")
  inspect(refreshed.drop_position is None, content="true")
  inspect(refreshed.collapsed_nodes.contains(ids[0]), content="true")
  inspect(refreshed.collapsed_nodes.contains(stale_id), content="false")
}
