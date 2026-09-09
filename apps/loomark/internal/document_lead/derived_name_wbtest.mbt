///|
test "derive_name uses the first parser-recognized readable line" {
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
      ("# 😀\nBody\n", Some("😀")),
      ("# )bad\n", Some(")bad")),
      ("#   \n", None),
    ] {
    let (source, expected) = fixture
    assert_eq(derive_name(source), Ok(expected))
  }
}

///|
test "derived name reuse requires a certified unchanged prefix" {
  for
    fixture in [
      ("# Stable\n\nOld body\n", "# Stable\n\nOld body\n", Some("Stable"), true),
      ("# Stable\n\nOld body\n", "# Stable\n\nNew body\n", Some("Stable"), true),
      (
        "# Stable\r\nOld body\r\n",
        "# Stable\r\nNew body\r\n",
        Some("Stable"),
        true,
      ),
      ("- item\n  # Listed\n", "- item\n  # Changed\n", Some("item"), true),
      (
        "# Stable\n\nOld body\n",
        "# Changed\n\nNew body\n",
        Some("Changed"),
        false,
      ),
      ("# )bad\n\nOld body\n", "# )bad\n\nNew body\n", Some(")bad"), false),
      ("# )bad\n\nOld body\n", "# )bad\n\nOld body\n", Some(")bad"), false),
    ] {
    let (old_source, new_source, name, expected) = fixture
    assert_eq(
      derived_name_survives_edit(old_source, new_source, name),
      expected,
    )
  }
}
