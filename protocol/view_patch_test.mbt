// Tests for ViewPatch, Decoration, and Diagnostic JSON serialization.

///|
test "Decoration to_json produces object-based JSON" {
  let dec = @protocol.Decoration(from=0, to=5, css_class="keyword")
  let s = dec.to_json().stringify()
  inspect(
    s,
    content="{\"from\":0,\"to\":5,\"css_class\":\"keyword\",\"data\":null,\"widget\":false}",
  )
}

///|
test "Decoration with data and widget to_json" {
  let dec = @protocol.Decoration(
    from=10,
    to=15,
    css_class="peer-cursor",
    data="Alice",
    widget=true,
  )
  let s = dec.to_json().stringify()
  assert_true(s.contains("\"data\":\"Alice\""))
  assert_true(s.contains("\"widget\":true"))
  assert_true(s.contains("\"css_class\":\"peer-cursor\""))
}

///|
test "Diagnostic to_json produces object-based JSON" {
  let diag = @protocol.Diagnostic(
    from=0,
    to=3,
    severity=@protocol.SevError,
    message="unbound var",
  )
  let s = diag.to_json().stringify()
  inspect(
    s,
    content="{\"from\":0,\"to\":3,\"severity\":\"error\",\"message\":\"unbound var\"}",
  )
}

///|
test "ViewPatch::TextChange to_json" {
  let patch = @protocol.ViewPatch::TextChange(from=1, to=5, insert="hello")
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"TextChange\""))
  assert_true(s.contains("\"from\":1"))
  assert_true(s.contains("\"to\":5"))
  assert_true(s.contains("\"insert\":\"hello\""))
}

///|
test "ViewPatch::ReplaceNode to_json" {
  let node = @protocol.ViewNode(
    id=@core.NodeId::from_int(42),
    kind_tag="Var",
    label="x",
    text_range=(0, 1),
  )
  let patch = @protocol.ViewPatch::ReplaceNode(
    node_id=@core.NodeId::from_int(42),
    node~,
  )
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"ReplaceNode\""))
  assert_true(s.contains("\"node_id\":42"))
  assert_true(s.contains("\"kind_tag\":\"Var\""))
}

///|
test "ViewPatch::InsertChild to_json" {
  let child = @protocol.ViewNode(
    id=@core.NodeId::from_int(10),
    kind_tag="Int",
    label="5",
    text_range=(3, 4),
  )
  let patch = @protocol.ViewPatch::InsertChild(
    parent_id=@core.NodeId::from_int(1),
    index=2,
    child~,
  )
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"InsertChild\""))
  assert_true(s.contains("\"parent_id\":1"))
  assert_true(s.contains("\"index\":2"))
}

///|
test "ViewPatch::RemoveChild to_json" {
  let patch = @protocol.ViewPatch::RemoveChild(
    parent_id=@core.NodeId::from_int(1),
    index=0,
    child_id=@core.NodeId::from_int(5),
  )
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"RemoveChild\""))
  assert_true(s.contains("\"parent_id\":1"))
  assert_true(s.contains("\"index\":0"))
  assert_true(s.contains("\"child_id\":5"))
}

///|
test "ViewPatch::UpdateNode to_json with text" {
  let patch = @protocol.ViewPatch::UpdateNode(
    node_id=@core.NodeId::from_int(7),
    label="42",
    css_class="Int",
    text=Some("42"),
  )
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"UpdateNode\""))
  assert_true(s.contains("\"node_id\":7"))
  assert_true(s.contains("\"label\":\"42\""))
  assert_true(s.contains("\"text\":\"42\""))
}

///|
test "ViewPatch::UpdateNode to_json without text" {
  let patch = @protocol.ViewPatch::UpdateNode(
    node_id=@core.NodeId::from_int(7),
    label="x",
    css_class="Var",
    text=None,
  )
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"text\":null"))
}

///|
test "ViewPatch::SetDecorations to_json" {
  let decs = [
    @protocol.Decoration(from=0, to=3, css_class="keyword"),
    @protocol.Decoration(from=4, to=5, css_class="ident"),
  ]
  let patch = @protocol.ViewPatch::SetDecorations(decorations=decs)
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"SetDecorations\""))
  assert_true(s.contains("\"decorations\":["))
  assert_true(s.contains("\"keyword\""))
  assert_true(s.contains("\"ident\""))
}

///|
test "ViewPatch::SetDiagnostics to_json" {
  let diags = [
    @protocol.Diagnostic(
      from=0,
      to=3,
      severity=@protocol.SevError,
      message="bad",
    ),
  ]
  let patch = @protocol.ViewPatch::SetDiagnostics(diagnostics=diags)
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"SetDiagnostics\""))
  assert_true(s.contains("\"diagnostics\":["))
  assert_true(s.contains("\"severity\":\"error\""))
}

///|
test "ViewPatch::SetSelection to_json" {
  let patch = @protocol.ViewPatch::SetSelection(anchor=5, head=10)
  let s = patch.to_json().stringify()
  inspect(s, content="{\"type\":\"SetSelection\",\"anchor\":5,\"head\":10}")
}

///|
test "ViewPatch::SelectNode to_json" {
  let patch = @protocol.ViewPatch::SelectNode(
    node_id=@core.NodeId::from_int(99),
  )
  let s = patch.to_json().stringify()
  inspect(s, content="{\"type\":\"SelectNode\",\"node_id\":99}")
}

///|
test "ViewPatch::FullTree to_json with node" {
  let root = @protocol.ViewNode(
    id=@core.NodeId::from_int(1),
    kind_tag="Module",
    label="module",
    text_range=(0, 10),
  )
  let patch = @protocol.ViewPatch::FullTree(root=Some(root))
  let s = patch.to_json().stringify()
  assert_true(s.contains("\"type\":\"FullTree\""))
  assert_true(s.contains("\"root\":{"))
}

///|
test "ViewPatch::FullTree to_json with null root" {
  let patch = @protocol.ViewPatch::FullTree(root=None)
  let s = patch.to_json().stringify()
  inspect(s, content="{\"type\":\"FullTree\",\"root\":null}")
}
