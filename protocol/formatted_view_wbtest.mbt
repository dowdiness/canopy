///|
test "layout_to_view_tree: single line, no annotations" {
  let layout = @pretty.text("hello world")
  let view = layout_to_view_tree(layout)
  assert_eq(view.kind_tag, "formatted-text")
  assert_eq(view.children.length(), 1)
  assert_eq(view.children[0].text, Some("hello world"))
  assert_eq(view.children[0].token_spans.length(), 0)
}

///|
test "layout_to_view_tree: single line with annotation" {
  let layout = @pretty.annotate(
    @pretty.SyntaxCategory::Keyword,
    @pretty.text("let"),
  )
  let view = layout_to_view_tree(layout)
  assert_eq(view.children.length(), 1)
  let line = view.children[0]
  assert_eq(line.text, Some("let"))
  assert_eq(line.token_spans.length(), 1)
  assert_eq(line.token_spans[0].role, "keyword")
  assert_eq(line.token_spans[0].start, 0)
  assert_eq(line.token_spans[0].end, 3)
}

///|
test "layout_to_view_tree: multi-line with nest" {
  let layout = @pretty.concat(
    @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text("let")),
    @pretty.nest(
      @pretty.concat(
        @pretty.hardline(),
        @pretty.annotate(@pretty.SyntaxCategory::Identifier, @pretty.text("x")),
      ),
      indent=2,
    ),
  )
  let view = layout_to_view_tree(layout)
  assert_eq(view.children.length(), 2)
  let line0 = view.children[0]
  assert_eq(line0.text, Some("let"))
  assert_eq(line0.token_spans.length(), 1)
  assert_eq(line0.token_spans[0].role, "keyword")
  let line1 = view.children[1]
  assert_eq(line1.text, Some("  x"))
  assert_eq(line1.token_spans.length(), 1)
  assert_eq(line1.token_spans[0].role, "identifier")
  assert_eq(line1.token_spans[0].start, 2)
  assert_eq(line1.token_spans[0].end, 3)
}

///|
test "layout_to_view_tree: annotation spanning line break" {
  let inner = @pretty.concat(
    @pretty.text("if"),
    @pretty.concat(@pretty.hardline(), @pretty.text("then")),
  )
  let layout = @pretty.annotate(@pretty.SyntaxCategory::Keyword, inner)
  let view = layout_to_view_tree(layout)
  assert_eq(view.children.length(), 2)
  let line0 = view.children[0]
  assert_eq(line0.text, Some("if"))
  assert_eq(line0.token_spans.length(), 1)
  assert_eq(line0.token_spans[0].role, "keyword")
  assert_eq(line0.token_spans[0].start, 0)
  assert_eq(line0.token_spans[0].end, 2)
  let line1 = view.children[1]
  assert_eq(line1.text, Some("then"))
  assert_eq(line1.token_spans.length(), 1)
  assert_eq(line1.token_spans[0].role, "keyword")
  assert_eq(line1.token_spans[0].start, 0)
  assert_eq(line1.token_spans[0].end, 4)
}

///|
test "layout_to_view_tree: mixed annotated and unannotated text" {
  let layout = @pretty.concat(
    @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text("let")),
    @pretty.concat(
      @pretty.text(" "),
      @pretty.concat(
        @pretty.annotate(@pretty.SyntaxCategory::Identifier, @pretty.text("x")),
        @pretty.concat(
          @pretty.text(" = "),
          @pretty.annotate(@pretty.SyntaxCategory::Number, @pretty.text("42")),
        ),
      ),
    ),
  )
  let view = layout_to_view_tree(layout)
  assert_eq(view.children.length(), 1)
  let line = view.children[0]
  assert_eq(line.text, Some("let x = 42"))
  assert_eq(line.token_spans.length(), 3)
  assert_eq(line.token_spans[0].role, "keyword")
  assert_eq(line.token_spans[0].start, 0)
  assert_eq(line.token_spans[0].end, 3)
  assert_eq(line.token_spans[1].role, "identifier")
  assert_eq(line.token_spans[1].start, 4)
  assert_eq(line.token_spans[1].end, 5)
  assert_eq(line.token_spans[2].role, "number")
  assert_eq(line.token_spans[2].start, 8)
  assert_eq(line.token_spans[2].end, 10)
}

///|
test "layout_to_view_tree: empty layout" {
  let layout : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.text("")
  let view = layout_to_view_tree(layout)
  assert_eq(view.kind_tag, "formatted-text")
  assert_eq(view.children.length(), 0)
}

///|
test "layout_to_view_tree: node IDs are sequential" {
  let layout = @pretty.concat(
    @pretty.text("a"),
    @pretty.concat(@pretty.hardline(), @pretty.text("b")),
  )
  let view = layout_to_view_tree(layout)
  assert_eq(view.id, @core.NodeId::from_int(0))
  assert_eq(view.children[0].id, @core.NodeId::from_int(1))
  assert_eq(view.children[1].id, @core.NodeId::from_int(2))
}

///|
test "layout_to_view_tree: group flattening (narrow width)" {
  let layout = @pretty.group(
    @pretty.concat(
      @pretty.text("a"),
      @pretty.concat(@pretty.line(), @pretty.text("b")),
    ),
  )
  let wide = layout_to_view_tree(layout, width=80)
  assert_eq(wide.children.length(), 1)
  assert_eq(wide.children[0].text, Some("a b"))
  let narrow = layout_to_view_tree(layout, width=1)
  assert_eq(narrow.children.length(), 2)
  assert_eq(narrow.children[0].text, Some("a"))
  assert_eq(narrow.children[1].text, Some("b"))
}
