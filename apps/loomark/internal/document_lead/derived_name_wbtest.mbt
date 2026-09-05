///|
test "name derivation certifies only a reusable readable prefix" {
  for
    fixture in [
      ("# Stable\n\nBody\n", Some("Stable"), Some(9), Some(9)),
      ("# Stable\r\nBody\r\n", Some("Stable"), Some(10), Some(10)),
      ("# Stable\rBody\r", Some("Stable"), Some(9), Some(9)),
      ("# 😀\nBody\n", Some("😀"), Some(5), Some(5)),
      ("> # Quoted\n", Some("Quoted"), Some(11), Some(11)),
      ("- item\n  # Listed\n", Some("item"), Some(18), Some(7)),
      ("# Stable", Some("Stable"), None, None),
    ] {
    let (source, expected_name, expected_end, expected_certified_end) = fixture
    guard derive_name_with_certificate(source) is Ok(derivation) else {
      fail("expected derived name")
    }
    assert_eq(derivation.name, expected_name)
    assert_eq(derivation.reusable_prefix_end, expected_end)
    assert_eq(
      certified_name_prefix_end(source, derivation.name),
      expected_certified_end,
    )
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
test "certified derived name survives only a matching prefix edit" {
  // A certificate remains valid for the unchanged source as well as a suffix edit.
  assert_true(
    derived_name_survives_edit(
      "# Stable\n\nOld body\n",
      "# Stable\n\nOld body\n",
      Some("Stable"),
    ),
  )
  assert_true(
    derived_name_survives_edit(
      "# Stable\n\nOld body\n",
      "# Stable\n\nNew body\n",
      Some("Stable"),
    ),
  )
  assert_false(
    derived_name_survives_edit(
      "# Stable\n\nOld body\n",
      "# Changed\n\nNew body\n",
      Some("Changed"),
    ),
  )
  assert_true(
    derived_name_survives_edit(
      "# Changed\n\nNew body\n",
      "# Changed\n\nNew body\n",
      Some("Changed"),
    ),
  )
  assert_false(
    derived_name_survives_edit(
      "# )bad\n\nOld body\n",
      "# )bad\n\nNew body\n",
      Some(")bad"),
    ),
  )
  // Recovered headings derive a display name but have no reusable prefix certificate.
  assert_false(
    derived_name_survives_edit(
      "# )bad\n\nOld body\n",
      "# )bad\n\nOld body\n",
      Some(")bad"),
    ),
  )
}

///|
test "derived name uses the first parser-recognized readable line" {
  for
    fixture in [
      ("Ordinary text\ncontinued\n", Some("Ordinary text")),
      ("## First\n\n> Quoted\n", Some("First")),
      ("- item\n  # Listed\n", Some("item")),
      (
        "# **Bold** *italic* `code` [link](https://example.com)\n",
        Some("Bold italic code link"),
      ),
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
