///|
/// Compare a resolved edit with the canonical diff for a single matrix row.
fn assert_resolved_edit_matches(
  old_source : String,
  new_source : String,
  expected : @loom_core.Edit,
  known_start : Int,
  known_old_len : Int,
  known_new_len : Int,
) -> Unit raise Failure {
  let resolved = try! resolve_applied_edit(
    old_source,
    new_source,
    Some(@loom_core.Edit::new(known_start, known_old_len, known_new_len)),
  )
  match resolved {
    Some(edit) =>
      if edit.start() != expected.start() ||
        edit.old_len() != expected.old_len() ||
        edit.new_len() != expected.new_len() {
        fail(
          "resolved edit differs: \{old_source} -> \{new_source}, known=\{known_start}/\{known_old_len}/\{known_new_len}, actual=\{edit.start()}/\{edit.old_len()}/\{edit.new_len()}, expected=\{expected.start()}/\{expected.old_len()}/\{expected.new_len()}",
        )
      }
    None => fail("known edit unexpectedly resolved to None")
  }
}

///|
/// Exhaustively vary the supplied known edit over a small UTF-16 matrix. The
/// resolver must return the same range as `compute_edit`, even when the hint is
/// invalid, over-wide, shifted, or ambiguous around repeated characters.
fn assert_resolve_matrix(
  old_source : String,
  new_source : String,
) -> Unit raise Failure {
  let old_length = old_source.length()
  let new_length = new_source.length()
  let expected = compute_edit(old_source, new_source)
  for known_start in 0..<=old_length {
    for known_old_len in 0..<=old_length {
      for known_new_len in 0..<=new_length {
        assert_resolved_edit_matches(
          old_source, new_source, expected, known_start, known_old_len, known_new_len,
        )
      }
    }
  }
}

///|
test "resolve_applied_edit preserves the canonical ASCII edit matrix" {
  let cases = [
    ("", ""),
    ("abc", "abc"),
    ("abc", "xabc"),
    ("abc", "abcx"),
    ("abc", "aXbc"),
    ("abc", "ac"),
    ("abc", "aXc"),
    ("x", "xx"),
    ("xx", "x"),
    ("abcd", "aXcd"),
    ("aab", "ab"),
    ("aba", "aXba"),
  ]
  for case in cases {
    let (old_source, new_source) = case
    assert_resolve_matrix(old_source, new_source)
  }
}

///|
test "resolve_applied_edit preserves Unicode and line-ending boundaries" {
  let cases = [
    ("😀a", "😁a"),
    ("e\u{0301}x", "ex"),
    ("👩‍💻x", "👩‍💼x"),
    ("🇺🇸x", "🇨🇦x"),
    ("a\r\nb", "a\nb"),
    ("a\rb", "a\nb"),
  ]
  for case in cases {
    let (old_source, new_source) = case
    assert_resolve_matrix(old_source, new_source)
  }
}

///|
test "known edit fast path is conservative around boundaries" {
  let ascii_old = "abc"
  let ascii_new = "aXc"
  let ascii_edit = compute_edit(ascii_old, ascii_new)
  assert_true(
    known_edit_matches_source_change(ascii_old, ascii_new, ascii_edit),
  )

  let repeated_old = "x"
  let repeated_new = "xx"
  let repeated_edit = compute_edit(repeated_old, repeated_new)
  assert_false(
    known_edit_matches_source_change(repeated_old, repeated_new, repeated_edit),
  )

  let unicode_old = "e\u{0301}x"
  let unicode_new = "ex"
  let unicode_edit = compute_edit(unicode_old, unicode_new)
  assert_false(
    known_edit_matches_source_change(unicode_old, unicode_new, unicode_edit),
  )

  let crlf_old = "a\r\nb"
  let crlf_new = "a\nb"
  let crlf_edit = compute_edit(crlf_old, crlf_new)
  assert_false(known_edit_matches_source_change(crlf_old, crlf_new, crlf_edit))

  let lone_cr_old = "a\rb"
  let lone_cr_new = "a\rXb"
  let lone_cr_edit = compute_edit(lone_cr_old, lone_cr_new)
  assert_true(
    known_edit_matches_source_change(lone_cr_old, lone_cr_new, lone_cr_edit),
  )

  let lone_lf_old = "a\nb"
  let lone_lf_new = "a\nXb"
  let lone_lf_edit = compute_edit(lone_lf_old, lone_lf_new)
  assert_true(
    known_edit_matches_source_change(lone_lf_old, lone_lf_new, lone_lf_edit),
  )
}

///|
test "resolve_applied_edit keeps absent hints absent" {
  let resolved = try! resolve_applied_edit("abc", "aXbc", None)
  match resolved {
    None => ()
    Some(_) => fail("an absent known edit must remain absent")
  }
}
