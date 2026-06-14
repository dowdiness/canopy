///|
fn cstfold_term(source : String) -> @ast.Term raise {
  let (cst, _) = @parser.parse_cst(source)
  @parser.syntax_node_to_term(@seam.SyntaxNode::from_cst(cst))
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
test "cstfold parity: valid module and fn sources agree" {
  assert_clean_projection_kind_matches_fold("let x = 1\nx + 2")
  assert_clean_projection_kind_matches_fold("fn id(x) { x }\nid")
  assert_clean_projection_kind_matches_fold("fn choose(x, y) { x }\nchoose")
}

///|
test "cstfold parity: raw block divergence stays behind compatibility adapter" {
  assert_projection_fold_classification("{ 1 }", Int(1), Module([], Int(1)))
  assert_projection_fold_classification("{ }", Unit, Error("empty block"))
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
  assert_projection_matches_compatible_fold("let x = { { 1 } }\nx")
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
