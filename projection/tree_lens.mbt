// TreeLens: Bidirectional transformation between CanonicalModel and AstNode
// Model ↔ Interactive Tree (AST view)

///|
/// Create a tree lens for CanonicalModel ↔ AstNode? transformation
pub fn tree_lens() -> Lens[CanonicalModel, ProjNode?] {
  Lens::new(tree_lens_get, tree_lens_put)
}

///|
/// Get the interactive tree from the canonical model
pub fn tree_lens_get(model : CanonicalModel) -> Result[ProjNode?, String] {
  Ok(model.get_ast())
}

///|
/// Put an AST back into the canonical model
pub fn tree_lens_put(
  model : CanonicalModel,
  ast : ProjNode?,
) -> Result[CanonicalModel, String] {
  match ast {
    Some(new_ast) =>
      // Reconcile with existing AST to preserve node IDs
      match model.get_ast() {
        Some(old_ast) => {
          let reconciled = reconcile_ast(old_ast, new_ast, model)
          model.set_ast(reconciled)
          Ok(model)
        }
        None => {
          model.set_ast(new_ast)
          Ok(model)
        }
      }
    None =>
      // Cannot clear AST - return error as this is not a valid operation
      Err("Cannot set AST to None - model requires an AST")
  }
}

///|
/// Tree edit operations for the interactive tree editor
pub enum TreeEditOp {
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
/// Apply a tree edit operation to the canonical model
pub fn tree_lens_apply_edit(
  model : CanonicalModel,
  edit : TreeEditOp,
) -> Result[CanonicalModel, String] {
  match edit {
    // Selection operations don't modify the AST
    TreeEditOp::Select(node_id~) => {
      let _ = node_id
      Ok(model)
    }
    TreeEditOp::SelectRange(start~, end~) => {
      let _ = (start, end)
      Ok(model)
    }

    // Inline editing
    TreeEditOp::StartEdit(node_id~) => {
      let _ = node_id
      Ok(model)
    }
    TreeEditOp::CommitEdit(node_id~, new_value~) => {
      // Parse the new value to get a ProjNode
      let (parsed, _) = parse_to_proj_node(new_value)
      // Assign fresh IDs to avoid collisions with existing AST nodes
      let new_node = assign_fresh_ids(parsed, model)
      // Replace the node with the parsed content
      let op = ReplaceNode(node_id~, new_node~)
      match model.apply_operation(op) {
        Ok(_) => Ok(model)
        Err(msg) => Err(msg)
      }
    }
    TreeEditOp::CancelEdit => Ok(model)

    // Structural operations
    TreeEditOp::Delete(node_id~) => {
      let op = DeleteNode(node_id~)
      match model.apply_operation(op) {
        Ok(_) => Ok(model)
        Err(msg) => Err(msg)
      }
    }
    TreeEditOp::WrapInLambda(node_id~, var_name~) =>
      // Get the existing node to wrap
      match model.get_node(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          // Get text representation of the existing node
          let existing_text = @ast.print_term(existing.kind)
          // Parse a lambda wrapping it
          let lambda_text = "λ" + var_name + "." + existing_text
          let (parsed, _) = parse_to_proj_node(lambda_text)
          // Assign fresh IDs to avoid collisions with existing AST nodes
          let new_node = assign_fresh_ids(parsed, model)
          // Replace the node
          let op = ReplaceNode(node_id~, new_node~)
          match model.apply_operation(op) {
            Ok(_) => Ok(model)
            Err(msg) => Err(msg)
          }
        }
      }
    TreeEditOp::WrapInApp(node_id~) =>
      // Get the existing node to wrap as the function
      match model.get_node(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          // Get text representation of the existing node
          let existing_text = @ast.print_term(existing.kind)
          // Parse an application with a placeholder argument
          let app_text = "(" + existing_text + ") _"
          let (parsed, _) = parse_to_proj_node(app_text)
          // Assign fresh IDs to avoid collisions with existing AST nodes
          let new_node = assign_fresh_ids(parsed, model)
          // Replace the node
          let op = ReplaceNode(node_id~, new_node~)
          match model.apply_operation(op) {
            Ok(_) => Ok(model)
            Err(msg) => Err(msg)
          }
        }
      }
    TreeEditOp::InsertChild(parent~, index~, kind~) => {
      // Create a placeholder node based on the kind
      let placeholder_text = match kind {
        @ast.Term::Int(_) => "0"
        @ast.Term::Var(_) => "_"
        @ast.Term::Lam(_, _) => "λx.x"
        @ast.Term::App(_, _) => "f x"
        @ast.Term::Bop(_, _, _) => "0 + 0"
        @ast.Term::If(_, _, _) => "if 0 then 0 else 0"
        @ast.Term::Let(_, _, _) => "let x = 0 in x"
        @ast.Term::Unit => "()"
        @ast.Term::Error(_) => "_"
      }
      let (parsed, _) = parse_to_proj_node(placeholder_text)
      // Assign fresh IDs to avoid collisions with existing AST nodes
      let new_node = assign_fresh_ids(parsed, model)
      let op = InsertNode(parent~, index~, node=new_node)
      match model.apply_operation(op) {
        Ok(_) => Ok(model)
        Err(msg) => Err(msg)
      }
    }

    // Drag and drop
    TreeEditOp::StartDrag(node_id~) => {
      let _ = node_id
      Ok(model)
    }
    TreeEditOp::DragOver(target~, position~) => {
      let _ = (target, position)
      Ok(model)
    }
    TreeEditOp::Drop(source~, target~, position~) =>
      // Get the target's parent to determine where to insert
      match model.find_parent(target) {
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
          let op = MoveNode(node_id=source, new_parent~, new_index~)
          match model.apply_operation(op) {
            Ok(_) => Ok(model)
            Err(msg) => Err(msg)
          }
        }
      }

    // Navigation (doesn't modify AST)
    TreeEditOp::Collapse(node_id~) => {
      let _ = node_id
      Ok(model)
    }
    TreeEditOp::Expand(node_id~) => {
      let _ = node_id
      Ok(model)
    }
  }
}
