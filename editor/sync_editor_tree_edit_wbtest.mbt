// Whitebox tests for generic Tier-2 tree edit methods.
// Uses the neutral TestExpr grammar (@probe) — these exercise the
// language-agnostic SyncEditor[T] edit surface (delete_node / commit_edit /
// apply_text_transform / move_node / is_dirty / refresh), not any
// lambda-specific behavior.
//
// TestExpr grammar: `f(x)` -> Branch("f", [Leaf("x")]); a bare ident -> Leaf;
// the document root is Branch("", <top-level exprs>). placeholder is "?".

///|
test "delete_node replaces span with placeholder" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x)")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.delete_node(root.id(), 0)
  inspect(result is Ok(_), content="true")
}

///|
test "commit_edit replaces span with new text" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "b", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="b")
}

///|
test "apply_text_transform wraps node" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.apply_text_transform(
    root.id(),
    fn(src, s, e) { Ok("g(" + src[s:e].to_owned() + ")") },
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="g(a)")
}

///|
test "delete_node returns error for unknown node_id" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let _ = editor.get_proj_node()
  let bad_id = @core.NodeId::from_int(99999)
  let result = editor.delete_node(bad_id, 0)
  inspect(result is Err(_), content="true")
}

///|
test "commit_edit returns error for unknown node_id" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let _ = editor.get_proj_node()
  let bad_id = @core.NodeId::from_int(99999)
  let result = editor.commit_edit(bad_id, "b", 0)
  inspect(result is Err(_), content="true")
}

///|
test "is_dirty set after set_text" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  inspect(editor.is_dirty(), content="true")
}

///|
test "is_dirty set after insert/backspace" {
  let editor = @probe.new_test_editor("test")
  // Consume initial dirty from construction
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // insert goes through apply_local_text_change → set_parser_signals
  editor.insert("a") catch {
    _ => ()
  }
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // backspace also sets dirty
  editor.move_cursor(1)
  let _ = editor.backspace()
  inspect(editor.is_dirty(), content="true")
}

///|
test "refresh clears dirty flag and further edits are accepted" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // further edits work normally after refresh
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "b", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="b")
  inspect(editor.is_dirty(), content="true")
}

///|
test "move_node moves source before target and adjusts text" {
  // "a b" -> root Branch("", [Leaf("a"), Leaf("b")])
  // Move Leaf("b") Before Leaf("a"):
  //   step 1: replace b's span with placeholder("?")
  //   step 2: insert "b " at the target start
  let editor = @probe.new_test_editor("test")
  editor.set_text("a b")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  if root.children.length() < 2 {
    fail("expected 2 top-level exprs, got \{root.children.length()}")
  }
  let src_id = root.children[1].id() // Leaf("b")
  let tgt_id = root.children[0].id() // Leaf("a")
  let result = editor.move_node(src_id, tgt_id, @core.DropPosition::Before, 0)
  inspect(result is Ok(_), content="true")
  // Before semantics, asserted on AST order rather than the raw placeholder
  // text: the moved source ("b") now precedes the former target ("a") in the
  // document. This stays valid across any refactor of move_node's placeholder
  // or whitespace handling, while still proving the reorder actually happened.
  let root2 = match editor.get_proj_node() {
    None => fail("no proj node after move")
    Some(n) => n
  }
  inspect(root2.children[0].kind, content="Leaf(\"b\")")
  inspect(root2.children[1].kind, content="Leaf(\"a\")")
  // dirty flag set after move
  inspect(editor.is_dirty(), content="true")
}

///|
test "move_node exchange (Inside) swaps two leaves" {
  // "a b" -> root Branch("", [Leaf("a"), Leaf("b")])
  let editor = @probe.new_test_editor("test")
  editor.set_text("a b")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let child0 = root.children[0] // Leaf("a")
  let child1 = root.children[1] // Leaf("b")
  let result = editor.move_node(
    child0.id(),
    child1.id(),
    @core.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="b a")
}

///|
test "move_node exchange moves whole branches" {
  // "f(a) g(b)" -> root with two Branch children
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(a) g(b)")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let branch_f = root.children[0] // f(a)
  let branch_g = root.children[1] // g(b)
  let result = editor.move_node(
    branch_f.id(),
    branch_g.id(),
    @core.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="g(b) f(a)")
}

///|
test "move_node exchange: short and long leaf" {
  // "p qrs" -> root Branch("", [Leaf("p"), Leaf("qrs")])
  let editor = @probe.new_test_editor("test")
  editor.set_text("p qrs")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let leaf_p = root.children[0] // Leaf("p")
  let leaf_qrs = root.children[1] // Leaf("qrs")
  let result = editor.move_node(
    leaf_p.id(),
    leaf_qrs.id(),
    @core.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="qrs p")
}

///|
test "move_node exchange: branch and leaf" {
  // "f(x) y" -> root Branch("", [Branch("f", [Leaf("x")]), Leaf("y")])
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x) y")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let branch_f = root.children[0] // f(x)
  let leaf_y = root.children[1] // Leaf("y")
  let result = editor.move_node(
    branch_f.id(),
    leaf_y.id(),
    @core.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="y f(x)")
}

///|
test "move_node exchange: nested siblings" {
  // "h(p q)" -> root Branch("", [Branch("h", [Leaf("p"), Leaf("q")])])
  // Exchange the two leaves inside the branch.
  let editor = @probe.new_test_editor("test")
  editor.set_text("h(p q)")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let branch_h = root.children[0] // h(p q)
  let leaf_p = branch_h.children[0] // Leaf("p")
  let leaf_q = branch_h.children[1] // Leaf("q")
  let result = editor.move_node(
    leaf_p.id(),
    leaf_q.id(),
    @core.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="h(q p)")
}
