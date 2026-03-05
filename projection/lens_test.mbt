// Tests for the projectional editing infrastructure

///|
test "SourceMap from_ast" {
  // Use the parser to create an AST
  let (ast, _) = parse_to_proj_node("42")
  let source_map = SourceMap::from_ast(ast)
  inspect(source_map.node_count() >= 1, content="true")
}

///|
test "parse_to_proj_node preserves child-specific ranges" {
  let (ast, _) = parse_to_proj_node("x + 1")
  inspect(ast.children.length(), content="2")
  if ast.children.length() >= 2 {
    inspect(ast.children[0].start < ast.children[1].start, content="true")
    inspect(ast.children[0].end <= ast.children[1].start, content="true")
  }
}

///|
test "node_at_position distinguishes left and right operands" {
  let (ast, _) = parse_to_proj_node("x + 1")
  guard ast.children.length() == 2 else {
    abort("Expected binary expression with two children")
  }
  let model = CanonicalModel::from_ast(ast)
  let left_pos = ast.children[0].start
  let right_pos = if ast.children[1].end > ast.children[1].start {
    ast.children[1].end - 1
  } else {
    ast.children[1].start
  }

  match model.node_at_position(left_pos) {
    Some(node_id) =>
      match model.get_node(node_id) {
        Some(node) =>
          inspect(node.start, content=ast.children[0].start.to_string())
        None => abort("Expected left operand node to exist")
      }
    None => abort("Expected node at left operand position")
  }
  match model.node_at_position(right_pos) {
    Some(node_id) =>
      match model.get_node(node_id) {
        Some(node) =>
          inspect(node.start, content=ast.children[1].start.to_string())
        None => abort("Expected right operand node to exist")
      }
    None => abort("Expected node at right operand position")
  }
}

///|
test "CanonicalModel creation" {
  let model = CanonicalModel::new()
  inspect(model.node_count(), content="0")
}

///|
test "CanonicalModel from parsed AST" {
  // Use the parser to create an AST
  let (ast, _) = parse_to_proj_node("x")
  let model = CanonicalModel::from_ast(ast)
  inspect(model.node_count() >= 1, content="true")
  inspect(model.has_errors(), content="false")
}

///|
test "text_lens_get renders AST to text" {
  // Use the parser to create an AST
  let (ast, _) = parse_to_proj_node("x")
  let model = CanonicalModel::from_ast(ast)
  match text_lens_get(model) {
    Ok(text) => inspect(text, content="x")
    Err(msg) => abort("text_lens_get failed: " + msg)
  }
}

///|
test "text_lens_diff detects changes" {
  let edits = text_lens_diff("hello", "hello")
  inspect(edits.length(), content="0")
  let edits2 = text_lens_diff("hello", "world")
  inspect(edits2.length() > 0, content="true")
}

///|
test "Result operations" {
  let ok_result : Result[Int, String] = Ok(42)
  let err_result : Result[Int, String] = Err("test error")
  inspect(ok_result is Ok(_), content="true")
  inspect(err_result is Ok(_), content="false")
  inspect(ok_result.unwrap(), content="42")
  let mapped = ok_result.map(fn(x) { x * 2 })
  inspect(mapped.unwrap(), content="84")
}

///|
test "TreeEditorState creation" {
  let state = TreeEditorState::new()
  inspect(state.tree is None, content="true")
  inspect(state.selection.length(), content="0")
}

///|
test "TreeEditorState from model" {
  let (ast, _) = parse_to_proj_node("x + 1")
  let model = CanonicalModel::from_ast(ast)
  let state = TreeEditorState::from_model(model)
  inspect(state.tree is Some(_), content="true")
}

///|
test "InteractiveTreeNode from AstNode" {
  let (ast, _) = parse_to_proj_node("λx.x")
  let source_map = SourceMap::from_ast(ast)
  let tree = InteractiveTreeNode::from_term_node(ast, source_map)
  // Should be a lambda node - check first character is λ
  inspect(tree.label[:1].to_string(), content="λ")
}

// =============================================================================
// Bug Fix Tests: text_lens_diff
// =============================================================================

///|
test "text_lens_diff preserves common prefix" {
  // "hello world" -> "hello there" should only edit the different part
  let edits = text_lens_diff("hello world", "hello there")
  // Should have edits (insert and/or delete) but not at position 0
  inspect(edits.length() > 0, content="true")
  // First edit should not start at position 0 (common prefix "hello " preserved)
  match edits[0] {
    TextInsert(position~, ..) => inspect(position >= 6, content="true")
    TextDelete(start~, ..) => inspect(start >= 6, content="true")
    _ => ()
  }
}

///|
test "text_lens_diff preserves common suffix" {
  // "abc xyz" -> "def xyz" should preserve " xyz" suffix
  let edits = text_lens_diff("abc xyz", "def xyz")
  inspect(edits.length() > 0, content="true")
  // Edits should only affect the first 3 characters
  for edit in edits {
    match edit {
      TextInsert(position~, ..) => inspect(position <= 3, content="true")
      TextDelete(start~, end~) => {
        inspect(start <= 3, content="true")
        // After insert adjustment, end should still be reasonable
        inspect(end <= 6, content="true")
      }
      _ => ()
    }
  }
}

///|
test "text_lens_diff handles pure insertion" {
  // "ab" -> "abc" should just insert 'c' at position 2
  let edits = text_lens_diff("ab", "abc")
  inspect(edits.length(), content="1")
  match edits[0] {
    TextInsert(position~, text~) => {
      inspect(position, content="2")
      inspect(text, content="c")
    }
    _ => abort("Expected TextInsert")
  }
}

///|
test "text_lens_diff handles pure deletion" {
  // "abc" -> "ab" should just delete 'c'
  let edits = text_lens_diff("abc", "ab")
  inspect(edits.length(), content="1")
  match edits[0] {
    TextDelete(start~, end~) => {
      inspect(start, content="2")
      inspect(end, content="3")
    }
    _ => abort("Expected TextDelete")
  }
}

///|
test "text_lens_diff handles replacement in middle" {
  // "abXYZcd" -> "ab123cd" should edit only the middle part
  let edits = text_lens_diff("abXYZcd", "ab123cd")
  inspect(edits.length(), content="2") // Insert then delete
  // First should be insert at position 2
  match edits[0] {
    TextInsert(position~, text~) => {
      inspect(position, content="2")
      inspect(text, content="123")
    }
    _ => abort("Expected TextInsert first")
  }
  // Second should be delete (adjusted for the insert)
  match edits[1] {
    TextDelete(start~, end~) => {
      // After inserting "123" (3 chars) at position 2,
      // the old "XYZ" is now at positions 5-8
      inspect(start, content="5")
      inspect(end, content="8")
    }
    _ => abort("Expected TextDelete second")
  }
}

///|
test "text_lens_diff identical strings produce no edits" {
  let edits = text_lens_diff("same text", "same text")
  inspect(edits.length(), content="0")
}

///|
test "text_lens_diff empty to non-empty" {
  let edits = text_lens_diff("", "hello")
  inspect(edits.length(), content="1")
  match edits[0] {
    TextInsert(position~, text~) => {
      inspect(position, content="0")
      inspect(text, content="hello")
    }
    _ => abort("Expected TextInsert")
  }
}

///|
test "text_lens_diff non-empty to empty" {
  let edits = text_lens_diff("hello", "")
  inspect(edits.length(), content="1")
  match edits[0] {
    TextDelete(start~, end~) => {
      inspect(start, content="0")
      inspect(end, content="5")
    }
    _ => abort("Expected TextDelete")
  }
}

// =============================================================================
// Bug Fix Tests: reconcile_children (node unregistration)
// =============================================================================

///|
test "reconcile_ast removes nodes from registry when children decrease" {
  // Create model with AST: (x y z) - application with 3 parts conceptually
  // Actually let's use a binary operation: x + y
  let (ast1, _) = parse_to_proj_node("1 + 2 + 3")
  let model = CanonicalModel::from_ast(ast1)
  let initial_count = model.node_count()

  // Use text_lens_put which internally calls reconcile_ast with simpler expression
  match text_lens_put(model, "1 + 2") {
    Ok(updated_model) => {
      // After reconciliation, node count should be less
      let final_count = updated_model.node_count()
      inspect(final_count < initial_count, content="true")
    }
    Err(msg) => abort("text_lens_put failed: " + msg)
  }
}

///|
test "reconcile preserves IDs for matching nodes" {
  // Parse initial expression
  let (ast1, _) = parse_to_proj_node("x + 1")
  let model = CanonicalModel::from_ast(ast1)

  // Get the root node ID
  let root_id = match model.get_ast() {
    Some(ast) => ast.node_id
    None => abort("No AST")
  }

  // Reconcile with same structure, different value
  match text_lens_put(model, "x + 2") {
    Ok(updated_model) =>
      // Root ID should be preserved (same structure)
      match updated_model.get_ast() {
        Some(ast) => inspect(ast.node_id, content=root_id.to_string())
        None => abort("No AST after reconcile")
      }
    Err(msg) => abort("text_lens_put failed: " + msg)
  }
}

// =============================================================================
// Regression: parenthesized expressions cover paren positions
// =============================================================================

///|
test "node_at_position covers parenthesis positions" {
  // (x) should have span 0..3, not 1..2
  let (ast, _) = parse_to_proj_node("(x)")
  let model = CanonicalModel::from_ast(ast)
  // Position 0 = '(' — must resolve to a node
  inspect(model.node_at_position(0) is None, content="false")
  // Position 2 = ')' — must resolve to a node
  inspect(model.node_at_position(2) is None, content="false")
  // The inner node should span the full parenthesized range
  inspect(ast.start, content="0")
  inspect(ast.end, content="3")
}

// =============================================================================
// Bug Fix Tests: apply_edit (position shifting)
// See source_map_wbtest.mbt for whitebox tests that access internal types
// =============================================================================
