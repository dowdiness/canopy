///|
test "REPL source identity is construction-scoped" {
  let repl_a = ReplState::new("same-agent")
  let repl_b = ReplState::new("same-agent")
  inspect(repl_a.source_id == repl_b.source_id, content="false")
}
