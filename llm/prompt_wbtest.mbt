///|
test "typo_correction_system_prompt" {
  inspect(
    typo_correction_system_prompt,
    content=(
      #|You are a Japanese/English text proofreader.
      #|Fix typos, misspellings, and grammatical errors in the given text.
      #|Respond ONLY with a JSON object in this exact format:
      #|{"original": "<original text>", "fixed": "<corrected text>"}
      #|Do not explain. Do not add any text outside the JSON.
    ),
  )
}

///|
test "structured_edit_system_prompt" {
  inspect(
    structured_edit_system_prompt,
    content=(
      #|You are an editor assistant. The user will provide text content and an editing instruction.
      #|Respond ONLY with a JSON array of edit operations. Each operation is one of:
      #|- {"action": "replace", "line": <1-based line number>, "old": "<text to find on that line>", "new": "<replacement text>"}
      #|- {"action": "insert", "line": <1-based line number>, "text": "<text to insert after this line>"}
      #|- {"action": "delete", "line": <1-based line number>}
      #|If no changes are needed, return an empty array: []
      #|Do not explain. Do not add any text outside the JSON array.
    ),
  )
}

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
