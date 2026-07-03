///|
test "snapshot_span_edits keeps short inserted text unchanged" {
  let e = @core.SpanEdit::{ start: 0, delete_len: 0, inserted: "hello" }
  let result = snapshot_span_edits([e], 200)
  inspect(result[0].inserted, content="hello")
  inspect(result[0].start, content="0")
  inspect(result[0].delete_len, content="0")
}

///|
test "snapshot_span_edits truncates long inserted text by codepoint" {
  let long = "a".repeat(250)
  let e = @core.SpanEdit::{ start: 0, delete_len: 0, inserted: long }
  let result = snapshot_span_edits([e], 200)
  let got = result[0].inserted
  inspect(got.length() <= long.length(), content="true")
  inspect(got.has_suffix("…"), content="true")
  // Codepoint count (not UTF-16): 200 'a' + '…'
  inspect(got.length(), content="201")
}

///|
test "snapshot_span_edits empty array unchanged" {
  let result = snapshot_span_edits([], 200)
  inspect(result.is_empty(), content="true")
}

///|
test "snapshot_span_edits preserves start and delete_len" {
  let e = @core.SpanEdit::{ start: 42, delete_len: 3, inserted: "abc" }
  let result = snapshot_span_edits([e], 1)
  inspect(result[0].start, content="42")
  inspect(result[0].delete_len, content="3")
  inspect(result[0].inserted, content="a…")
}
