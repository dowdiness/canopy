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
