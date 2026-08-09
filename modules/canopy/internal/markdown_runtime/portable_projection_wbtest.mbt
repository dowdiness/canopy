///|
test "inserted sentinel is absent from the projected edit" {
  let before = "a\n"
  let edit : @core.SpanEdit = {
    start: 2,
    delete_len: 0,
    inserted: "\u{200B}\n",
  }
  let after = "a\n\u{200B}\n"
  let after_hidden = [@loom.Range::new(2, 3)]
  match project_markdown_edit(before, [], edit, after, after_hidden) {
    Ok(projected) => {
      assert_eq(projected.start, 2)
      assert_eq(projected.delete_len, 0)
      assert_eq(projected.inserted, "\n")
      assert_eq(
        apply_span_edit(project_source(before, []).unwrap(), projected),
        "a\n\n",
      )
      assert_eq(project_source(after, after_hidden).unwrap(), "a\n\n")
    }
    Err(_) => fail("expected the inserted sentinel to project away")
  }
}

///|
test "source projection removes only marked hidden ranges" {
  assert_eq(
    project_source("a\u{200B}b", [@loom.Range::new(1, 2)]).unwrap(),
    "ab",
  )
  assert_eq(project_source("a\u{200B}b", []).unwrap(), "a\u{200B}b")
}

///|
test "source projection copies and sorts unsorted ranges" {
  let ranges = [@loom.Range::new(6, 8), @loom.Range::new(1, 3)]
  assert_eq(project_source("0123456789", ranges).unwrap(), "034589")
  assert_eq(ranges[0].start, 6)
  assert_eq(ranges[0].end, 8)
  assert_eq(ranges[1].start, 1)
  assert_eq(ranges[1].end, 3)
}

///|
test "source projection permits adjacent ranges" {
  assert_eq(
    project_source("abcdef", [@loom.Range::new(1, 2), @loom.Range::new(2, 4)]).unwrap(),
    "aef",
  )
}

///|
test "source projection uses UTF-16 offsets around non-BMP text" {
  assert_eq(
    project_source("😀a😀", [@loom.Range::new(2, 3)]).unwrap(),
    "😀😀",
  )
}

///|
test "source projection preserves LF CRLF CR and EOF layout" {
  assert_eq(
    project_source("a\n\u{200B}\nb", [@loom.Range::new(2, 3)]).unwrap(),
    "a\n\nb",
  )
  assert_eq(
    project_source("a\r\n\u{200B}\r\nb", [@loom.Range::new(3, 4)]).unwrap(),
    "a\r\n\r\nb",
  )
  assert_eq(
    project_source("a\r\u{200B}\r b", [@loom.Range::new(2, 3)]).unwrap(),
    "a\r\r b",
  )
  assert_eq(project_source("a\u{200B}", [@loom.Range::new(1, 2)]).unwrap(), "a")
}

///|
test "source projection rejects malformed and overlapping ranges" {
  expect_source_error(
    project_source("abc", [@loom.Range::new(-1, 1)]),
    PortableProjectionError::InvalidHiddenRange,
  )
  expect_source_error(
    project_source("abc", [@loom.Range::new(1, 1)]),
    PortableProjectionError::InvalidHiddenRange,
  )
  expect_source_error(
    project_source("abc", [@loom.Range::new(2, 1)]),
    PortableProjectionError::InvalidHiddenRange,
  )
  expect_source_error(
    project_source("abc", [@loom.Range::new(1, 4)]),
    PortableProjectionError::InvalidHiddenRange,
  )
  expect_source_error(
    project_source("abc", [@loom.Range::new(0, 2), @loom.Range::new(1, 3)]),
    PortableProjectionError::OverlappingHiddenRanges,
  )
}

///|
test "edit projection handles hidden deletion and unmarked user ZWSP" {
  let hidden_delete : @core.SpanEdit = { start: 1, delete_len: 1, inserted: "" }
  match
    project_markdown_edit(
      "aXb",
      [@loom.Range::new(1, 2)],
      hidden_delete,
      "ab",
      [],
    ) {
    Ok(projected) => {
      assert_eq(projected.start, 1)
      assert_eq(projected.delete_len, 0)
      assert_eq(projected.inserted, "")
    }
    Err(_) => fail("hidden deletion should be representable")
  }
  let user_zwsp : @core.SpanEdit = {
    start: 1,
    delete_len: 0,
    inserted: "\u{200B}",
  }
  match project_markdown_edit("ab", [], user_zwsp, "a\u{200B}b", []) {
    Ok(projected) => assert_eq(projected.inserted, "\u{200B}")
    Err(_) => fail("unmarked user ZWSP should remain visible")
  }
}

///|
test "edit projection supports sequential synthetic one-edit steps" {
  let first : @core.SpanEdit = {
    start: 1,
    delete_len: 0,
    inserted: "\n\u{200B}\n",
  }
  let first_after = "a\n\u{200B}\n"
  let first_projected = project_markdown_edit("a", [], first, first_after, [
    @loom.Range::new(2, 3),
  ]).unwrap()
  let portable_after_first = apply_span_edit("a", first_projected)
  let second : @core.SpanEdit = { start: 4, delete_len: 0, inserted: "!" }
  let second_after = "a\n\u{200B}\n!"
  let second_projected = project_markdown_edit(
    first_after,
    [@loom.Range::new(2, 3)],
    second,
    second_after,
    [@loom.Range::new(2, 3)],
  ).unwrap()
  assert_eq(
    apply_span_edit(portable_after_first, second_projected),
    project_source(second_after, [@loom.Range::new(2, 3)]).unwrap(),
  )
}

///|
test "edit projection handles non-BMP text and CRLF CR EOF" {
  let crlf_edit : @core.SpanEdit = {
    start: 4,
    delete_len: 0,
    inserted: "\u{200B}\r\n",
  }
  let crlf_after = "😀\r\n\u{200B}\r\n"
  let crlf_projected = project_markdown_edit(
    "😀\r\n",
    [],
    crlf_edit,
    crlf_after,
    [@loom.Range::new(4, 5)],
  ).unwrap()
  assert_eq(crlf_projected.start, 4)
  assert_eq(crlf_projected.inserted, "\r\n")
  assert_eq(
    apply_span_edit(project_source("😀\r\n", []).unwrap(), crlf_projected),
    project_source(crlf_after, [@loom.Range::new(4, 5)]).unwrap(),
  )

  let cr_edit : @core.SpanEdit = {
    start: 3,
    delete_len: 0,
    inserted: "\u{200B}\r",
  }
  let cr_after = "😀\r\u{200B}\r"
  let cr_projected = project_markdown_edit("😀\r", [], cr_edit, cr_after, [
    @loom.Range::new(3, 4),
  ]).unwrap()
  assert_eq(cr_projected.start, 3)
  assert_eq(cr_projected.inserted, "\r")
  assert_eq(
    apply_span_edit(project_source("😀\r", []).unwrap(), cr_projected),
    project_source(cr_after, [@loom.Range::new(3, 4)]).unwrap(),
  )

  let eof_edit : @core.SpanEdit = {
    start: 2,
    delete_len: 0,
    inserted: "\u{200B}",
  }
  let eof_after = "😀\u{200B}"
  let eof_projected = project_markdown_edit("😀", [], eof_edit, eof_after, [
    @loom.Range::new(2, 3),
  ]).unwrap()
  assert_eq(eof_projected.start, 2)
  assert_eq(eof_projected.inserted, "")
  assert_eq(
    apply_span_edit(project_source("😀", []).unwrap(), eof_projected),
    project_source(eof_after, [@loom.Range::new(2, 3)]).unwrap(),
  )
}

///|
test "edit projection rejects invalid edit bounds and source mismatch" {
  let invalid : @core.SpanEdit = { start: -1, delete_len: 0, inserted: "x" }
  expect_edit_error(
    project_markdown_edit("abc", [], invalid, "abcx", []),
    PortableProjectionError::InvalidEditRange,
  )
  let overflowing_start : @core.SpanEdit = {
    start: 0x7FFFFFFF,
    delete_len: 1,
    inserted: "",
  }
  expect_edit_error(
    project_markdown_edit("abc", [], overflowing_start, "abc", []),
    PortableProjectionError::InvalidEditRange,
  )
  let overflowing_delete : @core.SpanEdit = {
    start: 1,
    delete_len: 0x7FFFFFFF,
    inserted: "",
  }
  expect_edit_error(
    project_markdown_edit("abc", [], overflowing_delete, "abc", []),
    PortableProjectionError::InvalidEditRange,
  )
  let mismatch : @core.SpanEdit = { start: 1, delete_len: 1, inserted: "x" }
  expect_edit_error(
    project_markdown_edit("abc", [], mismatch, "abc", []),
    PortableProjectionError::CanonicalAfterSourceMismatch,
  )
}

///|
test "edit projection rejects a valid but non-representable metadata transition" {
  let edit : @core.SpanEdit = { start: 1, delete_len: 0, inserted: "x" }
  expect_edit_error(
    project_markdown_edit("ab", [], edit, "axb", [@loom.Range::new(0, 1)]),
    PortableProjectionError::NonRepresentable,
  )
}

///|
test "coordinate map collapses only validated hidden UTF-16 ranges" {
  let coordinates = make_portable_coordinate_map("😀\u{200B}A\u{200B}B", [
    @loom.Range::new(2, 3),
  ]).unwrap()
  assert_eq(coordinates.source(), "😀A\u{200B}B")
  assert_eq(coordinates.project_offset(0), Ok(0))
  assert_eq(coordinates.project_offset(2), Ok(2))
  assert_eq(coordinates.project_offset(3), Ok(2))
  assert_eq(coordinates.project_offset(6), Ok(5))
  assert_eq(coordinates.project_range(2, 3), Ok((2, 2)))
  assert_eq(coordinates.project_range(0, 6), Ok((0, 5)))
}

///|
test "coordinate map rejects invalid canonical offsets and ranges" {
  let coordinates = make_portable_coordinate_map("abc", []).unwrap()
  assert_eq(
    coordinates.project_offset(-1),
    Err(PortableProjectionError::InvalidCoordinateRange),
  )
  assert_eq(
    coordinates.project_offset(4),
    Err(PortableProjectionError::InvalidCoordinateRange),
  )
  assert_eq(
    coordinates.project_range(2, 1),
    Err(PortableProjectionError::InvalidCoordinateRange),
  )
  assert_eq(
    coordinates.project_range(0, 4),
    Err(PortableProjectionError::InvalidCoordinateRange),
  )
}

///|
fn expect_source_error(
  result : Result[String, PortableProjectionError],
  expected : PortableProjectionError,
) -> Unit raise {
  match result {
    Err(error) => assert_eq(error, expected)
    Ok(_) => fail("expected source projection error")
  }
}

///|
fn expect_edit_error(
  result : Result[@core.SpanEdit, PortableProjectionError],
  expected : PortableProjectionError,
) -> Unit raise {
  match result {
    Err(error) => assert_eq(error, expected)
    Ok(_) => fail("expected edit projection error")
  }
}
