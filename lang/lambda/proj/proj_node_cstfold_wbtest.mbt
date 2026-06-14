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
test "cstfold parity: valid leaf and wrapper sources agree" {
  assert_clean_projection_kind_matches_fold("42")
  assert_clean_projection_kind_matches_fold("x")
  assert_clean_projection_kind_matches_fold("_")
  assert_clean_projection_kind_matches_fold("(1)")
}

///|
test "cstfold parity: valid composite sources agree" {
  assert_clean_projection_kind_matches_fold("f x")
  assert_clean_projection_kind_matches_fold("(f, x) => f x")
  assert_clean_projection_kind_matches_fold("1 + 2 + 3")
  assert_clean_projection_kind_matches_fold("if x then 1 else 2")
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
