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
