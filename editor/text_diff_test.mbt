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

// ─── Non-ASCII safety probes (issue #216) ────────────────────────────────
//
// `compute_edit` (and the `text_change` library it wraps) computes edit
// payloads in UTF-16 code units. When two strings differ inside a
// surrogate pair, the longest-common-prefix walk can land *between* the
// high and low surrogates and emit an Edit whose `start` is mid-surrogate.
// Pinning the current numeric output here so that:
//   1. The bug is visible in the test suite.
//   2. When grapheme-aware diffing lands (issue #216 Step 2), these
//      assertions go red and the maintainer is forced to revisit them.
//
// Each test names what would be wrong about the pinned value so the post-fix
// expectation is recoverable from the test alone.

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
/// (U+1F600 vs U+1F601 share high surrogate U+D83D). The current code-unit
/// walk in `text_change` reaches a state where it tries to slice mid-
/// surrogate-pair, and `String::sub` aborts. Stack:
///   compute_edit -> @text_change.compute_text_change -> String::sub -> abort.
///
/// Post-fix expected: the diff treats the emoji as one indivisible unit
/// and emits a non-mid-surrogate edit (likely start=0 spanning the whole
/// emoji), no abort.
test "panic #216: compute_edit aborts on shared high-surrogate emoji" {
  let _ = compute_edit("😀A", "😁B")
}

///|
/// #216 xfail: appending a non-BMP emoji to ASCII text. Surface symptom is
/// less dramatic than the shared-surrogate case but the resulting Edit still
/// describes a 2-code-unit insert, which downstream consumers may mis-handle
/// as "two edits" rather than "one grapheme insert".
test "#216 xfail: compute_edit reports non-BMP append as 2-unit insert" {
  let old = "a"
  let new = "a😀"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="1")
  // Post-fix (grapheme-counted) expectation could be 2 (still 2 code units)
  // OR 1 (one grapheme inserted). The unit needs to be specified by the API.
  inspect(edit.new_end(), content="3")
}

///|
/// #216 xfail: deleting only the combining mark of a NFD "é" produces an
/// edit that removes a single code unit but leaves the user with "e" —
/// visually one grapheme survived, but it isn't the same grapheme they
/// started with. Pinning the current numeric output.
test "#216 xfail: compute_edit deletes only combining mark from NFD é" {
  let old = "e\u{0301}"
  let new = "e"
  let edit = compute_edit(old, new)
  inspect(edit.start, content="1")
  inspect(edit.old_end(), content="2")
  inspect(edit.new_end(), content="1")
}
