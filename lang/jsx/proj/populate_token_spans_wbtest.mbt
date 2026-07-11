///| Regression tests for populate_token_spans (Task 2.3), including a
/// Codex-review-caught bug (2026-07-11): an unclosed element's lone
/// open-tag `>` was being recorded as its `close_bracket`, and nested
/// same-tag elements' `close_bracket` disambiguation was unverified.

///|
fn source_map_for(
  text : String,
) -> (@core.ProjNode[@jsx.JsxNode], @core.SourceMap) {
  let parser = @loom.new_parser(text, @jsx.jsx_grammar)
  let (proj_memo, _, source_map_memo) = build_jsx_projection_memos(parser)
  let root = proj_memo.read_or_abort().unwrap()
  let source_map = source_map_memo.read_or_abort()
  (root, source_map)
}

///|
test "token spans: unclosed element has no close_bracket" {
  let (root, source_map) = source_map_for("<div><span>text")
  let div = root.children[0]
  inspect(
    source_map.get_token_span(div.id(), "close_bracket") is None,
    content="true",
  )
}

///|
test "token spans: closed element has close_bracket at its own '>'" {
  // "<p>hi</p>" — the close tag's '>' is the last character, offset 8..9.
  let (root, source_map) = source_map_for("<p>hi</p>")
  let p = root.children[0]
  let span = source_map.get_token_span(p.id(), "close_bracket").unwrap()
  inspect(span.start, content="8")
  inspect(span.end, content="9")
}

///|
test "token spans: nested same-tag elements each get their own close_bracket" {
  // "<div><div>x</div></div>" — inner '>' at 16..17, outer '>' at 22..23.
  let (root, source_map) = source_map_for("<div><div>x</div></div>")
  let outer = root.children[0]
  let inner = outer.children[0]
  let outer_span = source_map
    .get_token_span(outer.id(), "close_bracket")
    .unwrap()
  let inner_span = source_map
    .get_token_span(inner.id(), "close_bracket")
    .unwrap()
  inspect(inner_span.start, content="16")
  inspect(outer_span.start, content="22")
}
