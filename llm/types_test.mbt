///|
test "EditAction::FixTypos show" {
  let action : @llm.EditAction = FixTypos(original="teh", fixed="the")
  inspect(action, content="FixTypos(original=\"teh\", fixed=\"the\")")
}

///|
test "EditAction::Replace show" {
  let action : @llm.EditAction = Replace(line=3, old="hello", new="world")
  inspect(action, content="Replace(line=3, old=\"hello\", new=\"world\")")
}

///|
test "EditAction::Insert show" {
  let action : @llm.EditAction = Insert(line=5, text="new line")
  inspect(action, content="Insert(line=5, text=\"new line\")")
}

///|
test "EditAction::Delete show" {
  let action : @llm.EditAction = Delete(line=2)
  inspect(action, content="Delete(line=2)")
}

///|
test "EditAction equality" {
  let a : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let b : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let c : @llm.EditAction = FixTypos(original="teh", fixed="thee")
  assert_eq(a, b)
  assert_not_eq(a, c)
}

///|
test "Role show" {
  inspect(@llm.Role::System, content="System")
  inspect(@llm.Role::User, content="User")
  inspect(@llm.Role::Assistant, content="Assistant")
}

///|
test "Message construction" {
  let msg = @llm.Message(role=User, content="hello")
  inspect(msg.role, content="User")
  inspect(msg.content, content="hello")
}

///|
test "GeminiConfig defaults" {
  let cfg = @llm.GeminiConfig(api_key="test-key")
  inspect(cfg.model, content="gemini-2.5-flash")
  inspect(cfg.max_output_tokens, content="1024")
}

///|
test "EditAction::FixTypos to_json uses object format" {
  let action : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let json = action.to_json().stringify()
  assert_true(json.contains("\"action\""))
  assert_true(json.contains("\"fix_typos\""))
}

///|
test "EditAction::Replace to_json" {
  let action : @llm.EditAction = Replace(line=3, old="hello", new="world")
  let json = action.to_json().stringify()
  assert_true(json.contains("\"action\""))
  assert_true(json.contains("\"replace\""))
  assert_true(json.contains("\"line\""))
}
