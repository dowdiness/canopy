///|
test "name derivation certifies a line-terminated first readable prefix" {
  guard derive_name_with_certificate("# Stable\n\nBody\n") is Ok(terminated) else {
    fail("expected derived top-level name")
  }
  assert_eq(terminated.name, Some("Stable"))
  assert_eq(terminated.reusable_prefix_end, Some(9))

  for
    fixture in [
      ("# Stable\r\nBody\r\n", 10),
      ("# Stable\rBody\r", 9),
      ("# 😀\nBody\n", 5),
    ] {
    let (source, expected_end) = fixture
    guard derive_name_with_certificate(source) is Ok(line_terminated) else {
      fail("expected line-terminated derived name")
    }
    assert_eq(line_terminated.reusable_prefix_end, Some(expected_end))
    assert_eq(
      certified_name_prefix_end(source, line_terminated.name),
      Some(expected_end),
    )
  }

  guard derive_name_with_certificate("# Stable") is Ok(eof) else {
    fail("expected EOF-derived name")
  }
  assert_eq(eof.name, Some("Stable"))
  assert_eq(eof.reusable_prefix_end, None)

  let quote = "> # Quoted\n"
  guard derive_name_with_certificate(quote) is Ok(quoted) else {
    fail("expected quoted derived name")
  }
  assert_eq(quoted.reusable_prefix_end, Some(quote.length()))
  assert_eq(certified_name_prefix_end(quote, quoted.name), Some(quote.length()))

  let list = "- item\n  # Listed\n"
  guard derive_name_with_certificate(list) is Ok(listed) else {
    fail("expected listed derived name")
  }
  assert_eq(listed.reusable_prefix_end, Some(list.length()))
  assert_eq(certified_name_prefix_end(list, listed.name), Some(7))
}

///|
test "recovered top-level heading derives a name but cannot certify reuse" {
  let source = "# )bad\n"
  let (cst, diagnostics) = try! @markdown.parse_cst(name_source_id, source)
  let root = @seam.SyntaxNode::from_cst(cst)
  guard root.first_child() is Some(heading) else {
    fail("expected recovered heading")
  }
  assert_true(diagnostics.is_empty())
  assert_true(heading.cst_node().has_any_error())
  guard derive_name_with_certificate(source) is Ok(derivation) else {
    fail("expected recovered heading name")
  }
  assert_eq(derivation.name, Some(")bad"))
  assert_eq(derivation.reusable_prefix_end, None)
  assert_eq(certified_name_prefix_end(source, derivation.name), None)
}

///|
test "derived name uses the first readable document line" {
  assert_eq(
    derive_name("Ordinary text\ncontinued\n"),
    Ok(Some("Ordinary text")),
  )
}

///|
test "derived name uses the first readable content in document order" {
  assert_eq(
    derive_name("## First\n\n> # Quoted\n\n# Later\n"),
    Ok(Some("First")),
  )
  assert_eq(derive_name("- item\n  # Listed\n\n# Later\n"), Ok(Some("item")))
}

///|
test "derived name flattens supported inline content" {
  guard derive_name_with_certificate(
      "# **Bold** *italic* `code` [link](https://example.com)\n",
    )
    is Ok({ name: Some(name), .. }) else {
    fail("expected flattened ATX H1")
  }
  assert_eq(name, "Bold italic code link")
}

///|
test "derived name supports readable Markdown block appearances" {
  for
    fixture in [
      ("Setext\n======\n", Some("Setext")),
      ("> Quoted\n", Some("Quoted")),
      ("- [ ] Task\n", Some("Task")),
      ("```md\n# Fenced\n```\n", Some("# Fenced")),
      ("![Alt text](image.png)\n", Some("Alt text")),
      ("---\n\nAfter rule\n", Some("After rule")),
      ("<div>raw</div>\n\nAfter HTML\n", Some("After HTML")),
      ("#   \n", None),
    ] {
    let (source, expected) = fixture
    assert_eq(derive_name(source), Ok(expected))
  }
}
