// Tests for parse recovery producing explicit Error ProjNodes
// instead of silently coercing to Int(0) / Plus.

///|
test "recovery: int literal overflow yields Error node" {
  // parse_int overflows on 20+ digit integers, so IntLiteralView::value
  // returns None. Recovery should emit an Error node, not Int(0).
  let (proj, _) = parse_to_proj_node("99999999999999999999")
  match proj.kind {
    Error(msg) => inspect(msg, content="invalid integer literal")
    other => fail("expected Error node, got \{other}")
  }
}

///|
test "recovery: valid int literal still produces Int" {
  let (proj, _) = parse_to_proj_node("42")
  inspect(proj.kind, content="Int(42)")
}
