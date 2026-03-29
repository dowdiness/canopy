// Whitebox tests for JSON projection builder.

///|
test "parse null → ProjNode with kind Null, 0 children" {
  let (proj, errors) = parse_to_proj_node("null")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Null")
  inspect(proj.children.length(), content="0")
  inspect(proj.start, content="0")
  inspect(proj.end, content="4")
}

///|
test "parse number → ProjNode with kind Number" {
  let (proj, errors) = parse_to_proj_node("42")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Number(42)")
  inspect(proj.children.length(), content="0")
}

///|
test "parse string → ProjNode with kind String (unescaped)" {
  let (proj, errors) = parse_to_proj_node("\"hello\"")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="String(\"hello\")")
  inspect(proj.children.length(), content="0")
}

///|
test "parse string with escapes → properly unescaped" {
  let (proj, _errors) = parse_to_proj_node("\"hello\\nworld\"")
  inspect(proj.kind, content="String(\"hello\\nworld\")")
}

///|
test "parse array [1, 2, 3] → Array with 3 children" {
  let (proj, errors) = parse_to_proj_node("[1, 2, 3]")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Array([Number(1), Number(2), Number(3)])")
  inspect(proj.children.length(), content="3")
  inspect(proj.children[0].kind, content="Number(1)")
  inspect(proj.children[1].kind, content="Number(2)")
  inspect(proj.children[2].kind, content="Number(3)")
}

///|
test "parse object {\"a\": 1, \"b\": true} → Object with 2 children" {
  let (proj, errors) = parse_to_proj_node("{\"a\": 1, \"b\": true}")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="2")
  // First child: key "a", value Number(1)
  inspect(proj.children[0].kind, content="Number(1)")
  // Second child: key "b", value Bool(true)
  inspect(proj.children[1].kind, content="Bool(true)")
  // Object kind contains the full member list
  inspect(
    proj.kind,
    content="Object([(\"a\", Number(1)), (\"b\", Bool(true))])",
  )
}

///|
test "parse nested {\"data\": [1, 2]} → correct nesting" {
  let (proj, errors) = parse_to_proj_node("{\"data\": [1, 2]}")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="1")
  // The child is a member with Array value
  let data_child = proj.children[0]
  inspect(data_child.kind, content="Array([Number(1), Number(2)])")
  inspect(data_child.children.length(), content="2")
  inspect(data_child.children[0].kind, content="Number(1)")
  inspect(data_child.children[1].kind, content="Number(2)")
}

///|
test "parse empty object {} → 0 children" {
  let (proj, errors) = parse_to_proj_node("{}")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Object([])")
  inspect(proj.children.length(), content="0")
}

///|
test "parse empty array [] → 0 children" {
  let (proj, errors) = parse_to_proj_node("[]")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Array([])")
  inspect(proj.children.length(), content="0")
}

///|
test "parse true / false → Bool" {
  let (t, _) = parse_to_proj_node("true")
  inspect(t.kind, content="Bool(true)")
  let (f, _) = parse_to_proj_node("false")
  inspect(f.kind, content="Bool(false)")
}

///|
test "parse error recovery {\"a\": } → Object with Error child" {
  let (proj, errors) = parse_to_proj_node("{\"a\": }")
  // Should have parse errors
  inspect(errors.length() > 0, content="true")
  // But still produces an Object node
  inspect(proj.children.length(), content="1")
}

///|
test "object child ProjNode uses value span (not member span)" {
  // "{\"a\": 1}" — the NumberValue node includes leading trivia (space)
  // so it spans [5, 7), not [1, 7) which would be the MemberNode span
  let (proj, _errors) = parse_to_proj_node("{\"a\": 1}")
  let child = proj.children[0]
  // Object starts at 0, ends at 8
  inspect(proj.start, content="0")
  inspect(proj.end, content="8")
  // Child span should cover only the value node, not the full member.
  // The NumberValue node starts at 5 (leading trivia) and ends at 7.
  inspect(child.start, content="5")
  inspect(child.end, content="7")
}

///|
test "SourceMap from_ast produces correct ranges" {
  let (proj, _errors) = parse_to_proj_node("{\"a\": 1, \"b\": 2}")
  let sm = @core.SourceMap::from_ast(proj)
  // Root + 2 children = 3 nodes
  inspect(sm.node_count(), content="3")
  // Root range
  inspect(sm.get_range(proj.id()) is Some(_), content="true")
  // Children ranges
  inspect(sm.get_range(proj.children[0].id()) is Some(_), content="true")
  inspect(sm.get_range(proj.children[1].id()) is Some(_), content="true")
}

///|
test "token spans for object keys stored on Object node" {
  let text = "{\"a\": 1, \"b\": 2}"
  let (cst, _) = @json.parse_cst(text) catch { _ => abort("parse failed") }
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref::new(0)
  let proj = syntax_to_proj_node(syntax_node, counter)
  let sm = @core.SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax_node, proj)
  // Key spans are stored on the Object ProjNode (parent), not on children
  let key0_span = sm.get_token_span(proj.id(), "key:0")
  inspect(key0_span is Some(_), content="true")
  let key1_span = sm.get_token_span(proj.id(), "key:1")
  inspect(key1_span is Some(_), content="true")
  // Member spans are also stored on the Object ProjNode
  let member0_span = sm.get_token_span(proj.id(), "member:0")
  inspect(member0_span is Some(_), content="true")
  let member1_span = sm.get_token_span(proj.id(), "member:1")
  inspect(member1_span is Some(_), content="true")
}

///|
test "reconcile preserves IDs on value edit" {
  let (old_proj, _) = parse_to_proj_node("{\"a\": 1, \"b\": 2}")
  let (new_proj, _) = parse_to_proj_node("{\"a\": 99, \"b\": 2}")
  let counter = Ref::new(100)
  let reconciled = @core.reconcile(old_proj, new_proj, counter)
  // Object kind matches → old root ID preserved
  inspect(reconciled.node_id, content=old_proj.node_id.to_string())
  // Second child (unchanged "b": 2) should preserve ID
  inspect(
    reconciled.children[1].node_id,
    content=old_proj.children[1].node_id.to_string(),
  )
}

///|
test "parse floating point number" {
  let (proj, errors) = parse_to_proj_node("3.14")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Number(3.14)")
}

///|
test "parse negative number" {
  let (proj, errors) = parse_to_proj_node("-42")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Number(-42)")
}
