///|
test "rejected edit invalidates queued full-value input, not later native input" {
  let deleted = InputEdit::{
    owner: "first",
    version: 4,
    change: @text_change.ReplaceAll("bc"),
  }
  let queued = InputEdit::{
    owner: "first",
    version: 4,
    change: @text_change.ReplaceAll("bcX"),
  }
  let later = InputEdit::{
    owner: "first",
    version: 5,
    change: @text_change.ReplaceRange(start=3, delete_len=0, inserted="X"),
  }
  assert_eq(
    admit_edit("first", 4, deleted),
    Some(@text_change.ReplaceAll("bc")),
  )
  assert_eq(admit_edit("first", 5, queued), None)
  assert_eq(
    admit_edit("first", 5, later),
    Some(@text_change.ReplaceRange(start=3, delete_len=0, inserted="X")),
  )
  assert_eq(admit_edit("second", 4, deleted), None)
}

///|
test "two ordinary edits remain admissible in one input epoch" {
  let first = InputEdit::{
    owner: "same",
    version: 2,
    change: @text_change.ReplaceRange(start=0, delete_len=1, inserted=""),
  }
  let second = InputEdit::{
    owner: "same",
    version: 2,
    change: @text_change.ReplaceRange(start=2, delete_len=0, inserted="X"),
  }
  assert_eq(
    admit_edit("same", 2, first),
    Some(@text_change.ReplaceRange(start=0, delete_len=1, inserted="")),
  )
  assert_eq(
    admit_edit("same", 2, second),
    Some(@text_change.ReplaceRange(start=2, delete_len=0, inserted="X")),
  )
  assert_eq(admit_edit("same", 3, first), None)
}
