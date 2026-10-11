///|
test "line replacements preserve empty lines and join or split only affected lines" {
  for
    (before, after, first, removed, inserted) in [
      ("", "a\n", 0, 1, ["a", ""]),
      ("a\nb", "aXb", 0, 2, ["aXb"]),
      ("a\nb\nc", "a\nc", 1, 2, ["c"]),
      ("a\nb", "a\nx\nb", 1, 1, ["x", "b"]),
      ("a\nb", "a\nb\n", 1, 1, ["b", ""]),
      ("a\n", "", 0, 2, [""]),
    ] {
    let replacement = @writing_focus.TextLines(before)
      .replace_text(after)
      .unwrap()
    assert_eq((replacement.first, replacement.removed), (first, removed))
    assert_eq(replacement.inserted.to_owned(), inserted)
    assert_eq(replacement.text_lines.lines().to_owned().join("\n"), after)
  }
}

///|
test "replacement searches can divide surrogate pairs without corrupting text" {
  let original = @writing_focus.TextLines("header\n😀a\n\nlast")
  let replacement = original.replace_text("header\n😃a\n\nlast").unwrap()
  assert_eq((replacement.first, replacement.removed), (1, 1))
  assert_eq(replacement.inserted.to_owned(), ["😃a"])
  assert_eq(replacement.text_lines.focus_lines(12, 12).unwrap().first, 3)
  assert_eq(original.lines().to_owned(), ["header", "😀a", "", "last"])
}

///|
test "successive replacements preserve focus grouping when fences and paragraphs change" {
  let sources = [
    "first\n\n```\ncode\n\nmore\n```\n\nlast", "first\n\ncode\n\nmore\n\nlast", "first\n\n    code\n\n    more\n\nlast",
    "first\n\n😀 revised\n\nlast\n", "",
  ]
  let original = @writing_focus.TextLines("first\n\nlast")
  sources.fold(init=original, (previous, text) => {
    let next = previous.replace_text(text).unwrap().text_lines
    let rebuilt = @writing_focus.TextLines(text)
    assert_eq(next.lines().to_owned(), rebuilt.lines().to_owned())
    for offset in 0..<=text.length() {
      let actual = next.focus_lines(offset, offset).unwrap()
      let expected = rebuilt.focus_lines(offset, offset).unwrap()
      assert_eq((actual.first, actual.last), (expected.first, expected.last))
    }
    next
  })
  |> ignore
  assert_eq(original.lines().to_owned(), ["first", "", "last"])
}
