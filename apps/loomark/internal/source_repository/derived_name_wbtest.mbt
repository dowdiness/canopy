///|
test "derived name uses the first ATX H1 in document order" {
  guard derive_name("## Skip\n\n> # Quoted\n\n# Later\n") is Ok(Some(quoted)) else {
    fail("expected quoted ATX H1")
  }
  assert_eq(quoted, "Quoted")
  guard derive_name("- item\n  # Listed\n\n# Later\n") is Ok(Some(listed)) else {
    fail("expected listed ATX H1")
  }
  assert_eq(listed, "Listed")
}

///|
test "derived name flattens supported inline content" {
  guard derive_name("# **Bold** *italic* `code` [link](https://example.com)\n")
    is Ok(Some(name)) else {
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
    assert_true(derive_name(source) is Ok(None))
  }
}
