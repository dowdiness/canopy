// Whitebox tests for TreeEditorState using ProjNode + SourceMap directly.

///|
fn tree_editor_test_state(
  source : String,
) -> (ProjNode[@ast.Term], SourceMap, TreeEditorState[@ast.Term]) {
  let (root, _) = @lambda_proj.parse_to_proj_node(source)
  let source_map = SourceMap::from_ast(root)
  (root, source_map, TreeEditorState::from_projection(Some(root), source_map))
}

///|
fn tree_editor_test_ids(
  tree : InteractiveTreeNode[@ast.Term]?,
) -> Array[NodeId] {
  let result : Array[NodeId] = []
  match tree {
    None => ()
    Some(node) => tree_editor_test_collect(node, result)
  }
  result
}

///|
fn tree_editor_test_collect(
  node : InteractiveTreeNode[@ast.Term],
  result : Array[NodeId],
) -> Unit {
  result.push(node.id)
  match node.children {
    Loaded(children) =>
      for child in children {
        tree_editor_test_collect(child, result)
      }
    Elided(_) => ()
  }
}

///|
fn tree_editor_test_loaded_children(
  node : InteractiveTreeNode[@ast.Term],
) -> Array[InteractiveTreeNode[@ast.Term]] raise {
  match node.children {
    Loaded(children) => children
    Elided(_) => fail("expected loaded children")
  }
}

///|
fn tree_editor_test_elided_descendant_count(
  node : InteractiveTreeNode[@ast.Term],
) -> Int raise {
  match node.children {
    Elided(descendant_count) => descendant_count
    Loaded(_) => fail("expected elided children")
  }
}

///|
fn tree_editor_test_refresh_minimal(
  node : ProjNode[@ast.Term],
  source_map : SourceMap,
  ui_state : TreeUIState,
  previous_nodes : Map[NodeId, InteractiveTreeNode[@ast.Term]],
) -> RefreshedInteractiveNode[@ast.Term] {
  let new_loaded_nodes : Map[NodeId, InteractiveTreeNode[@ast.Term]] = {}
  refresh_node_minimal(
    node, source_map, ui_state, previous_nodes, new_loaded_nodes,
  )
}

///|
test "refresh_node_minimal skips unchanged subtrees" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 4)")
  let old_source_map = SourceMap::from_ast(old_root)
  let state = TreeEditorState::from_projection(Some(old_root), old_source_map)
  let (new_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 5)")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(1000))
  let source_map = SourceMap::from_ast(reconciled)
  let ui_state : TreeUIState = {
    collapsed_nodes: @immut/hashset.new(),
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  let new_loaded_nodes : Map[NodeId, InteractiveTreeNode[@ast.Term]] = {}
  let left_result = refresh_node_minimal(
    reconciled.children[0],
    source_map,
    ui_state,
    state.loaded_nodes,
    new_loaded_nodes,
  )
  // Left subtree is unchanged — should be reused AND children carried over
  inspect(left_result.reused_previous, content="true")
  // All left subtree nodes should be carried over to new_loaded_nodes
  let old_tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let left_children = tree_editor_test_loaded_children(
    tree_editor_test_loaded_children(old_tree)[0],
  )
  inspect(new_loaded_nodes.get(left_children[0].id) is Some(_), content="true")
  inspect(new_loaded_nodes.get(left_children[1].id) is Some(_), content="true")
}

///|
test "TreeEditorState::new creates empty state" {
  let state : TreeEditorState[@ast.Term] = TreeEditorState::new()
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
  match collapsed.loaded_nodes.get(root_id) {
    Some(node) => {
      inspect(node.collapsed, content="true")
      inspect(tree_editor_test_loaded_children(node).length(), content="1")
    }
    None => fail("Loaded node not found")
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
  match expanded.loaded_nodes.get(root_id) {
    Some(node) => inspect(node.collapsed, content="false")
    None => fail("Loaded node not found")
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
  match refreshed.loaded_nodes.get(root_id) {
    Some(node) => inspect(node.collapsed, content="true")
    None => fail("Loaded node not found")
  }
}

///|
test "refresh elides collapsed descendants while keeping structural indexes" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right = root_children[1]
  let right_children = tree_editor_test_loaded_children(right)
  let right_leaf_id = right_children[1].id

  let refreshed = state
    .apply_edit(Collapse(node_id=right.id))
    .refresh(Some(root), source_map)
  let refreshed_tree = match refreshed.tree {
    Some(tree) => tree
    None => fail("expected refreshed tree")
  }
  let refreshed_right = tree_editor_test_loaded_children(refreshed_tree)[1]

  inspect(refreshed_right.collapsed, content="true")
  inspect(
    tree_editor_test_elided_descendant_count(refreshed_right),
    content="2",
  )
  let preorder = build_preorder_from_tree(refreshed.tree)
  inspect(preorder.range_by_root.get(right.id) is Some(_), content="true")
  inspect(refreshed.loaded_nodes.get(right_leaf_id) is None, content="true")
}

///|
test "hydrate_subtree expands an elided branch without full refresh" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right = root_children[1]
  let right_leaf_id = tree_editor_test_loaded_children(right)[1].id

  let elided = state
    .apply_edit(Collapse(node_id=right.id))
    .refresh(Some(root), source_map)
  let expanded = elided.expand_node(right.id, Some(root), source_map)
  let expanded_tree = match expanded.tree {
    Some(tree) => tree
    None => fail("expected hydrated tree")
  }
  let hydrated_right = tree_editor_test_loaded_children(expanded_tree)[1]
  let hydrated_children = tree_editor_test_loaded_children(hydrated_right)

  inspect(hydrated_right.collapsed, content="false")
  inspect(hydrated_children.length(), content="2")
  inspect(hydrated_children[1].label, content="4")
  inspect(expanded.loaded_nodes.get(right_leaf_id) is Some(_), content="true")
}

///|
test "apply_edit Expand is a no-op for elided branches" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let right = tree_editor_test_loaded_children(tree)[1]
  let elided = state
    .apply_edit(Collapse(node_id=right.id))
    .refresh(Some(root), source_map)
  let expanded = elided.apply_edit(Expand(node_id=right.id))
  let expanded_tree = match expanded.tree {
    Some(tree) => tree
    None => fail("expected expanded tree")
  }
  let expanded_right = tree_editor_test_loaded_children(expanded_tree)[1]

  inspect(expanded_right.collapsed, content="true")
  inspect(
    tree_editor_test_elided_descendant_count(expanded_right) > 0,
    content="true",
  )
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
test "Select updates loaded tree flags locally" {
  let (_, _, state) = tree_editor_test_state("1 + 2")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right = root_children[1]
  let selected = state.apply_edit(Select(node_id=right.id))
  let selected_tree = match selected.tree {
    Some(tree) => tree
    None => fail("expected selected tree")
  }
  let selected_children = tree_editor_test_loaded_children(selected_tree)

  inspect(selected.selection.length(), content="1")
  inspect(selected_children[0].selected, content="false")
  inspect(selected_children[1].selected, content="true")
}

///|
test "SelectRange updates loaded tree flags locally" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let selected = state.apply_edit(
    SelectRange(start=root_children[0].id, end=root_children[1].id),
  )
  let selected_tree = match selected.tree {
    Some(tree) => tree
    None => fail("expected selected tree")
  }
  let selected_children = tree_editor_test_loaded_children(selected_tree)

  inspect(selected.selection.length(), content="4")
  inspect(selected_tree.selected, content="false")
  inspect(selected_children[0].selected, content="true")
  inspect(selected_children[1].selected, content="true")
}

///|
test "SelectRange ignores elided subtree endpoints" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let left_id = root_children[0].id
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let right_id = root_children[1].id
  let right_leaf_id = right_children[1].id

  let refreshed = state
    .apply_edit(Collapse(node_id=right_id))
    .refresh(Some(root), source_map)
  // right_leaf_id is inside an elided subtree, so it is not in the lazy
  // preorder index. SelectRange returns empty => selection unchanged.
  let selected = refreshed.apply_edit(
    SelectRange(start=left_id, end=right_leaf_id),
  )

  // Empty result preserves prior selection (which is empty here)
  inspect(selected.selection.length(), content="0")
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
test "Delete clears hidden descendant UI state when subtree is elided" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right = root_children[1]
  let hidden_leaf_id = tree_editor_test_loaded_children(right)[1].id
  let collapsed = state
    .apply_edit(Select(node_id=hidden_leaf_id))
    .apply_edit(StartEdit(node_id=hidden_leaf_id))
    .apply_edit(Collapse(node_id=right.id))
    .refresh(Some(root), source_map)
  let deleted = collapsed.apply_edit(Delete(node_id=right.id))

  inspect(deleted.selection.length(), content="0")
  inspect(deleted.editing_node is None, content="true")
  inspect(deleted.edit_value, content="")
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
test "DragOver rejects descendant as drop target" {
  let (_, _, state) = tree_editor_test_state("λx.x + 1")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let root_id = tree.id
  let root_children = tree_editor_test_loaded_children(tree)
  let lambda_body = tree_editor_test_loaded_children(root_children[0])
  let descendant_id = lambda_body[0].id
  let dragover = state
    .apply_edit(StartDrag(node_id=root_id))
    .apply_edit(DragOver(target=descendant_id, position=Inside))
  inspect(dragover.drop_target is None, content="true")
}

///|
test "DragOver allows elided descendant as drop target (lazy parent map)" {
  // With lazy-only parent map, elided descendants are not in the parent index.
  // is_descendant_of returns false, so the DragOver is accepted.
  // In practice, elided nodes are not visible in the UI, so this case
  // cannot occur from user interaction.
  let (root, source_map, state) = tree_editor_test_state("λx.x + 1")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let lambda_body = tree_editor_test_loaded_children(root_children[0])
  let descendant_id = lambda_body[0].id
  let refreshed = state
    .apply_edit(Collapse(node_id=tree.id))
    .refresh(Some(root), source_map)
  let dragover = refreshed
    .apply_edit(StartDrag(node_id=tree.id))
    .apply_edit(DragOver(target=descendant_id, position=Inside))
  inspect(dragover.drop_target is Some(_), content="true")
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
  let stale_id = NodeId::from_int(9999)
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
  inspect(refreshed.collapsed_nodes.contains(stale_id), content="true")
}

///|
test "from_projection builds structural indexes" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let ids = tree_editor_test_ids(state.tree)
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let root_id = tree.id
  let left_id = root_children[0].id
  let right_id = root_children[1].id
  let right_leaf_id = right_children[1].id

  let preorder = build_preorder_from_tree(state.tree)
  let parent_map = build_parent_map_from_tree(state.tree)
  inspect(preorder.ids == ids, content="true")
  inspect(
    preorder.range_by_root.get(root_id) == Some((0, ids.length() - 1)),
    content="true",
  )
  inspect(preorder.range_by_root.get(left_id) == Some((1, 3)), content="true")
  inspect(preorder.range_by_root.get(right_id) == Some((4, 6)), content="true")
  inspect(parent_map.get(left_id) == Some(root_id), content="true")
  inspect(parent_map.get(right_leaf_id) == Some(right_id), content="true")
  inspect(state.loaded_nodes.get(right_leaf_id) is Some(_), content="true")
}

///|
test "refresh rebuilds structural indexes for updated projection" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 4)")
  let old_source_map = SourceMap::from_ast(old_root)
  let state = TreeEditorState::from_projection(Some(old_root), old_source_map)
  let (new_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 5)")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(1000))
  let source_map = SourceMap::from_ast(reconciled)
  let refreshed = state.refresh(Some(reconciled), source_map)
  let ids = tree_editor_test_ids(refreshed.tree)
  let tree = match refreshed.tree {
    Some(tree) => tree
    None => fail("expected refreshed tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let right_id = root_children[1].id
  let right_leaf_id = right_children[1].id

  let preorder = build_preorder_from_tree(refreshed.tree)
  let parent_map = build_parent_map_from_tree(refreshed.tree)
  inspect(preorder.ids == ids, content="true")
  inspect(preorder.range_by_root.get(right_id) == Some((4, 6)), content="true")
  inspect(parent_map.get(right_leaf_id) == Some(right_id), content="true")
  match refreshed.loaded_nodes.get(right_leaf_id) {
    Some(node) => inspect(node.label, content="5")
    None => fail("expected loaded node")
  }
}

///|
test "refresh builder reuses unchanged sibling subtree after unrelated leaf change" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 4)")
  let old_source_map = SourceMap::from_ast(old_root)
  let state = TreeEditorState::from_projection(Some(old_root), old_source_map)
  let (new_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 5)")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(1000))
  let source_map = SourceMap::from_ast(reconciled)
  let ui_state : TreeUIState = {
    collapsed_nodes: @immut/hashset.new(),
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }

  let refreshed_root = tree_editor_test_refresh_minimal(
    reconciled,
    source_map,
    ui_state,
    state.loaded_nodes,
  )
  let refreshed_left = tree_editor_test_refresh_minimal(
    reconciled.children[0],
    source_map,
    ui_state,
    state.loaded_nodes,
  )
  let refreshed_right = tree_editor_test_refresh_minimal(
    reconciled.children[1],
    source_map,
    ui_state,
    state.loaded_nodes,
  )

  inspect(refreshed_root.reused_previous, content="false")
  inspect(refreshed_left.reused_previous, content="true")
  inspect(refreshed_right.reused_previous, content="false")
}

///|
test "refresh builder reuses root when projection and UI state are unchanged" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let ui_state : TreeUIState = {
    collapsed_nodes: state.collapsed_nodes,
    selection: @immut/hashset.from_iter(state.selection.iter()),
    editing_node: state.editing_node,
    drop_target: state.drop_target,
  }

  let refreshed = tree_editor_test_refresh_minimal(
    root,
    source_map,
    ui_state,
    state.loaded_nodes,
  )

  inspect(refreshed.reused_previous, content="true")
}

///|
test "refresh builder limits UI-only selection invalidation to selected branch" {
  let (root, source_map, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let root_children = tree_editor_test_loaded_children(tree)
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let selected_leaf = right_children[1].id
  let selected_state = state.apply_edit(Select(node_id=selected_leaf))
  let ui_state : TreeUIState = {
    collapsed_nodes: selected_state.collapsed_nodes,
    selection: @immut/hashset.from_iter(selected_state.selection.iter()),
    editing_node: selected_state.editing_node,
    drop_target: selected_state.drop_target,
  }

  let refreshed_root = tree_editor_test_refresh_minimal(
    root,
    source_map,
    ui_state,
    state.loaded_nodes,
  )
  let refreshed_left = tree_editor_test_refresh_minimal(
    root.children[0],
    source_map,
    ui_state,
    state.loaded_nodes,
  )
  let refreshed_right = tree_editor_test_refresh_minimal(
    root.children[1],
    source_map,
    ui_state,
    state.loaded_nodes,
  )
  let refreshed_leaf = tree_editor_test_refresh_minimal(
    root.children[1].children[1],
    source_map,
    ui_state,
    state.loaded_nodes,
  )

  inspect(refreshed_root.reused_previous, content="false")
  inspect(refreshed_left.reused_previous, content="true")
  inspect(refreshed_right.reused_previous, content="false")
  inspect(refreshed_leaf.reused_previous, content="false")
}

///|
test "build_parent_map_from_tree matches eagerly-built parent_by_child" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let lazy_map = build_parent_map_from_tree(Some(tree))
  let root_children = tree_editor_test_loaded_children(tree)
  let left_id = root_children[0].id
  let right_id = root_children[1].id
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let right_leaf_id = right_children[1].id
  inspect(lazy_map.get(left_id) == Some(tree.id), content="true")
  inspect(lazy_map.get(right_leaf_id) == Some(right_id), content="true")
  inspect(lazy_map.get(tree.id) is None, content="true")
}

///|
test "build_preorder_from_tree matches eagerly-built indexes" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => fail("expected tree")
  }
  let lazy_preorder = build_preorder_from_tree(Some(tree))
  let root_children = tree_editor_test_loaded_children(tree)
  let right_id = root_children[1].id
  inspect(lazy_preorder.ids.length(), content="7")
  inspect(lazy_preorder.ids[0] == tree.id, content="true")
  inspect(
    lazy_preorder.range_by_root.get(right_id) == Some((4, 6)),
    content="true",
  )
}

///|
test "TreeEditorState::refresh preserves unchanged sibling subtree through public API" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 4)")
  let old_source_map = SourceMap::from_ast(old_root)
  let state = TreeEditorState::from_projection(Some(old_root), old_source_map)
  let old_tree = match state.tree {
    Some(tree) => tree
    None => fail("expected initial tree")
  }
  let old_root_children = tree_editor_test_loaded_children(old_tree)
  let old_left = old_root_children[0]
  let old_right = old_root_children[1]

  let (new_root, _) = @lambda_proj.parse_to_proj_node("(1 + 2) + (3 + 5)")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(1000))
  let source_map = SourceMap::from_ast(reconciled)
  let refreshed = state.refresh(Some(reconciled), source_map)
  let refreshed_tree = match refreshed.tree {
    Some(tree) => tree
    None => fail("expected refreshed tree")
  }
  let refreshed_root_children = tree_editor_test_loaded_children(refreshed_tree)
  let refreshed_left = refreshed_root_children[0]
  let refreshed_right = refreshed_root_children[1]
  let refreshed_right_children = tree_editor_test_loaded_children(
    refreshed_right,
  )

  inspect(
    interactive_node_stamp(refreshed_left) == interactive_node_stamp(old_left),
    content="true",
  )
  // Stamp uses shallow kind_tag + label (not deep T equality).
  // Right subtree's kind_tag and label are unchanged (both "Bop" / "+"),
  // so stamps match — deep child changes are caught by recursive child walk.
  inspect(
    interactive_node_stamp(refreshed_right) == interactive_node_stamp(old_right),
    content="true",
  )
  inspect(refreshed_right_children[1].label, content="5")
}
