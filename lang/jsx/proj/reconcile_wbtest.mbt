///| Whitebox tests for reconcile — pure DomPatch generation.

///|
/// First render produces patches.
test "reconcile: first render produces patches" {
  let (root, _) = parse_to_proj_node("<p>hello</p>")
  let (patches, reached) = reconcile(root, [])
  inspect(patches.length() > 0, content="true")
  inspect(reached.length() > 0, content="true")
}

///|
/// Empty existing set → all nodes new → all Make patches.
test "reconcile: empty existing produces Make" {
  let (root, _) = parse_to_proj_node("<span>text</span>")
  let (patches, _) = reconcile(root, [])
  for p in patches {
    match p {
      MakeElement(_, _, _, _, _)
      | MakeText(_, _, _, _)
      | MakeExprSpan(_, _, _, _) => ()
      _ => fail("non-Make patch on first render: " + patch_label(p))
    }
  }
}

///|
/// Helper: check if any patch matches a predicate.
fn has_patch(patches : Array[DomPatch], kind : String) -> Bool {
  for p in patches {
    if patch_label(p) == kind {
      return true
    }
  }
  false
}

///|
/// Helper: find value in a SetText patch.
fn find_text(patches : Array[DomPatch], expected : String) -> Bool {
  for p in patches {
    match p {
      SetText(_, s) => if s == expected { return true }
      _ => ()
    }
  }
  false
}

///|
/// Helper: collect IDs that correspond to mounted DOM nodes.
fn patch_ids(patches : Array[DomPatch]) -> Array[Int] {
  let ids : Array[Int] = []
  for patch in patches {
    match patch {
      MakeElement(_, id, _, _, _)
      | MakeText(_, id, _, _)
      | MakeExprSpan(_, id, _, _)
      | SetText(id, _)
      | SetExpr(id, _)
      | SetAttrs(id, _) => ids.push(id)
      Release(_) => ()
    }
  }
  ids
}

///|
/// Helper: count element creation patches for one tag.
fn count_make_element(patches : Array[DomPatch], expected : String) -> Int {
  let mut count = 0
  for patch in patches {
    match patch {
      MakeElement(_, _, tag, _, _) => if tag == expected { count += 1 }
      _ => ()
    }
  }
  count
}

///|
/// Helper: count text creation patches for one value.
fn count_make_text(patches : Array[DomPatch], expected : String) -> Int {
  let mut count = 0
  for patch in patches {
    match patch {
      MakeText(_, _, text, _) => if text == expected { count += 1 }
      _ => ()
    }
  }
  count
}

///|
/// Second render with same text → SetText.
test "reconcile: existing text produces SetText" {
  let (root, _) = parse_to_proj_node("<p>hello</p>")
  let (_, reached) = reconcile(root, [])
  let (patches, _) = reconcile(root, reached)
  inspect(has_patch(patches, "SetText"), content="true")
  inspect(has_patch(patches, "MakeText"), content="false")
}

///|
/// Text content change → SetText with updated value.
test "reconcile: text change produces SetText with new value" {
  let (root, _) = parse_to_proj_node("<p>hello</p>")
  let (_, reached) = reconcile(root, [])
  let (root2, _) = parse_to_proj_node("<p>world</p>")
  let (patches, _) = reconcile(root2, reached)
  inspect(find_text(patches, "world"), content="true")
}

///|
/// Element with attributes.
test "reconcile: element attributes" {
  let (root, _) = parse_to_proj_node("<div class=\"foo\">x</div>")
  let (p1, reached) = reconcile(root, [])
  inspect(has_patch(p1, "MakeElement"), content="true")
  let (root2, _) = parse_to_proj_node("<div class=\"foo\">x</div>")
  let (p2, _) = reconcile(root2, reached)
  inspect(has_patch(p2, "SetAttrs"), content="true")
}

///|
/// Node removed → Release.
test "reconcile: removed node produces Release" {
  let (root, _) = parse_to_proj_node("<p>hello</p>")
  let (_, reached) = reconcile(root, [])
  let (root2, _) = parse_to_proj_node("<div></div>")
  let (patches, _) = reconcile(root2, reached)
  inspect(has_patch(patches, "Release"), content="true")
}

///|
/// Nested elements produce correct node count.
test "reconcile: nested elements" {
  let (root, _) = parse_to_proj_node("<div><h1>title</h1><p>body</p></div>")
  let (_, reached) = reconcile(root, [])
  inspect(reached.length(), content="6")
}

///|
/// A trailing `<` is a recoverable parser state, not a valid DOM element.
test "reconcile: incomplete tag does not produce empty MakeElement" {
  let (root, _) = parse_to_proj_node("<div><p>text</p>\n<")
  let (patches, _) = reconcile(root, [])
  for patch in patches {
    match patch {
      MakeElement(_, _, "", _, _) =>
        fail("empty tag must not cross the DOM patch boundary")
      _ => ()
    }
  }
}

///|
/// An explicitly recovered empty-tag element remains in the projection but
/// is transparent at the DOM patch boundary: its child renders under the
/// recovery node's parent and the empty tag itself is never mounted.
test "reconcile: empty-tag recovery is transparent and preserves children" {
  let text_kind = @jsx.JsxNode::Text("hello")
  let child = @core.ProjNode::ProjNode(text_kind, 0, 5, 2, [])
  let recovery_kind = @jsx.JsxNode::Element(tag="", attrs=[], children=[
    text_kind,
  ])
  let recovery = @core.ProjNode::ProjNode(recovery_kind, 0, 5, 1, [child])
  let root_kind = @jsx.JsxNode::Root(children=[recovery_kind])
  let root = @core.ProjNode::ProjNode(root_kind, 0, 5, 0, [recovery])
  let (patches, _) = reconcile(root, [])
  inspect(patches.length(), content="1")
  match patches[0] {
    MakeText(parent_id, _, text, index) => {
      inspect(parent_id, content="-1")
      inspect(text, content="hello")
      inspect(index, content="0")
    }
    other =>
      fail("expected transparent recovery child patch: " + patch_label(other))
  }
}

///|
/// When a duplicate same-kind sibling is appended, only the new tail should
/// cross the DOM mount boundary on the second render.
test "reconcile: append equal-kind sibling mounts only the tail" {
  let (old_root, _) = parse_to_proj_node(
    "<div><span>a</span><span>b</span></div>",
  )
  let (first_patches, _) = reconcile(old_root, [])
  let existing = patch_ids(first_patches)
  let (new_raw, _) = parse_to_proj_node(
    "<div><span>a</span><span>b</span><span>c</span></div>",
  )
  let new_root = reconcile_jsx_projection(old_root, new_raw, Ref(1000), None)
  let (patches, _) = reconcile(new_root, existing)
  inspect(count_make_element(patches, "div"), content="0")
  inspect(count_make_element(patches, "span"), content="1")
  inspect(count_make_text(patches, "a"), content="0")
  inspect(count_make_text(patches, "b"), content="0")
  inspect(count_make_text(patches, "c"), content="1")
  inspect(has_patch(patches, "Release"), content="false")
}

///|
/// Attribute differences are part of the exact subtree key, so a same-tag
/// middle insertion does not retarget either existing sibling.
test "reconcile: attribute-distinct siblings preserve exact identities" {
  let (old_root, _) = parse_to_proj_node(
    "<div><span class=\"a\"/><span class=\"b\"/></div>",
  )
  let old_div = old_root.children[0]
  let (new_raw, _) = parse_to_proj_node(
    "<div><span class=\"a\"/><span class=\"x\"/><span class=\"b\"/></div>",
  )
  let new_root = reconcile_jsx_projection(old_root, new_raw, Ref(1000), None)
  let new_div = new_root.children[0]
  inspect(new_div.children[0].id() == old_div.children[0].id(), content="true")
  inspect(new_div.children[2].id() == old_div.children[1].id(), content="true")
  inspect(new_div.children[1].id() != old_div.children[0].id(), content="true")
  inspect(new_div.children[1].id() != old_div.children[1].id(), content="true")
}

///|
test "reconcile: attribute key separates delimiter-containing values" {
  let one = @jsx.JsxNode::Element(
    tag="div",
    attrs=[
      @jsx.JsxAttr::JsxAttr(
        name="a",
        value=@jsx.JsxAttrValue::StringLit("x,b=string:y"),
      ),
    ],
    children=[],
  )
  let two = @jsx.JsxNode::Element(
    tag="div",
    attrs=[
      @jsx.JsxAttr::JsxAttr(name="a", value=@jsx.JsxAttrValue::StringLit("x")),
      @jsx.JsxAttr::JsxAttr(name="b", value=@jsx.JsxAttrValue::StringLit("y")),
    ],
    children=[],
  )
  inspect(jsx_exact_key(one) == jsx_exact_key(two), content="false")
}

///|
/// An empty-tag recovery node remains transparent when its existing child is
/// updated on a later render.
test "reconcile: empty-tag recovery updates existing child" {
  let first_text_kind = @jsx.JsxNode::Text("before")
  let first_child = @core.ProjNode::ProjNode(first_text_kind, 0, 6, 2, [])
  let first_recovery_kind = @jsx.JsxNode::Element(tag="", attrs=[], children=[
    first_text_kind,
  ])
  let first_recovery = @core.ProjNode::ProjNode(first_recovery_kind, 0, 6, 1, [
    first_child,
  ])
  let first_root_kind = @jsx.JsxNode::Root(children=[first_recovery_kind])
  let first_root = @core.ProjNode::ProjNode(first_root_kind, 0, 6, 0, [
    first_recovery,
  ])
  let (first_patches, _) = reconcile(first_root, [])
  let existing = patch_ids(first_patches)

  let next_text_kind = @jsx.JsxNode::Text("after")
  let next_child = @core.ProjNode::ProjNode(next_text_kind, 0, 5, 2, [])
  let next_recovery_kind = @jsx.JsxNode::Element(tag="", attrs=[], children=[
    next_text_kind,
  ])
  let next_recovery = @core.ProjNode::ProjNode(next_recovery_kind, 0, 5, 1, [
    next_child,
  ])
  let next_root_kind = @jsx.JsxNode::Root(children=[next_recovery_kind])
  let next_root = @core.ProjNode::ProjNode(next_root_kind, 0, 5, 0, [
    next_recovery,
  ])
  let (patches, _) = reconcile(next_root, existing)
  inspect(find_text(patches, "after"), content="true")
  inspect(has_patch(patches, "MakeText"), content="false")
  inspect(has_patch(patches, "Release"), content="false")
}

///|
/// Removing the child below an empty-tag recovery node releases its mounted
/// child even though the recovery node itself was never mounted.
test "reconcile: empty-tag recovery removal releases child" {
  let text_kind = @jsx.JsxNode::Text("hello")
  let child = @core.ProjNode::ProjNode(text_kind, 0, 5, 2, [])
  let recovery_kind = @jsx.JsxNode::Element(tag="", attrs=[], children=[
    text_kind,
  ])
  let recovery = @core.ProjNode::ProjNode(recovery_kind, 0, 5, 1, [child])
  let root_kind = @jsx.JsxNode::Root(children=[recovery_kind])
  let root = @core.ProjNode::ProjNode(root_kind, 0, 5, 0, [recovery])
  let (first_patches, _) = reconcile(root, [])
  let existing = patch_ids(first_patches)

  let empty_recovery_kind = @jsx.JsxNode::Element(tag="", attrs=[], children=[])
  let empty_recovery = @core.ProjNode::ProjNode(empty_recovery_kind, 0, 0, 1, [])
  let empty_root_kind = @jsx.JsxNode::Root(children=[empty_recovery_kind])
  let empty_root = @core.ProjNode::ProjNode(empty_root_kind, 0, 0, 0, [
    empty_recovery,
  ])
  let (patches, _) = reconcile(empty_root, existing)
  inspect(patches.length(), content="1")
  match patches[0] {
    Release(id) => inspect(id, content="2")
    other => fail("expected recovery child release: " + patch_label(other))
  }
}

///|
/// Second render of nested tree produces Update patches.
test "reconcile: nested second render" {
  let (root, _) = parse_to_proj_node("<div><h1>title</h1></div>")
  let (_, reached) = reconcile(root, [])
  let (root2, _) = parse_to_proj_node("<div><h1>changed</h1></div>")
  let (patches, _) = reconcile(root2, reached)
  inspect(find_text(patches, "changed"), content="true")
}

///|
fn patch_label(p : DomPatch) -> String {
  match p {
    MakeElement(_, _, _, _, _) => "MakeElement"
    MakeText(_, _, _, _) => "MakeText"
    MakeExprSpan(_, _, _, _) => "MakeExprSpan"
    SetText(_, _) => "SetText"
    SetExpr(_, _) => "SetExpr"
    SetAttrs(_, _) => "SetAttrs"
    Release(_) => "Release"
  }
}
