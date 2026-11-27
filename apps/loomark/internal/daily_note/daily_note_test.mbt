///|
test "an existing note for the date opens instead of a new one" {
  let documents = [("a", "# 2026-11-27 \nold"), ("b", "# 2026-11-27\nolder")]
  assert_eq(@daily_note.today(documents[:], "2026-11-27"), Existing("a"))
}

///|
test "a new note is the date heading, with the template body when one exists" {
  let blank : Array[(String, String)] = [("a", "text")]
  assert_eq(@daily_note.today(blank[:], "2026-11-27"), New("# 2026-11-27\n\n"))
  let template = [("t", "# Daily template\n\n## メモ\n")]
  assert_eq(
    @daily_note.today(template[:], "2026-11-27"),
    New("# 2026-11-27\n\n## メモ\n"),
  )
}
