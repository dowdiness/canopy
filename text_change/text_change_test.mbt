///|
test "compute_text_change replaces middle span" {
  let change = compute_text_change("abc", "aXYc")
  inspect(change.start, content="1")
  inspect(change.delete_len, content="1")
  inspect(change.inserted, content="XY")
}

///|
test "compute_text_change returns no-op for equal text" {
  let change = compute_text_change("abc", "abc")
  inspect(change.start, content="3")
  inspect(change.delete_len, content="0")
  inspect(change.inserted, content="")
  inspect(change.is_noop(), content="true")
}

///|
test "compute_text_change handles insertion into empty text" {
  let change = compute_text_change("", "abc")
  inspect(change.start, content="0")
  inspect(change.delete_len, content="0")
  inspect(change.inserted, content="abc")
}

///|
test "compute_text_change handles deleting all text" {
  let change = compute_text_change("abc", "")
  inspect(change.start, content="0")
  inspect(change.delete_len, content="3")
  inspect(change.inserted, content="")
}

///|
test "TextChange::to_parser_edit preserves coordinates" {
  let edit = compute_text_change("hello", "heXllo").to_parser_edit()
  inspect(edit.start, content="2")
  inspect(edit.old_len, content="0")
  inspect(edit.new_len, content="1")
}
