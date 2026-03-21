// Whitebox tests for compute_text_edit

///|
/// Build a registry from a ProjNode tree.
fn text_edit_test_registry(root : ProjNode) -> Map[NodeId, ProjNode] {
  let registry : Map[NodeId, ProjNode] = {}
  fn register(node : ProjNode) {
    registry[node.id()] = node
    for child in node.children {
      register(child)
    }
  }
  register(root)
  registry
}

///|
/// Apply span edits to text (in reverse document order) and return the result.
fn apply_edits(text : String, edits : Array[SpanEdit]) -> String {
  let sorted = edits.copy()
  sorted.sort_by((a, b) => b.start.compare(a.start))
  let mut result = text
  for edit in sorted {
    result = result[:edit.start].to_string() +
      edit.inserted +
      result[edit.start + edit.delete_len:].to_string()
  }
  result
}

///|
test "compute_text_edit: CommitEdit replaces single expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    CommitEdit(node_id=root_id, new_value="99"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].start, content="0")
      inspect(edits[0].delete_len, content="2")
      inspect(apply_edits(text, edits), content="99")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: CommitEdit replaces left operand in binary expr" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // children[0] is the left operand (Var("x")), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=lhs.id(), new_value="y"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].start, content="0")
      inspect(edits[0].delete_len, content="1")
      inspect(apply_edits(text, edits), content="y + 1")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: no-op ops return empty array" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    Select(node_id=NodeId(0)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result, content="Ok(Some(([], RestoreCursor)))")
}

///|
test "compute_text_edit: Delete replaces node with placeholder" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    Delete(node_id=root_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      // Int node → placeholder "0"
      inspect(apply_edits(text, edits), content="0")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Delete replaces Var with placeholder" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // children[0] is the left operand Var("x"), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    Delete(node_id=lhs.id()),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      // Var → placeholder "a", parent re-rendered with print_term
      inspect(apply_edits(text, edits), content="(a + 1)")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInLambda wraps node in lambda abstraction" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInLambda(node_id=root_id, var_name="x"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(apply_edits(text, edits), content="(λx. 42)")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInApp wraps node in application" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInApp(node_id=root_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(apply_edits(text, edits), content="(42 a)")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InsertChild into Module inserts def text" {
  let text = "let y = 1\ny"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  // Insert a new Int def at index 1 (before the body)
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=1, kind=@ast.Term::Int(0)),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      // Should insert "let x = 0\n" at the body position
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nlet x = 0\ny")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InsertChild into non-Module re-renders parent" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  // Insert a Var child into a Bop node — re-renders with print_term
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=0, kind=@ast.Term::Var("z")),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      // Bop re-rendered via rebuild_kind + print_term with new child inserted
      let new_text = apply_edits(text, edits)
      // Pin exact expected output from rebuild_kind + print_term
      inspect(
        new_text,
        content=(
          #|(z + x)
        ),
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Drop produces two edits" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // source = children[0] (Var "x"), target = children[1] (Int 1)
  let source_node = proj.children[0]
  let target_node = proj.children[1]
  let result = compute_text_edit(
    Drop(source=source_node.id(), target=target_node.id(), position=After),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      // Drop should produce 2 edits: delete at source + insert at target
      inspect(edits.length(), content="2")
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #| + 1x
        ),
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Drop with unknown source returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    Drop(source=NodeId(9999), target=proj.id(), position=Before),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: WrapInLambda with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    WrapInLambda(node_id=NodeId(9999), var_name="x"),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: CommitEdit with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    CommitEdit(node_id=NodeId(9999), new_value="x"),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap Lam keeps body" {
  let text = "(λx. 42)"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let lam_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=lam_id, keep_child_index=0),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="42")
      // Should use MoveCursor, not RestoreCursor
      inspect(hint == FocusHint::RestoreCursor, content="false")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Unwrap Bop keeps left" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=0),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => inspect(apply_edits(text, edits), content="1")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Unwrap Bop keeps right" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=1),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => inspect(apply_edits(text, edits), content="2")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInIf wraps node in if-then-else" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInIf(node_id=root_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      inspect(apply_edits(text, edits), content="if 0 then 42 else 0")
      // MoveCursor should point to condition placeholder at offset 3
      inspect(hint, content="MoveCursor(position=3)")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInBop wraps node in binary operation" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInBop(node_id=root_id, op=@ast.Bop::Plus),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="(42 + 0)")
      // MoveCursor should point to placeholder "0" at offset 6
      inspect(hint, content="MoveCursor(position=6)")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ChangeOperator changes Bop operator" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    ChangeOperator(node_id=root_id, new_op=@ast.Bop::Minus),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      inspect(apply_edits(text, edits), content="(1 - 2)")
      inspect(hint, content="RestoreCursor")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: SwapChildren swaps Bop operands" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    SwapChildren(node_id=root_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      inspect(apply_edits(text, edits), content="(2 + 1)")
      inspect(hint, content="RestoreCursor")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DeleteBinding removes first let line" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Delete first binding
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DeleteBinding removes second let line" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Delete second binding
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DeleteBinding removes only binding" {
  let text = "let x = 42\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="x")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DeleteBinding with unknown id returns error" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=NodeId(9999)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: DuplicateBinding copies binding with _copy suffix" {
  let text = "let x = 42\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 42\nlet x_copy = 42\nlet y = 1\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DuplicateBinding on last binding" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet x_copy = 0\nx")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: MoveBindingDown swaps two bindings" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nlet x = 0\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: MoveBindingDown rejects when scoping violated" {
  // y uses x, so moving x down past y would break scoping
  let text = "let x = 0\nlet y = x\ny"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingDown rejects last binding" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingUp swaps two bindings" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nlet x = 0\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: AddBinding adds new let line" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let module_id = proj.id()
  let result = compute_text_edit(
    AddBinding(module_node_id=module_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet x = 0\nx")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ExtractToLet from body" {
  let text = "let x = 0\nx + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Body is Bop(+, Var(x), Int(1)). Extract the whole body expression.
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet y = (x + 1)\ny")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ExtractToLet sub-expression from body" {
  let text = "let x = 0\nx + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Extract Var("x") from the body (left operand of +)
  let body = proj.children[proj.children.length() - 1]
  let var_x = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=var_x.id(), var_name="z"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet z = x\nz + 1")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ExtractToLet rejects lambda-captured var" {
  // Inside λx. (x + 1), trying to extract the body which captures x
  let text = "λx. x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // The body of lambda is Bop(+, Var(x), Int(1)) — child[0] of Lam
  let body = proj.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: ExtractToLet bare expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    ExtractToLet(node_id=proj.id(), var_name="x"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 42\nx")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineDefinition sole usage removes binding" {
  let text = "let x = 42\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Body is the last child of Module — Var("x")
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="42")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineDefinition multiple usages keeps binding" {
  let text = "let x = 42\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Body is Bop(+, Var(x), Var(x)). Get the left Var.
  let body = proj.children[proj.children.length() - 1]
  let lhs = body.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=lhs.id()),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 42\n42 + x")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineAllUsages replaces all refs and removes binding" {
  // Note: right operand range in BinaryExpr may include leading whitespace
  // from the CST, so "x + x" -> "42 +42" — reparsing normalizes spacing.
  let text = "let x = 42\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // The right operand's source range includes leading space from CST,
      // resulting in minor whitespace irregularity; reparsing normalizes.
      inspect(new_text, content="42 +42")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineDefinition on non-Var returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    InlineDefinition(node_id=proj.id()),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages with unknown binding returns error" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=NodeId(9999)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineDefinition on lambda-bound var returns error" {
  let text = "λx. x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Body is Var("x") — child[0] of Lam
  let var_x = proj.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=var_x.id()),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages no usages just removes binding" {
  let text = "let x = 42\n0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="0")
    }
    _ => fail("expected Some edits")
  }
}
