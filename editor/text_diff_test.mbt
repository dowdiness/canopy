// Tests for text diffing utilities

///|
test "compute_edit - insert at start" {
  let old = "abc"
  let new = "xabc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="0")
  inspect(edit.new_end(), content="1")
}

///|
test "compute_edit - insert at end" {
  let old = "abc"
  let new = "abcx"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="3")
  inspect(edit.old_end(), content="3")
  inspect(edit.new_end(), content="4")
}

///|
test "compute_edit - insert in middle" {
  let old = "abc"
  let new = "aXbc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="1")
  inspect(edit.new_end(), content="2")
}

///|
test "compute_edit - delete at start" {
  let old = "abc"
  let new = "bc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="1")
  inspect(edit.new_end(), content="0")
}

///|
test "compute_edit - delete at end" {
  let old = "abc"
  let new = "ab"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="2")
  inspect(edit.old_end(), content="3")
  inspect(edit.new_end(), content="2")
}

///|
test "compute_edit - delete in middle" {
  let old = "abc"
  let new = "ac"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="1")
}

///|
test "compute_edit - replace single char" {
  let old = "abc"
  let new = "aXc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="2")
}

///|
test "compute_edit - replace multiple chars" {
  let old = "abc"
  let new = "aXYc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="3")
}

///|
test "compute_edit - no change" {
  let old = "abc"
  let new = "abc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="3")
  inspect(edit.old_end(), content="3")
  inspect(edit.new_end(), content="3")
}

///|
test "compute_edit - empty to text" {
  let old = ""
  let new = "abc"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="0")
  inspect(edit.new_end(), content="3")
}

///|
test "compute_edit - text to empty" {
  let old = "abc"
  let new = ""
  let edit = compute_edit(old, new)
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="3")
  inspect(edit.new_end(), content="0")
}

///|
test "compute_edit - lambda expression edit" {
  let old = "λx.x"
  let new = "λx.x + 1"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="4")
  inspect(edit.old_end(), content="4")
  inspect(edit.new_end(), content="8")
}

///|
test "compute_edit - lambda parameter change" {
  let old = "λx.x"
  let new = "λy.y"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="4")
  inspect(edit.new_end(), content="4")
}

///|
test "compute_edit - complex lambda edit" {
  let old = "λf.λx.f x"
  let new = "λf.λx.f (f x)"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="8")
  inspect(edit.old_end(), content="9")
  inspect(edit.new_end(), content="13")
}

// --- Non-ASCII safety probes (issue #216) -------------------------------
//
// `compute_edit` (and the `text_change` library it wraps) computes edit
// payloads in UTF-16 code units, but the diff window must be aligned to
// grapheme-cluster boundaries so it never slices through surrogate pairs or
// combining-mark clusters.

///|
/// BMP-only input: lambda + Hiragana baseline. Must keep working both
/// before and after the grapheme-aware fix.
test "compute_edit - BMP non-ASCII (Hiragana) baseline" {
  let old = "あいう"
  let new = "あxう"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="2")
}

///|
/// #216: two non-BMP emoji that differ only in their low surrogate
/// (U+1F600 vs U+1F601 share high surrogate U+D83D). The diff treats each
/// emoji as an indivisible grapheme and does not slice the surrogate pair.
test "#216: compute_edit handles shared high-surrogate emoji" {
  let edit = compute_edit("😀", "😁")
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="2")
}

///|
/// #216: appending a non-BMP emoji to ASCII text produces one splice whose
/// insert length spans the full UTF-16 surrogate pair.
test "#216: compute_edit reports non-BMP append as full emoji insert" {
  let old = "a"
  let new = "a😀"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="1")
  inspect(edit.new_end(), content="3")
}

///|
/// #216: deleting from a decomposed acute-accented grapheme deletes the full
/// cluster rather than only the combining mark suffix.
test "#216: compute_edit deletes full NFD combining-mark cluster" {
  let old = "e\u{0301}"
  let new = "e"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="0")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="1")
}
