///|
test "derived name uses the first ATX H1 in document order" {
  assert_eq(
    derive_name("## Skip\n\n> # Quoted\n\n# Later\n"),
    Ok(Some("Quoted")),
  )
  assert_eq(derive_name("- item\n  # Listed\n\n# Later\n"), Ok(Some("Listed")))
}

///|
test "derived name flattens supported inline content" {
  assert_eq(
    derive_name("# **Bold** *italic* `code` [link](https://example.com)\n"),
    Ok(Some("Bold italic code link")),
  )
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
    assert_eq(derive_name(source), Ok(None))
  }
}
