///| Whitebox tests for JSX projection (Task 2.2 Step 4 checkpoint).

///|
test "parse and project basic element" {
  // parse_to_proj_node always wraps in Root (Task 1.2 Step 5: a streaming
  // prefix can legally have several roots) — the plan's original snippet
  // predates that AST divergence and asserted "Element" directly at the
  // top; check the wrapped element instead.
  let (root, errors) = parse_to_proj_node("<div>hello</div>")
  inspect(errors.length(), content="0")
  inspect(root.kind.kind_tag(), content="Root")
  inspect(root.children[0].kind.kind_tag(), content="Element")
}

///|
test "projection: root wraps top-level nodes" {
  let (root, _) = parse_to_proj_node("<div/>")
  inspect(root.kind.kind_tag(), content="Root")
  inspect(root.children.length(), content="1")
}

///|
test "projection: element with text child" {
  let (root, errors) = parse_to_proj_node("<p>hello world</p>")
  inspect(errors.length(), content="0")
  let el = root.children[0]
  inspect(el.children.length(), content="1")
  inspect(el.children[0].kind.kind_tag(), content="Text")
}

///|
test "projection: nested elements" {
  let (root, errors) = parse_to_proj_node(
    "<div><h1>title</h1><p>body</p></div>",
  )
  inspect(errors.length(), content="0")
  let div = root.children[0]
  inspect(div.children.length(), content="2")
  inspect(div.children[0].kind.kind_tag(), content="Element")
  inspect(div.children[1].kind.kind_tag(), content="Element")
}

///|
test "projection: attrs are excluded from proj children" {
  let (root, errors) = parse_to_proj_node("<div class=\"a\" id=\"b\">x</div>")
  inspect(errors.length(), content="0")
  let div = root.children[0]
  // Only the Text child appears — the two attrs must not be counted.
  inspect(div.children.length(), content="1")
  inspect(div.children[0].kind.kind_tag(), content="Text")
}

///|
test "projection: expression span child" {
  let (root, errors) = parse_to_proj_node("<p>{title}</p>")
  inspect(errors.length(), content="0")
  let p = root.children[0]
  inspect(p.children[0].kind.kind_tag(), content="ExprSpan")
}

///|
test "projection: fragment" {
  let (root, errors) = parse_to_proj_node("<><span/><span/></>")
  inspect(errors.length(), content="0")
  let fragment = root.children[0]
  inspect(fragment.kind.kind_tag(), content="Fragment")
  inspect(fragment.children.length(), content="2")
}

///|
test "projection: unclosed element still exposes parsed children" {
  let (root, errors) = parse_to_proj_node("<div><span>text")
  // Design B case 2: diagnostics are pushed, but children are not
  // discarded.
  inspect(errors.length() > 0, content="true")
  let div = root.children[0]
  inspect(div.kind.kind_tag(), content="Element")
  inspect(div.children.length(), content="1")
  let span = div.children[0]
  inspect(span.children.length(), content="1")
  inspect(span.children[0].kind.kind_tag(), content="Text")
}
