// Whitebox tests for compute_text_edit

///|
/// Parse text and build ProjNode, SourceMap with token spans, registry, and ModuleProjection.
/// Uses the full syntax tree → ProjNode pipeline so token spans are populated.
fn parse_with_token_spans(
  text : String,
) -> (
  ProjNode[@ast.Term],
  SourceMap,
  Map[NodeId, ProjNode[@ast.Term]],
  ModuleProjection,
) raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  (proj, sm, registry, fp)
}

///|
/// Build a registry from a ProjNode tree.
fn text_edit_test_registry(
  root : ProjNode[@ast.Term],
) -> Map[NodeId, ProjNode[@ast.Term]] {
  let registry : Map[NodeId, ProjNode[@ast.Term]] = {}
  fn register(node : ProjNode[@ast.Term]) {
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
  fp : ModuleProjection,
) -> EditContext[@ast.Term] {
  { source_text: text, source_map, registry, module_projection: fp }
}

///|
test "compute_text_edit: CommitEdit replaces single expression" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    CommitEdit(node_id=root_id, new_value="99"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // children[0] is the left operand (Var("x")), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=lhs.id(), new_value="y"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let body = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    CommitEdit(node_id=body.id(), new_value="y"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    Select(node_id=NodeId::from_int(0)),
    make_edit_ctx(text, source_map, registry, fp),
  )
  @debug.debug_inspect(result, content="Ok(Some(([], RestoreCursor)))")
}

///|
test "compute_text_edit: Delete replaces node with placeholder" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    Delete(node_id=root_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // children[0] is the left operand Var("x"), span [0, 1)
  let lhs = proj.children[0]
  let result = compute_text_edit(
    Delete(node_id=lhs.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let body = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    Delete(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInLambda(node_id=root_id, var_name="x"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let func = proj.children[0]
  let result = compute_text_edit(
    WrapInLambda(node_id=func.id(), var_name="x"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInApp(node_id=root_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  // Insert a new Int def at index 1 (before the body)
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=1, kind=@ast.Term::Int(0)),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  // Insert a Var child into a Bop node — re-renders with print_term
  let result = compute_text_edit(
    InsertChild(parent=root_id, index=0, kind=@ast.Term::Var("z")),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // source = children[0] (Var "x"), target = children[1] (Int 1)
  let source_node = proj.children[0]
  let target_node = proj.children[1]
  let result = compute_text_edit(
    Drop(source=source_node.id(), target=target_node.id(), position=After),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, source_map, registry, fp) = parse_with_token_spans(text)
  let source = proj.children[0]
  let target = proj.children[1]
  let result = compute_text_edit(
    Drop(source=source.id(), target=target.id(), position=Inside),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, source_map, registry, fp) = parse_with_token_spans(text)
  let source = proj.children[1]
  let target = proj.children[0]
  let result = compute_text_edit(
    Drop(source=source.id(), target=target.id(), position=Before),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    Drop(source=NodeId::from_int(9999), target=proj.id(), position=Before),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop synthetic multi-param lambda source is rejected" {
  let text = "(x, y) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let inner_lam = proj.children[0]
  let body = inner_lam.children[0]
  let result = compute_text_edit(
    Drop(source=inner_lam.id(), target=body.id(), position=After),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop synthetic multi-param lambda target is rejected" {
  let text = "(x, y) => x + z"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let inner_lam = proj.children[0]
  let body_bop = inner_lam.children[0]
  let source = body_bop.children[1]
  let result = compute_text_edit(
    Drop(source=source.id(), target=inner_lam.id(), position=Before),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: WrapInLambda with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    WrapInLambda(node_id=NodeId::from_int(9999), var_name="x"),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: CommitEdit with unknown node returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    CommitEdit(node_id=NodeId::from_int(9999), new_value="x"),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap Lam keeps body" {
  let text = "(x) => 42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let lam_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=lam_id, keep_child_index=0),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let lam = proj.children[0].children[0]
  let result = compute_text_edit(
    Unwrap(node_id=lam.id(), keep_child_index=0),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap synthetic multi-param lambda is rejected" {
  let text = "(x, y) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let inner_lam = proj.children[0]
  let result = compute_text_edit(
    Unwrap(node_id=inner_lam.id(), keep_child_index=0),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Unwrap Bop keeps left" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=0),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=1),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInIf(node_id=root_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    WrapInBop(node_id=root_id, op=@ast.Bop::Plus),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    ChangeOperator(node_id=root_id, new_op=@ast.Bop::Minus),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let root_id = proj.id()
  let result = compute_text_edit(
    SwapChildren(node_id=root_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Delete first binding
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Delete second binding
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=fp.defs[1].3),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=NodeId::from_int(9999)),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: DuplicateBinding copies binding with _copy suffix" {
  let text = "let x = 42\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
test "compute_text_edit: DuplicateBinding preserves typed fn syntax" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=fp.defs[0].3),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(
        new_text,
        content="fn twice(f : Int -> Int, x : Int) { f x }\nfn twice_copy(f : Int -> Int, x : Int) { f x }\ntwice",
      )
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
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingDown rejects last binding" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: MoveBindingUp swaps two bindings" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=fp.defs[1].3),
    make_edit_ctx(text, source_map, registry, fp),
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
test "compute_text_edit: AddBinding adds new let line" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let module_id = proj.id()
  let result = compute_text_edit(
    AddBinding(module_node_id=module_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Body is Bop(+, Var(x), Int(1)). Extract the whole body expression.
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Extract Var("x") from the body (left operand of +)
  let body = proj.children[proj.children.length() - 1]
  let var_x = body.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=var_x.id(), var_name="z"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // The body of lambda is Bop(+, Var(x), Int(1)) — child[0] of Lam
  let body = proj.children[0]
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: ExtractToLet rejects module-def enclosing env capture" {
  let text = "let x = y\nlet y = 1\n0"
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let init_y = fp.defs[0].1
  let result = compute_text_edit(
    ExtractToLet(node_id=init_y.id(), var_name="z"),
    make_edit_ctx(text, sm, registry, fp),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot extract: expression captures lambda-bound variables\")",
  )
}

///|
test "compute_text_edit: ExtractToLet rejects later module-def shadow capture" {
  let text = "let y = 1\nlet x = y\nlet y = 2\n0"
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let init_y = fp.defs[1].1
  let result = compute_text_edit(
    ExtractToLet(node_id=init_y.id(), var_name="z"),
    make_edit_ctx(text, sm, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    ExtractToLet(node_id=proj.id(), var_name="x"),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Body is the last child of Module — Var("x")
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Body is Bop(+, Var(x), Var(x)). Get the left Var.
  let body = proj.children[proj.children.length() - 1]
  let lhs = body.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=lhs.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    InlineDefinition(node_id=proj.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages with unknown binding returns error" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=NodeId::from_int(9999)),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages preserves typed fn binding" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice id 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=fp.defs[0].3),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, source_map, registry, fp),
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
test "compute_text_edit: InlineAllUsages first duplicate preserves shadowed body" {
  let text = "let x = 0\nlet x = x\nx"
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=fp.defs[0].3),
    make_edit_ctx(text, sm, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // Body is Var("x") — child[0] of Lam
  let var_x = proj.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=var_x.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages no usages just removes binding" {
  let text = "let x = 42\n0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=fp.defs[1].3),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // proj is Lam("x", Var("x"))
  let lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // body Var("x") is child[0] of Lam
  let var_x = proj.children[0]
  let result = compute_text_edit(
    Rename(node_id=var_x.id(), new_name="z"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // Use the binding_node_id from module_projection
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="x"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // body is Var("x") — last child of Module
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    Rename(node_id=body.id(), new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  // The block body `x` is the unique Var("x") in the program.
  let mut inner_x : NodeId? = None
  for id, node in registry {
    if node.kind is @ast.Term::Var("x") {
      inner_x = Some(id)
    }
  }
  guard inner_x is Some(inner_x_id) else {
    fail("could not locate block-local Var(\"x\")")
  }
  let result = compute_text_edit(
    Rename(node_id=inner_x_id, new_name="w"),
    make_edit_ctx(text, sm, registry, fp),
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
/// Block-local rename via the BINDER-CLICK path (`rename_binding_by_id`). The
/// nested `LetDef` node is resolved to its own block declaration by structural
/// node id, so it renames the block-local `x`, not the root def at index 0.
test "compute_text_edit: Rename block-local binding by binder id" {
  let text =
    #|let x = 1
    #|let y = { let x = 2
    #|  x }
    #|y
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // proj.children[1] = LetDef y; its init child[0] is the block Module;
  // that block's child[0] is the nested LetDef x.
  let nested_let_def = proj.children[1].children[0].children[0]
  let result = compute_text_edit(
    Rename(node_id=nested_let_def.id(), new_name="w"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  // The block body `x` (unique Var("x")) resolves to the root `x`.
  let mut inner_x : NodeId? = None
  for id, node in registry {
    if node.kind is @ast.Term::Var("x") {
      inner_x = Some(id)
    }
  }
  guard inner_x is Some(inner_x_id) else { fail("could not locate Var(\"x\")") }
  let result = compute_text_edit(
    Rename(node_id=inner_x_id, new_name="w"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let result = compute_text_edit(
    Rename(node_id=fp.defs[0].3, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Note: right operand's range may include leading space from CST
      inspect(new_text.contains("let y = 42"), content="true")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename nested lambda" {
  let text = "(x, y) => x"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  // Rename outer lambda param "x" to "z"
  let outer_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=outer_id, new_name="z"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let inner_lam = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    Rename(node_id=inner_lam.id(), new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let _ = proj
  let result = compute_text_edit(
    Rename(node_id=NodeId::from_int(9999), new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects capture of free variable" {
  // (x) => y  — renaming x to y would capture the free y
  let text = "(x) => y"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects capture by inner lambda binder" {
  // (x, y) => x — renaming outer x to y would rebind the use to inner y.
  let text = "(x, y) => x"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let outer_lam_id = proj.id()
  let result = compute_text_edit(
    Rename(node_id=outer_lam_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename rejects duplicate module binding name" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let _ = proj
  // Rename binding x → y should fail because y already exists
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Rename module binding rejects inner lambda capture" {
  // let x = 0\n(y) => x — renaming x→y would capture at the inner (y) =>
  let text = "let x = 0\n(y) => x"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let _ = proj
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    Rename(node_id=binding_id, new_name="y"),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineDefinition rejects capture" {
  // let y = 1\nlet x = y\n(y) => x — inlining x would produce (y) => y (capture)
  let text = "let y = 1\nlet x = y\n(y) => x"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let _ = sm
  // Body is (y) => x — the Lam node
  let body = proj.children[proj.children.length() - 1]
  // body is Lam("y", Var("x")), child[0] is Var("x")
  let var_x = body.children[0]
  let result = compute_text_edit(
    InlineDefinition(node_id=var_x.id()),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineDefinition allows same module-def reference" {
  let text = "let y = 1\nlet x = y\nx"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, sm, registry, fp),
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
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    make_edit_ctx(text, sm, registry, fp),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: InlineAllUsages rejects capture" {
  let text = "let y = 1\nlet x = y\n(y) => x"
  let (proj, sm, registry, fp) = parse_with_token_spans(text)
  let _ = proj
  let _ = sm
  // Binding "x" is at def index 1
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    make_edit_ctx(text, sm, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: InlineAllUsages allows same module-def reference" {
  let text = "let y = 1\nlet x = y\nx"
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=fp.defs[1].3),
    make_edit_ctx(text, sm, registry, fp),
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
  let (_, sm, registry, fp) = parse_with_token_spans(text)
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=fp.defs[1].3),
    make_edit_ctx(text, sm, registry, fp),
  )
  @debug.debug_inspect(
    result,
    content="Err(\"Cannot inline: would capture variables bound by enclosing lambda\")",
  )
}

///|
test "compute_text_edit: middleware rejects missing node for structural ops" {
  let text = "42"
  let (_, source_map, registry, fp) = parse_with_token_spans(text)
  let fake_id = NodeId::from_int(99999)
  let result = compute_text_edit(
    Delete(node_id=fake_id),
    make_edit_ctx(text, source_map, registry, fp),
  )
  @debug.debug_inspect(result, content="Err(\"Node not found: NodeId(99999)\")")
}

///|
test "compute_text_edit: MoveBindingUp allows valid swap where prev uses cur" {
  // prev (x) uses cur's name (y) — after swap, y comes first so ref is valid
  let text = "let x = y\nlet y = 0\nx"
  let (_, source_map, registry, fp) = parse_with_token_spans(text)
  let binding_id = fp.defs[1].3
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (_, source_map, registry, fp) = parse_with_token_spans(text)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    make_edit_ctx(text, source_map, registry, fp),
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
test "compute_text_edit: Unwrap cursor at replacement start" {
  // Unwrap Bop keeps right child — cursor should be at range.start (0),
  // not the original position of the right child
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=1),
    make_edit_ctx(text, source_map, registry, fp),
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
  let (_, source_map, registry, fp) = parse_with_token_spans(text)
  let module_id = fp.final_expr.unwrap().id()
  let result = compute_text_edit(
    InsertChild(parent=module_id, index=-1, kind=@ast.Term::Int(0)),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: AddBinding rejects non-Module target" {
  let text = "42"
  let (_, source_map, registry, fp) = parse_with_token_spans(text)
  let root_id = NodeId::from_int(0)
  // root is an Int, not a Module
  let result = compute_text_edit(
    AddBinding(module_node_id=root_id),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
test "compute_text_edit: Drop self-drop returns error" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let id = proj.id()
  let result = compute_text_edit(
    Drop(source=id, target=id, position=After),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let child = proj.children[0] // Var(x), inside the Bop
  let result = compute_text_edit(
    Drop(source=proj.id(), target=child.id(), position=After),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  // source = Int(1) at children[1], target = Var(x) at children[0]
  let source_node = proj.children[1]
  let target_node = proj.children[0]
  let result = compute_text_edit(
    Drop(source=source_node.id(), target=target_node.id(), position=Before),
    make_edit_ctx(text, source_map, registry, fp),
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
  let fp = ModuleProjection::from_proj_node(proj)
  let result = compute_text_edit(
    Drop(source=proj.id(), target=NodeId::from_int(9999), position=After),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}
