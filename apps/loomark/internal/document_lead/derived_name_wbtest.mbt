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
    assert_eq(derive_name(source).text(), expected)
  }
}

///|
test "malformed and recovered sources remain total" {
  assert_eq(derive_name("# [unterminated\n").text(), "[unterminated")
}

///|
test "DerivedName equality ignores its reuse certificate" {
  assert_eq(derive_name("# Stable"), derive_name("# Stable\n"))
}

///|
test "derived name updates through its certified prefix" {
  let stable = derive_name("# Stable\n\nOld body\n")
  assert_eq(stable.text(), "Stable")
  assert_eq(stable.update("# Stable\n\nNew body\n"), stable)
  assert_eq(
    derive_name("# Stable\r\nOld body\r\n")
    .update("# Stable\r\nNew body\r\n")
    .text(),
    "Stable",
  )
  assert_eq(
    derive_name("- item\n  # Listed\n").update("- item\n  # Changed\n").text(),
    "item",
  )
  assert_eq(
    derive_name("# Stable\n\nOld body\n")
    .update("# Changed\n\nNew body\n")
    .text(),
    "Changed",
  )
  assert_eq(
    derive_name("# )bad\n\nOld body\n").update("# )bad\n\nNew body\n").text(),
    ")bad",
  )
}

///|
test "reference definitions invalidate reusable prefixes" {
  assert_eq(
    derive_name("[Name]\n").update("[Name]\n\n[Name]: /destination\n").text(),
    "Name",
  )
  assert_eq(
    derive_name("# [Name]\n")
    .update("# [Name]\n\n[Name]: /destination\n")
    .text(),
    "Name",
  )
}

///|
test "uncertified and empty names reparse on update" {
  assert_eq(
    derive_name("# )bad\n\nOld body\n").update("# )bad\n\nOld body\n").text(),
    ")bad",
  )
  assert_eq(derive_name("\n").update("\n# Later\n").text(), "Later")
  assert_eq(derive_name("plain").update("plain\n").text(), "plain")
}
