///|
test "derive_name uses the first parser-recognized readable line" {
  for
    fixture in [
      ("Ordinary text\ncontinued\n", "Ordinary text"),
      ("## First\n\n> Quoted\n", "First"),
      ("- item\n  # Listed\n", "item"),
      (
        "# **Bold** *italic* `code` [link](https://example.com)\n", "Bold italic code link",
      ),
      ("Setext\n======\n", "Setext"),
      ("> Quoted\n", "Quoted"),
      ("- [ ] Task\n", "Task"),
      ("```md\n# Fenced\n```\n", "# Fenced"),
      ("![Alt text](image.png)\n", "Alt text"),
      ("---\n\nAfter rule\n", "After rule"),
      ("<div>raw</div>\n\nAfter HTML\n", "After HTML"),
      ("# 😀\nBody\n", "😀"),
      ("", ""),
      ("  \n\t\n", ""),
      ("# )bad\n", ")bad"),
      ("#   \n", ""),
    ] {
    let (source, expected) = fixture
    assert_eq(derive_name(source), expected)
  }
}

///|
test "malformed and recovered sources remain total" {
  assert_eq(derive_name("# [unterminated\n"), "[unterminated")
}

///|
test "derived name reuse requires a certified unchanged prefix" {
  for
    fixture in [
      ("# Stable\n\nOld body\n", "# Stable\n\nOld body\n", "Stable", true),
      ("# Stable\n\nOld body\n", "# Stable\n\nNew body\n", "Stable", true),
      ("# Stable\r\nOld body\r\n", "# Stable\r\nNew body\r\n", "Stable", true),
      ("- item\n  # Listed\n", "- item\n  # Changed\n", "item", true),
      ("# Stable\n\nOld body\n", "# Changed\n\nNew body\n", "Changed", false),
      ("# )bad\n\nOld body\n", "# )bad\n\nNew body\n", ")bad", false),
      ("# )bad\n\nOld body\n", "# )bad\n\nOld body\n", ")bad", false),
      // An unchanged empty prefix cannot prove that later content stays unnamed.
      ("\n", "\n# Later\n", "", false),
    ] {
    let (old_source, new_source, name, expected) = fixture
    assert_eq(
      derived_name_survives_edit(old_source, new_source, name),
      expected,
    )
  }
}
