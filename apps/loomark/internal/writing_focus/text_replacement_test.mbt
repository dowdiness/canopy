///|
test "mirror edits reconstruct the requested text across line joins and splits" {
  for
    (before, after) in [
      ("", "a\n"),
      ("a\nb", "aXb"),
      ("a\nb\nc", "a\nc"),
      ("a\nb", "a\nx\nb"),
      ("a\nb", "a\nb\n"),
      ("a\n", ""),
    ] {
    let source = @writing_focus.TextLines(before)
    let edit = source.replace_text(after).unwrap()
    let reconstructed = source.lines()[:edit.first].to_owned()
    reconstructed.append(edit.inserted)
    reconstructed.append(source.lines()[edit.first + edit.removed:])
    assert_eq(reconstructed.join("\n"), after)
    assert_eq(edit.source.lines().to_owned(), reconstructed)
    assert_eq(source.lines().to_owned().join("\n"), before)
  }
}

///|
test "replacement searches can divide surrogate pairs without corrupting text" {
  let original = @writing_focus.TextLines("header\n😀a\n\nlast")
  let updated = original.replace_text("header\n😃a\n\nlast").unwrap().source
  assert_eq(updated.lines().to_owned(), ["header", "😃a", "", "last"])
  assert_eq(focused_lines(updated, 12, 12).first, 3)
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
    let next = previous.replace_text(text).unwrap().source
    let rebuilt = @writing_focus.TextLines(text)
    assert_eq(next.lines().to_owned(), rebuilt.lines().to_owned())
    for offset in 0..<=text.length() {
      let actual = next.focus_lines(offset, offset)
      let expected = rebuilt.focus_lines(offset, offset)
      assert_eq((actual.first, actual.last), (expected.first, expected.last))
    }
    next
  })
  |> ignore
  assert_eq(original.lines().to_owned(), ["first", "", "last"])
}
