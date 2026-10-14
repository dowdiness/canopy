///|
test "text_profile counts visible characters without spaces or line breaks" {
  inspect(text_profile("").characters, content="0")
  inspect(text_profile("日本語の文章").characters, content="6")
  inspect(
    text_profile("今日は、晴れ。\n\n明日も　晴れ").characters,
    content="12",
  )
  inspect(text_profile("# Title\n\n- one").characters, content="10")
  // Combined marks, ideographic variants, and emoji sequences are one character each.
  inspect(text_profile("e\u{301}").characters, content="1")
  inspect(text_profile("葛\u{E0100}城").characters, content="2")
  inspect(
    text_profile("👨\u{200D}👩\u{200D}👧👍\u{1F3FD}").characters,
    content="2",
  )
}

///|
test "character_count_label groups thousands" {
  inspect(character_count_label(1), content="1 character")
  inspect(character_count_label(999), content="999 characters")
  inspect(character_count_label(1204), content="1,204 characters")
  inspect(character_count_label(1234567), content="1,234,567 characters")
}
