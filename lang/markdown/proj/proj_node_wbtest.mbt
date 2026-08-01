///| Whitebox tests for Markdown projection.

///|
let markdown_projection_test_source : @loomcore.SourceId = @loomcore.SourceId(
  "canopy-test:markdown-projection",
)

///|
test "projection: empty document" {
  let (proj, errors) = parse_to_proj_node(markdown_projection_test_source, "")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="0")
}

///|
test "projection: single paragraph" {
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "Hello world",
  )
  inspect(proj.children.length(), content="1")
}

///|
test "projection: heading levels" {
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "# H1\n\n## H2\n\n### H3",
  )
  inspect(proj.children.length(), content="3")
}

/// Block quotes keep their existing flattened paragraph payload as an aligned
/// leaf. Nested headings under unsupported containers are intentionally omitted
/// with their semantic/syntax descendants; direct document headings stay
/// editable and retain their own source range.

///|
test "projection: block quote before heading preserves payload alignment" {
  let source = "> quoted\n\n# Heading\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [quote, heading] => {
      match quote.kind {
        Paragraph([Text(text)]) => inspect(text, content="> quoted")
        _ => fail("expected flattened block quote paragraph payload")
      }
      match heading.kind {
        Heading(level, [Text(text)]) => {
          inspect(level, content="1")
          inspect(text, content="Heading")
        }
        _ => fail("expected heading payload")
      }
      inspect(quote.start, content="0")
      inspect(quote.end, content="9")
      inspect(heading.start, content="10")
    }
    _ => fail("expected aligned quote and heading projection children")
  }
}

///|
test "projection: heading before block quote preserves payload alignment" {
  let source = "# Heading\n\n> quoted\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [heading, quote] => {
      match heading.kind {
        Heading(level, [Text(text)]) => {
          inspect(level, content="1")
          inspect(text, content="Heading")
        }
        _ => fail("expected heading payload")
      }
      match quote.kind {
        Paragraph([Text(text)]) => inspect(text, content="> quoted")
        _ => fail("expected flattened block quote paragraph payload")
      }
      inspect(heading.start, content="0")
      inspect(heading.end, content="10")
      inspect(quote.start, content="11")
    }
    _ => fail("expected aligned heading and quote projection children")
  }
}

///|
test "projection: block quote before and after setext heading stays aligned" {
  let before_source = "> quoted\n\nTitle\n---\n"
  let (before, before_errors) = parse_to_proj_node(
    markdown_projection_test_source, before_source,
  )
  assert_eq(before_errors.length(), 0)
  match before.children {
    [quote, heading] => {
      match quote.kind {
        Paragraph([Text(text)]) => assert_eq(text, "> quoted")
        _ => fail("expected flattened block quote paragraph payload")
      }
      match heading.kind {
        Heading(2, [Text(text)]) => assert_eq(text, "Title")
        _ => fail("expected setext heading payload")
      }
    }
    _ => fail("expected quote and setext heading children")
  }
  let after_source = "Title\n---\n\n> quoted\n"
  let (after, after_errors) = parse_to_proj_node(
    markdown_projection_test_source, after_source,
  )
  assert_eq(after_errors.length(), 0)
  match after.children {
    [heading, quote] => {
      match heading.kind {
        Heading(2, [Text(text)]) => assert_eq(text, "Title")
        _ => fail("expected setext heading payload")
      }
      match quote.kind {
        Paragraph([Text(text)]) => assert_eq(text, "> quoted")
        _ => fail("expected flattened block quote paragraph payload")
      }
    }
    _ => fail("expected setext heading and quote children")
  }
}

///|
test "projection: thematic break keeps neighboring heading alignment" {
  let source = "# Before\n\n---\n\n## After\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [before, thematic, after] => {
      match before.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Before")
        _ => fail("expected leading heading payload")
      }
      match thematic.kind {
        Paragraph([Text(text)]) => inspect(text, content="---")
        _ => fail("expected thematic-break paragraph payload")
      }
      match after.kind {
        Heading(2, [Text(text)]) => inspect(text, content="After")
        _ => fail("expected trailing heading payload")
      }
      inspect(before.start, content="0")
      inspect(thematic.start, content="10")
      inspect(after.start, content="15")
    }
    _ => fail("expected aligned heading and thematic-break children")
  }
}

///|
test "projection: quote and heading terminators preserve alignment" {
  let cases : Array[(String, Int)] = [
    ("> quoted\n\n# Heading\n", 10),
    ("> quoted\r\n\r\n# Heading", 12),
    ("> quoted\r\r# Heading", 10),
    ("> quoted\n\n# Heading", 10),
  ]
  for case in cases {
    let source = case.0
    let (proj, errors) = parse_to_proj_node(
      markdown_projection_test_source, source,
    )
    assert_eq(errors.length(), 0)
    match proj.children {
      [quote, heading] => {
        match quote.kind {
          Paragraph([Text(text)]) => assert_eq(text, "> quoted")
          _ => fail("expected flattened block quote payload")
        }
        match heading.kind {
          Heading(1, [Text(text)]) => assert_eq(text, "Heading")
          _ => fail("expected heading payload")
        }
        assert_eq(heading.start, case.1)
      }
      _ => fail("expected aligned quote and heading projection children")
    }
  }
}

/// Nested headings under unsupported containers remain intentionally omitted:
/// the container's flattened semantic payload and its direct CST node are the
/// only projected value, so no descendant can shift a later direct heading.

///|
test "projection: quoted nested heading is omitted without shifting direct heading" {
  let source = "> # Nested\n\n# Direct\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [quote, heading] => {
      match quote.kind {
        Paragraph([Text(text)]) => inspect(text, content="> # Nested")
        _ => fail("expected flattened block quote payload")
      }
      match heading.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Direct")
        _ => fail("expected direct heading payload")
      }
      inspect(heading.start, content="12")
    }
    _ => fail("expected nested quote heading to stay omitted")
  }
}

///|
test "projection: listed nested heading is omitted without shifting direct heading" {
  let source = "- item\n  # Nested\n\n# Direct\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [list, heading] => {
      match list.kind {
        UnorderedList([UnorderedListItem([Text(text)])]) =>
          inspect(text, content="item")
        _ => fail("expected list item payload")
      }
      match heading.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Direct")
        _ => fail("expected direct heading payload")
      }
      inspect(heading.start, content="19")
    }
    _ => fail("expected nested list heading to stay omitted")
  }
}

///|
test "projection: ordered nested heading is omitted without shifting direct heading" {
  let source = "1. item\n   ## Nested\n\n# Direct\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [list, heading] => {
      match list.kind {
        OrderedList([OrderedListItem([Text(text)], Some(_))], Some(_)) =>
          inspect(text, content="item")
        _ => fail("expected ordered list item payload")
      }
      match heading.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Direct")
        _ => fail("expected direct heading payload")
      }
      inspect(heading.start, content="22")
    }
    _ => fail("expected nested ordered heading to stay omitted")
  }
}

///|
test "projection: quoted setext heading is omitted without shifting direct heading" {
  let source = "> Nested\n> ---\n\n# Direct\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [quote, heading] => {
      match quote.kind {
        Paragraph([Text(text)]) => inspect(text, content="> Nested\n> ---")
        _ => fail("expected flattened block quote payload")
      }
      match heading.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Direct")
        _ => fail("expected direct heading payload")
      }
      inspect(heading.start, content="16")
    }
    _ => fail("expected nested quote setext heading to stay omitted")
  }
}

///|
test "projection: listed setext heading is omitted without shifting direct heading" {
  let source = "- item\n  Nested\n  ---\n\n# Direct\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  match proj.children {
    [list, heading] => {
      match list.kind {
        UnorderedList([UnorderedListItem(_)]) => ()
        _ => fail("expected list item payload")
      }
      match heading.kind {
        Heading(1, [Text(text)]) => inspect(text, content="Direct")
        _ => fail("expected direct heading payload")
      }
      inspect(heading.start, content="23")
    }
    _ => fail("expected nested list setext heading to stay omitted")
  }
}

///|
test "source map: ATX heading separates marker and text" {
  let source = "## Title\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, diagnostics) = @markdown.parse_cst(
    markdown_projection_test_source, source,
  )
  inspect(diagnostics.length(), content="0")
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let heading = proj.children[0]
  match source_map.get_token_span(heading.id(), "marker") {
    Some(span) => inspect(source[span.start:span.end].to_owned(), content="## ")
    None => fail("expected ATX heading marker span")
  }
  match source_map.get_token_span(heading.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.end].to_owned(), content="Title")
    None => fail("expected ATX heading text span")
  }
}

///|
test "source map: aligned block quote and heading keep matching ranges" {
  let source = "> quote\n\n# Heading\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, diagnostics) = @markdown.parse_cst(
    markdown_projection_test_source, source,
  )
  inspect(diagnostics.length(), content="0")
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let quote = proj.children[0]
  let heading = proj.children[1]
  match source_map.get_range(quote.id()) {
    Some(range) => {
      assert_eq(range.start, 0)
      assert_eq(range.end, 8)
    }
    None => fail("expected block quote range")
  }
  match source_map.get_range(heading.id()) {
    Some(range) => {
      assert_eq(range.start, 9)
      assert_eq(range.end, 19)
    }
    None => fail("expected heading range")
  }
  match source_map.get_token_span(heading.id(), "marker") {
    Some(span) => assert_eq(source[span.start:span.end].to_owned(), "# ")
    None => fail("expected heading marker span")
  }
  match source_map.get_token_span(heading.id(), "text") {
    Some(span) => assert_eq(source[span.start:span.end].to_owned(), "Heading")
    None => fail("expected heading text span")
  }
}

///|
test "source map: setext heading separates underline and text" {
  let source = "Title\n---\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, diagnostics) = @markdown.parse_cst(
    markdown_projection_test_source, source,
  )
  inspect(diagnostics.length(), content="0")
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let heading = proj.children[0]
  match source_map.get_token_span(heading.id(), "marker") {
    Some(span) => inspect(source[span.start:span.end].to_owned(), content="---")
    None => fail("expected setext heading underline span")
  }
  match source_map.get_token_span(heading.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.end].to_owned(), content="Title")
    None => fail("expected setext heading text span")
  }
}

///|
test "source map: multiline setext text excludes underline separator" {
  let source = "Foo\nbar\n---\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, diagnostics) = @markdown.parse_cst(
    markdown_projection_test_source, source,
  )
  inspect(diagnostics.length(), content="0")
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let heading = proj.children[0]
  match source_map.get_token_span(heading.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.end].to_owned(), content="Foo\nbar")
    None => fail("expected multiline setext heading text span")
  }
}

///|
test "source map: indented setext text excludes separator indentation" {
  let source = "Title\n   ---\n"
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, source,
  )
  inspect(errors.length(), content="0")
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, diagnostics) = @markdown.parse_cst(
    markdown_projection_test_source, source,
  )
  inspect(diagnostics.length(), content="0")
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  let heading = proj.children[0]
  match source_map.get_token_span(heading.id(), "text") {
    Some(span) =>
      inspect(source[span.start:span.end].to_owned(), content="Title")
    None => fail("expected indented setext heading text span")
  }
}

///|
test "projection: delimiter resolver preserves italic and bold payloads" {
  let (proj, errors) = parse_to_proj_node(
    markdown_projection_test_source, "_em_ and **strong**\n",
  )
  inspect(errors.length(), content="0")
  match proj.children[0].kind {
    Paragraph([Italic([Text(em)]), Text(separator), Bold([Text(strong)])]) => {
      inspect(em, content="em")
      inspect(separator, content=" and ")
      inspect(strong, content="strong")
    }
    _ => fail("expected italic and bold paragraph payloads")
  }
}

///|
test "projection: unordered list" {
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "- first\n- second\n- third",
  )
  inspect(proj.children.length(), content="1")
  let list = proj.children[0]
  inspect(list.children.length(), content="3")
}

///|
test "projection: ordered list" {
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "1. first\n2. second\n",
  )
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
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(markdown_projection_test_source, source)
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
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  let source_map = @core.SourceMap::from_ast(proj)
  let view = proj_to_view_node(proj, source_map, source_text=Some(source))
  inspect(view.children[0].kind_tag, content="OrderedList")
}

///|
test "source map: outer ordered item marker wins over nested bullet" {
  let source = "1. parent\n   - child\n"
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(markdown_projection_test_source, source)
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
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "```js\nconsole.log(42)\n```",
  )
  inspect(proj.children.length(), content="1")
}

///|
test "projection: html block" {
  let source = "# Before\n\n<div>\nraw\n</div>\n\nAfter"
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  inspect(proj.children.length(), content="3")
  match proj.children[1].kind {
    HtmlBlock(value) => inspect(value, content="<div>\nraw\n</div>\n")
    _ => fail("expected html block payload")
  }
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(markdown_projection_test_source, source)
  populate_token_spans(source_map, @seam.SyntaxNode::from_cst(cst), proj)
  // Verify the "text" span covers the raw HTML content
  match source_map.get_token_span(proj.children[1].id(), "text") {
    Some(range) =>
      inspect(source[range.start:range.end], content="<div>\nraw\n</div>\n")
    None => fail("expected text span for html block")
  }
}

///|
test "projection: mixed blocks" {
  let source = "# Title\n\nSome text.\n\n- item one\n- item two\n\nMore text."
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  inspect(proj.children.length(), content="4")
}

///|
test "projection: node positions span source text" {
  let source = "# Hello\n\nWorld"
  let (proj, _) = parse_to_proj_node(markdown_projection_test_source, source)
  inspect(proj.start, content="0")
  inspect(proj.children[0].start, content="0")
}

///|
test "projection: IDs are unique" {
  let (proj, _) = parse_to_proj_node(
    markdown_projection_test_source, "# H1\n\n- a\n- b",
  )
  let ids : Array[Int] = []
  fn collect(node : @core.ProjNode[@markdown.Block]) {
    ids.push(node.node_id)
    for child in node.children {
      collect(child)
    }
  }
  collect(proj)
  let unique : Map[Int, Bool] = Map([])
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
  let parser = @loom.new_imperative_parser(
    markdown_projection_test_source, source, @markdown.markdown_grammar,
  )
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

///|
test "projection: incremental quote edit matches fresh shape ranges and identity" {
  let source = "> quote\n\n# Heading\n"
  let edited_source = "> quoted\n\n# Heading\n"
  let parser = @loom.new_imperative_parser(
    markdown_projection_test_source, source, @markdown.markdown_grammar,
  )
  let counter : Ref[Int] = Ref(0)
  let _ = parser.parse()
  let syntax1 = parser.get_syntax_tree().unwrap()
  let initial = syntax_to_proj_node(syntax1, counter)
  let quote_id = initial.children[0].node_id
  let heading_id = initial.children[1].node_id
  let edit = @loomcore.Edit::new(2, 5, 6)
  let _ = parser.edit(edit, edited_source)
  let syntax2 = parser.get_syntax_tree().unwrap()
  let raw = syntax_to_proj_node(syntax2, counter)
  let incremental = @core.reconcile(initial, raw, counter)
  let (fresh, _) = parse_to_proj_node(
    markdown_projection_test_source, edited_source,
  )
  let incremental_map = source_map_for(edited_source, incremental)
  let fresh_map = source_map_for(edited_source, fresh)
  assert_eq(incremental.equal(fresh), true)
  assert_eq(incremental_map.equal(fresh_map), true)
  assert_eq(incremental.children[0].node_id, quote_id)
  assert_eq(incremental.children[1].node_id, heading_id)
  match incremental.children[1].kind {
    Heading(1, [Text(text)]) => assert_eq(text, "Heading")
    _ => fail("expected matching heading payload after incremental edit")
  }
}

///|
test "projection: incremental quote insertion keeps following heading identity" {
  let source = "# Heading\n"
  let edited_source = "> quote\n\n# Heading\n"
  let parser = @loom.new_imperative_parser(
    markdown_projection_test_source, source, @markdown.markdown_grammar,
  )
  let counter : Ref[Int] = Ref(0)
  let _ = parser.parse()
  let syntax1 = parser.get_syntax_tree().unwrap()
  let initial = syntax_to_proj_node(syntax1, counter)
  let heading_id = initial.children[0].node_id
  let edit = @loomcore.Edit::new(0, 0, edited_source.length())
  let _ = parser.edit(edit, edited_source)
  let syntax2 = parser.get_syntax_tree().unwrap()
  let raw = syntax_to_proj_node(syntax2, counter)
  let incremental = @core.reconcile(initial, raw, counter)
  let (fresh, _) = parse_to_proj_node(
    markdown_projection_test_source, edited_source,
  )
  assert_eq(incremental.children.length(), fresh.children.length())
  assert_eq(incremental.children[1].kind, fresh.children[1].kind)
  assert_eq(incremental.children[1].start, fresh.children[1].start)
  assert_eq(incremental.children[1].end, fresh.children[1].end)
  assert_eq(incremental.children[1].node_id, heading_id)
}
