// Parity tests: merge_to_edits must produce the same Edit as compute_edit
// for single-change (old, new) pairs.
// For no-change pairs, merge_to_edits returns [] (loom optimization).

///|
test "merge_to_edits - insert at start" {
  let edits = merge_to_edits("abc", "xabc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "xabc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - insert at end" {
  let edits = merge_to_edits("abc", "abcx")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "abcx")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - insert in middle" {
  let edits = merge_to_edits("abc", "aXbc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXbc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete at start" {
  let edits = merge_to_edits("abc", "bc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "bc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete at end" {
  let edits = merge_to_edits("abc", "ab")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "ab")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - delete in middle" {
  let edits = merge_to_edits("abc", "ac")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "ac")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - replace single char" {
  let edits = merge_to_edits("abc", "aXc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - replace multiple chars" {
  let edits = merge_to_edits("abc", "aXYc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("abc", "aXYc")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}

///|
test "merge_to_edits - no change returns empty array" {
  // loom's text_to_delta optimizes identical strings to []
  // (unlike compute_edit which returns a no-op Edit at the end)
  let edits = merge_to_edits("abc", "abc")
  inspect(edits.length(), content="0")
}

///|
test "merge_to_edits - empty to text" {
  let edits = merge_to_edits("", "abc")
  inspect(edits.length(), content="1")
  let e = edits[0]
  inspect(e.start, content="0")
  inspect(e.old_len, content="0")
  inspect(e.new_len, content="3")
}

///|
test "merge_to_edits - text to empty" {
  let edits = merge_to_edits("abc", "")
  inspect(edits.length(), content="1")
  let e = edits[0]
  inspect(e.start, content="0")
  inspect(e.old_len, content="3")
  inspect(e.new_len, content="0")
}

///|
test "merge_to_edits - both empty returns empty array" {
  let edits = merge_to_edits("", "")
  inspect(edits.length(), content="0")
}

///|
test "merge_to_edits - lambda expression edit" {
  let edits = merge_to_edits("λx.x", "λx.x + 1")
  inspect(edits.length(), content="1")
  let e = edits[0]
  let expected = compute_edit("λx.x", "λx.x + 1")
  assert_eq(e.start, expected.start)
  assert_eq(e.old_len, expected.old_len)
  assert_eq(e.new_len, expected.new_len)
}
