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
    let updated = @writing_focus.Layout(source).replace_text(after).unwrap()
    let edit = updated.edit_from(source).unwrap()
    let reconstructed = source.lines()[:edit.first].to_owned()
    reconstructed.append(edit.inserted)
    reconstructed.append(source.lines()[edit.first + edit.removed:])
    assert_eq(reconstructed.join("\n"), after)
    assert_eq(updated.source().lines().to_owned(), reconstructed)
    assert_eq(source.lines().to_owned().join("\n"), before)
  }
}

///|
test "replacement searches can divide surrogate pairs without corrupting text" {
  let original = @writing_focus.Layout(
    @writing_focus.TextLines("header\n😀a\n\nlast"),
  )
  let updated = original.replace_text("header\n😃a\n\nlast").unwrap()
  assert_eq(updated.source().lines().to_owned(), ["header", "😃a", "", "last"])
  assert_eq(focused_lines(updated, 12, 12).first, 3)
  assert_eq(original.source().lines().to_owned(), [
    "header", "😀a", "", "last",
  ])
}

///|
test "successive replacements preserve focus grouping when fences and paragraphs change" {
  let sources = [
    "first\n\n```\ncode\n\nmore\n```\n\nlast", "first\n\ncode\n\nmore\n\nlast", "first\n\n    code\n\n    more\n\nlast",
    "first\n\n😀 revised\n\nlast\n", "",
  ]
  let original = @writing_focus.Layout(
    @writing_focus.TextLines("first\n\nlast"),
  )
  sources.fold(init=original, (previous, text) => {
    let next = previous.replace_text(text).unwrap()
    let rebuilt = @writing_focus.Layout(@writing_focus.TextLines(text))
    assert_eq(
      next.source().lines().to_owned(),
      rebuilt.source().lines().to_owned(),
    )
    for offset in 0..<=text.length() {
      match (next.focus(offset, offset), rebuilt.focus(offset, offset)) {
        (Lines(actual), Lines(expected)) =>
          assert_eq(
            (actual.lines.first, actual.lines.last),
            (expected.lines.first, expected.lines.last),
          )
        (Document(actual), Document(expected)) =>
          assert_eq((actual.start, actual.end), (expected.start, expected.end))
        _ =>
          fail(
            "incremental edits and a fresh layout must select the same focus",
          )
      }
    }
    next
  })
  |> ignore
  assert_eq(original.source().lines().to_owned(), ["first", "", "last"])
}
