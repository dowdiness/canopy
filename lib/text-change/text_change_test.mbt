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
test "compute_text_change replaces whole non-BMP emoji cluster" {
  let change = compute_text_change("a😀", "a😁")
  inspect(change.start, content="1")
  inspect(change.delete_len, content="2")
  inspect(change.inserted, content="😁")
}

///|
test "compute_text_change appends whole non-BMP emoji cluster" {
  let change = compute_text_change("a", "a😀")
  inspect(change.start, content="1")
  inspect(change.delete_len, content="0")
  inspect(change.inserted, content="😀")
}

///|
test "compute_text_change replaces whole combining-mark cluster" {
  let change = compute_text_change("e\u{0301}", "a\u{0301}")
  inspect(change.start, content="0")
  inspect(change.delete_len, content="2")
  inspect(change.inserted, content="a\u{0301}")
}
