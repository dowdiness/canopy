///| Whitebox tests for Markdown projection.

///|
test "projection: empty document" {
  let (proj, errors) = parse_to_proj_node("")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="0")
}

///|
test "projection: single paragraph" {
  let (proj, _) = parse_to_proj_node("Hello world")
  inspect(proj.children.length(), content="1")
}

///|
test "projection: heading levels" {
  let (proj, _) = parse_to_proj_node("# H1\n\n## H2\n\n### H3")
  inspect(proj.children.length(), content="3")
}

///|
test "projection: unordered list" {
  let (proj, _) = parse_to_proj_node("- first\n- second\n- third")
  inspect(proj.children.length(), content="1")
  let list = proj.children[0]
  inspect(list.children.length(), content="3")
}

///|
test "projection: ordered list" {
  let (proj, _) = parse_to_proj_node("1. first\n2. second\n")
  inspect(proj.children.length(), content="1")
  let list = proj.children[0]
  match list.kind {
    OrderedList(_, Some(marker)) => inspect(marker.text(), content="1.")
    _ => fail("expected ordered-list payload")
  }
  inspect(list.children.length(), content="2")
}

///|
test "source map: ordered list item text excludes marker" {
  let source = "1. first\n2. second\n"
  let (proj, _) = parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(source)
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let item = proj.children[0].children[0]
  match source_map.get_token_span(item.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.end].to_owned(), content="first")
    None => fail("expected ordered list item text span")
  }
}

///|
test "view: ordered list keeps ordered kind tag from payload" {
  let source = "1. first\n2. second\n"
  let (proj, _) = parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  let view = proj_to_view_node(proj, source_map, source_text=Some(source))
  inspect(view.children[0].kind_tag, content="OrderedList")
}

///|
test "source map: outer ordered item marker wins over nested bullet" {
  let source = "1. parent\n   - child\n"
  let (proj, _) = parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(source)
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let item = proj.children[0].children[0]
  match source_map.get_token_span(item.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.start + 6].to_owned(), content="parent")
    None => fail("expected outer ordered list item text span")
  }
}

///|
test "projection: code block" {
  let (proj, _) = parse_to_proj_node("```js\nconsole.log(42)\n```")
  inspect(proj.children.length(), content="1")
}

///|
test "projection: html block" {
  let source = "# Before\n\n<div>\nraw\n</div>\n\nAfter"
  let (proj, _) = parse_to_proj_node(source)
  inspect(proj.children.length(), content="3")
  match proj.children[1].kind {
    HtmlBlock(value) => inspect(value, content="<div>\nraw\n</div>\n")
    _ => fail("expected html block payload")
  }
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(source)
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  // Verify the "text" span covers the raw HTML content
  match source_map.get_token_span(proj.children[1].id(), "text") {
    Some(range) => inspect(source[range.start:range.end], content="<div>\nraw\n</div>\n")
    None => fail("expected text span for html block")
  }
}

///|
test "projection: mixed blocks" {
  let source = "# Title\n\nSome text.\n\n- item one\n- item two\n\nMore text."
  let (proj, _) = parse_to_proj_node(source)
  inspect(proj.children.length(), content="4")
}

///|
test "projection: node positions span source text" {
  let source = "# Hello\n\nWorld"
  let (proj, _) = parse_to_proj_node(source)
  inspect(proj.start, content="0")
  inspect(proj.children[0].start, content="0")
}

///|
test "projection: IDs are unique" {
  let (proj, _) = parse_to_proj_node("# H1\n\n- a\n- b")
  let ids : Array[Int] = []
  fn collect(node : @core.ProjNode[@markdown.Block]) {
    ids.push(node.node_id)
    for child in node.children {
      collect(child)
    }
  }
  collect(proj)
  let unique : Map[Int, Bool] = {}
  let mut all_unique = true
  for id in ids {
    if unique.get(id) == Some(true) {
      all_unique = false
    }
    unique[id] = true
  }
  inspect(all_unique, content="true")
}

///|
test "projection: incremental reparse preserves IDs" {
  let source = "# Hello\n\nWorld"
  let parser = @loom.new_imperative_parser(source, @markdown.markdown_grammar)
  let counter : Ref[Int] = Ref(0)
  // Initial parse
  let _ = parser.parse()
  // First projection
  let syntax1 = parser.get_syntax_tree().unwrap()
  let proj1 = syntax_to_proj_node(syntax1, counter)
  let heading_id = proj1.children[0].node_id
  let para_id = proj1.children[1].node_id
  // Incremental edit: change "World" to "World!"
  // Edit::new(start, old_len, new_len) — "World" starts at offset 9, 5 chars → 6 chars
  let edit = @loomcore.Edit::new(9, 5, 6)
  let _ = parser.edit(edit, "# Hello\n\nWorld!")
  // Second projection with reconciliation
  let syntax2 = parser.get_syntax_tree().unwrap()
  let proj2_raw = syntax_to_proj_node(syntax2, counter)
  let proj2 = @core.reconcile(proj1, proj2_raw, counter)
  // IDs should be preserved for unchanged structure
  inspect(proj2.children[0].node_id == heading_id, content="true")
  // Paragraph content changed, but structure is same — ID preserved
  inspect(proj2.children[1].node_id == para_id, content="true")
}
