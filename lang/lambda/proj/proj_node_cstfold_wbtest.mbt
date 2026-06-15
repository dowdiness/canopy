///|
fn cstfold_term(source : String) -> @ast.Term raise {
  let (cst, _) = @parser.parse_cst(source)
  @parser.syntax_node_to_term(@seam.SyntaxNode::from_cst(cst))
}

///|
fn cstfold_shallow_first_child(source : String) -> @ast.Term raise {
  let (cst, _) = @parser.parse_cst(source)
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [expr, ..] => cstfold_projection_compatible_shallow_kind(expr)
    [] => fail("expected expression child for " + source)
  }
}

///|
fn assert_term_equal(
  context : String,
  expected : @ast.Term,
  actual : @ast.Term,
) -> Unit raise {
  if actual != expected {
    let expected_text = @debug.to_string(expected)
    let actual_text = @debug.to_string(actual)
    fail(context + ": expected " + expected_text + ", got " + actual_text)
  }
}

///|
fn assert_clean_projection_kind_matches_fold(source : String) -> Unit raise {
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  let folded = cstfold_term(source)
  assert_term_equal(
    "expected projection/CstFold parity for " + source,
    folded,
    proj.kind,
  )
}

///|
fn assert_projection_fold_classification(
  source : String,
  expected_projection : @ast.Term,
  expected_fold : @ast.Term,
) -> Unit raise {
  let (proj, _errors) = parse_to_proj_node(source)
  let folded = cstfold_term(source)
  assert_term_equal(
    "projection classification for " + source,
    expected_projection,
    proj.kind,
  )
  assert_term_equal(
    "CstFold classification for " + source,
    expected_fold,
    folded,
  )
}

///|
fn assert_projection_matches_compatible_fold(source : String) -> Unit raise {
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  assert_term_equal(
    "expected projection/CstFold compatibility for " + source,
    folded,
    proj.kind,
  )
}

///|
fn assert_projection_metadata(
  context : String,
  proj : ProjNode[@ast.Term],
  expected_start : Int,
  expected_end : Int,
  expected_node_id : Int,
) -> Unit raise {
  if proj.start != expected_start ||
    proj.end != expected_end ||
    proj.node_id != expected_node_id {
    fail(
      context +
      ": expected metadata " +
      expected_start.to_string() +
      ".." +
      expected_end.to_string() +
      " #" +
      expected_node_id.to_string() +
      ", got " +
      proj.start.to_string() +
      ".." +
      proj.end.to_string() +
      " #" +
      proj.node_id.to_string(),
    )
  }
}

///|
fn assert_leaf_projection_metadata(
  source : String,
  expected_kind : @ast.Term,
  expected_start : Int,
  expected_end : Int,
) -> Unit raise {
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  assert_term_equal(
    "sample should pin CstFold-compatible leaf kind for " + source,
    expected_kind,
    folded,
  )
  assert_term_equal(
    "leaf kind should come from CstFold-compatible term for " + source,
    folded,
    proj.kind,
  )
  assert_projection_metadata(
    "leaf projection for " + source,
    proj,
    expected_start,
    expected_end,
    0,
  )
  if !proj.children.is_empty() {
    fail("expected childless leaf projection for " + source)
  }
}

///|
test "cstfold parity: valid leaf and wrapper sources agree" {
  assert_clean_projection_kind_matches_fold("42")
  assert_clean_projection_kind_matches_fold("x")
  assert_clean_projection_kind_matches_fold("_")
  assert_clean_projection_kind_matches_fold("(1)")
}

///|
test "cstfold-backed leaf projection preserves leaf metadata" {
  assert_leaf_projection_metadata("42", Int(42), 0, 2)
  assert_leaf_projection_metadata("  x", Var("x"), 0, 3)
  assert_leaf_projection_metadata("_", Hole(0), 0, 1)
}

///|
test "cstfold parity: valid composite sources agree" {
  assert_clean_projection_kind_matches_fold("f x")
  assert_clean_projection_kind_matches_fold("(f, x) => f x")
  assert_clean_projection_kind_matches_fold("1 + 2 + 3")
  assert_clean_projection_kind_matches_fold("if x then 1 else 2")
}

///|
test "cstfold-backed branch shape does not fold nested if children" {
  let source = "if x then if y then 1 else 2 else 3"
  assert_term_equal(
    "recursive fold should still see the nested if",
    If(Var("x"), If(Var("y"), Int(1), Int(2)), Int(3)),
    cstfold_projection_compatible_term(cstfold_term(source)),
  )
  assert_term_equal(
    "shallow IfExpr parent shape should use placeholders for children",
    If(Unit, Unit, Unit),
    cstfold_shallow_first_child(source),
  )
}

///|
test "cstfold-backed if projection preserves branch metadata" {
  let source = "if x then 1 else 2"
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  assert_term_equal(
    "if parent kind should come from CstFold-compatible term",
    folded,
    proj.kind,
  )
  assert_projection_metadata("if parent", proj, 0, 18, 3)
  match proj.children {
    [cond, then_, else_] => {
      assert_term_equal("if condition child kind", Var("x"), cond.kind)
      assert_term_equal("if then child kind", Int(1), then_.kind)
      assert_term_equal("if else child kind", Int(2), else_.kind)
      assert_projection_metadata("if condition child", cond, 2, 4, 0)
      assert_projection_metadata("if then child", then_, 9, 11, 1)
      assert_projection_metadata("if else child", else_, 16, 18, 2)
    }
    _ => fail("expected exactly three if children")
  }
}

///|
test "cstfold-backed if projection preserves recovered child kind" {
  let source = "if 1 + then 2 else 3"
  let (proj, errors) = parse_to_proj_node(source)
  if errors.is_empty() {
    fail("expected recovery diagnostics for " + source)
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  if folded == proj.kind {
    fail(
      "expected legacy recovered child kind to differ from raw CstFold child",
    )
  }
  assert_term_equal(
    "if parent should rebuild CstFold-compatible shape from projected children",
    rebuild_kind(folded, proj.children),
    proj.kind,
  )
  match proj.children {
    [cond, then_, else_] => {
      match cond.kind {
        Bop(Plus, Int(1), Error(projected_msg)) =>
          inspect(projected_msg.contains("unknown node kind"), content="true")
        _ => fail("unexpected recovered if condition child")
      }
      assert_term_equal("recovered if then child kind", Int(2), then_.kind)
      assert_term_equal("recovered if else child kind", Int(3), else_.kind)
    }
    _ => fail("expected exactly three recovered if children")
  }
}

///|
test "cstfold-backed flat app and bop shallow shapes do not fold nested children" {
  let app_source = "f (g x) y"
  assert_term_equal(
    "recursive fold should still see the nested app argument",
    App(App(Var("f"), App(Var("g"), Var("x"))), Var("y")),
    cstfold_projection_compatible_term(cstfold_term(app_source)),
  )
  assert_term_equal(
    "shallow AppExpr parent shape should use placeholders for flat children",
    App(App(Unit, Unit), Unit),
    cstfold_shallow_first_child(app_source),
  )
  let bop_source = "1 + (2 - 3) + 4"
  assert_term_equal(
    "recursive fold should still see the nested bop operand",
    Bop(Plus, Bop(Plus, Int(1), Bop(Minus, Int(2), Int(3))), Int(4)),
    cstfold_projection_compatible_term(cstfold_term(bop_source)),
  )
  assert_term_equal(
    "shallow BinaryExpr parent shape should use placeholders for flat operands",
    Bop(Plus, Bop(Plus, Unit, Unit), Unit),
    cstfold_shallow_first_child(bop_source),
  )
}

///|
test "app projection preserves left-nested spine metadata" {
  let source = "f x y"
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  assert_term_equal(
    "app projection should stay left nested",
    App(App(Var("f"), Var("x")), Var("y")),
    proj.kind,
  )
  assert_projection_metadata("app outer", proj, 0, 5, 4)
  match proj.children {
    [inner, y] => {
      assert_term_equal(
        "app outer left child kind",
        App(Var("f"), Var("x")),
        inner.kind,
      )
      assert_term_equal("app outer right child kind", Var("y"), y.kind)
      assert_projection_metadata("app inner", inner, 0, 3, 2)
      assert_projection_metadata("app y child", y, 3, 5, 3)
      match inner.children {
        [f, x] => {
          assert_term_equal("app func child kind", Var("f"), f.kind)
          assert_term_equal("app first arg child kind", Var("x"), x.kind)
          assert_projection_metadata("app func child", f, 0, 1, 0)
          assert_projection_metadata("app first arg child", x, 1, 3, 1)
        }
        _ => fail("expected exactly two inner app children")
      }
    }
    _ => fail("expected exactly two outer app children")
  }
}

///|
test "app projection preserves recovered argument child" {
  let source = "f ("
  let (proj, errors) = parse_to_proj_node(source)
  if errors.is_empty() {
    fail("expected recovery diagnostics for " + source)
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  if folded == proj.kind {
    fail("expected recovered app argument to differ from raw CstFold child")
  }
  assert_term_equal(
    "app parent should rebuild CstFold-compatible shape from projected children",
    rebuild_kind(folded, proj.children),
    proj.kind,
  )
  assert_projection_metadata("recovered app parent", proj, 0, 3, 2)
  match proj.children {
    [func, arg] => {
      assert_term_equal("recovered app func kind", Var("f"), func.kind)
      match arg.kind {
        Error(projected_msg) =>
          inspect(projected_msg.contains("unknown node kind"), content="true")
        _ => fail("unexpected recovered app argument child")
      }
      assert_projection_metadata("recovered app func child", func, 0, 1, 0)
      assert_projection_metadata("recovered app arg child", arg, 1, 3, 1)
    }
    _ => fail("expected exactly two recovered app children")
  }
}

///|
test "bop projection preserves left-nested spine metadata" {
  let source = "1 + 2 - 3"
  let (proj, errors) = parse_to_proj_node(source)
  if !errors.is_empty() {
    fail(
      "expected clean parse for " + source + ", got " + @debug.to_string(errors),
    )
  }
  assert_term_equal(
    "bop projection should stay left nested",
    Bop(Minus, Bop(Plus, Int(1), Int(2)), Int(3)),
    proj.kind,
  )
  assert_projection_metadata("bop outer", proj, 0, 9, 4)
  match proj.children {
    [inner, rhs] => {
      assert_term_equal(
        "bop outer left child kind",
        Bop(Plus, Int(1), Int(2)),
        inner.kind,
      )
      assert_term_equal("bop outer right child kind", Int(3), rhs.kind)
      assert_projection_metadata("bop inner", inner, 0, 5, 2)
      assert_projection_metadata("bop rhs child", rhs, 7, 9, 3)
      match inner.children {
        [lhs, mid] => {
          assert_term_equal("bop lhs child kind", Int(1), lhs.kind)
          assert_term_equal("bop mid child kind", Int(2), mid.kind)
          assert_projection_metadata("bop lhs child", lhs, 0, 1, 0)
          assert_projection_metadata("bop mid child", mid, 3, 5, 1)
        }
        _ => fail("expected exactly two inner bop children")
      }
    }
    _ => fail("expected exactly two outer bop children")
  }
}

///|
test "bop projection preserves recovered rhs child metadata" {
  let source = "1 +"
  let (proj, errors) = parse_to_proj_node(source)
  if errors.is_empty() {
    fail("expected recovery diagnostics for " + source)
  }
  let folded = cstfold_projection_compatible_term(cstfold_term(source))
  if folded == proj.kind {
    fail("expected recovered bop rhs to differ from raw CstFold child")
  }
  assert_term_equal(
    "bop parent should rebuild CstFold-compatible shape from projected children",
    rebuild_kind(folded, proj.children),
    proj.kind,
  )
  assert_projection_metadata("recovered bop parent", proj, 0, 3, 2)
  match proj.children {
    [lhs, rhs] => {
      assert_term_equal("recovered bop lhs kind", Int(1), lhs.kind)
      match rhs.kind {
        Error(projected_msg) =>
          inspect(projected_msg.contains("unknown node kind"), content="true")
        _ => fail("unexpected recovered bop rhs child")
      }
      assert_projection_metadata("recovered bop lhs child", lhs, 0, 1, 0)
      assert_projection_metadata("recovered bop rhs child", rhs, 3, 3, 1)
    }
    _ => fail("expected exactly two recovered bop children")
  }
}

///|
test "cstfold parity: valid module and fn sources agree" {
  assert_clean_projection_kind_matches_fold("let x = 1\nx + 2")
  assert_clean_projection_kind_matches_fold("fn id(x) { x }\nid")
  assert_clean_projection_kind_matches_fold("fn choose(x, y) { x }\nchoose")
}

///|
test "cstfold parity: block projection agrees with cstfold; empty-block divergence stays behind adapter" {
  // Non-empty-body blocks: canopy projection now matches Loom CstFold directly.
  assert_projection_fold_classification(
    "{ 1 }",
    Module([], Int(1)),
    Module([], Int(1)),
  )
  // Empty block: canopy gives Module([], Unit), Loom gives Error("empty block").
  // The compatibility adapter bridges this remaining divergence.
  assert_projection_fold_classification(
    "{ }",
    Module([], Unit),
    Error("empty block"),
  )
  assert_term_equal(
    "empty block compatibility normalization",
    Unit,
    cstfold_projection_compatible_term(Error("empty block")),
  )
  assert_term_equal(
    "nested empty block compatibility normalization",
    Module([("x", Unit)], Var("x")),
    cstfold_projection_compatible_term(
      Module([("x", Error("empty block"))], Var("x")),
    ),
  )
  assert_projection_matches_compatible_fold("{ 1 }")
  assert_projection_matches_compatible_fold("{ { 1 } }")
  // Double-nested empty-def block in let-def init position: Loom's
  // convert_let_def calls convert_function_body on the init expression, which
  // transparently unwraps an outer empty-def block (defs empty → return body).
  // Canopy's project_let_def calls syntax_to_proj_node, which preserves all
  // empty-def blocks as Module nodes. The result: Loom folds to
  // Module([], Int(1)) as the init (outer unwrapped), while Canopy produces
  // Module([], Module([], Int(1))) (both levels preserved).
  assert_projection_fold_classification(
    "let x = { { 1 } }\nx",
    Module([("x", Module([], Module([], Int(1))))], Var("x")),
    Module([("x", Module([], Int(1)))], Var("x")),
  )
  assert_projection_matches_compatible_fold("{ let x = 1; { x } }")
}

///|
test "cstfold parity: recovery divergence is classified separately" {
  let source = "1 +"
  let (proj, errors) = parse_to_proj_node(source)
  if errors.is_empty() {
    fail("expected recovery diagnostics for " + source)
  }
  let folded = cstfold_term(source)
  if proj.kind == folded {
    fail("expected projection/CstFold recovery divergence for " + source)
  }
  match (proj.kind, folded) {
    (
      Bop(Plus, Int(1), Error(projected_msg)),
      Bop(Plus, Int(1), Error(folded_msg)),
    ) => {
      inspect(projected_msg.contains("unknown node kind"), content="true")
      inspect(folded_msg, content="ErrorNode")
    }
    _ => {
      let projected_text = @debug.to_string(proj.kind)
      let folded_text = @debug.to_string(folded)
      fail(
        "unexpected recovery classification: projected=" +
        projected_text +
        ", folded=" +
        folded_text,
      )
    }
  }
}
