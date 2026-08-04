///|
/// A multi-change CodeMirror transaction reaches the source store as separate,
/// ordered loom edits — each rebased onto the document the previous edit
/// produced, and paired with the full source it yields.
///
/// Base document `abcdef`, one transaction with two replaced ranges (CodeMirror
/// yields them ascending and non-overlapping, in pre-transaction coordinates):
///   - replace [1,2) "b" with "XY"
///   - delete  [4,5) "e"
/// Worked by hand:
///   change 1: start 1 (+0), old_len 1, new_len 2 -> "aXYcdef"; running shift +1
///   change 2: start 4 (+1)=5, old_len 1, new_len 0 -> "aXYcdf"
test "multi-change transaction lowers to ordered, rebased edits" {
  let result = changes_to_edits("abcdef", [
    @codemirror.ChangeDelta::new(1, 2, "XY"),
    @codemirror.ChangeDelta::new(4, 5, ""),
  ])
  inspect(result.length(), content="2")
  let (edit0, source0) = result[0]
  inspect(edit0.start, content="1")
  inspect(edit0.old_len, content="1")
  inspect(edit0.new_len, content="2")
  inspect(source0, content="aXYcdef")
  let (edit1, source1) = result[1]
  inspect(edit1.start, content="5")
  inspect(edit1.old_len, content="1")
  inspect(edit1.new_len, content="0")
  inspect(source1, content="aXYcdf")
}

///|
/// Offsets are UTF-16 code units end to end, so a change spanning a non-BMP
/// (surrogate-pair) glyph carries `old_len == 2` and splices on code-unit
/// boundaries. Base `a😀b` (code units: a=0, 😀=1..3, b=3); replace the emoji
/// span [1,3) with "z" -> edit start 1, old_len 2, new_len 1, source "azb".
test "code-unit coordinates survive a non-BMP change" {
  let result = changes_to_edits("a😀b", [
    @codemirror.ChangeDelta::new(1, 3, "z"),
  ])
  inspect(result.length(), content="1")
  let (edit, source) = result[0]
  inspect(edit.start, content="1")
  inspect(edit.old_len, content="2")
  inspect(edit.new_len, content="1")
  inspect(source, content="azb")
}
