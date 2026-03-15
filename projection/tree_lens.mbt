// Tree editing operations over pure ProjNode trees.

///|
/// Tree edit operations for the interactive tree editor
pub(all) enum TreeEditOp {
  // Selection
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)

  // Inline editing
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit

  // Structural operations
  Delete(node_id~ : NodeId)
  WrapInLambda(node_id~ : NodeId, var_name~ : String)
  WrapInApp(node_id~ : NodeId)
  InsertChild(parent~ : NodeId, index~ : Int, kind~ : @ast.Term)

  // Drag and drop
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)

  // Navigation
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)
} derive(Show)

///|
/// Apply a tree edit operation directly to a ProjNode tree.
pub fn apply_edit_to_proj(
  root : ProjNode,
  edit : TreeEditOp,
  registry : Map[NodeId, ProjNode],
  counter : Ref[Int],
) -> Result[ProjNode, String] {
  match edit {
    // Selection operations don't modify the AST
    TreeEditOp::Select(node_id~) => {
      let _ = node_id
      Ok(root)
    }
    TreeEditOp::SelectRange(start~, end~) => {
      let _ = (start, end)
      Ok(root)
    }

    // Inline editing
    TreeEditOp::StartEdit(node_id~) => {
      let _ = node_id
      Ok(root)
    }
    TreeEditOp::CommitEdit(node_id~, new_value~) => {
      let (parsed, _) = parse_to_proj_node(new_value)
      let new_node = assign_fresh_ids(parsed, counter)
      match registry.get(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(_) => {
          let replacement = ProjNode::new(
            new_node.kind,
            new_node.start,
            new_node.end,
            node_id.0,
            new_node.children,
          )
          Ok(update_node_in_tree(root, node_id, replacement))
        }
      }
    }
    TreeEditOp::CancelEdit => Ok(root)

    // Structural operations
    TreeEditOp::Delete(node_id~) =>
      if NodeId(root.node_id) == node_id {
        Err("Cannot delete root or node not found")
      } else {
        match find_parent_recursive(root, node_id) {
          None => Err("Cannot delete root or node not found")
          Some((parent_node, index)) => {
            let target = parent_node.children[index]
            match parent_node.kind {
              @ast.Term::Error(_) => {
                let new_parent = remove_child_at(parent_node, index)
                Ok(
                  update_node_in_tree(
                    root,
                    NodeId(parent_node.node_id),
                    new_parent,
                  ),
                )
              }
              _ =>
                match deleted_placeholder(target, counter) {
                  Ok(replacement) =>
                    Ok(update_node_in_tree(root, node_id, replacement))
                  Err(msg) => Err(msg)
                }
            }
          }
        }
      }
    TreeEditOp::WrapInLambda(node_id~, var_name~) =>
      match registry.get(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          let existing_text = @ast.print_term(existing.kind)
          let lambda_text = "λ" + var_name + "." + existing_text
          let (parsed, diagnostics) = parse_to_proj_node(lambda_text)
          if diagnostics.length() > 0 {
            return Err("Failed to parse wrapped lambda: " + diagnostics[0])
          }
          let new_node = assign_fresh_ids(parsed, counter)
          let replacement = ProjNode::new(
            new_node.kind,
            new_node.start,
            new_node.end,
            node_id.0,
            new_node.children,
          )
          Ok(update_node_in_tree(root, node_id, replacement))
        }
      }
    TreeEditOp::WrapInApp(node_id~) =>
      match registry.get(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          let existing_text = @ast.print_term(existing.kind)
          let app_text = "(" + existing_text + ") a"
          let (parsed, diagnostics) = parse_to_proj_node(app_text)
          if diagnostics.length() > 0 {
            return Err("Failed to parse wrapped application: " + diagnostics[0])
          }
          let new_node = assign_fresh_ids(parsed, counter)
          let replacement = ProjNode::new(
            new_node.kind,
            new_node.start,
            new_node.end,
            node_id.0,
            new_node.children,
          )
          Ok(update_node_in_tree(root, node_id, replacement))
        }
      }
    TreeEditOp::InsertChild(parent~, index~, kind~) => {
      let placeholder_text = placeholder_text_for_kind(kind)
      let (parsed, diagnostics) = parse_to_proj_node(placeholder_text)
      if diagnostics.length() > 0 {
        return Err("Failed to parse placeholder: " + diagnostics[0])
      }
      let new_node = assign_fresh_ids(parsed, counter)
      match registry.get(parent) {
        None => Err("Parent node not found: " + parent.to_string())
        Some(parent_node) => {
          let new_parent = insert_child_at(parent_node, index, new_node)
          Ok(update_node_in_tree(root, parent, new_parent))
        }
      }
    }

    // Drag and drop
    TreeEditOp::StartDrag(node_id~) => {
      let _ = node_id
      Ok(root)
    }
    TreeEditOp::DragOver(target~, position~) => {
      let _ = (target, position)
      Ok(root)
    }
    TreeEditOp::Drop(source~, target~, position~) =>
      match find_parent_recursive(root, target) {
        None => Err("Cannot drop on root node")
        Some((parent_node, target_index)) => {
          let new_index = match position {
            Before => target_index
            After => target_index + 1
            Inside => 0 // Insert as first child of target
          }
          let new_parent = match position {
            Before | After => NodeId(parent_node.node_id)
            Inside => target
          }
          match registry.get(source) {
            None => Err("Node to move not found: " + source.to_string())
            Some(node_to_move) =>
              match find_parent_recursive(root, source) {
                None => Err("Cannot move root node")
                Some((old_parent, old_index)) => {
                  let old_parent_id = NodeId(old_parent.node_id)
                  let parent_after_remove = remove_child_at(
                    old_parent, old_index,
                  )
                  match get_node_in_tree(root, new_parent) {
                    None =>
                      Err("New parent not found: " + new_parent.to_string())
                    Some(_) =>
                      if get_node_in_tree(node_to_move, new_parent) is Some(_) {
                        Err(
                          "Cannot move node under its own subtree: " +
                          new_parent.to_string(),
                        )
                      } else {
                        let root_after_remove = update_node_in_tree(
                          root, old_parent_id, parent_after_remove,
                        )
                        let adjusted_index = if old_parent_id == new_parent &&
                          old_index < new_index {
                          new_index - 1
                        } else {
                          new_index
                        }
                        match get_node_in_tree(root_after_remove, new_parent) {
                          None =>
                            Err(
                              "New parent not found: " + new_parent.to_string(),
                            )
                          Some(new_parent_node) => {
                            let parent_after_insert = insert_child_at(
                              new_parent_node, adjusted_index, node_to_move,
                            )
                            Ok(
                              update_node_in_tree(
                                root_after_remove, new_parent, parent_after_insert,
                              ),
                            )
                          }
                        }
                      }
                  }
                }
              }
          }
        }
      }

    // Navigation (doesn't modify AST)
    TreeEditOp::Collapse(node_id~) => {
      let _ = node_id
      Ok(root)
    }
    TreeEditOp::Expand(node_id~) => {
      let _ = node_id
      Ok(root)
    }
  }
}

///|
fn find_parent_recursive(
  node : ProjNode,
  target_id : NodeId,
) -> (ProjNode, Int)? {
  for i, child in node.children {
    if child.id() == target_id {
      return Some((node, i))
    }
    match find_parent_recursive(child, target_id) {
      Some(result) => return Some(result)
      None => continue
    }
  }
  None
}

///|
fn update_node_in_tree(
  root : ProjNode,
  target_id : NodeId,
  new_node : ProjNode,
) -> ProjNode {
  if root.id() == target_id {
    new_node
  } else {
    let new_children : Array[ProjNode] = []
    for child in root.children {
      new_children.push(update_node_in_tree(child, target_id, new_node))
    }
    ProjNode::new(
      rebuild_kind(root.kind, new_children),
      root.start,
      root.end,
      root.node_id,
      new_children,
    )
  }
}

///|
fn remove_child_at(node : ProjNode, index : Int) -> ProjNode {
  let new_children : Array[ProjNode] = []
  for i, child in node.children {
    if i != index {
      new_children.push(child)
    }
  }
  ProjNode::new(
    rebuild_kind(node.kind, new_children),
    node.start,
    node.end,
    node.node_id,
    new_children,
  )
}

///|
fn deleted_placeholder(
  node : ProjNode,
  counter : Ref[Int],
) -> Result[ProjNode, String] {
  let placeholder_text = placeholder_text_for_kind(node.kind)
  let (parsed, diagnostics) = parse_to_proj_node(placeholder_text)
  if diagnostics.length() > 0 {
    Err("Failed to parse delete placeholder: " + diagnostics[0])
  } else {
    let replacement = assign_fresh_ids(parsed, counter)
    Ok(
      ProjNode::new(
        replacement.kind,
        node.start,
        node.end,
        node.node_id,
        replacement.children,
      ),
    )
  }
}

///|
fn placeholder_text_for_kind(kind : @ast.Term) -> String {
  match kind {
    @ast.Term::Int(_) => "0"
    @ast.Term::Var(_) => "a"
    @ast.Term::Lam(_, _) => "λx.x"
    @ast.Term::App(_, _) => "f x"
    @ast.Term::Bop(_, _, _) => "0 + 0"
    @ast.Term::If(_, _, _) => "if 0 then 0 else 0"
    @ast.Term::Let(_, _, _) => "let x = 0\nx"
    @ast.Term::Unit => "()"
    @ast.Term::Error(_) => "a"
  }
}

///|
fn insert_child_at(node : ProjNode, index : Int, child : ProjNode) -> ProjNode {
  let new_children : Array[ProjNode] = []
  for i, c in node.children {
    if i == index {
      new_children.push(child)
    }
    new_children.push(c)
  }
  if index >= node.children.length() {
    new_children.push(child)
  }
  ProjNode::new(
    rebuild_kind(node.kind, new_children),
    node.start,
    node.end,
    node.node_id,
    new_children,
  )
}

///|
fn get_node_in_tree(root : ProjNode, target_id : NodeId) -> ProjNode? {
  if root.id() == target_id {
    Some(root)
  } else {
    for child in root.children {
      match get_node_in_tree(child, target_id) {
        Some(found) => return Some(found)
        None => continue
      }
    }
    None
  }
}
