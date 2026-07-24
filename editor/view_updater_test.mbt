// Tests for ViewUpdater: compute_view_patches and get_view_tree.
// Uses the neutral TestExpr grammar — these exercise the generic view-diffing
// pipeline (FullTree / Update / Replace / Insert / Remove / diagnostics), not
// language-specific decorations (those live in lang/lambda).

///|
test "get_view_tree returns ViewNode for non-empty editor" {
  let editor = try! @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let tree = editor.get_view_tree()
  assert_true(tree is Some(_))
  let node = tree.unwrap()
  inspect(node.kind_tag, content="Branch")
  assert_true(node.children.length() > 0)
}

///|
// #2 (issue #600): the empty / first-render generic editor. Unlike lambda
// (whose empty source folds to `None`), the neutral TestExpr grammar always
// yields the empty-document `Branch("", [])`, so `get_view_tree` is `Some` even
// with no text and the first `compute_view_patches` emits a `FullTree`. This
// pins the generic empty-document behavior, which the moved lambda companion
// test (`editor_view_decorations_test.mbt`) does not cover.
test "empty generic editor yields an empty-document view and a FullTree patch" {
  let editor = try! @probe.new_test_editor("test")
  // No text inserted.
  let tree = editor.get_view_tree()
  assert_true(tree is Some(_))
  let node = tree.unwrap()
  inspect(node.kind_tag, content="Branch")
  inspect(node.label, content="")
  inspect(node.children.length(), content="0")
  // First render emits a FullTree patch (previous view is None).
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let patches = @editor.compute_view_patches(state, editor)
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
// #3 (issue #600): NodeId stability across an unrelated sibling edit, on the
// neutral grammar. Editing one sibling's label must not renumber an untouched
// sibling — `reconcile` preserves the NodeId when `same_kind` holds. The moved
// lambda companion test asserts this only against lambda's Module/def-index
// projection; this pins it for the generic pipeline.
test "NodeId stable across an unrelated sibling edit" {
  let editor = try! @probe.new_test_editor("test")
  editor.set_text("f(x y)")
  // root Branch("") -> child Branch("f") -> [Leaf("x"), Leaf("y")]
  let root = editor.get_proj_node().unwrap()
  let x_id = root.children[0].children[0].id()
  // Edit only the sibling: "y" -> "z". The "x" leaf is untouched.
  editor.set_text("f(x z)")
  // "x" must keep its identity: the same NodeId still resolves to Leaf("x").
  match editor.get_node(x_id) {
    Some(node) => inspect(node.kind, content="Leaf(\"x\")")
    None => fail("x leaf lost its NodeId after an unrelated sibling edit")
  }
}

///|
test "initial state produces FullTree patch" {
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
// #8 (issue #600): a pure leaf-label change must emit a minimal `UpdateNode`,
// not a `ReplaceNode`. The Leaf("a") -> Leaf("b") edit keeps the kind (so
// `same_kind` holds, the NodeId is preserved) and TestExpr has all-None
// capabilities — no eval-annotation churn to force a wider patch. The earlier
// UpdateNode-OR-ReplaceNode looseness only existed to tolerate lambda's
// eval-annotation diffs, which the generic pipeline does not produce. Assert
// the tight shape so diff minimality is actually verified.
test "single character leaf edit produces a minimal UpdateNode (not ReplaceNode)" {
  let editor = try! @probe.new_test_editor("test")
  editor.set_text("a")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let _ = @editor.compute_view_patches(state, editor)
  // Change "a" to "b"
  editor.set_text("b")
  let patches = @editor.compute_view_patches(state, editor)
  // The new label "b" arrives via UpdateNode...
  let has_update_b = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::UpdateNode(label~, ..) => label == "b"
        _ => false
      }
    })
  assert_true(has_update_b)
  // ...and NOT via a ReplaceNode (which would mean the diff rebuilt the leaf
  // instead of updating it in place).
  let has_replace = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::ReplaceNode(_) => true
        _ => false
      }
    })
  assert_false(has_replace)
}

///|
test "structural edit produces ReplaceNode" {
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
  let editor = try! @probe.new_test_editor("test")
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
