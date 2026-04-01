// Tests for ViewNode JSON serialization.

///|
test "TokenSpan to_json produces object-based JSON" {
  let span = @protocol.TokenSpan(role="param", start=2, end=5)
  let json = span.to_json()
  let s = json.stringify()
  inspect(s, content="{\"role\":\"param\",\"start\":2,\"end\":5}")
}

///|
test "ViewNode to_json produces object-based JSON" {
  let node = @protocol.ViewNode(
    id=@core.NodeId::from_int(42),
    kind_tag="Lam",
    label="\u{03BB}x",
    text_range=(0, 5),
    css_class="Lam",
  )
  let json = node.to_json()
  let s = json.stringify()
  // Verify it's an object, not an array (derive(ToJson) would produce array-based)
  assert_true(s.has_prefix("{"))
  // Verify key fields are present
  assert_true(s.contains("\"id\":42"))
  assert_true(s.contains("\"kind_tag\":\"Lam\""))
  assert_true(s.contains("\"text\":null"))
  assert_true(s.contains("\"text_range\":[0,5]"))
  assert_true(s.contains("\"children\":[]"))
}
