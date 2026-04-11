// Tests for ViewUpdater: compute_view_patches and get_view_tree.

///|
test "get_view_tree returns None for empty editor" {
  let editor = @lambda.new_lambda_editor("test").0
  let tree = editor.get_view_tree()
  assert_true(tree is None)
}

///|
test "get_view_tree returns ViewNode for non-empty editor" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("\\x.x")
  let tree = editor.get_view_tree()
  assert_true(tree is Some(_))
  let node = tree.unwrap()
  inspect(node.kind_tag, content="Lam")
  assert_true(node.children.length() > 0)
}

///|
test "initial state produces FullTree patch" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("\\x.x")
  let state = @editor.ViewUpdateState::new()
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain FullTree since previous is None
  let has_full_tree = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::FullTree(_) => true
        _ => false
      }
    })
  assert_true(has_full_tree)
}

///|
test "unchanged tree produces no tree patches" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("\\x.x")
  let state = @editor.ViewUpdateState::new()
  // First call: FullTree
  let _ = @editor.compute_view_patches(state, editor)
  // Second call without changes: no tree patches (only diagnostics)
  let patches = @editor.compute_view_patches(state, editor)
  let tree_patches = patches
    .iter()
    .filter(fn(p) {
      match p {
        @protocol.ViewPatch::FullTree(_) => true
        @protocol.ViewPatch::ReplaceNode(_) => true
        @protocol.ViewPatch::InsertChild(_) => true
        @protocol.ViewPatch::RemoveChild(_) => true
        @protocol.ViewPatch::UpdateNode(_) => true
        _ => false
      }
    })
    .collect()
  // Should have no tree-modifying patches
  inspect(tree_patches.length(), content="0")
}

///|
test "single character edit produces UpdateNode or ReplaceNode for changed leaf" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("1")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, editor)
  // Change "1" to "2"
  editor.set_text("2")
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain an UpdateNode or ReplaceNode reflecting the new value "2".
  // With language capabilities providing eval annotations, annotation changes
  // may cause ReplaceNode instead of UpdateNode.
  let has_update = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::UpdateNode(label~, ..) => label == "2"
        @protocol.ViewPatch::ReplaceNode(node~, ..) => node.label == "2"
        _ => false
      }
    })
  assert_true(has_update)
}

///|
test "structural edit produces ReplaceNode" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, editor)
  // Change from Var to Lam — structural change
  editor.set_text("\\x.x")
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain a ReplaceNode (kind changed from Var to Lam)
  let has_replace = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::ReplaceNode(_) => true
        _ => false
      }
    })
  assert_true(has_replace)
}

///|
test "diagnostics are emitted for parse errors" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x +")
  let state = @editor.ViewUpdateState::new()
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain SetDiagnostics with errors
  let has_diagnostics = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::SetDiagnostics(diagnostics~) =>
          diagnostics.length() > 0
        _ => false
      }
    })
  assert_true(has_diagnostics)
}

///|
test "diagnostics are cleared when parse succeeds" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x +")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, editor)
  // Fix the parse error
  editor.set_text("x + 1")
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain SetDiagnostics with empty diagnostics
  let has_empty_diagnostics = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::SetDiagnostics(diagnostics~) =>
          diagnostics.length() == 0
        _ => false
      }
    })
  assert_true(has_empty_diagnostics)
}

///|
test "child insertion detected" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("let x = 1\nx")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, editor)
  // Add another definition
  editor.set_text("let x = 1\nlet y = 2\nx")
  let patches = @editor.compute_view_patches(state, editor)
  // Should have InsertChild or ReplaceNode for the structural change
  let has_structural = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::InsertChild(_) => true
        @protocol.ViewPatch::ReplaceNode(_) => true
        _ => false
      }
    })
  assert_true(has_structural)
}

///|
test "child removal detected" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("let x = 1\nlet y = 2\nx")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, editor)
  // Remove one definition
  editor.set_text("let x = 1\nx")
  let patches = @editor.compute_view_patches(state, editor)
  // Should have RemoveChild or ReplaceNode
  let has_structural = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::RemoveChild(_) => true
        @protocol.ViewPatch::ReplaceNode(_) => true
        _ => false
      }
    })
  assert_true(has_structural)
}

///|
test "proj_to_view_node converts a simple ProjNode tree" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("\\x.x")
  let proj_node = editor.get_proj_node().unwrap()
  let source_map = editor.get_source_map()
  let view_node = @protocol.proj_to_view_node(proj_node, source_map)
  // Root should be Lam
  inspect(view_node.kind_tag, content="Lam")
  // Should have a child (the body Var)
  assert_true(view_node.children.length() > 0)
  // JSON serialization should work
  let json_str = view_node.to_json().stringify()
  assert_true(json_str.has_prefix("{"))
}

///|
test "proj_to_view_node node_count for 10 defs" {
  let editor = @lambda.new_lambda_editor("test").0
  let segments : Array[String] = []
  for i = 0; i < 10; i = i + 1 {
    segments.push("let f\{i} = \\x.x + \{i}")
  }
  segments.push("f0")
  editor.set_text(segments.join("\n"))
  let proj_node = editor.get_proj_node().unwrap()
  let source_map = editor.get_source_map()
  let view_node = @protocol.proj_to_view_node(proj_node, source_map)
  let count = view_node.node_count()
  // Reasonable node count for 10 defs with lambda/bop structure
  assert_true(count >= 30)
  assert_true(count <= 200)
}

///|
test "FullTree emitted when tree appears from empty" {
  let editor = @lambda.new_lambda_editor("test").0
  let state = @editor.ViewUpdateState::new()
  // Empty editor — no tree
  let patches1 = @editor.compute_view_patches(state, editor)
  let full_tree_none = patches1
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::FullTree(root=None) => true
        _ => false
      }
    })
  assert_true(full_tree_none)
  // Now add text
  editor.set_text("1")
  let patches2 = @editor.compute_view_patches(state, editor)
  let full_tree_some = patches2
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::FullTree(root=Some(_)) => true
        _ => false
      }
    })
  assert_true(full_tree_some)
}
