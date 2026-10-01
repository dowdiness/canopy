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
