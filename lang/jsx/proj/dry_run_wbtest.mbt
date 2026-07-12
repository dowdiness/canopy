///|
/// Whitebox tests for the pure model behind the JSX commit boundary.
fn DryRunModel::shape(self : DryRunModel) -> String {
  shape_children(self.children)
}

///|
fn shape_children(children : Array[DryRunNode]) -> String {
  "[" + children.map(shape_node).join(",") + "]"
}

///|
fn shape_node(node : DryRunNode) -> String {
  match node {
    DryRunNode::Element(node_id, tag, attrs, children) =>
      "E(" +
      node_id.to_string() +
      "," +
      tag +
      "," +
      attrs.length().to_string() +
      "," +
      shape_children(children) +
      ")"
    DryRunNode::Text(node_id, value) =>
      "T(" + node_id.to_string() + "," + value + ")"
    DryRunNode::ExprSpan(node_id, raw) =>
      "X(" + node_id.to_string() + "," + raw + ")"
  }
}

///|
test "dry run preserves mixed sibling order and applies nested updates" {
  let first = DryRunModel::empty()
    .apply([
      DomPatch::MakeElement(-1, 1, "div", [], 0),
      DomPatch::MakeText(1, 2, "a", 0),
      DomPatch::MakeElement(1, 3, "span", [], 1),
      DomPatch::MakeText(3, 4, "inside", 0),
      DomPatch::MakeExprSpan(1, 5, "value", 2),
    ])
    .unwrap()
  inspect(
    first.shape(),
    content="[E(1,div,0,[T(2,a),E(3,span,0,[T(4,inside)]),X(5,value)])]",
  )

  let updated = first
    .apply([DomPatch::SetText(4, "changed"), DomPatch::SetExpr(5, "next")])
    .unwrap()
  inspect(
    updated.shape(),
    content="[E(1,div,0,[T(2,a),E(3,span,0,[T(4,changed)]),X(5,next)])]",
  )
  // apply() is a pure state transition from the caller's perspective.
  inspect(
    first.shape(),
    content="[E(1,div,0,[T(2,a),E(3,span,0,[T(4,inside)]),X(5,value)])]",
  )
}

///|
test "dry run releases before evaluating insertion indexes" {
  let first = DryRunModel::empty()
    .apply([
      DomPatch::MakeElement(-1, 1, "div", [], 0),
      DomPatch::MakeText(1, 2, "a", 0),
      DomPatch::MakeText(1, 3, "b", 1),
      DomPatch::MakeText(1, 4, "c", 2),
    ])
    .unwrap()
  let updated = first
    .apply([DomPatch::Release(3), DomPatch::MakeText(1, 5, "new", 1)])
    .unwrap()
  inspect(updated.shape(), content="[E(1,div,0,[T(2,a),T(5,new),T(4,c)])]")
}

///|
test "dry run rejects an invalid parent without mutating the prior model" {
  let first = DryRunModel::empty()
    .apply([DomPatch::MakeElement(-1, 1, "div", [], 0)])
    .unwrap()
  let failed = first.apply([DomPatch::MakeText(99, 2, "orphan", 0)])
  match failed {
    Ok(_) => fail("invalid patch unexpectedly succeeded")
    Err(message) => inspect(message, content="missing parent node: 99")
  }
  inspect(first.shape(), content="[E(1,div,0,[])]")
}

///|
test "dry run normalizes DOM attribute values and names" {
  let model = DryRunModel::empty()
    .apply([
      DomPatch::MakeElement(
        -1,
        1,
        "div",
        [
          @jsx.JsxAttr::JsxAttr(
            name="data-genui-label",
            value=@jsx.JsxAttrValue::StringLit("a&amp;b"),
          ),
          @jsx.JsxAttr::JsxAttr(
            name="data-other",
            value=@jsx.JsxAttrValue::StringLit("a&amp;b"),
          ),
          @jsx.JsxAttr::JsxAttr(
            name="data-node-id",
            value=@jsx.JsxAttrValue::StringLit("spoof"),
          ),
          @jsx.JsxAttr::JsxAttr(name="hidden", value=@jsx.JsxAttrValue::Bare),
          @jsx.JsxAttr::JsxAttr(
            name="data-genui-expression",
            value=@jsx.JsxAttrValue::ExprSpan(raw="value"),
          ),
          @jsx.JsxAttr::JsxAttr(
            name="data-genui-label",
            value=@jsx.JsxAttrValue::StringLit("last&amp;value"),
          ),
        ],
        0,
      ),
    ])
    .unwrap()
  let attrs = match model.children[0] {
    DryRunNode::Element(_, _, attrs, _) => attrs
    _ => fail("expected a root element")
  }
  assert_eq(attrs.length(), 3)
  assert_true(attrs[0].value == @jsx.JsxAttrValue::StringLit("last&value"))
  assert_true(attrs[1].value == @jsx.JsxAttrValue::StringLit("a&amp;b"))
  assert_true(attrs[2].value == @jsx.JsxAttrValue::StringLit(""))
}
