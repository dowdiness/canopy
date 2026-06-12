// Lambda view tests for the lambda editor, moved here from
// editor/view_updater_test.mbt as part of the editor-neutral-test-grammar
// work (#599):
//   - semantic-binder / semantic-bound decorations come from lambda's
//     LanguageCapabilities;
//   - empty-source → None projection (and the resulting FullTree(None)) is
//     lambda's projection special-casing — the generic projection used by the
//     neutral TestExpr grammar always yields a (possibly empty) tree.

///|
test "get_view_tree returns None for empty editor" {
  let editor = new_lambda_editor("test").0
  let tree = editor.get_view_tree()
  assert_true(tree is None)
}

///|
test "FullTree emitted when tree appears from empty" {
  let editor = new_lambda_editor("test").0
  let state = @editor.ViewUpdateState::ViewUpdateState()
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

///|
test "semantic decorations are emitted and stable" {
  let editor = new_lambda_editor("test-semantic-decorations").0
  editor.set_text("λx. x")
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let patches = @editor.compute_view_patches(state, editor)
  let has_semantic_decoration = patches
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::SetDecorations(decorations~) =>
          decorations
          .iter()
          .any(fn(d) {
            d.css_class == "semantic-binder" || d.css_class == "semantic-bound"
          })
        _ => false
      }
    })
  assert_true(has_semantic_decoration)
  let unchanged = @editor.compute_view_patches(state, editor)
  let repeats_decorations = unchanged
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::SetDecorations(_) => true
        _ => false
      }
    })
  inspect(repeats_decorations, content="false")
}
