///|
/// Property: concatenating view node line texts with newlines equals render_string.
fn prop_view_text_matches_render(term : @ast.Term) -> Bool {
  let layout = @pretty.Pretty::to_layout(term)
  let view = @protocol.layout_to_view_tree(layout)
  let buf = StringBuilder::new()
  for i, child in view.children {
    if i > 0 {
      buf.write_char('\n')
    }
    match child.text {
      Some(t) => buf.write_string(t)
      None => ()
    }
  }
  let view_text = buf.to_string()
  let expected = @pretty.render_string(layout)
  view_text == expected
}

///|
test "property: view tree text == render_string" {
  @qc.quick_check_fn(prop_view_text_matches_render)
}

///|
/// Property: token spans within each line do not overlap.
fn prop_token_spans_no_overlap(term : @ast.Term) -> Bool {
  let layout = @pretty.Pretty::to_layout(term)
  let view = @protocol.layout_to_view_tree(layout)
  for child in view.children {
    let sorted = child.token_spans.copy()
    sorted.sort_by(fn(a, b) { a.start.compare(b.start) })
    for i = 1; i < sorted.length(); i = i + 1 {
      if sorted[i].start < sorted[i - 1].end {
        return false
      }
    }
  }
  true
}

///|
test "property: token spans do not overlap within a line" {
  @qc.quick_check_fn(prop_token_spans_no_overlap)
}
