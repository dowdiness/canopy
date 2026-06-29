// Whitebox tests for compute_text_edit

///|
/// Parse text and build ProjNode, SourceMap with token spans, registry, and definition index.
/// Uses the full syntax tree → ProjNode pipeline so token spans are populated.
fn parse_with_token_spans(
  text : String,
) -> (ProjNode[@ast.Term], SourceMap, Map[NodeId, ProjNode[@ast.Term]]) raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry = text_edit_test_registry(proj)
  (proj, sm, registry)
}

///|
/// Build a registry from a ProjNode tree.
fn text_edit_test_registry(
  root : ProjNode[@ast.Term],
) -> Map[NodeId, ProjNode[@ast.Term]] {
  let registry : Map[NodeId, ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  registry
}

///|
/// Apply span edits to text (in reverse document order) and return the result.
fn apply_edits(text : String, edits : Array[SpanEdit]) -> String {
  let sorted = edits.copy()
  sorted.sort_by((a, b) => b.start.compare(a.start))
  let mut result = text
  for edit in sorted {
    result = result[:edit.start].to_owned() +
      edit.inserted +
      result[edit.start + edit.delete_len:].to_owned()
  }
  result
}

///|
fn make_edit_ctx(
  text : String,
  source_map : SourceMap,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  root : ProjNode[@ast.Term],
) -> EditContext[@ast.Term] {
  {
    source_text: text,
    source_map,
    registry,
    definition_index: DefinitionIndex::from_proj_node(root),
  }
}

///|
test "compute_text_edit: CommitEdit replaces single expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    CommitEdit(node_id=root_id, new_value="99"),
    make_edit_ctx(text, source_map, registry, proj),
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
  // children[0] is the left operand (Var("x")), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=lhs.id(), new_value="y"),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: CommitEdit inside fn body preserves braces" {
  let text = "fn id(x : Int) { x }\nid 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let body = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=body.id(), new_value="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(apply_edits(text, edits), content="fn id(x : Int) {y }\nid 1")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: no-op ops return empty array" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    Select(node_id=NodeId::from_int(0)),
    make_edit_ctx(text, source_map, registry, proj),
  )
  @debug.debug_inspect(result, content="Ok(Some(([], RestoreCursor)))")
}

///|
test "compute_text_edit: Delete replaces node with placeholder" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    Delete(node_id=root_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  // children[0] is the left operand Var("x"), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    Delete(node_id=lhs.id()),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: Delete inside fn body preserves braces" {
  let text = "fn id(x : Int) { x }\nid 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let body = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    Delete(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(apply_edits(text, edits), content="fn id(x : Int) {a }\nid 1")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInLambda wraps node in lambda abstraction" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInLambda(node_id=root_id, var_name="x"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(apply_edits(text, edits), content="(x) => 42")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInLambda parenthesizes subexpression" {
  let text = "f 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let func = proj.children[0]
  let result = compute_text_edit(
    WrapInLambda(node_id=func.id(), var_name="x"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(apply_edits(text, edits), content="((x) => f) 1")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: WrapInApp wraps node in application" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInApp(node_id=root_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  // Insert a new Int def at index 1 (before the body)
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=1, kind=@ast.Term::Int(0)),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  // Insert a Var child into a Bop node — re-renders with print_term
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=0, kind=@ast.Term::Var("z")),
    make_edit_ctx(text, source_map, registry, proj),
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
  // source = children[0] (Var "x"), target = children[1] (Int 1)
  let source_node = proj.children[0]
  let target_node = proj.children[1]
  let result = compute_text_edit(
    Drop(source=source_node.id(), target=target_node.id(), position=After),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: Drop LetDef Inside moves the whole binding row after target" {
  let text = "let x = 1\nlet y = 2\nx"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let source = proj.children[0]
  let target = proj.children[1]
  let result = compute_text_edit(
    Drop(source=source.id(), target=target.id(), position=Inside),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let y = 2
          #|let x = 1
          #|x
        ),
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Drop LetDef Before moves the whole binding row before target" {
  let text = "let x = 1\nlet y = 2\nx"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let source = proj.children[1]
  let target = proj.children[0]
  let result = compute_text_edit(
    Drop(source=source.id(), target=target.id(), position=Before),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let y = 2
          #|let x = 1
          #|x
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
  let result = compute_text_edit(
    Drop(source=NodeId::from_int(9999), target=proj.id(), position=Before),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop synthetic multi-param lambda source is rejected" {
  let text = "(x, y) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let inner_lam = proj.children[0]
  let body = inner_lam.children[0]
  let result = compute_text_edit(
    Drop(source=inner_lam.id(), target=body.id(), position=After),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop synthetic multi-param lambda target is rejected" {
  let text = "(x, y) => x + z"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let inner_lam = proj.children[0]
  let body_bop = inner_lam.children[0]
  let source = body_bop.children[1]
  let result = compute_text_edit(
    Drop(source=source.id(), target=inner_lam.id(), position=Before),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: WrapInLambda with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    WrapInLambda(node_id=NodeId::from_int(9999), var_name="x"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: CommitEdit with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    CommitEdit(node_id=NodeId::from_int(9999), new_value="x"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap Lam keeps body" {
  let text = "(x) => 42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let lam_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=lam_id, keep_child_index=0),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: Unwrap synthetic fn lambda is rejected" {
  let text = "fn id(x : Int) { x }\nid 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let lam = proj.children[0].children[0]
  let result = compute_text_edit(
    Unwrap(node_id=lam.id(), keep_child_index=0),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap synthetic multi-param lambda is rejected" {
  let text = "(x, y) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let inner_lam = proj.children[0]
  let result = compute_text_edit(
    Unwrap(node_id=inner_lam.id(), keep_child_index=0),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap Bop keeps left" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=0),
    make_edit_ctx(text, source_map, registry, proj),
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
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=1),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInIf(node_id=root_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInBop(node_id=root_id, op=@ast.Bop::Plus),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  let result = compute_text_edit(
    ChangeOperator(node_id=root_id, new_op=@ast.Bop::Minus),
    make_edit_ctx(text, source_map, registry, proj),
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
  let root_id = proj.id()
  let result = compute_text_edit(
    SwapChildren(node_id=root_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  // Delete first binding
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  // Delete second binding
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: DeleteBinding removes second fn line" {
  let text = "fn id(x) { x }\nfn apply(f, x) { f x }\napply id 42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=proj.children[1].id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="fn id(x) { x }\napply id 42")
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
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=NodeId::from_int(9999)),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: DeleteBinding with init id returns error" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let init_id = proj.children[0].children[0].id()
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=init_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: DuplicateBinding copies binding with fresh numeric suffix" {
  let text = "let x = 42\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 42\nlet x1 = 42\nlet y = 1\nx + y")
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
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet x1 = 0\nx")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DuplicateBinding preserves typed fn syntax" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=proj.children[0].id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content="fn twice(f : Int -> Int, x : Int) { f x }\nfn twice1(f : Int -> Int, x : Int) { f x }\ntwice",
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: DuplicateBinding produces lexable name and reparses (root)" {
  let text = "let x = 42\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(root_def_names(new_text), content="x,x1,y")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DuplicateBinding skips existing numeric suffix (root)" {
  let text = "let x = 42\nlet x1 = 1\nx + x1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(root_def_names(new_text), content="x,x2,x1")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DuplicateBinding skips suffix that would capture later free reference (root)" {
  let text = "let x = 42\nlet y = x1\ny"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(root_def_names(new_text), content="x,x2,y")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingDown swaps two bindings" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingDown rejects last binding" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingUp swaps two bindings" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: MoveBindingUp swaps fn bindings" {
  let text = "fn id(x) { x }\nfn apply(f, x) { f x }\napply id 42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=proj.children[1].id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content="fn apply(f, x) { f x }\nfn id(x) { x }\napply id 42",
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
/// Reparse `text` and return the definition names, in order, of the binding
/// block held in root definition `def_index`'s initialiser. Used by the
/// block-local binding-op tests to assert SOUNDNESS structurally (the edited
/// text reparses to the intended block shape), not just by string match — a
/// botched swap can string-match an expectation while reparsing to a different
/// structure (see the #649/#650 reparse-gate lesson).
fn nested_block_def_names(def_index : Int, text : String) -> String raise {
  let (proj, _) = parse_to_proj_node(text)
  match proj.children[def_index].children[0].kind {
    @ast.Term::Module(defs, _) => defs.map(fn(d) { d.0 }).join(",")
    other =>
      fail(
        "expected root def initializer to reparse as block Module, got: " +
        @debug.to_string(other),
      )
  }
}

///|
/// Reparse `text` and return the root definition names, in order. Used with
/// nested_block_def_names for shadowing cases where both root and block scopes
/// must survive a block-local edit.
fn root_def_names(text : String) -> String raise {
  let (proj, _) = parse_to_proj_node(text)
  match proj.kind {
    @ast.Term::Module(defs, _) => defs.map(fn(d) { d.0 }).join(",")
    other =>
      fail(
        "expected edited text to reparse as root Module, got: " +
        @debug.to_string(other),
      )
  }
}

///|
/// Build an edit context and return the block in root definition `def_index`'s
/// initializer. Keeps block-local edit tests focused on the operation under test.
fn block_local_edit_ctx(
  text : String,
  def_index : Int,
) -> (EditContext[@ast.Term], ProjNode[@ast.Term]) raise {
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[def_index].children[0]
  (make_edit_ctx(text, source_map, registry, proj), block)
}

///|
/// Like `block_local_edit_ctx`, but preserves token spans for edit ops that
/// rewrite binding text.
fn block_local_edit_ctx_with_token_spans(
  text : String,
  def_index : Int,
) -> (EditContext[@ast.Term], ProjNode[@ast.Term]) raise {
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let block = proj.children[def_index].children[0]
  (make_edit_ctx(text, source_map, registry, proj), block)
}

///|
test "compute_text_edit: DeleteBinding removes block-local binding" {
  // `b` is block-local to `z`'s initialiser; root-relative lookup would reject
  // it. The block-aware op deletes it and the result reparses to a block with
  // only `a`.
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let binding_id = block.children[1].id()
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet z = { let a = 1\n  a }\nz")
      inspect(nested_block_def_names(1, new_text), content="a")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingDown swaps block-local bindings" {
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let x = 0
          #|let z = { let b = 2
          #|  let a = 1
          #|  a }
          #|z
        ),
      )
      inspect(nested_block_def_names(1, new_text), content="b,a")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingUp swaps block-local bindings" {
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let block = proj.children[1].children[0]
  let binding_id = block.children[1].id()
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let x = 0
          #|let z = { let b = 2
          #|  let a = 1
          #|  a }
          #|z
        ),
      )
      inspect(nested_block_def_names(1, new_text), content="b,a")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingUp rejects first block-local binding" {
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  // `a` is the first def in the block scope (scope-local def_index 0).
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: DuplicateBinding on block-local binding" {
  // Block-local duplicate is reachable, produces a lexable fresh name, and keeps
  // the inserted binding aligned with the enclosing block.
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content="let x = 0\nlet z = { let a = 1\n  let a1 = 1\n  let b = 2\n  a }\nz",
      )
      inspect(nested_block_def_names(1, new_text), content="a,a1,b")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DuplicateBinding on block-local binding produces lexable name and reparses with correct indentation" {
  let text = "let x = 0\nlet z = { let a = 1\n  let b = 2\n  a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(
        new_text,
        content="let x = 0\nlet z = { let a = 1\n  let a1 = 1\n  let b = 2\n  a }\nz",
      )
      inspect(nested_block_def_names(1, new_text), content="a,a1,b")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DuplicateBinding skips existing numeric suffix (block-local)" {
  let text = "let z = { let a = 1\n  let a1 = 2\n  a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[0].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(
        new_text,
        content="let z = { let a = 1\n  let a2 = 1\n  let a1 = 2\n  a }\nz",
      )
      inspect(nested_block_def_names(0, new_text), content="a,a2,a1")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DuplicateBinding skips suffix that would capture later free reference (block-local)" {
  let text = "let z = { let a = 1\n  let b = a1\n  b }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[0].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (_, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(
        new_text,
        content="let z = { let a = 1\n  let a2 = 1\n  let b = a1\n  b }\nz",
      )
      inspect(nested_block_def_names(0, new_text), content="a,a2,b")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingDown rejects block-local scoping violation" {
  let text = "let z = { let a = 1\n  let b = a\n  b }\nz"
  let (ctx, block) = block_local_edit_ctx(text, 0)
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=block.children[0].id()),
    ctx,
  )
  match result {
    Err(msg) => inspect(msg, content="Cannot move down: b uses a in its init")
    _ => fail("expected scoping error, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingUp rejects block-local scoping violation" {
  let text = "let z = { let a = 1\n  let b = a\n  b }\nz"
  let (ctx, block) = block_local_edit_ctx(text, 0)
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=block.children[1].id()),
    ctx,
  )
  match result {
    Err(msg) => inspect(msg, content="Cannot move up: b uses a in its init")
    _ => fail("expected scoping error, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DeleteBinding succeeds on referenced block-local binding" {
  // Characterizes current behavior: delete has no scoping guard, so it succeeds
  // even though the result leaves `b`'s initializer referencing missing `a`.
  // TODO: file a follow-up if DeleteBinding should reject live references the
  // way MoveBinding{Up,Down} reject scoping-violating swaps.
  let text = "let z = { let a = 1\n  let b = a\n  b }\nz"
  let (ctx, block) = block_local_edit_ctx(text, 0)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=block.children[0].id()),
    ctx,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let z = {  let b = a\n  b }\nz")
      inspect(nested_block_def_names(0, new_text), content="b")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: DeleteBinding preserves root binding when deleting block-local shadow" {
  let text = "let x = 0\nlet z = { let x = 2\n  x }\nz"
  let (ctx, block) = block_local_edit_ctx(text, 1)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=block.children[0].id()),
    ctx,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet z = {  x }\nz")
      inspect(root_def_names(new_text), content="x,z")
      inspect(nested_block_def_names(1, new_text), content="")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingUp swaps block-local binding that shadows root name" {
  let text = "let x = 0\nlet z = { let a = 1\n  let x = 2\n  a }\nz"
  let (ctx, block) = block_local_edit_ctx_with_token_spans(text, 1)
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=block.children[1].id()),
    ctx,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let x = 0
          #|let z = { let x = 2
          #|  let a = 1
          #|  a }
          #|z
        ),
      )
      inspect(root_def_names(new_text), content="x,z")
      inspect(nested_block_def_names(1, new_text), content="x,a")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
/// ExtractToLet is block-aware for block BODY expressions: inserting `let y =
/// expr` immediately before the body leaves block-local bindings in scope, so
/// the extraction succeeds even when the body references block-local names.
/// Verified by reparsing: root keeps exactly 1 def, block gains `y` as a new
/// def after `a`, and block body becomes `y`.
test "compute_text_edit: ExtractToLet handles block body with block-local free var" {
  let text = "let z = { let a = 1\n  a + 1 }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[0].children[0]
  let body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed")
      }
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          let inner_block = result_proj.children[0].children[0]
          match inner_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="2")
              inspect(block_defs[0].0, content="a")
              inspect(block_defs[1].0, content="y")
            }
            _ => fail("expected inner block to be Module")
          }
        }
        _ => fail("expected root to be Module")
      }
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// If var_name is already bound in the block body (outside the extracted
/// expression), inserting `let var_name = expr` would silently retarget those
/// uses to the new binding, changing semantics. The block-body path must refuse.
/// Example: `(a + 1) + a` extracting `(a + 1)` as `a` would produce
/// `let a = (a + 1)\na + a` where the suffix `a` now refers to the new binding
/// instead of the original `let a = 1`.
test "compute_text_edit: ExtractToLet refuses block-body extraction when var_name would capture suffix" {
  let text = "let z = { let a = 1\n  (a + 1) + a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Extract `(a + 1)` from the body: block→body→Add(Add(Var(a),Int(1)), Var(a))
  let block = proj.children[0].children[0]
  let body = block.children[block.children.length() - 1]
  // body is Add(Add(Var(a),Int(1)), Var(a)); first child is (a + 1)
  let extracted = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=extracted.id(), var_name="a"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Free (unresolved) Var(var_name) in the suffix is also a capture: the new
/// `let var_name = expr` would bind it, changing the program from unbound/stuck
/// to a resolved value. The check must fire for free uses too, not just
/// already-resolved ones.
/// Example: `(a + 1) + y` — `y` is free. Extracting `(a + 1)` as `y` would
/// produce `let y = a + 1\ny + y` where `y` is now bound.
test "compute_text_edit: ExtractToLet refuses block-body extraction when var_name would bind free suffix ref" {
  let text = "let z = { let a = 1\n  (a + 1) + y }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[0].children[0]
  let body = block.children[block.children.length() - 1]
  let extracted = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=extracted.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Free (unresolved) Var(var_name) anywhere in the block is also a capture:
/// inserting `let var_name = expr` before all defs would bind it.
/// Example: `y` is free in `{ let a = 1\n  y + a }`. Extracting `1` as `y`
/// would produce `{ let y = 1\n  let a = 1\n  y + a }` where the previously
/// unbound `y` now resolves.
test "compute_text_edit: ExtractToLet refuses block-def extraction when var_name would bind free block ref" {
  let text = "let z = { let a = 1\n  y + a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[0].children[0]
  let lit_1 = block.children[0].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=lit_1.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Inserting `let var_name = expr` before all block defs makes var_name
/// visible throughout the block. Any existing Var(var_name) in the block
/// (in later def initializers or the body) that currently resolves to an
/// outer binding is silently retargeted, changing semantics. The block-def
/// path must refuse.
/// Example: outer `y`, block `{ let a = 1\n  y + a }`, extracting `1` as
/// `y` would insert `let y = 1` before `let a`, making body `y + a` resolve
/// `y` to 1 instead of the outer binding.
test "compute_text_edit: ExtractToLet refuses block-def extraction when var_name would capture block ref" {
  let text = "let y = 5\nlet z = { let a = 1\n  y + a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // z is proj.children[1] (second root def); block is z's init
  let z_def = proj.children[1]
  let block = z_def.children[0]
  // Extract Int(1) from `let a = 1`: block→LetDef("a")→Int(1)
  let lit_1 = block.children[0].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=lit_1.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Extracting from a block DEF when the expression uses a block-local binding
/// defined earlier in the same block is correctly refused. Inserting `let y =
/// expr` before all block defs would put `expr` before `a`'s binding, leaving
/// `a` unbound. The root-relative capture guard catches this case.
test "compute_text_edit: ExtractToLet refuses block-def extraction with block-local free var" {
  let text = "let z = { let a = 1\n  let b = a + 1\n  b }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Extract `a + 1` (the init of `let b`): block→LetDef("b")→Add(Var("a"), Int(1))
  let block = proj.children[0].children[0]
  let b_init = block.children[1].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=b_init.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Lambda param referenced in a block-def init: the param is declared OUTSIDE
/// the block (in the enclosing lambda), so it stays in scope at the insertion
/// point. This exercises the scope_is_within check on the block-def path.
///
/// Parser wraps the top-level lambda as an unnamed binding, so proj.kind is
/// Module([("", Lam("x",…))], Unit). Navigation must go through that wrapper.
test "compute_text_edit: ExtractToLet allows block-def extraction when lambda param is from outside the block" {
  let text = "fn(x) { let y = x\ny }"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // proj = Module([("", Lam("x", …))], Unit)
  // proj.children[0] = LetDef("", Lam("x", …))
  // proj.children[0].children[0] = Lam("x", inner_block)
  // proj.children[0].children[0].children[0] = inner_block = Module([("y",…)],…)
  // inner_block.children[0] = LetDef("y", Var("x"))
  // inner_block.children[0].children[0] = Var("x")  ← target
  let lam = proj.children[0].children[0]
  let inner_block = lam.children[0]
  let let_y = inner_block.children[0]
  let x_var = let_y.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=x_var.id(), var_name="v"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      // Root still has 1 def (the unnamed lambda binding); lambda body block
      // gains the new "v" binding as its first def.
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          let lam_block = result_proj.children[0].children[0].children[0]
          match lam_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="2")
              inspect(block_defs[0].0, content="v")
              inspect(block_defs[1].0, content="y")
            }
            _ =>
              fail(
                "expected lambda body block to be Module, got " +
                @debug.to_string(lam_block.kind),
              )
          }
        }
        _ => fail("expected root Module")
      }
    }
    other => fail("expected Ok(Some(_)), got: " + @debug.to_string(other))
  }
}

///|
/// Extracting a block-internal expression with no block-local free var inserts
/// the let inside the enclosing block (not hoisted to root). Verified by
/// reparsing: root keeps exactly 1 def, and the block gains the new binding
/// as its first def.
test "compute_text_edit: ExtractToLet inserts inside block for block-internal def" {
  let text = "let z = { let a = 1\n  a + 1 }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Int(1) is: proj→LetDef("z")→block→LetDef("a")→Int(1)
  let block = proj.children[0].children[0]
  let lit_1 = block.children[0].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=lit_1.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed")
      }
      // The let binding must be inside the block, so root still has exactly 1 def.
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          // Block is z's init — it should now have 2 defs: y then a.
          let inner_block = result_proj.children[0].children[0]
          match inner_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="2")
              inspect(block_defs[0].0, content="y")
              inspect(block_defs[1].0, content="a")
            }
            _ => fail("expected inner block to be Module")
          }
        }
        _ => fail("expected root to be Module")
      }
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// Non-first block def: extracting a block-internal expression that is not in
/// the first binding still inserts let y before all block defs (at block start).
test "compute_text_edit: ExtractToLet inserts before all block defs for non-first def" {
  let text = "let z = { let a = 1\n  let b = 2\n  a + b }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Extract Int(2) from `let b = 2`: proj→LetDef("z")→block→LetDef("b")→Int(2)
  let block = proj.children[0].children[0]
  let lit_2 = block.children[1].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=lit_2.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed")
      }
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          let inner_block = result_proj.children[0].children[0]
          match inner_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="3")
              inspect(block_defs[0].0, content="y")
              inspect(block_defs[1].0, content="a")
              inspect(block_defs[2].0, content="b")
            }
            _ => fail("expected inner block to be Module")
          }
        }
        _ => fail("expected root to be Module")
      }
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// Extracting from a lambda body nested inside a block-with-defs must use
/// block-body insertion, not root insertion. Previously `scope_has_module_defs`
/// returned false for the lambda scope so the node fell through to root.
/// The ancestor-scope walk finds the enclosing block Module even when the
/// selected node is in a lambda scope under the block scope.
/// Verified by reparsing: root keeps 1 def, block gains a new def `y`.
test "compute_text_edit: ExtractToLet finds block via ancestor scope for lambda-in-block" {
  let text = "let z = { let a = 1\n(x) => a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // proj→LetDef("z")→block→[LetDef("a"), Lam("x", Var("a"))]; extract Var("a")
  let block = proj.children[0].children[0]
  let var_a = block.children[1].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=var_a.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed")
      }
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          let inner_block = result_proj.children[0].children[0]
          match inner_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="2")
              inspect(block_defs[0].0, content="a")
              inspect(block_defs[1].0, content="y")
            }
            _ => fail("expected inner block to be Module")
          }
        }
        _ => fail("expected root to be Module")
      }
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// Extracting a lambda-body expression that captures the lambda param must be
/// refused even when the lambda is nested inside a block (block-body path).
/// The let would be inserted before the lambda, outside the param's scope,
/// making the param references unbound.
test "compute_text_edit: ExtractToLet refuses lambda-param rebind in lambda-in-block" {
  let text = "let z = { let a = 1\n(x) => x + a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // proj→LetDef("z")→block→[LetDef("a"), Lam("x", Add(Var("x"), Var("a")))]; extract body
  let block = proj.children[0].children[0]
  let lam_body = block.children[1].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=lam_body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// The primary bug-report case: extracting `1` from `let z = { 1 + 2 }` was
/// inserting at root scope instead of inside the block. Empty-def blocks used
/// to collapse in projection to their body node (no Module in the registry),
/// so `find_enclosing_block` returned None. Now empty-def blocks always emit
/// a Module ProjNode, giving the scope graph a block scope to detect.
/// Verified by reparsing: root still has 1 def (z), block gains def `y`.
test "compute_text_edit: ExtractToLet inserts inside empty-def block body" {
  let text = "let z = { 1 + 2 }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // After Option B: proj→LetDef("z")→Module([], Add)→[Add→[Int(1), Int(2)]]
  let block = proj.children[0].children[0]
  let int_1 = block.children[0].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=int_1.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      match result_proj.kind {
        @ast.Term::Module(root_defs, _) => {
          inspect(root_defs.length(), content="1")
          let inner_block = result_proj.children[0].children[0]
          match inner_block.kind {
            @ast.Term::Module(block_defs, _) => {
              inspect(block_defs.length(), content="1")
              inspect(block_defs[0].0, content="y")
            }
            _ =>
              fail(
                "expected inner block to be Module, got: " +
                @debug.to_string(inner_block.kind),
              )
          }
        }
        _ => fail("expected root to be Module")
      }
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// Build a fresh scope graph for a reparsed projection.
fn scope_graph_for_proj(proj : ProjNode[@ast.Term]) -> @scope.ScopeGraph {
  let registry = text_edit_test_registry(proj)
  let source_map = SourceMap::from_ast(proj)
  @scope.build(registry, source_map)
}

///|
/// Assert that `var_node` resolves to `expected_decl_node` in `g`.
fn expect_var_resolves_to(
  g : @scope.ScopeGraph,
  var_node : ProjNode[@ast.Term],
  expected_name : String,
  expected_decl_node : ProjNode[@ast.Term],
  unresolved_message : String,
) -> Unit raise {
  match @scope.declaration(g, var_node.id()) {
    Some(decl) => {
      inspect(decl.name, content=expected_name)
      inspect(decl.node_id == expected_decl_node.id(), content="true")
    }
    None => fail(unresolved_message)
  }
}

///|
test "compute_text_edit: ExtractToLet block-body preserves resolution when block-local def shadows outer var [#659]" {
  let text = "let a = 0\nlet z = { let a = 1\n  a + 1 }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(root_def_names(new_text), content="a,z")
      inspect(nested_block_def_names(1, new_text), content="a,y")
      let g = scope_graph_for_proj(result_proj)
      let result_block = result_proj.children[1].children[0]
      let y_init = result_block.children[1].children[0]
      expect_var_resolves_to(
        g,
        y_init.children[0],
        "a",
        result_block.children[0],
        "`a` in y's init is unresolved (expected block-local resolution)",
      )
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: ExtractToLet block-body sub-expr preserves block-local free var resolution [#659]" {
  let text = "let a = 0\nlet z = { let a = 1\n  (a + 2) + a }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let body = block.children[block.children.length() - 1]
  let extracted = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=extracted.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      let g = scope_graph_for_proj(result_proj)
      let result_block = result_proj.children[1].children[0]
      let y_init = result_block.children[1].children[0]
      expect_var_resolves_to(
        g,
        y_init.children[0],
        "a",
        result_block.children[0],
        "`a` in y's init is unresolved",
      )
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: ExtractToLet block-body preserves mixed inner/outer free var resolution [#659]" {
  let text = "let x = 10\nlet z = { let a = 1\n  a + x }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (result_proj, _) = parse_to_proj_node(new_text) catch {
        _ => fail("reparse failed: " + new_text)
      }
      inspect(root_def_names(new_text), content="x,z")
      inspect(nested_block_def_names(1, new_text), content="a,y")
      let g = scope_graph_for_proj(result_proj)
      let result_block = result_proj.children[1].children[0]
      let y_init = result_block.children[1].children[0]
      expect_var_resolves_to(
        g,
        y_init.children[0],
        "a",
        result_block.children[0],
        "`a` in y's init is unresolved",
      )
      expect_var_resolves_to(
        g,
        y_init.children[1],
        "x",
        result_proj.children[0],
        "`x` in y's init is unresolved",
      )
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: AddBinding adds new let line" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let module_id = proj.id()
  let result = compute_text_edit(
    AddBinding(module_node_id=module_id),
    make_edit_ctx(text, source_map, registry, proj),
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
  // Body is Bop(+, Var(x), Int(1)). Extract the whole body expression.
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
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
  // Extract Var("x") from the body (left operand of +)
  let body = proj.children[proj.children.length() - 1]
  let var_x = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=var_x.id(), var_name="z"),
    make_edit_ctx(text, source_map, registry, proj),
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
  // Inside (x) => (x + 1), trying to extract the body which captures x
  let text = "(x) => x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // The body of lambda is Bop(+, Var(x), Int(1)) — child[0] of Lam
  let body = proj.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: ExtractToLet rejects module-def enclosing env capture" {
  let text = "let x = y\nlet y = 1\n0"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let init_y = proj.children[0].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=init_y.id(), var_name="z"),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot extract: expression captures lambda-bound variables\")",
  )
}

///|
test "compute_text_edit: ExtractToLet rejects later module-def shadow capture" {
  let text = "let y = 1\nlet x = y\nlet y = 2\n0"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let init_y = proj.children[1].children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=init_y.id(), var_name="z"),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot extract: expression captures lambda-bound variables\")",
  )
}

///|
test "compute_text_edit: ExtractToLet bare expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    ExtractToLet(node_id=proj.id(), var_name="x"),
    make_edit_ctx(text, source_map, registry, proj),
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
/// Regression test for #651: `free_names_captured_at_use_sites` was Module-blind —
/// it found the inner `g` inside `{ let g = 1; g }` and falsely flagged it as
/// capturing the outer free `g`, causing a spurious rejection.
test "compute_text_edit: ExtractToLet defs-empty does not reject block-shadowed free name [#651]" {
  // `g` is free on the left side; the block on the right locally shadows it.
  // The inner `g`'s binder is inside the extraction subtree, so it is not a
  // real capture of the outer `g` and must not trigger a rejection.
  let text = "g + { let g = 1\n  g }"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    ExtractToLet(node_id=proj.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = (g + { let g = 1\ng })\ny")
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition sole usage removes binding" {
  let text = "let x = 42\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Body is the last child of Module — Var("x")
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: InlineDefinition nested block uses resolved declaration" {
  let text = "let x = 0\nlet z = { let x = 1\n  x }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let inner_body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=inner_body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet z = {1 }\nz")
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
  // Body is Bop(+, Var(x), Var(x)). Get the left Var.
  let body = proj.children[proj.children.length() - 1]
  let lhs = body.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=lhs.id()),
    make_edit_ctx(text, source_map, registry, proj),
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
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
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
test "compute_text_edit: InlineAllUsages nested block uses binding declaration" {
  let text = "let x = 0\nlet z = { let x = 1\n  x }\nz"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet z = {1 }\nz")
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
  let result = compute_text_edit(
    InlineDefinition(node_id=proj.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages with unknown binding returns error" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=NodeId::from_int(9999)),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages preserves typed fn binding" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice id 1"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=proj.children[0].id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="((f : Int -> Int, x : Int) => { f x }) id 1")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition preserves typed fn binding" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="((f : Int -> Int, x : Int) => { f x })")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition preserves indented typed fn binding" {
  let text = "  fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="((f : Int -> Int, x : Int) => { f x })")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition zero-param fn uses block body" {
  let text = "fn answer() { 42 }\nanswer"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="{ 42 }")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition zero-param fn with lambda body uses block body" {
  let text = "fn make() { (x) => x }\nmake"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="{ (x) => x }")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition typed fn rejects missing keyword span" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Err(msg) =>
      inspect(msg, content="Cannot rewrite fn binding: keyword range not found")
    _ => fail("expected structured metadata rejection")
  }
}

///|
test "compute_text_edit: InlineDefinition typed fn rejects missing parameter span" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  source_map.set_token_span(
    proj.children[0].id(),
    @lambda_proj.FN_BINDING_KEYWORD_ROLE,
    @loomcore.Range::new(0, 2),
  )
  let registry = text_edit_test_registry(proj)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Err(msg) =>
      inspect(
        msg,
        content="Cannot rewrite fn binding: parameter list range not found",
      )
    _ => fail("expected structured metadata rejection")
  }
}

///|
test "compute_text_edit: InlineAllUsages first duplicate preserves shadowed body" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=proj.children[0].id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // The init Var range includes its leading space, matching existing inline
      // whitespace behavior; the assertion pins the resolved-reference set.
      inspect(new_text, content="let x =0\nx")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition on lambda-bound var returns error" {
  let text = "(x) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // Body is Var("x") — child[0] of Lam
  let var_x = proj.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=var_x.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages no usages just removes binding" {
  let text = "let x = 42\n0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="0")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineAllUsages removes unused second fn binding" {
  let text = "fn id(x) { x }\nfn unused(x) { x }\nid 42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=proj.children[1].id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="fn id(x) { x }\nid 42")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename lambda param" {
  let text = "(x) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  // proj is Lam("x", Var("x"))
  let lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="(y) => y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename var resolves to lambda binder" {
  let text = "(x) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  // body Var("x") is child[0] of Lam
  let var_x = proj.children[0]
  let result = compute_text_edit(
    Rename(node_id=var_x.id(), new_name="z"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="(z) => z")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename module binding" {
  let text = "let x = 42\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  // Use the binding LetDef node id from the generic ProjNode tree.
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 42\ny")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename module binding to same name remains valid" {
  let text = "let x = 42\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="x"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content=text)
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: Rename module binding via Var" {
  let text = "let x = 42\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  // body is Var("x") — last child of Module
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    Rename(node_id=body.id(), new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 42\ny")
    }
    _ => fail("expected Some edits")
  }
}

///|
/// Block-local rename soundness (docs/TODO.md §20 exit criterion).
/// Root `x` (def_index 0) and the block-local `x` (also def_index 0) collide on
/// index, so a root-relative resolver renames the WRONG binding. The only
/// `Var("x")` in the whole tree is the block body usage, so we locate it by
/// scanning the registry — renaming it must touch ONLY the block binder + body,
/// leaving the unrelated root `let x = 1` intact.
test "compute_text_edit: Rename block-local binding leaves root binding intact" {
  let text =
    #|let x = 1
    #|let y = { let x = 2
    #|  x }
    #|y
  let (proj, sm, registry) = parse_with_token_spans(text)
  // The block body `x` is the unique Var("x") in the program.
  guard registry.values().find_first(fn(n) { n.kind is @ast.Term::Var("x") })
    is Some(inner_x) else {
    fail("could not locate block-local Var(\"x\")")
  }
  let inner_x_id = inner_x.id()
  let result = compute_text_edit(
    Rename(node_id=inner_x_id, new_name="w"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #|let x = 1
          #|let y = { let w = 2
          #|  w }
          #|y
        ),
      )
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
/// Capturing an EXISTING use of the target name must be rejected. The block body
/// `y` resolves to the root `y`; renaming the nested `x` binder to `y` would
/// silently re-bind that `y` to the new local — so the rename must fail rather
/// than change the meaning of an existing reference.
test "compute_text_edit: Rename block binder rejects capture of existing target use" {
  let text =
    #|let y = 1
    #|let z = { let x = 2
    #|  y }
    #|z
  let (proj, sm, registry) = parse_with_token_spans(text)
  // proj.children[1] = LetDef z; its init[0] is the block Module; that block's
  // child[0] is the nested LetDef x binder.
  let nested_x = proj.children[1].children[0].children[0]
  let result = compute_text_edit(
    Rename(node_id=nested_x.id(), new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Block-local rename via the BINDER-CLICK path (`rename_binding_by_id`). The
/// nested `LetDef` node is resolved to its own block declaration by structural
/// node id, so it renames the block-local `x`, not the root def at index 0.
test "compute_text_edit: Rename block-local binding by binder id" {
  let text =
    #|let x = 1
    #|let y = { let x = 2
    #|  x }
    #|y
  let (proj, sm, registry) = parse_with_token_spans(text)
  // proj.children[1] = LetDef y; its init child[0] is the block Module;
  // that block's child[0] is the nested LetDef x.
  let nested_let_def = proj.children[1].children[0].children[0]
  let result = compute_text_edit(
    Rename(node_id=nested_let_def.id(), new_name="w"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(
        apply_edits(text, edits),
        content=(
          #|let x = 1
          #|let y = { let w = 2
          #|  w }
          #|y
        ),
      )
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
/// A reference inside a block that resolves to an OUTER (root) binding must
/// still rename the root binding — confirms the decl-threading change keeps
/// block→outer resolution sound, not just block-local.
test "compute_text_edit: Rename block reference to outer binding renames root" {
  let text =
    #|let x = 1
    #|let y = { let z = 2
    #|  x }
    #|y
  let (proj, sm, registry) = parse_with_token_spans(text)
  // The block body `x` (unique Var("x")) resolves to the root `x`.
  guard registry.values().find_first(fn(n) { n.kind is @ast.Term::Var("x") })
    is Some(inner_x) else {
    fail("could not locate Var(\"x\")")
  }
  let inner_x_id = inner_x.id()
  let result = compute_text_edit(
    Rename(node_id=inner_x_id, new_name="w"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(
        apply_edits(text, edits),
        content=(
          #|let w = 1
          #|let y = { let z = 2
          #|  w }
          #|y
        ),
      )
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: Rename first duplicate module binding preserves shadowed body" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    Rename(node_id=proj.children[0].id(), new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // The init Var range includes its leading space; the body x must remain
      // shadowed by the second def and therefore unchanged.
      inspect(new_text, content="let y = 0\nlet x = y\nx")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: Rename module binding with multiple usages" {
  let text = "let x = 42\nx + x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 42\ny + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename nested lambda" {
  let text = "(x, y) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  // Rename outer lambda param "x" to "z"
  let outer_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=outer_id, new_name="z"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="(z, y) => z")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename typed fn second param ignores type identifiers" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let inner_lam = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    Rename(node_id=inner_lam.id(), new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content="fn twice(f : Int -> Int, y : Int) { f y }\ntwice",
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename with unknown node returns error" {
  let text = "42"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  let result = compute_text_edit(
    Rename(node_id=NodeId::from_int(9999), new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects capture of free variable" {
  // (x) => y  — renaming x to y would capture the free y
  let text = "(x) => y"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects capture by inner lambda binder" {
  // (x, y) => x — renaming outer x to y would rebind the use to inner y.
  let text = "(x, y) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let outer_lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=outer_lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects duplicate module binding name" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  // Rename binding x → y should fail because y already exists
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename module binding rejects inner lambda capture" {
  // let x = 0\n(y) => x — renaming x→y would capture at the inner (y) =>
  let text = "let x = 0\n(y) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineDefinition rejects capture" {
  // let y = 1\nlet x = y\n(y) => x — inlining x would produce (y) => y (capture)
  let text = "let y = 1\nlet x = y\n(y) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = sm
  // Body is (y) => x — the Lam node
  let body = proj.children[proj.children.length() - 1]
  // body is Lam("y", Var("x")), child[0] is Var("x")
  let var_x = body.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=var_x.id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineDefinition allows same module-def reference" {
  let text = "let y = 1\nlet x = y\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\ny")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineDefinition rejects later module-def shadow capture" {
  let text = "let y = 1\nlet x = y\nlet y = 2\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: InlineDefinition rejects nested block shadow capture" {
  let text = "let y = 0\nlet z = { let x = y\nlet y = 1\nx }\nz"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  let block = proj.children[1].children[0]
  let block_body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=block_body.id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: InlineAllUsages rejects capture" {
  let text = "let y = 1\nlet x = y\n(y) => x"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  let _ = sm
  // Binding "x" is at def index 1
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, sm, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages rejects nested block shadow capture" {
  let text = "let y = 0\nlet z = { let x = y\nlet y = 1\nx }\nz"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let _ = proj
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id()
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: InlineAllUsages allows same module-def reference" {
  let text = "let y = 1\nlet x = y\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=proj.children[1].id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\ny")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: InlineAllUsages rejects later module-def shadow capture" {
  let text = "let y = 1\nlet x = y\nlet y = 2\nx"
  let (proj, sm, registry) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=proj.children[1].id()),
    make_edit_ctx(text, sm, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: middleware rejects missing node for structural ops" {
  let text = "42"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let fake_id = NodeId::from_int(99999)
  let result = compute_text_edit(
    Delete(node_id=fake_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  @debug.debug_inspect(result, content="Err(\"Node not found: NodeId(99999)\")")
}

///|
test "compute_text_edit: MoveBindingUp allows valid swap where prev uses cur" {
  // prev (x) uses cur's name (y) — after swap, y comes first so ref is valid
  let text = "let x = y\nlet y = 0\nx"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 0\nlet x = y\nx")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingDown allows valid swap where cur uses next" {
  // cur (x) uses next's name (y) — after swap, y comes first so ref is valid
  let text = "let x = y\nlet y = 0\nx"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 0\nlet x = y\nx")
    }
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingUp rejects when swap would re-target prev's init via shadow" {
  // let x=1; let c=x; let x=2 — c's init refs "x" (resolves to x=1).
  // Moving x=2 up past c would make c see x=2 instead; semantics change.
  let text = "let x = 1\nlet c = x\nlet x = 2\nc"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  // defs[2] is `let x = 2`
  let binding_id = proj.children[2].id()
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingDown rejects when swap would re-target cur's init via shadow" {
  // let b=0; let cur=b; let b=1 — cur's init refs "b", currently resolves
  // to b=0 (earlier def). Moving cur down past b=1 would shadow b=0 with b=1.
  let text = "let b = 0\nlet cur = b\nlet b = 1\ncur"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  // defs[1] is `let cur = b`
  let binding_id = proj.children[1].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingUp rejects when block-local init resolves name from outer scope" {
  // `let c = x` inside the block currently sees the outer `x = 0`.
  // Moving the block-local `let x = 2` above `let c = x` would retarget c's
  // `x` from the outer def to the inner one — no earlier SAME-scope sibling
  // named "x" exists, but the outer resolution is enough to block.
  let text = "let x = 0\nlet z = { let c = x; let x = 2; c }\nz"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let block = proj.children[1].children[0]
  let binding_id = block.children[1].id() // `let x = 2`
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingDown rejects when block-local init resolves name from outer scope" {
  // `let c = y` inside the block currently sees the outer `y = 0`.
  // Moving `let c = y` below `let y = 2` would retarget c's `y` from the
  // outer def to the inner one — same outer-scope retargeting case as above.
  let text = "let y = 0\nlet z = { let c = y; let y = 2; c }\nz"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let block = proj.children[1].children[0]
  let binding_id = block.children[0].id() // `let c = y`
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingUp allows free→bound improvement when no earlier sibling shadows" {
  // prev's init references cur's name, but no earlier sibling with that name
  // exists — the reference was free before the swap and becomes bound after.
  // init_ref_resolves returns false (ref is free) → ALLOW (not an unconditional block).
  let text = "let a = x\nlet x = 0\na"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[1].id() // `let x = 0`
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(apply_edits(text, edits), content="let x = 0\nlet a = x\na")
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: MoveBindingDown allows free→bound improvement when no earlier sibling shadows" {
  // cur's init references next's name, but no earlier sibling with that name
  // exists — the reference was free before the swap and becomes bound after.
  // init_ref_resolves returns false (ref is free) → ALLOW (not an unconditional block).
  let text = "let a = b\nlet b = 0\na"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[0].id() // `let a = b`
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) =>
      inspect(apply_edits(text, edits), content="let b = 0\nlet a = b\na")
    _ => fail("expected Some edits, got: " + @debug.to_string(result))
  }
}

///|
test "compute_text_edit: Unwrap cursor at replacement start" {
  // Unwrap Bop keeps right child — cursor should be at range.start (0),
  // not the original position of the right child
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=1),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((_, hint))) =>
      match hint {
        MoveCursor(position~) =>
          // Cursor at start of replacement text, not right child's original pos
          inspect(position, content="0")
        _ => fail("expected MoveCursor, got: " + hint.to_string())
      }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InsertChild rejects negative index" {
  let text = "let x = 0\nx"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let module_id = proj.children.last().unwrap().id()
  let result = compute_text_edit(
    InsertChild(parent=module_id, index=-1, kind=@ast.Term::Int(0)),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: AddBinding rejects non-Module target" {
  let text = "42"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let root_id = NodeId::from_int(0)
  // root is an Int, not a Module
  let result = compute_text_edit(
    AddBinding(module_node_id=root_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop self-drop returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let id = proj.id()
  let result = compute_text_edit(
    Drop(source=id, target=id, position=After),
    make_edit_ctx(text, source_map, registry, proj),
  )
  @debug.debug_inspect(result, content="Err(\"Cannot drop onto self\")")
}

///|
test "compute_text_edit: Drop descendant-drop returns error" {
  // "x + 1" parses as Bop(Var(x), Int(1))
  // Dropping the root Bop onto its child Var(x) is a descendant-drop
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let child = proj.children[0] // Var(x), inside the Bop
  let result = compute_text_edit(
    Drop(source=proj.id(), target=child.id(), position=After),
    make_edit_ctx(text, source_map, registry, proj),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot drop into own descendant\")",
  )
}

///|
test "compute_text_edit: Drop with Before position inserts at target start" {
  let text = "x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  // source = Int(1) at children[1], target = Var(x) at children[0]
  let source_node = proj.children[1]
  let target_node = proj.children[0]
  let result = compute_text_edit(
    Drop(source=source_node.id(), target=target_node.id(), position=Before),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="2")
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content=(
          #| 1x +
        ),
      )
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Drop with unknown target returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let result = compute_text_edit(
    Drop(source=proj.id(), target=NodeId::from_int(9999), position=After),
    make_edit_ctx(text, source_map, registry, proj),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Regression test for #651: `init_ref_resolves` was Module-blind — when `h`'s
/// init contained `{ let f = 1; f }`, it found the inner `f` (which resolves to
/// the inner binding) and falsely concluded the outer `f` was referenced in the
/// init, blocking a legal MoveBindingDown.
test "compute_text_edit: MoveBindingDown does not reject block-shadowed name in init [#651-init-ref]" {
  // `f` is NOT referenced in `h`'s init — the `f` inside the block is locally
  // bound there. Moving `f` past `h` must succeed.
  let text = "let f = 0\nlet h = { let f = 1\n  f }\nf"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let binding_id = proj.children[0].id()
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let h = { let f = 1\n  f }\nlet f = 0\nf")
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}

///|
/// Regression test for #651: `free_name_would_rebind_to` was Module-blind — when
/// `h`'s init was `f + { let f = 1; f }`, the inner block-bound `f` was falsely
/// treated as a free use of the outer `f` and produced a spurious rebind error,
/// blocking a legal InlineDefinition.
test "compute_text_edit: InlineDefinition does not reject block-shadowed free name in init [#651-rebind]" {
  // `h`'s init contains the outer free `f` AND a nested block that locally
  // re-shadows `f`. The inner `f`'s binder is inside the init subtree — it is
  // NOT a free reference to the outer `f` and must not trigger a rebind error.
  let text = "let f = 0\nlet h = f + { let f = 1\n  f }\nh"
  let (proj, source_map, registry) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, proj),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let f = 0\nf + { let f = 1\n  f }")
    }
    _ => fail("expected Ok(Some(edits)), got: " + @debug.to_string(result))
  }
}
