///|
let lambda_semantic_projection_test_source : @loomcore.SourceId = @loomcore.SourceId(
  "canopy-test:lambda-semantic-projection",
)

///|
fn parse_fixture(
  text : String,
) -> (@core.ProjNode[@ast.Term], @core.SourceMap) raise {
  let (cst, _) = @parser.parse_cst(lambda_semantic_projection_test_source, text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let root = @lambda_proj.to_proj_node(syntax, Ref(0))
  let source_map = @core.SourceMap::from_ast(root)
  @lambda_proj.populate_token_spans(source_map, syntax, root)
  (root, source_map)
}

///|
fn semantic_diagnostics_fixture(text : String) -> @loomcore.DiagnosticSet raise {
  let (root, source_map) = parse_fixture(text)
  build_semantic_diagnostics(
    lambda_semantic_projection_test_source, text, root, source_map,
  )
}

///|
fn has_annotation(
  projection : SemanticProjection,
  node_id : @core.NodeId,
  label : String,
) -> Bool {
  match projection.annotations.get(node_id) {
    Some(anns) => anns.iter().any(fn(ann) { ann.label == label })
    None => false
  }
}

///|
test "semantic projection annotates lambda binder and bound use" {
  let (root, source_map) = parse_fixture("(x) => x")
  let projection = build_semantic_projection(root, source_map)
  assert_true(has_annotation(projection, root.id(), "(x) =>"))
  assert_true(has_annotation(projection, root.children[0].id(), "bound x"))
  inspect(semantic_diagnostics_fixture("(x) => x").length(), content="0")
  assert_true(
    projection.decorations
    .iter()
    .any(fn(d) { d.css_class == "semantic-binder" }),
  )
  assert_true(
    projection.decorations.iter().any(fn(d) { d.css_class == "semantic-bound" }),
  )
}

///|
test "semantic projection reports free variable" {
  let text = "(x) => y"
  let (root, source_map) = parse_fixture(text)
  let projection = build_semantic_projection(root, source_map)
  let body = root.children[0]
  assert_true(has_annotation(projection, body.id(), "free y"))
  inspect(
    build_semantic_diagnostics(
      lambda_semantic_projection_test_source, text, root, source_map,
    ).length(),
    content="1",
  )
  assert_true(
    projection.decorations.iter().any(fn(d) { d.css_class == "semantic-free" }),
  )
}

///|
test "free-variable diagnostic in a module def is scope-sourced" {
  // `z` is free in def 0's init; the body `a` resolves to def 0. This exercises
  // the scope-graph diagnostic path through the MODULE route (not just the bare
  // lambda route), proving `push_scope_failures` reconstructs and resolves the
  // module-def graph rather than the diagnostic still coming from stale env logic.
  let (root, source_map) = parse_fixture("let a = z\na")
  let diagnostics = build_semantic_diagnostics(
    lambda_semantic_projection_test_source, "let a = z\na", root, source_map,
  )
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics.items()[0].message(), content="Free variable 'z'")
}

///|
/// Differential oracle. The scope-graph classifier (`failures()`, i.e.
/// `resolution.decl is None`) must agree, reference-by-reference, with the
/// environment walk (`analyze_var`'s "bound "/"free " annotation) that drives
/// the visual decorations. The env walk recurses into nested blocks with a
/// sequential `scoped` env, so it is the oracle here.
///
/// Hand-checked oracle spot-check (shadowing): for
/// `let x = 1\nlet y = { let x = 2; x }\ny`, the block's `x` shadows the outer
/// `x`; the block body `x` resolves to the block `x`; every reference is bound,
/// so the env walk reports 0 free — which is correct.
///
/// This is the test that would have caught the block-scope regression: before
/// the builder modelled nested-block (`Module`) scopes, the graph reported
/// block-local bindings as free while the env walk bound them.
fn assert_classifiers_agree(program : String) -> Unit raise {
  let (root, source_map) = parse_fixture(program)
  let projection = build_semantic_projection(root, source_map)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(root, registry)
  let graph = @lambda_scope.build(registry, source_map)
  for r in graph.refs {
    let scope_free = r.resolution.decl is None
    let anns = match projection.annotations.get(r.node_id) {
      Some(anns) => anns
      None => []
    }
    let env_free = anns.iter().any(fn(a) { a.label == "free " + r.name })
    let env_bound = anns.iter().any(fn(a) { a.label == "bound " + r.name })
    // The env walk must classify every reference exactly once; "no annotation"
    // is itself a regression (Codex pre-PR finding), not an implicit "bound".
    if env_free == env_bound {
      fail(
        "env walk did not classify `" +
        r.name +
        "` exactly once in `" +
        program +
        "` (free=" +
        env_free.to_string() +
        " bound=" +
        env_bound.to_string() +
        ")",
      )
    }
    if scope_free != env_free {
      fail(
        "classifier disagreement in `" +
        program +
        "` for `" +
        r.name +
        "`: scope_free=" +
        scope_free.to_string() +
        " env_free=" +
        env_free.to_string(),
      )
    }
  }
}

///|
fn scope_free_names(program : String) -> Array[String] raise {
  let (root, source_map) = parse_fixture(program)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(root, registry)
  let graph = @lambda_scope.build(registry, source_map)
  @lambda_scope.failures(graph, source_map).map(fn(f) { f.name })
}

///|
test "scope and env classifiers agree on block programs" {
  // block-local binding: `x` is bound inside the block (was the regression)
  assert_classifiers_agree("let y = { let x = 1; x }\ny")
  // doubly-nested blocks: two simultaneously non-trivial cutoffs
  assert_classifiers_agree("let o = { let a = 1; { let b = a; b } }\no")
  // block def shadows an outer def
  assert_classifiers_agree("let x = 1\nlet y = { let x = 2; x }\ny")
  // cross-boundary ref to an outer def that precedes the block (sequential)
  assert_classifiers_agree("let a = 1\nlet y = { let b = a; b }\ny")
  // genuine free var inside a block — both classifiers must agree it is free
  assert_classifiers_agree("let y = { let b = q; b }\ny")
}

///|
test "block classifier non-vacuity: block-local bound, block-free surfaced" {
  // The block-local `x` must NOT be reported free (it is bound in the block).
  assert_false(scope_free_names("let y = { let x = 1; x }\ny").contains("x"))
  // A genuinely free `q` inside a block MUST be surfaced, and it must be the
  // ONLY failure — length 1 + contains `q` proves the set is exactly `["q"]`,
  // closing the reverse direction the per-ref oracle leaves open (a silently
  // dropped ref would under-report here).
  let block_free = scope_free_names("let y = { let b = q; b }\ny")
  assert_eq(block_free.length(), 1)
  assert_true(block_free.contains("q"))
}

///|
test "semantic projection respects sequential module bindings" {
  let (root, source_map) = parse_fixture("let x = 1\nlet y = x\nx + y")
  let projection = build_semantic_projection(root, source_map)
  assert_true(has_annotation(projection, root.children[0].id(), "let x"))
  assert_true(has_annotation(projection, root.children[1].id(), "let y"))
  assert_false(has_annotation(projection, root.id(), "let x"))
  assert_false(has_annotation(projection, root.id(), "let y"))
  inspect(
    semantic_diagnostics_fixture("let x = 1\nlet y = x\nx + y").length(),
    content="0",
  )
}

///|
test "semantic diagnostics preserve neutral warning labels and identities" {
  let text = "(x) => y"
  let diagnostics = semantic_diagnostics_fixture(text)
  let diagnostic = diagnostics.items()[0]
  debug_inspect(diagnostic.severity(), content="Warning")
  inspect(
    diagnostic.code().unwrap().value(),
    content="lambda.unresolved_reference",
  )
  inspect(diagnostic.message(), content="Free variable 'y'")
  inspect(diagnostic.source().name(), content="lambda.semantic")
  inspect(
    diagnostic.source().name() == lambda_semantic_projection_test_source.value(),
    content="false",
  )
  let labels = diagnostic.labels()
  inspect(labels.length() >= 2, content="true")
  debug_inspect(labels[0].style(), content="Primary")
  debug_inspect(labels[0].message(), content="Some(\"unresolved identifier\")")
  inspect(
    labels[0].span().source_id().value(),
    content="canopy-test:lambda-semantic-projection",
  )
  inspect(labels[0].span().range().start().value(), content="7")
  inspect(labels[0].span().range().end().value(), content="8")
  inspect(
    labels
    .get_view(start=1)
    .unwrap()
    .all(label => {
      label.style() == @loomcore.LabelStyle::Secondary &&
      label.message() == Some("searched lexical scope")
    }),
    content="true",
  )
}

///|
test "semantic diagnostics keep missing witness locations as notes" {
  let text = "(x) => y"
  let (root, populated_source_map) = parse_fixture(text)
  let sparse_source_map = @core.SourceMap::new()
  let body = root.children[0]
  let reference_span = populated_source_map
    .get_token_span(body.id(), @lambda_proj.REFERENCE_NAME_ROLE)
    .unwrap()
  sparse_source_map.set_token_span(
    body.id(),
    @lambda_proj.REFERENCE_NAME_ROLE,
    reference_span,
  )
  let diagnostic = build_semantic_diagnostics(
      lambda_semantic_projection_test_source, text, root, sparse_source_map,
    ).items()[0]
  inspect(diagnostic.labels().length(), content="1")
  inspect(diagnostic.notes().length() >= 1, content="true")
  inspect(
    diagnostic
    .notes()
    .all(note => note == "searched lexical scope without source span"),
    content="true",
  )
}

///|
test "semantic diagnostic boundary rejects invalid source ranges" {
  let text = "(x) => y"
  let (root, source_map) = parse_fixture(text)
  let body = root.children[0]
  let rejected = (range, validation_source) => {
    source_map.set_token_span(
      body.id(),
      @lambda_proj.REFERENCE_NAME_ROLE,
      range,
    )
    try {
      let _ = build_semantic_diagnostics(
        lambda_semantic_projection_test_source, validation_source, root, source_map,
      )
      false
    } catch {
      _ => true
    }
  }
  inspect(rejected(@loomcore.Range::new(-1, 1), text), content="true")
  inspect(rejected(@loomcore.Range::new(2, 1), text), content="true")
  inspect(rejected(@loomcore.Range::new(7, 9), text), content="true")
  inspect(rejected(@loomcore.Range::new(7, 8), "123456😀"), content="true")
}

///|
test "semantic diagnostics are defensive copies and render from one neutral value" {
  let text = "(x) => y"
  let diagnostics = semantic_diagnostics_fixture(text)
  let exposed = diagnostics.items()
  let exposed_labels = exposed[0].labels()
  let exposed_notes = exposed[0].notes()
  exposed.clear()
  exposed_labels.clear()
  exposed_notes.push("mutated")
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics.items()[0].labels().length() >= 2, content="true")
  inspect(diagnostics.items()[0].notes().contains("mutated"), content="false")
  let provider = @loomcore.SourceProvider(requested => {
    if requested == lambda_semantic_projection_test_source {
      Some(
        @loomcore.DiagnosticSourceFile(
          "lambda.mbt",
          text,
          @loomcore.LineIndex::new(text),
        ),
      )
    } else {
      None
    }
  })
  inspect(
    diagnostics.items()[0].render_plain(provider).contains("Free variable 'y'"),
    content="true",
  )
}
