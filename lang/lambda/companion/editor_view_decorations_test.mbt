// Lambda view tests for the lambda editor, moved here from
// editor/view_updater_test.mbt as part of the editor-neutral-test-grammar
// work (#599):
//   - semantic-binder / semantic-bound decorations come from lambda's
//     LanguageCapabilities;
//   - empty source now follows the generic projection memo path and yields a
//     Unit projection rather than Lambda's former flat-memo `None` special case.

///|
test "get_view_tree returns Unit for empty editor" {
  let editor = new_lambda_editor("test").0
  let tree = editor.get_view_tree()
  guard tree is Some(node) else { fail("expected Unit projection") }
  inspect(node.kind_tag, content="Unit")
}

///|
test "FullTree emitted for empty editor then updated after text" {
  let editor = new_lambda_editor("test").0
  let state = @editor.ViewUpdateState::ViewUpdateState()
  let patches1 = @editor.compute_view_patches(state, editor)
  let full_tree_unit = patches1
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::FullTree(root=Some(node)) =>
          node.kind_tag == "Unit"
        _ => false
      }
    })
  assert_true(full_tree_unit)
  editor.set_text("1")
  let patches2 = @editor.compute_view_patches(state, editor)
  let has_tree_update = patches2
    .iter()
    .any(fn(p) {
      match p {
        @protocol.ViewPatch::ReplaceNode(_)
        | @protocol.ViewPatch::UpdateNode(_) => true
        _ => false
      }
    })
  assert_true(has_tree_update)
}

///|
test "semantic decorations are emitted and stable" {
  let editor = new_lambda_editor("test-semantic-decorations").0
  editor.set_text("(x) => x")
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
