// Whitebox tests for TreeEditorState

///|
/// Helper to create a tree editor state from source code
fn create_editor_state(source : String) -> TreeEditorState {
  let (ast, _) = parse_to_proj_node(source)
  let model = CanonicalModel::from_ast(ast)
  TreeEditorState::from_model(model)
}

///|
/// Helper to get node IDs from a tree in pre-order
fn collect_all_node_ids(tree : InteractiveTreeNode?) -> Array[NodeId] {
  let result : Array[NodeId] = []
  match tree {
    None => ()
    Some(node) => collect_ids_helper(node, result)
  }
  result
}

///|
fn collect_ids_helper(
  node : InteractiveTreeNode,
  result : Array[NodeId],
) -> Unit {
  result.push(node.id)
  for child in node.children {
    collect_ids_helper(child, result)
  }
}

// ============================================================================
// Tests for Collapse/Expand
// ============================================================================

///|
test "Collapse sets collapsed state on node" {
  let state = create_editor_state("λx.x + 1")
  let ids = collect_all_node_ids(state.tree)
  // Collapse the first node (root)
  let root_id = ids[0]
  let new_state = state.apply_edit(Collapse(node_id=root_id))
  // Check collapsed_nodes set contains the ID
  inspect(new_state.collapsed_nodes.contains(root_id), content="true")
  // Check tree node is marked collapsed
  match find_node(new_state.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="true")
    None => abort("Node not found")
  }
}

///|
test "Expand clears collapsed state on node" {
  let state = create_editor_state("λx.x + 1")
  let ids = collect_all_node_ids(state.tree)
  let root_id = ids[0]
  // First collapse, then expand
  let collapsed_state = state.apply_edit(Collapse(node_id=root_id))
  let expanded_state = collapsed_state.apply_edit(Expand(node_id=root_id))
  // Check collapsed_nodes set no longer contains the ID
  inspect(expanded_state.collapsed_nodes.contains(root_id), content="false")
  // Check tree node is not collapsed
  match find_node(expanded_state.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="false")
    None => abort("Node not found")
  }
}

///|
test "Collapse preserves state across refresh_from_model" {
  let (ast, _) = parse_to_proj_node("λx.x + 1")
  let model = CanonicalModel::from_ast(ast)
  let state = TreeEditorState::from_model(model)
  let ids = collect_all_node_ids(state.tree)
  let root_id = ids[0]
  // Collapse the root
  let collapsed_state = state.apply_edit(Collapse(node_id=root_id))
  // Refresh from model (simulating model update)
  let refreshed_state = collapsed_state.refresh_from_model(model)
  // Collapsed state should be preserved
  inspect(refreshed_state.collapsed_nodes.contains(root_id), content="true")
  match find_node(refreshed_state.tree, root_id) {
    Some(node) => inspect(node.collapsed, content="true")
    None => abort("Node not found")
  }
}

///|
test "Multiple nodes can be collapsed independently" {
  let state = create_editor_state("(λx.x) (λy.y)")
  let ids = collect_all_node_ids(state.tree)
  // Collapse two different nodes
  let state2 = state.apply_edit(Collapse(node_id=ids[0]))
  let state3 = state2.apply_edit(Collapse(node_id=ids[1]))
  inspect(state3.collapsed_nodes.contains(ids[0]), content="true")
  inspect(state3.collapsed_nodes.contains(ids[1]), content="true")
  // Expand one
  let state4 = state3.apply_edit(Expand(node_id=ids[0]))
  inspect(state4.collapsed_nodes.contains(ids[0]), content="false")
  inspect(state4.collapsed_nodes.contains(ids[1]), content="true")
}

// ============================================================================
// Tests for Select and SelectRange
// ============================================================================

///|
test "Select sets single node selection" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(Select(node_id=ids[1]))
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == ids[1], content="true")
}

///|
test "SelectRange collects nodes between start and end" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Select from first child to second child
  // Tree structure: Bop(+) -> [Int(1), Int(2)]
  // Pre-order: Bop, Int(1), Int(2)
  let new_state = state.apply_edit(SelectRange(start=ids[0], end=ids[2]))
  // Should select all three nodes
  inspect(new_state.selection.length(), content="3")
}

///|
test "SelectRange with same start and end selects single node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(SelectRange(start=ids[1], end=ids[1]))
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == ids[1], content="true")
}

// ============================================================================
// Tests for Delete
// ============================================================================

///|
test "Delete clears selection if deleted node was selected" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Select a node
  let selected_state = state.apply_edit(Select(node_id=ids[1]))
  inspect(selected_state.selection.length(), content="1")
  // Delete the selected node
  let deleted_state = selected_state.apply_edit(Delete(node_id=ids[1]))
  // Selection should be cleared
  inspect(deleted_state.selection.length(), content="0")
}

///|
test "Delete preserves selection of other nodes" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Select root node
  let selected_state = state.apply_edit(Select(node_id=ids[0]))
  // Delete a different node
  let deleted_state = selected_state.apply_edit(Delete(node_id=ids[1]))
  // Selection of root should be preserved
  inspect(deleted_state.selection.length(), content="1")
  inspect(deleted_state.selection[0] == ids[0], content="true")
}

///|
test "Delete clears editing state if editing deleted node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Start editing a node
  let editing_state = state.apply_edit(StartEdit(node_id=ids[1]))
  inspect(editing_state.editing_node is Some(_), content="true")
  // Delete the editing node
  let deleted_state = editing_state.apply_edit(Delete(node_id=ids[1]))
  // Editing should be cancelled
  inspect(deleted_state.editing_node is None, content="true")
  inspect(deleted_state.edit_value, content="")
}

///|
test "Delete removes node from collapsed set" {
  let state = create_editor_state("λx.x + 1")
  let ids = collect_all_node_ids(state.tree)
  // Collapse a node
  let collapsed_state = state.apply_edit(Collapse(node_id=ids[1]))
  inspect(collapsed_state.collapsed_nodes.contains(ids[1]), content="true")
  // Delete that node
  let deleted_state = collapsed_state.apply_edit(Delete(node_id=ids[1]))
  // Should be removed from collapsed set
  inspect(deleted_state.collapsed_nodes.contains(ids[1]), content="false")
}

///|
test "Delete clears entire subtree from collapsed set" {
  let state = create_editor_state("λx.λy.x + y")
  let ids = collect_all_node_ids(state.tree)
  // Collapse multiple nodes in a subtree
  let state2 = state.apply_edit(Collapse(node_id=ids[1]))
  let state3 = state2.apply_edit(Collapse(node_id=ids[2]))
  inspect(state3.collapsed_nodes.contains(ids[1]), content="true")
  inspect(state3.collapsed_nodes.contains(ids[2]), content="true")
  // Delete the parent (should clean up entire subtree)
  let deleted_state = state3.apply_edit(Delete(node_id=ids[0]))
  // All subtree nodes should be removed from collapsed set
  inspect(deleted_state.collapsed_nodes.contains(ids[0]), content="false")
  inspect(deleted_state.collapsed_nodes.contains(ids[1]), content="false")
  inspect(deleted_state.collapsed_nodes.contains(ids[2]), content="false")
}

///|
test "Delete clears dragging state if dragging deleted node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Start dragging a node
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  inspect(dragging_state.dragging is Some(_), content="true")
  // Delete the dragging node
  let deleted_state = dragging_state.apply_edit(Delete(node_id=ids[1]))
  // Dragging should be cleared
  inspect(deleted_state.dragging is None, content="true")
}

///|
test "Delete clears drop_target if targeting deleted node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Set up drag with drop target
  let drag_state = state.apply_edit(StartDrag(node_id=ids[1]))
  let target_state = drag_state.apply_edit(
    DragOver(target=ids[2], position=After),
  )
  inspect(target_state.drop_target is Some(_), content="true")
  // Delete the drop target
  let deleted_state = target_state.apply_edit(Delete(node_id=ids[2]))
  // Drop target should be cleared
  inspect(deleted_state.drop_target is None, content="true")
  inspect(deleted_state.drop_position is None, content="true")
}

// ============================================================================
// Tests for WrapInLambda and WrapInApp
// ============================================================================

///|
test "WrapInLambda keeps wrapped node selected" {
  let state = create_editor_state("x")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(WrapInLambda(node_id=ids[0], var_name="y"))
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == ids[0], content="true")
}

///|
test "WrapInApp keeps wrapped node selected" {
  let state = create_editor_state("x")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(WrapInApp(node_id=ids[0]))
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == ids[0], content="true")
}

// ============================================================================
// Tests for InsertChild
// ============================================================================

///|
test "InsertChild selects parent node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let parent_id = ids[0]
  let new_state = state.apply_edit(
    InsertChild(parent=parent_id, index=0, kind=@ast.Term::Int(0)),
  )
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == parent_id, content="true")
}

// ============================================================================
// Tests for Drag and Drop
// ============================================================================

///|
test "StartDrag sets dragging state" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(StartDrag(node_id=ids[1]))
  inspect(new_state.dragging is Some(_), content="true")
  match new_state.dragging {
    Some(id) => inspect(id == ids[1], content="true")
    None => abort("Expected dragging to be set")
  }
}

///|
test "StartDrag clears stale drop state" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Set up a previous drag with drop target
  let drag1 = state.apply_edit(StartDrag(node_id=ids[1]))
  let with_target = drag1.apply_edit(DragOver(target=ids[2], position=After))
  inspect(with_target.drop_target is Some(_), content="true")
  inspect(with_target.drop_position is Some(_), content="true")
  // Start a new drag - should clear stale drop state
  let drag2 = with_target.apply_edit(StartDrag(node_id=ids[0]))
  inspect(drag2.drop_target is None, content="true")
  inspect(drag2.drop_position is None, content="true")
}

///|
test "DragOver sets drop target and position" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  let dragover_state = dragging_state.apply_edit(
    DragOver(target=ids[2], position=After),
  )
  inspect(dragover_state.drop_target is Some(_), content="true")
  inspect(dragover_state.drop_position is Some(_), content="true")
}

///|
test "Drop clears drag state and selects dropped node" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  let dragover_state = dragging_state.apply_edit(
    DragOver(target=ids[2], position=After),
  )
  let dropped_state = dragover_state.apply_edit(
    Drop(source=ids[1], target=ids[2], position=After),
  )
  // Drag state should be cleared
  inspect(dropped_state.dragging is None, content="true")
  inspect(dropped_state.drop_target is None, content="true")
  inspect(dropped_state.drop_position is None, content="true")
  // Source node should be selected
  inspect(dropped_state.selection.length(), content="1")
  inspect(dropped_state.selection[0] == ids[1], content="true")
}

// ============================================================================
// Tests for StartEdit/CommitEdit/CancelEdit
// ============================================================================

///|
test "StartEdit sets editing state with node label" {
  let state = create_editor_state("42")
  let ids = collect_all_node_ids(state.tree)
  let new_state = state.apply_edit(StartEdit(node_id=ids[0]))
  inspect(new_state.editing_node is Some(_), content="true")
  inspect(new_state.edit_value, content="42")
}

///|
test "CommitEdit clears editing state" {
  let state = create_editor_state("42")
  let ids = collect_all_node_ids(state.tree)
  let editing_state = state.apply_edit(StartEdit(node_id=ids[0]))
  let committed_state = editing_state.apply_edit(
    CommitEdit(node_id=ids[0], new_value="100"),
  )
  inspect(committed_state.editing_node is None, content="true")
  inspect(committed_state.edit_value, content="")
}

///|
test "CancelEdit clears editing state" {
  let state = create_editor_state("42")
  let ids = collect_all_node_ids(state.tree)
  let editing_state = state.apply_edit(StartEdit(node_id=ids[0]))
  let cancelled_state = editing_state.apply_edit(CancelEdit)
  inspect(cancelled_state.editing_node is None, content="true")
  inspect(cancelled_state.edit_value, content="")
}

// ============================================================================
// Tests for from_term_node_with_state
// ============================================================================

///|
test "from_term_node_with_state applies collapsed state" {
  let (ast, _) = parse_to_proj_node("λx.x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  // Create collapsed set with root (immutable)
  let collapsed_nodes = @immut/hashset.new().add(root_id)
  // Create tree with collapsed state
  let tree = InteractiveTreeNode::from_term_node_with_state(
    ast,
    model.get_source_map(),
    collapsed_nodes,
  )
  inspect(tree.collapsed, content="true")
}

///|
test "from_term_node_with_state preserves non-collapsed nodes" {
  let (ast, _) = parse_to_proj_node("λx.x")
  let model = CanonicalModel::from_ast(ast)
  // Empty collapsed set (immutable)
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let tree = InteractiveTreeNode::from_term_node_with_state(
    ast,
    model.get_source_map(),
    collapsed_nodes,
  )
  inspect(tree.collapsed, content="false")
  // Children should also not be collapsed
  for child in tree.children {
    inspect(child.collapsed, content="false")
  }
}

// ============================================================================
// Tests for TreeEditorState::new
// ============================================================================

///|
test "TreeEditorState::new creates empty state" {
  let state = TreeEditorState::new()
  inspect(state.tree is None, content="true")
  inspect(state.selection.length(), content="0")
  inspect(state.editing_node is None, content="true")
  inspect(state.edit_value, content="")
  inspect(state.dragging is None, content="true")
  inspect(state.drop_target is None, content="true")
  inspect(state.drop_position is None, content="true")
  inspect(state.collapsed_nodes.length(), content="0")
}

// ============================================================================
// Tests for collect_nodes_in_range edge cases
// ============================================================================

///|
test "SelectRange on empty tree returns empty selection" {
  let state = TreeEditorState::new()
  let new_state = state.apply_edit(SelectRange(start=NodeId(0), end=NodeId(1)))
  inspect(new_state.selection.length(), content="0")
}

///|
test "SelectRange with missing start returns empty selection" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Use a non-existent start ID (simulates stale ID after model refresh)
  let missing_id = NodeId(9999)
  let new_state = state.apply_edit(SelectRange(start=missing_id, end=ids[1]))
  // Should return empty to avoid stale references
  inspect(new_state.selection.length(), content="0")
}

///|
test "SelectRange with missing end returns empty selection" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Use a non-existent end ID (simulates stale ID after model refresh)
  let missing_id = NodeId(9999)
  let new_state = state.apply_edit(SelectRange(start=ids[0], end=missing_id))
  // Should return empty to avoid stale references
  inspect(new_state.selection.length(), content="0")
}

///|
test "SelectRange with both missing on empty selection stays empty" {
  let state = create_editor_state("1 + 2")
  // No prior selection, both IDs stale
  let new_state = state.apply_edit(
    SelectRange(start=NodeId(9998), end=NodeId(9999)),
  )
  inspect(new_state.selection.length(), content="0")
}

///|
test "SelectRange with both missing preserves existing selection" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // First select a node
  let selected_state = state.apply_edit(Select(node_id=ids[0]))
  inspect(selected_state.selection.length(), content="1")
  // Try range select with both stale IDs
  let new_state = selected_state.apply_edit(
    SelectRange(start=NodeId(9998), end=NodeId(9999)),
  )
  // Existing selection should be preserved
  inspect(new_state.selection.length(), content="1")
  inspect(new_state.selection[0] == ids[0], content="true")
}

///|
test "SelectRange with reversed order selects same nodes as forward order" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Select from first to last (forward)
  let forward_state = state.apply_edit(SelectRange(start=ids[0], end=ids[2]))
  // Select from last to first (reversed)
  let reversed_state = state.apply_edit(SelectRange(start=ids[2], end=ids[0]))
  // Both should select the same 3 nodes
  inspect(forward_state.selection.length(), content="3")
  inspect(reversed_state.selection.length(), content="3")
  // Verify exact same nodes are selected (in tree order)
  for i, id in forward_state.selection {
    inspect(id == reversed_state.selection[i], content="true")
  }
}

// ============================================================================
// Tests for Drag/Drop Guards
// ============================================================================

///|
test "DragOver ignored when not dragging" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // DragOver without StartDrag should be ignored
  let new_state = state.apply_edit(DragOver(target=ids[1], position=After))
  inspect(new_state.drop_target is None, content="true")
  inspect(new_state.drop_position is None, content="true")
}

///|
test "DragOver rejects self as drop target" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  // Try to drag over self - should be rejected
  let dragover_state = dragging_state.apply_edit(
    DragOver(target=ids[1], position=After),
  )
  inspect(dragover_state.drop_target is None, content="true")
}

///|
test "DragOver rejects descendant as drop target" {
  let state = create_editor_state("λx.x + 1")
  let ids = collect_all_node_ids(state.tree)
  // Drag root, try to drop on child
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[0]))
  let dragover_state = dragging_state.apply_edit(
    DragOver(target=ids[1], position=Inside),
  )
  inspect(dragover_state.drop_target is None, content="true")
}

///|
test "Drop ignored when not dragging" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  // Try to drop without dragging - should be ignored
  let new_state = state.apply_edit(
    Drop(source=ids[1], target=ids[2], position=After),
  )
  // State should be unchanged (no selection change since not valid)
  inspect(new_state.selection.length(), content="0")
}

///|
test "Drop rejects mismatched source" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  // Try to drop with different source than what's being dragged
  let dropped_state = dragging_state.apply_edit(
    Drop(source=ids[0], target=ids[2], position=After),
  )
  // Should clear drag state but not select since invalid
  inspect(dropped_state.dragging is None, content="true")
  inspect(dropped_state.selection.length(), content="0")
}

///|
test "Drop rejects self as target" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let dragging_state = state.apply_edit(StartDrag(node_id=ids[1]))
  // Try to drop on self
  let dropped_state = dragging_state.apply_edit(
    Drop(source=ids[1], target=ids[1], position=After),
  )
  // Should clear drag state but not select since invalid
  inspect(dropped_state.dragging is None, content="true")
  inspect(dropped_state.selection.length(), content="0")
}

// ============================================================================
// Tests for Collapse/Expand Guards
// ============================================================================

///|
test "Collapse on missing node is no-op" {
  let state = create_editor_state("1 + 2")
  let missing_id = NodeId(9999)
  let new_state = state.apply_edit(Collapse(node_id=missing_id))
  // Should not add to collapsed_nodes
  inspect(new_state.collapsed_nodes.contains(missing_id), content="false")
}

///|
test "Expand on missing node is no-op" {
  let state = create_editor_state("1 + 2")
  let missing_id = NodeId(9999)
  let new_state = state.apply_edit(Expand(node_id=missing_id))
  // Should be a no-op
  inspect(new_state.collapsed_nodes.length(), content="0")
}

// ============================================================================
// Tests for Copy-on-Write (Aliasing Prevention)
// ============================================================================

///|
test "Collapse uses copy-on-write for collapsed_nodes" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let collapsed_state = state.apply_edit(Collapse(node_id=ids[0]))
  // Original state should NOT be mutated
  inspect(state.collapsed_nodes.contains(ids[0]), content="false")
  // New state should have the collapsed node
  inspect(collapsed_state.collapsed_nodes.contains(ids[0]), content="true")
}

///|
test "Expand uses copy-on-write for collapsed_nodes" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let collapsed_state = state.apply_edit(Collapse(node_id=ids[0]))
  let expanded_state = collapsed_state.apply_edit(Expand(node_id=ids[0]))
  // Collapsed state should NOT be mutated
  inspect(collapsed_state.collapsed_nodes.contains(ids[0]), content="true")
  // Expanded state should not have the node
  inspect(expanded_state.collapsed_nodes.contains(ids[0]), content="false")
}

///|
test "Delete uses copy-on-write for collapsed_nodes" {
  let state = create_editor_state("1 + 2")
  let ids = collect_all_node_ids(state.tree)
  let collapsed_state = state.apply_edit(Collapse(node_id=ids[1]))
  let deleted_state = collapsed_state.apply_edit(Delete(node_id=ids[1]))
  // Collapsed state should NOT be mutated
  inspect(collapsed_state.collapsed_nodes.contains(ids[1]), content="true")
  // Deleted state should have removed it
  inspect(deleted_state.collapsed_nodes.contains(ids[1]), content="false")
}

// ============================================================================
// Tests for refresh_from_model stale ID pruning
// ============================================================================

///|
test "refresh_from_model prunes stale selection IDs" {
  let (ast, _) = parse_to_proj_node("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let state = TreeEditorState::from_model(model)
  let ids = collect_all_node_ids(state.tree)
  // Select a node
  let selected_state = state.apply_edit(Select(node_id=ids[1]))
  // Add a stale ID to selection manually (simulating model change)
  let stale_id = NodeId(9999)
  let with_stale : TreeEditorState = {
    ..selected_state,
    selection: [ids[1], stale_id],
  }
  // Refresh should prune the stale ID
  let refreshed = with_stale.refresh_from_model(model)
  inspect(refreshed.selection.length(), content="1")
  inspect(refreshed.selection[0] == ids[1], content="true")
}

///|
test "refresh_from_model clears stale editing_node" {
  let (ast, _) = parse_to_proj_node("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let state = TreeEditorState::from_model(model)
  // Set editing_node to a stale ID
  let stale_id = NodeId(9999)
  let with_stale : TreeEditorState = {
    ..state,
    editing_node: Some(stale_id),
    edit_value: "test",
  }
  // Refresh should clear it
  let refreshed = with_stale.refresh_from_model(model)
  inspect(refreshed.editing_node is None, content="true")
  inspect(refreshed.edit_value, content="")
}

///|
test "refresh_from_model prunes stale collapsed_nodes" {
  let (ast, _) = parse_to_proj_node("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let state = TreeEditorState::from_model(model)
  let ids = collect_all_node_ids(state.tree)
  // Collapse a valid node
  let collapsed_state = state.apply_edit(Collapse(node_id=ids[0]))
  // Add a stale ID to collapsed_nodes (create new state with stale ID)
  let stale_id = NodeId(9999)
  let with_stale : TreeEditorState = {
    ..collapsed_state,
    collapsed_nodes: collapsed_state.collapsed_nodes.add(stale_id),
  }
  // Refresh should prune the stale ID
  let refreshed = with_stale.refresh_from_model(model)
  inspect(refreshed.collapsed_nodes.contains(ids[0]), content="true")
  inspect(refreshed.collapsed_nodes.contains(stale_id), content="false")
}
