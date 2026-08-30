///|
test "name derivation certifies only a line-terminated top-level first H1" {
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

  for source in ["> # Quoted\n", "- item\n  # Listed\n"] {
    guard derive_name_with_certificate(source) is Ok(nested) else {
      fail("expected nested derived name")
    }
    assert_eq(nested.reusable_prefix_end, None)
    assert_eq(certified_name_prefix_end(source, nested.name), None)
  }
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
test "derived name uses the first ATX H1 in document order" {
  guard derive_name_with_certificate("## Skip\n\n> # Quoted\n\n# Later\n")
    is Ok(quoted_derivation) &&
    quoted_derivation.name is Some(quoted) else {
    fail("expected quoted ATX H1")
  }
  assert_eq(quoted, "Quoted")
  assert_eq(quoted_derivation.reusable_prefix_end, None)
  guard derive_name_with_certificate("- item\n  # Listed\n\n# Later\n")
    is Ok({ name: Some(listed), .. }) else {
    fail("expected listed ATX H1")
  }
  assert_eq(listed, "Listed")
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
test "derived name fails closed for an unsafe inline semantic value" {
  let builder = StringBuilder()
  assert_false(
    append_inlines(
      [@markdown.Inline::Text("prefix"), @markdown.Inline::Error("recovered")],
      builder,
    ),
  )
}

///|
test "derived name excludes non-ATX-H1 forms" {
  for
    source in [
      "No heading\n", "Setext\n======\n", "## H2\n", "```md\n# Fenced\n```\n", "#   \n",
    ] {
    assert_true(derive_name_with_certificate(source) is Ok({ name: None, .. }))
  }
}
