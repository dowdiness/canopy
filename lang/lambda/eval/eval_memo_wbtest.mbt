///|
test "split_at_hardlines: separates module layout into segments" {
  let layout : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.separate(
    @pretty.hardline(),
    [@pretty.text("def0"), @pretty.text("def1"), @pretty.text("body")],
  )
  let segments = split_at_hardlines(layout)
  inspect(segments.length(), content="3")
  inspect(@pretty.render_string(segments[0], width=80), content="def0")
  inspect(@pretty.render_string(segments[1], width=80), content="def1")
  inspect(@pretty.render_string(segments[2], width=80), content="body")
}

///|
test "split_at_hardlines: single segment (no hardlines)" {
  let layout : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.text("hello")
  let segments = split_at_hardlines(layout)
  inspect(segments.length(), content="1")
}

///|
test "inject_eval_annotations: adds arrow to each segment" {
  let ast = @ast.Term::Module([("x", @ast.Term::Int(5))], @ast.Term::Var("x"))
  let layout = @pretty.Pretty::to_layout(ast)
  let results : Array[EvalResult] = [
    EvalResult::Value("5"),
    EvalResult::Value("5"),
  ]
  let annotated = inject_eval_annotations(layout, results)
  let text = @pretty.render_string(annotated, width=80)
  inspect(text.contains("\u{2192} 5"), content="true")
}

///|
test "inject_eval_annotations: suppressed results add nothing" {
  let ast = @ast.Term::Module([("x", @ast.Term::Hole(0))], @ast.Term::Hole(1))
  let layout = @pretty.Pretty::to_layout(ast)
  let results : Array[EvalResult] = [
    EvalResult::Suppressed,
    EvalResult::Suppressed,
  ]
  let annotated = inject_eval_annotations(layout, results)
  let text = @pretty.render_string(annotated, width=80)
  inspect(text.contains("\u{2192}"), content="false")
}

///|
test "inject_eval_annotations: error results have EvalError category" {
  let ast = @ast.Term::Var("x")
  let layout = @pretty.Pretty::to_layout(ast)
  let results : Array[EvalResult] = [
    EvalResult::Stuck("\u{2039}unbound: x\u{203a}"),
  ]
  let annotated = inject_eval_annotations(layout, results)
  let rendered = @pretty.render_spans(annotated, width=80)
  let has_eval_error = rendered
    .iter()
    .any(fn(pair) { pair.1 == @pretty.SyntaxCategory::EvalError })
  inspect(has_eval_error, content="true")
}
