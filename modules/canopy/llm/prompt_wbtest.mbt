///|
test "format_edit_user_message" {
  inspect(
    format_edit_user_message("line1\nline2\nline3", "Fix line 2"),
    content=(
      #|=== TEXT ===
      #|1: line1
      #|2: line2
      #|3: line3
      #|=== INSTRUCTION ===
      #|Fix line 2
    ),
  )
}

///|
test "split_lines preserves trailing empty segment" {
  // "a\n" should produce ["a", ""], not ["a"]
  debug_inspect(split_lines("a\n"), content="[\"a\", \"\"]")
}

///|
test "split_lines empty input" {
  debug_inspect(split_lines(""), content="[\"\"]")
}

///|
test "split_lines no trailing newline" {
  debug_inspect(split_lines("a\nb"), content="[\"a\", \"b\"]")
}
