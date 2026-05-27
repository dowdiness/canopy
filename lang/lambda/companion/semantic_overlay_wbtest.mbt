///|
test "semantic overlay annotations appear in lambda view tree" {
  let editor = new_lambda_editor("semantic-overlay-view").0
  editor.set_text("λx. x")
  let view = editor.get_view_tree()
  guard view is Some(root)
  assert_true(
    root.annotations
    .iter()
    .any(fn(ann) { ann.kind == "semantic-binder" && ann.label == "λx" }),
  )
  assert_true(
    root.children[0].annotations
    .iter()
    .any(fn(ann) { ann.kind == "semantic-ref" && ann.label == "bound x" }),
  )
}
