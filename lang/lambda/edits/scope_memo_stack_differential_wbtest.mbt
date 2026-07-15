// Level-B incremental ↔ fresh differential through the REAL editor-facing
// @incr memo stack.
//
// WHAT THIS PINS
// This file drives Lambda's editor-facing projection cells off a live
// `@loom.Parser` and the generic `@core.build_projection_memos` path exposed
// through `@lambda_proj.build_lambda_projection_memos`. After each parser edit
// it reads the cached projection, registry, and source map, then asserts scope
// resolution agrees with a fresh generic rebuild of the same source.
//
// NON-GOALS
// This intentionally does not assert registry/source-map object identity or
// patch-vs-rebuild behavior. #633 removes Lambda's custom patching side-channel
// from the editor-facing stack; optimizing projection diffing again requires a
// reproduced bottleneck and separate benchmarks.
//
// SCOPE
// Edits are ASCII-only, so a byte offset equals a UTF-16 code unit equals a char
// index and the minimal-diff `Edit` is unambiguous. Empty-source steps are out
// of scope (all sequences stay non-empty); a None projection on a non-empty
// source is treated as a hard failure, not a skipped comparison.

///|
/// A live memo stack: a real `@loom.Parser` plus the three production generic
/// projection memos, with a `Scope`/`Watch` GC anchor (incr convention for
/// long-lived Deriveds). The anchor reads terminal memos inside a tracked
/// closure so one Watch can root the chain if a test later forces GC.
struct LevelBStack {
  parser : @loom.Parser[@ast.Term]
  cached_proj_node : @incr.Derived[@core.ProjNode[@ast.Term]?]
  registry_memo : @incr.Derived[Map[@core.NodeId, @core.ProjNode[@ast.Term]]]
  source_map_memo : @incr.Derived[@core.SourceMap]
  scope : @incr.Scope
}

///|
fn LevelBStack::LevelBStack(source : String) -> LevelBStack {
  let parser = @loom.new_parser(source, @parser.lambda_grammar)
  let (cached_proj_node, registry_memo, source_map_memo) = @lambda_proj.build_lambda_projection_memos(
    parser,
  )
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let anchor = scope.derived(
    fn() {
      ignore(cached_proj_node.get_or_abort())
      ignore(registry_memo.get_or_abort())
      ignore(source_map_memo.get_or_abort())
    },
    label="level_b_anchor",
  )
  ignore(scope.add_watch(anchor.watch()))
  { parser, cached_proj_node, registry_memo, source_map_memo, scope }
}

///|
fn LevelBStack::dispose(self : LevelBStack) -> Unit {
  self.scope.dispose()
}

///|
/// Advance the parser by the minimal single-region edit turning `old` into `new`.
fn LevelBStack::apply(self : LevelBStack, old : String, new : String) -> Unit {
  self.parser.apply_edit(lb_minimal_edit(old, new), new)
}

///|
/// Minimal single-region replacement turning `old` into `new`, via common prefix
/// + common suffix. Offsets are UTF-16 code units (`code_unit_at` / `length`);
/// callers pass ASCII only, where code unit == byte == char, so the coordinates
/// handed to `apply_edit` are unambiguous.
fn lb_minimal_edit(old : String, new : String) -> @loomcore.Edit {
  let ol = old.length()
  let nl = new.length()
  let cap = if ol < nl { ol } else { nl }
  let mut p = 0
  while p < cap && old.code_unit_at(p) == new.code_unit_at(p) {
    p = p + 1
  }
  let mut s = 0
  while s < cap - p &&
        old.code_unit_at(ol - 1 - s) == new.code_unit_at(nl - 1 - s) {
    s = s + 1
  }
  @loomcore.Edit::new(p, ol - p - s, nl - p - s)
}

///|
/// Fresh generic projection rebuild used as the oracle for the live memo stack.
fn fresh_generic_graph_of(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  @scope.ScopeGraph,
  @core.SourceMap,
) raise {
  let (cst, _diags) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  let proj = @lambda_proj.to_proj_node(syntax, counter)
  let sm = @core.SourceMap::from_ast(proj)
  @lambda_proj.populate_token_spans(sm, syntax, proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(proj, registry)
  let graph = @scope.build(registry, sm)
  (proj, registry, graph, sm)
}

///|
/// Read the live memo stack and assert its incrementally-maintained scope
/// resolution agrees with a FRESH generic rebuild of the same current source.
fn assert_level_b_agrees(
  stack : LevelBStack,
  src : String,
  context : String,
) -> Unit raise {
  guard stack.parser.source().read_or_abort() == src else {
    fail(
      "[\{context}] parser source desynced from expected: minimal-diff Edit is wrong",
    )
  }
  let root_opt = stack.cached_proj_node.read_or_abort()
  let reg_i = stack.registry_memo.read_or_abort()
  let sm_i = stack.source_map_memo.read_or_abort()
  guard root_opt is Some(root) else {
    fail("[\{context}] memo projection is None on non-empty source: \{src}")
  }
  let g_i = @scope.build(reg_i, sm_i)
  let ranges_i = def_binding_ranges(root)
  let (proj_f, reg_f, g_f, sm_f) = fresh_generic_graph_of(src)
  let ranges_f = def_binding_ranges(proj_f)
  assert_resolution_agrees(
    ResolutionSide(
      graph=g_i,
      registry=reg_i,
      source_map=sm_i,
      ranges=ranges_i,
      value_label="memo",
      binder_label="memo",
    ),
    ResolutionSide(
      graph=g_f,
      registry=reg_f,
      source_map=sm_f,
      ranges=ranges_f,
      value_label="fresh",
      binder_label="fresh",
    ),
    context_prefix="[\{context}] ",
    binder_span_disagreement="binder span disagrees across memo/fresh",
  )
}

///|
/// Drive a non-empty edit sequence through the generic memo stack, asserting
/// agreement after every step.
fn lb_run_sequence(sources : Array[String]) -> Unit raise {
  guard sources.length() >= 1 else { fail("lb_run_sequence needs >=1 source") }
  let stack = LevelBStack(sources[0])
  assert_level_b_agrees(stack, sources[0], "init:\{sources[0]}")
  for i in 1..<sources.length() {
    stack.apply(sources[i - 1], sources[i])
    assert_level_b_agrees(stack, sources[i], "edit\{i}:\{sources[i]}")
  }
  stack.dispose()
}

///|
test "level-B generic: resolution-visible def-init edit agrees with fresh rebuild" {
  let s0 = "let x = 1\nlet y = 2\nx"
  let stack = LevelBStack(s0)
  assert_level_b_agrees(stack, s0, "init")
  let s1 = "let x = 1\nlet y = x\nx"
  stack.apply(s0, s1)
  assert_level_b_agrees(stack, s1, "after-resolution-visible-edit")
  stack.dispose()
}

///|
test "level-B generic: skipped registry reads still agree after later edits" {
  let s0 = "let a = 1\nlet b = 2\nb"
  let stack = LevelBStack(s0)
  ignore(stack.registry_memo.read_or_abort())
  ignore(stack.source_map_memo.read_or_abort())
  assert_level_b_agrees(stack, s0, "init")
  let sA = "let a = 1\nlet b = 3\nb"
  stack.apply(s0, sA)
  ignore(stack.source_map_memo.read_or_abort())
  let sB = "let a = 1\nlet b = 4\nb"
  stack.apply(sA, sB)
  assert_level_b_agrees(stack, sB, "after-skipped-registry-read")
  stack.dispose()
}

///|
test "level-B generic: def-init chain agrees every step" {
  lb_run_sequence([
    "let a = 1\nlet b = 2\na", "let a = 1\nlet b = 3\na", "let a = 4\nlet b = 3\na",
    "let a = 4\nlet b = a\na",
  ])
}

///|
test "level-B generic: insert and delete defs agree through the memo stack" {
  lb_run_sequence([
    "let x = 0\nx", "let x = 0\nlet y = 1\nx", "let x = 0\nlet y = 1\nlet z = 2\n(x z)",
    "let x = 0\nlet z = 2\n(x z)", "let z = 2\nz",
  ])
}

///|
test "level-B generic: growing an earlier def shifts later defs" {
  lb_run_sequence([
    "let a = 0\nlet b = 1\n(a + b)", "let a = (0 + 0)\nlet b = 1\n(a + b)", "let a = ((0 + 0) + 0)\nlet b = 1\n(a + b)",
  ])
}

///|
test "level-B generic: rename a binder flips shadowing" {
  lb_run_sequence([
    "let x = 1\nlet x = 2\nx", "let x = 1\nlet w = 2\nx", "let x = 1\nlet x = 2\nx",
  ])
}
