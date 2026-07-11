///|
test "parse_fix_typos" {
  let json_str =
    #|{"original": "teh quikc", "fixed": "the quick"}
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="1")
  inspect(
    actions[0],
    content="FixTypos(original=\"teh quikc\", fixed=\"the quick\")",
  )
}

///|
test "parse_replace action" {
  let json_str =
    #|[{"action": "replace", "line": 3, "old": "hello", "new": "world"}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="1")
  inspect(actions[0], content="Replace(line=3, old=\"hello\", new=\"world\")")
}

///|
test "parse_insert action" {
  let json_str =
    #|[{"action": "insert", "line": 5, "text": "new line here"}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="1")
  inspect(actions[0], content="Insert(line=5, text=\"new line here\")")
}

///|
test "parse_delete action" {
  let json_str =
    #|[{"action": "delete", "line": 2}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="1")
  inspect(actions[0], content="Delete(line=2)")
}

///|
test "parse_multiple actions" {
  let json_str =
    #|[{"action": "replace", "line": 1, "old": "a", "new": "b"}, {"action": "delete", "line": 3}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="2")
}

///|
test "parse_empty array" {
  let json_str =
    #|[]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="0")
}

///|
test "parse_malformed json" {
  let json_str = "not json at all"
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="0")
}

///|
test "parse_markdown_fenced_json returns empty" {
  // LLMs sometimes wrap JSON in markdown fences despite responseMimeType
  let json_str =
    #|```json
    #|[{"action": "delete", "line": 1}]
    #|```
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="0")
}

///|
test "parse_fractional_line_rejected" {
  // Line numbers must be integers; 3.5 should not silently truncate to 3
  let json_str =
    #|[{"action": "delete", "line": 3.5}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="0")
}

///|
test "parse_fix_typos with action field" {
  let json_str =
    #|{"action": "fix_typos", "original": "teh", "fixed": "the"}
  let actions = @llm.parse_edit_actions(json_str)
  inspect(actions.length(), content="1")
  inspect(actions[0], content="FixTypos(original=\"teh\", fixed=\"the\")")
}
