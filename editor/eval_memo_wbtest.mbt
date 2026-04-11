///|
test "pretty_view: eval annotations appear after edit" {
  let editor = @lambda.new_lambda_editor("test-eval-pretty").0
  editor.set_text("let x = 5\nx")
  let view = editor.get_pretty_view()
  let lines = view.children
  let has_eval_span = lines
    .iter()
    .any(fn(line) {
      line.token_spans.iter().any(fn(span) { span.role == "eval-annotation" })
    })
  inspect(has_eval_span, content="true")
}

///|
test "get_eval_annotations: module defs have annotations" {
  let (editor, companion) = @lambda.new_lambda_editor("test-struct-ann")
  editor.set_text("let x = 5\nx")
  let annotations = companion.get_eval_annotations(editor.get_proj_node())
  inspect(annotations.length() > 0, content="true")
}

///|
test "get_eval_annotations: empty for no text" {
  let (editor, companion) = @lambda.new_lambda_editor("test-struct-ann-empty")
  let annotations = companion.get_eval_annotations(editor.get_proj_node())
  inspect(annotations.length(), content="0")
}

///|
test "get_view_tree: annotations attached to view nodes" {
  let editor = @lambda.new_lambda_editor("test-view-eval").0
  editor.set_text("let x = 5\nx")
  let view = editor.get_view_tree()
  guard view is Some(root)
  // Check that at least one child node has annotations
  let has_annotation = root.children
    .iter()
    .any(fn(child) { child.annotations.length() > 0 })
  inspect(has_annotation, content="true")
}
