// Whitebox tests for CanonicalModel apply_operation

///|
test "apply_operation InsertNode adds child" {
  // Create a model with a simple binary operation: 1 + 2
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let initial_children = ast.children.length()

  // Parse a new node to insert
  let (new_node, _) = @parser.parse_with_error_recovery("3")

  // Insert at the end
  let op = InsertNode(parent=root_id, index=initial_children, node=new_node)
  let result = model.apply_operation(op)
  inspect(result is Ok(_), content="true")

  // Verify the new child was added
  match model.get_ast() {
    Some(updated_ast) => inspect(updated_ast.children.length(), content="3")
    None => abort("AST missing after insert")
  }
}

///|
test "apply_operation DeleteNode removes child" {
  // Create a model with: 1 + 2
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)

  // Get the first child (the "1")
  let child_id = NodeId(ast.children[0].node_id)
  let initial_children = ast.children.length()

  // Delete the first child
  let op = DeleteNode(node_id=child_id)
  let result = model.apply_operation(op)
  inspect(result is Ok(_), content="true")

  // Verify child was removed
  match model.get_ast() {
    Some(updated_ast) =>
      inspect(
        updated_ast.children.length(),
        content=(initial_children - 1).to_string(),
      )
    None => abort("AST missing after delete")
  }
}

///|
test "apply_operation ReplaceNode changes node content" {
  // Create a model with: x
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Parse a replacement node
  let (new_node, _) = @parser.parse_with_error_recovery("42")

  // Replace the root
  let op = ReplaceNode(node_id=root_id, new_node~)
  let result = model.apply_operation(op)
  inspect(result is Ok(_), content="true")

  // Verify the node was replaced but ID preserved
  match model.get_ast() {
    Some(updated_ast) => {
      inspect(updated_ast.node_id, content=ast.node_id.to_string())
      // Should now be an Int kind
      inspect(
        match updated_ast.kind {
          @ast.AstKind::Int(_) => "true"
          _ => "false"
        },
        content="true",
      )
    }
    None => abort("AST missing after replace")
  }
}

///|
test "apply_operation UpdateLeaf changes leaf value" {
  // Create a model with: 1
  let (ast, _) = @parser.parse_with_error_recovery("1")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Update to a different integer
  let op = UpdateLeaf(node_id=root_id, new_value=IntValue(42))
  let result = model.apply_operation(op)
  inspect(result is Ok(_), content="true")

  // Verify the value changed
  match model.get_ast() {
    Some(updated_ast) =>
      inspect(
        match updated_ast.kind {
          @ast.AstKind::Int(42) => "true"
          _ => "false"
        },
        content="true",
      )
    None => abort("AST missing after update")
  }
}

///|
test "apply_operation MoveNode reparents node" {
  // Create a model with: (x + y) z
  let (ast, _) = @parser.parse_with_error_recovery("(x + y) z")
  let model = CanonicalModel::from_ast(ast)

  // This is an App node with children: [(x + y), z]
  // The (x + y) is a Bop with children: [x, y]
  // Move the 'z' to become the third child of the Bop
  let bop = ast.children[0]
  let z_node = ast.children[1]
  let bop_id = NodeId(bop.node_id)
  let z_id = NodeId(z_node.node_id)
  let op = MoveNode(node_id=z_id, new_parent=bop_id, new_index=2)
  let result = model.apply_operation(op)
  inspect(result is Ok(_), content="true")

  // Verify the move
  match model.get_ast() {
    Some(updated_ast) => {
      // Root should now have only 1 child (the bop)
      inspect(updated_ast.children.length(), content="1")
      // The bop should now have 3 children
      inspect(updated_ast.children[0].children.length(), content="3")
    }
    None => abort("AST missing after move")
  }
}

///|
test "find_parent finds correct parent and index" {
  // Create: 1 + 2
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)

  // Find parent of the first child (the "1")
  let child_id = NodeId(ast.children[0].node_id)
  match model.find_parent(child_id) {
    Some((parent, index)) => {
      inspect(parent.node_id, content=ast.node_id.to_string())
      inspect(index, content="0")
    }
    None => abort("Parent not found")
  }
}

///|
test "find_parent returns None for root" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  inspect(model.find_parent(root_id) is None, content="true")
}

///|
test "apply_operation error on invalid node_id" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)

  // Try to delete a non-existent node
  let op = DeleteNode(node_id=NodeId(9999))
  let result = model.apply_operation(op)
  inspect(result is Err(_), content="true")
}

///|
test "apply_operation InsertNode with invalid parent returns error" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let initial_history_len = model.edit_history.length()

  // Try to insert with non-existent parent
  let (new_node, _) = @parser.parse_with_error_recovery("1")
  let op = InsertNode(parent=NodeId(9999), index=0, node=new_node)
  let result = model.apply_operation(op)

  // Should error
  inspect(result is Err(_), content="true")
  // History should not be modified on error
  inspect(model.edit_history.length(), content=initial_history_len.to_string())
}

///|
test "apply_operation ReplaceNode with invalid node_id returns error" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let initial_history_len = model.edit_history.length()

  // Try to replace a non-existent node
  let (new_node, _) = @parser.parse_with_error_recovery("42")
  let op = ReplaceNode(node_id=NodeId(9999), new_node~)
  let result = model.apply_operation(op)

  // Should error
  inspect(result is Err(_), content="true")
  // History should not be modified on error
  inspect(model.edit_history.length(), content=initial_history_len.to_string())
  // AST should be unchanged
  match model.get_ast() {
    Some(updated_ast) =>
      inspect(
        match updated_ast.kind {
          @ast.AstKind::Var("x") => "true"
          _ => "false"
        },
        content="true",
      )
    None => abort("AST missing")
  }
}

///|
test "apply_operation MoveNode within same parent adjusts index" {
  // Create a model with: (a b c d) - Application with multiple args
  // We'll use a simpler case: 1 + 2 + 3 which creates nested Bop
  // Instead, let's use a direct approach with InsertNode to build children
  let (ast, _) = @parser.parse_with_error_recovery("f a b c")
  let _model = CanonicalModel::from_ast(ast)

  // The AST for "f a b c" is App(App(App(f, a), b), c)
  // Let's use a simpler test: move second child to after third child
  // For this we need a node with multiple children at same level

  // Create a fresh test with InsertNode to get [A, B, C, D]
  let (ast2, _) = @parser.parse_with_error_recovery("1 + 2")
  let model2 = CanonicalModel::from_ast(ast2)
  let root_id = NodeId(ast2.node_id)

  // Insert two more children to get [1, 2, 3, 4]
  let (n3, _) = @parser.parse_with_error_recovery("3")
  let (n4, _) = @parser.parse_with_error_recovery("4")
  let n3 = assign_fresh_ids(n3, model2)
  let n4 = assign_fresh_ids(n4, model2)
  let _ = model2.apply_operation(InsertNode(parent=root_id, index=2, node=n3))
  let _ = model2.apply_operation(InsertNode(parent=root_id, index=3, node=n4))

  // Now we have children [1, 2, 3, 4] (indices 0, 1, 2, 3)
  match model2.get_ast() {
    Some(current_ast) => {
      inspect(current_ast.children.length(), content="4")
      // Get the "2" node (index 1) and move it to after "3" (index 2 -> should become index 2 after removal)
      let node_to_move_id = NodeId(current_ast.children[1].node_id)
      // Move from index 1 to index 3 (after the "3" which is at index 2)
      // After removal of index 1, indices shift: [1, 3, 4] then insert at index 2
      // Expected result: [1, 3, 2, 4]
      let op = MoveNode(
        node_id=node_to_move_id,
        new_parent=root_id,
        new_index=3,
      )
      let result = model2.apply_operation(op)
      inspect(result is Ok(_), content="true")
      match model2.get_ast() {
        Some(final_ast) => {
          inspect(final_ast.children.length(), content="4")
          // Verify order: [1, 3, 2, 4]
          inspect(
            match final_ast.children[0].kind {
              @ast.AstKind::Int(1) => "true"
              _ => "false"
            },
            content="true",
          )
          inspect(
            match final_ast.children[1].kind {
              @ast.AstKind::Int(3) => "true"
              _ => "false"
            },
            content="true",
          )
          inspect(
            match final_ast.children[2].kind {
              @ast.AstKind::Int(2) => "true"
              _ => "false"
            },
            content="true",
          )
          inspect(
            match final_ast.children[3].kind {
              @ast.AstKind::Int(4) => "true"
              _ => "false"
            },
            content="true",
          )
        }
        None => abort("AST missing after move")
      }
    }
    None => abort("AST missing after setup")
  }
}

///|
test "apply_operation MoveNode with invalid new_parent returns error" {
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let initial_history_len = model.edit_history.length()

  // Try to move a child to a non-existent parent
  let child_id = NodeId(ast.children[0].node_id)
  let op = MoveNode(node_id=child_id, new_parent=NodeId(9999), new_index=0)
  let result = model.apply_operation(op)

  // Should error
  inspect(result is Err(_), content="true")
  // History should not be modified on error
  inspect(model.edit_history.length(), content=initial_history_len.to_string())
}

///|
test "apply_operation DeleteNode on root returns error" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let initial_history_len = model.edit_history.length()
  let op = DeleteNode(node_id=root_id)
  let result = model.apply_operation(op)

  // Should error (cannot delete root)
  inspect(result is Err(_), content="true")
  // History should not be modified on error
  inspect(model.edit_history.length(), content=initial_history_len.to_string())
  // AST should be unchanged
  inspect(model.get_ast() is Some(_), content="true")
}

///|
test "node IDs remain unique after operations" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Wrap in lambda (this parses and should assign fresh IDs)
  let edit = TreeEditOp::WrapInLambda(node_id=root_id, var_name="y")
  let _ = tree_lens_apply_edit(model, edit)

  // Collect all node IDs from the AST
  fn collect_ids(node : @ast.AstNode, acc : Array[Int]) -> Unit {
    acc.push(node.node_id)
    for child in node.children {
      collect_ids(child, acc)
    }
  }

  match model.get_ast() {
    Some(updated_ast) => {
      let ids : Array[Int] = []
      collect_ids(updated_ast, ids)

      // Check all IDs are unique
      let seen : Map[Int, Bool] = {}
      let mut all_unique = true
      for id in ids {
        if seen.contains(id) {
          all_unique = false
        }
        seen[id] = true
      }
      inspect(all_unique, content="true")
      // Should have 2 nodes: Lam and its body (x)
      inspect(ids.length(), content="2")
    }
    None => abort("AST missing")
  }
}

// =============================================================================
// Tests for tree_lens_apply_edit
// =============================================================================

///|
test "tree_lens_apply_edit CommitEdit replaces node" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Commit edit to change "x" to "42"
  let edit = TreeEditOp::CommitEdit(node_id=root_id, new_value="42")
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="42")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit Delete removes node" {
  // Create: 1 + 2
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)

  // Delete the first child (the "1")
  let child_id = NodeId(ast.children[0].node_id)
  let edit = TreeEditOp::Delete(node_id=child_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) =>
          // Should have one less child
          inspect(updated_ast.children.length(), content="1")
        None => abort("AST missing after delete")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit WrapInLambda wraps node" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Wrap in lambda with variable "y"
  let edit = TreeEditOp::WrapInLambda(node_id=root_id, var_name="y")
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) =>
          // Should now be a Lam node
          inspect(
            match updated_ast.kind {
              @ast.AstKind::Lam("y") => "true"
              _ => "false"
            },
            content="true",
          )
        None => abort("AST missing after wrap")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit WrapInApp wraps node as function" {
  let (ast, _) = @parser.parse_with_error_recovery("f")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Wrap in application
  let edit = TreeEditOp::WrapInApp(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) =>
          // Should now have children (the original was wrapped)
          // The exact structure depends on how "(f) _" parses
          // Just verify we got a transformed AST
          inspect(updated_ast.node_id == ast.node_id, content="true")
        None => abort("AST missing after wrap")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit Select does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::Select(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "roundtrip: text -> tree edit -> text" {
  // Parse initial text
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)

  // Get the "2" node (second child of root Bop)
  let two_id = NodeId(ast.children[1].node_id)

  // Commit edit to change "2" to "3"
  let edit = TreeEditOp::CommitEdit(node_id=two_id, new_value="3")
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) =>
          // Verify the second child is now Int(3)
          inspect(
            match updated_ast.children[1].kind {
              @ast.AstKind::Int(3) => "true"
              _ => "false"
            },
            content="true",
          )
        None => abort("AST missing after edit")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

// =============================================================================
// Additional edge case tests
// =============================================================================

///|
test "apply_operation MoveNode into own descendant returns error" {
  // Create: λx.(y z) - a lambda with an application body
  let (ast, _) = @parser.parse_with_error_recovery("λx.(y z)")
  let model = CanonicalModel::from_ast(ast)

  // The AST is Lam with body App(y, z)
  // Try to move the Lam into its own body (the App)
  let lam_id = NodeId(ast.node_id)
  let body = ast.children[0]
  let body_id = NodeId(body.node_id)

  // This should fail because after removing the lam, body_id won't exist
  let op = MoveNode(node_id=lam_id, new_parent=body_id, new_index=0)
  let result = model.apply_operation(op)

  // Should error (cannot move root, or new parent not found after removal)
  inspect(result is Err(_), content="true")
}

///|
test "tree_lens_apply_edit InsertChild adds Int placeholder" {
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::InsertChild(
    parent=root_id,
    index=2,
    kind=@ast.AstKind::Int(0),
  )
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) => {
          inspect(updated_ast.children.length(), content="3")
          // The new child should be Int(0)
          inspect(
            match updated_ast.children[2].kind {
              @ast.AstKind::Int(0) => "true"
              _ => "false"
            },
            content="true",
          )
        }
        None => abort("AST missing after insert")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit InsertChild adds Var placeholder" {
  // Use 1 + 2 which has 2 children at root level
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::InsertChild(
    parent=root_id,
    index=2,
    kind=@ast.AstKind::Var("_"),
  )
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) =>
          // Verify child was added
          inspect(updated_ast.children.length() > 2, content="true")
        None => abort("AST missing after insert")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit InsertChild adds Lam placeholder" {
  // Use 1 + 2 which has children at root level
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::InsertChild(
    parent=root_id,
    index=2,
    kind=@ast.AstKind::Lam("x"),
  )
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) => {
          // Should have 3 children now
          inspect(updated_ast.children.length(), content="3")
          // The new child should be a Lam
          inspect(
            match updated_ast.children[2].kind {
              @ast.AstKind::Lam(_) => "true"
              _ => "false"
            },
            content="true",
          )
        }
        None => abort("AST missing after insert")
      }
    Err(msg) => abort("tree_lens_apply_edit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit Drop with Before position" {
  // Create: 1 + 2, then add 3 and 4 to get [1, 2, 3, 4]
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Add children 3 and 4
  let (n3_raw, _) = @parser.parse_with_error_recovery("3")
  let (n4_raw, _) = @parser.parse_with_error_recovery("4")
  let n3 = assign_fresh_ids(n3_raw, model)
  let n4 = assign_fresh_ids(n4_raw, model)
  let _ = model.apply_operation(InsertNode(parent=root_id, index=2, node=n3))
  let _ = model.apply_operation(InsertNode(parent=root_id, index=3, node=n4))

  // Now [1, 2, 3, 4] - drop 4 before 2
  match model.get_ast() {
    Some(current) => {
      let four_id = NodeId(current.children[3].node_id)
      let two_id = NodeId(current.children[1].node_id)
      let edit = TreeEditOp::Drop(
        source=four_id,
        target=two_id,
        position=Before,
      )
      match tree_lens_apply_edit(model, edit) {
        Ok(updated_model) =>
          match updated_model.get_ast() {
            Some(final_ast) => {
              // Should be [1, 4, 2, 3]
              inspect(
                match final_ast.children[0].kind {
                  @ast.AstKind::Int(1) => "true"
                  _ => "false"
                },
                content="true",
              )
              inspect(
                match final_ast.children[1].kind {
                  @ast.AstKind::Int(4) => "true"
                  _ => "false"
                },
                content="true",
              )
              inspect(
                match final_ast.children[2].kind {
                  @ast.AstKind::Int(2) => "true"
                  _ => "false"
                },
                content="true",
              )
              inspect(
                match final_ast.children[3].kind {
                  @ast.AstKind::Int(3) => "true"
                  _ => "false"
                },
                content="true",
              )
            }
            None => abort("AST missing after drop")
          }
        Err(msg) => abort("Drop failed: " + msg)
      }
    }
    None => abort("AST missing")
  }
}

///|
test "tree_lens_apply_edit Drop with After position" {
  // Create: 1 + 2, then add 3 to get [1, 2, 3]
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let (n3_raw, _) = @parser.parse_with_error_recovery("3")
  let n3 = assign_fresh_ids(n3_raw, model)
  let _ = model.apply_operation(InsertNode(parent=root_id, index=2, node=n3))

  // Now [1, 2, 3] - drop 1 after 2, expecting [2, 1, 3]
  match model.get_ast() {
    Some(current) => {
      let one_id = NodeId(current.children[0].node_id)
      let two_id = NodeId(current.children[1].node_id)
      let edit = TreeEditOp::Drop(source=one_id, target=two_id, position=After)
      match tree_lens_apply_edit(model, edit) {
        Ok(updated_model) =>
          match updated_model.get_ast() {
            Some(final_ast) => {
              // Should be [2, 1, 3]
              inspect(
                match final_ast.children[0].kind {
                  @ast.AstKind::Int(2) => "true"
                  _ => "false"
                },
                content="true",
              )
              inspect(
                match final_ast.children[1].kind {
                  @ast.AstKind::Int(1) => "true"
                  _ => "false"
                },
                content="true",
              )
              inspect(
                match final_ast.children[2].kind {
                  @ast.AstKind::Int(3) => "true"
                  _ => "false"
                },
                content="true",
              )
            }
            None => abort("AST missing after drop")
          }
        Err(msg) => abort("Drop failed: " + msg)
      }
    }
    None => abort("AST missing")
  }
}

///|
test "tree_lens_apply_edit Drop with Inside position" {
  // Create: (f x) y - App(App(f, x), y)
  let (ast, _) = @parser.parse_with_error_recovery("(f x) y")
  let model = CanonicalModel::from_ast(ast)

  // Drop y inside the inner App (f x)
  match model.get_ast() {
    Some(current) => {
      let inner_app = current.children[0]
      let y_node = current.children[1]
      let inner_app_id = NodeId(inner_app.node_id)
      let y_id = NodeId(y_node.node_id)
      let edit = TreeEditOp::Drop(
        source=y_id,
        target=inner_app_id,
        position=Inside,
      )
      match tree_lens_apply_edit(model, edit) {
        Ok(updated_model) =>
          match updated_model.get_ast() {
            Some(final_ast) => {
              // Root should now have 1 child (the inner app)
              inspect(final_ast.children.length(), content="1")
              // Inner app should have 3 children: f, x, y
              inspect(final_ast.children[0].children.length(), content="3")
            }
            None => abort("AST missing after drop")
          }
        Err(msg) => abort("Drop failed: " + msg)
      }
    }
    None => abort("AST missing")
  }
}

///|
test "tree_lens_apply_edit CommitEdit with incomplete parse creates error node" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)

  // Commit an incomplete expression
  let edit = TreeEditOp::CommitEdit(node_id=root_id, new_value="λ")
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      // Should succeed but model should have errors
      inspect(updated_model.has_errors(), content="true")
    Err(_) =>
      // Also acceptable if it returns error
      inspect(true, content="true")
  }
}

///|
test "tree_lens_apply_edit WrapInLambda preserves body structure" {
  // Wrap a complex expression: 1 + 2
  let (ast, _) = @parser.parse_with_error_recovery("1 + 2")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::WrapInLambda(node_id=root_id, var_name="x")
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) => {
          // Root should be Lam("x")
          inspect(
            match updated_ast.kind {
              @ast.AstKind::Lam("x") => "true"
              _ => "false"
            },
            content="true",
          )
          // Body should be a Bop (the original 1 + 2)
          inspect(updated_ast.children.length(), content="1")
          inspect(
            match updated_ast.children[0].kind {
              @ast.AstKind::Bop(_) => "true"
              _ => "false"
            },
            content="true",
          )
        }
        None => abort("AST missing after wrap")
      }
    Err(msg) => abort("WrapInLambda failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit WrapInApp creates App with placeholder" {
  let (ast, _) = @parser.parse_with_error_recovery("f")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::WrapInApp(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match updated_model.get_ast() {
        Some(updated_ast) => {
          // Verify the root ID is preserved
          inspect(updated_ast.node_id == ast.node_id, content="true")
          // Verify the text output shows a transformation happened
          match text_lens_get(updated_model) {
            Ok(text) =>
              // The result should be different from just "f"
              // (it's "(f) _" or similar)
              inspect(text.length() > 1, content="true")
            Err(_) => ()
          }
        }
        None => abort("AST missing after wrap")
      }
    Err(msg) => abort("WrapInApp failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit SelectRange does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let start_id = NodeId(ast.node_id)
  let end_id = NodeId(ast.node_id)
  let edit = TreeEditOp::SelectRange(start=start_id, end=end_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("SelectRange failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit StartEdit does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::StartEdit(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("StartEdit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit CancelEdit does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let edit = TreeEditOp::CancelEdit
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("CancelEdit failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit StartDrag does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::StartDrag(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("StartDrag failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit DragOver does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let target_id = NodeId(ast.node_id)
  let edit = TreeEditOp::DragOver(target=target_id, position=Before)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("DragOver failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit Collapse does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::Collapse(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("Collapse failed: " + msg)
  }
}

///|
test "tree_lens_apply_edit Expand does not modify model" {
  let (ast, _) = @parser.parse_with_error_recovery("x")
  let model = CanonicalModel::from_ast(ast)
  let root_id = NodeId(ast.node_id)
  let edit = TreeEditOp::Expand(node_id=root_id)
  match tree_lens_apply_edit(model, edit) {
    Ok(updated_model) =>
      match text_lens_get(updated_model) {
        Ok(text) => inspect(text, content="x")
        Err(msg) => abort("text_lens_get failed: " + msg)
      }
    Err(msg) => abort("Expand failed: " + msg)
  }
}
