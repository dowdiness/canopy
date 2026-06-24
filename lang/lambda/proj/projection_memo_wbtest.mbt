///|
fn module_binding_ids(
  root : @core.ProjNode[@ast.Term],
) -> Map[String, @core.NodeId] raise {
  match root.kind {
    Module(defs, _) => {
      let ids : Map[String, @core.NodeId] = {}
      for i, def in defs {
        if i < root.children.length() - 1 {
          ids[def.0] = root.children[i].id()
        }
      }
      ids
    }
    _ => fail("expected module root")
  }
}

///|
test "build_lambda_projection_memos: reordered defs preserve binding ids" {
  let parser = @loom.new_parser(
    "let x = 1\nlet y = 2\nx", @parser.lambda_grammar,
  )
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  let before = module_binding_ids(proj_memo.read_or_abort().unwrap())
  parser.set_source("let y = 2\nlet x = 1\nx")
  let after = module_binding_ids(proj_memo.read_or_abort().unwrap())
  inspect(after["x"] == before["x"], content="true")
  inspect(after["y"] == before["y"], content="true")
}

///|
fn module_binding_ids_in_order(
  root : @core.ProjNode[@ast.Term],
) -> Array[@core.NodeId] raise {
  match root.kind {
    Module(defs, _) =>
      [
        for i in 0..<defs.length() => {
          guard i + 1 < root.children.length() else {
            fail("missing LetDef child")
          }
          root.children[i].id()
        }
      ]
    _ => fail("expected module root")
  }
}

///|
test "build_lambda_projection_memos: duplicate defs preserve occurrence binding ids" {
  let parser = @loom.new_parser(
    "let x = 1\nlet x = 2\nx", @parser.lambda_grammar,
  )
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  let before = module_binding_ids_in_order(proj_memo.read_or_abort().unwrap())
  parser.set_source("let x = 1\nlet x = 3\nx")
  let after = module_binding_ids_in_order(proj_memo.read_or_abort().unwrap())
  inspect(after[0] == before[0], content="true")
  inspect(after[1] == before[1], content="true")
  inspect(after[0] == after[1], content="false")
}

///|
test "build_lambda_projection_memos: inserted def gets fresh id while neighbors stay stable" {
  let parser = @loom.new_parser(
    "let x = 1\nlet z = 3\nz", @parser.lambda_grammar,
  )
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  let before = module_binding_ids_in_order(proj_memo.read_or_abort().unwrap())
  parser.set_source("let x = 1\nlet y = 2\nlet z = 3\nz")
  let after = module_binding_ids_in_order(proj_memo.read_or_abort().unwrap())
  inspect(after[0] == before[0], content="true")
  inspect(after[2] == before[1], content="true")
  inspect(after[1] == before[0] || after[1] == before[1], content="false")
}

///|
test "build_lambda_projection_memos: root module id stays stable across rebuild" {
  let parser = @loom.new_parser("let x = 1\nx", @parser.lambda_grammar)
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  let before = proj_memo.read_or_abort().unwrap().id()
  parser.set_source("let x = 2\nx")
  let after = proj_memo.read_or_abort().unwrap().id()
  inspect(after == before, content="true")
}

///|
test "build_lambda_projection_memos: root block module keeps outer span" {
  let parser = @loom.new_parser("{ let x = 1\n  x }", @parser.lambda_grammar)
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  ignore(proj_memo.read_or_abort())
  parser.set_source("{ let x = 2\n  x }")
  let after = proj_memo.read_or_abort().unwrap()
  inspect(after.start, content="0")
  inspect(after.end, content="17")
}

///|
test "build_lambda_projection_memos: explicit Unit body keeps span" {
  let parser = @loom.new_parser("let x = 1\n{}", @parser.lambda_grammar)
  let (proj_memo, _, _) = build_lambda_projection_memos(parser)
  ignore(proj_memo.read_or_abort())
  parser.set_source("let x = 2\n{}")
  let after = proj_memo.read_or_abort().unwrap()
  let body = after.children[after.children.length() - 1]
  inspect(body.start, content="10")
  inspect(body.end, content="12")
}
