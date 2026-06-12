// Tests for ViewUpdater: compute_view_patches and get_view_tree.
// Uses the neutral TestExpr grammar — these exercise the generic view-diffing
// pipeline (FullTree / Update / Replace / Insert / Remove / diagnostics), not
// language-specific decorations (those live in lang/lambda).

///|
test "get_view_tree returns ViewNode for non-empty editor" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let tree = editor.get_view_tree()
  assert_true(tree is Some(_))
  let node = tree.unwrap()
  inspect(node.kind_tag, content="Branch")
  assert_true(node.children.length() > 0)
}

///|
test "initial state produces FullTree patch" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let state = @editor.ViewUpdateState::ViewUpdateState()
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let state = @editor.ViewUpdateState::ViewUpdateState()
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Change "a" to "b"
  editor.set_text("b")
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain an UpdateNode or ReplaceNode reflecting the new value "b".
  let has_update = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::UpdateNode(label~, ..) => label == "b"
        @protocol.ViewPatch::ReplaceNode(node~, ..) => node.label == "b"
        _ => false
      }
    })
  assert_true(has_update)
}

///|
test "structural edit produces ReplaceNode" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("x")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Change from Leaf to Branch — structural change
  editor.set_text("f(x)")
  let patches = @editor.compute_view_patches(state, editor)
  // Should contain a ReplaceNode (kind changed from Leaf to Branch)
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("foo(") // unclosed '('
  let state = @editor.ViewUpdateState::ViewUpdateState()
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("foo(") // unclosed '('
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Fix the parse error
  editor.set_text("foo(x)")
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(a)")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Add another child
  editor.set_text("f(a b)")
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(a b)")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Remove one child
  editor.set_text("f(a)")
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
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let proj_node = editor.get_proj_node().unwrap()
  let source_map = editor.get_source_map()
  let view_node = @protocol.proj_to_view_node(proj_node, source_map)
  // Root should be Branch
  inspect(view_node.kind_tag, content="Branch")
  // Should have a child
  assert_true(view_node.children.length() > 0)
  // JSON serialization should work
  let json_str = view_node.to_json().stringify()
  assert_true(json_str.has_prefix("{"))
}

///|
test "proj_to_view_node node_count for 10 branches" {
  let editor = @probe.new_test_editor("test")
  let segments : Array[String] = []
  for i = 0; i < 10; i = i + 1 {
    segments.push("f\{i}(x)")
  }
  editor.set_text(segments.join(" "))
  let proj_node = editor.get_proj_node().unwrap()
  let source_map = editor.get_source_map()
  let view_node = @protocol.proj_to_view_node(proj_node, source_map)
  let count = view_node.node_count()
  // Reasonable node count for 10 branches each with one leaf child.
  assert_true(count >= 10)
  assert_true(count <= 200)
}
