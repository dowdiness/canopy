///|
/// Plan C (#129) Step 1: Pin current agreement between edit-layer free_vars and
/// the scope graph BEFORE consolidating to graph-backed resolution.
///
/// For each source fixture we build one projection, one ScopeGraph, and compare:
///   1. Per-Var free/bound status: scope-graph `@scope.declaration` oracle vs
///      a ProjNode walk mirroring the free_vars.mbt scoping rules.
///   2. Module-end name resolution: `declaration_id_for_name_at_module_end` vs
///      `@scope.declaration_for_name_at` at the module body node.
///
/// Unbound nodes are treated differently by the two systems:
///   - Scope graph creates a Ref for `Unbound` with `resolution.decl = None`
///     (unresolved / scope-free).
///   - free_vars returns empty for `Unbound` (not considered a variable
///     reference).
/// This divergence is explicitly recorded here as a known delta; whether edit
/// guards should keep or change the free_vars behaviour is decided before
/// later steps.

///|
/// [Moved from free_vars.mbt — wbtest oracle only. Zero production callers.]
fn free_vars(
  term : @ast.Term,
  env : @immut/hashset.HashSet[String],
) -> @immut/hashset.HashSet[String] {
  match term {
    @ast.Term::Var(x) =>
      if env.contains(x) {
        @immut/hashset.new()
      } else {
        @immut/hashset.new().add(x)
      }
    @ast.Term::Lam(x, body) => free_vars(body, env.add(x))
    @ast.Term::App(f, a) => free_vars(f, env).union(free_vars(a, env))
    @ast.Term::Bop(_, l, r) => free_vars(l, env).union(free_vars(r, env))
    @ast.Term::If(c, t, e) =>
      free_vars(c, env).union(free_vars(t, env)).union(free_vars(e, env))
    @ast.Term::Module(defs, body) => {
      let mut result : @immut/hashset.HashSet[String] = @immut/hashset.new()
      let mut cur_env = env
      for def in defs {
        result = result.union(free_vars(def.1, cur_env))
        cur_env = cur_env.add(def.0)
      }
      result.union(free_vars(body, cur_env))
    }
    _ => @immut/hashset.new() // Int, Unit, Error, Unbound
  }
}

/// ---------------------------------------------------------------------------
/// Helpers: build oracle from text
/// ---------------------------------------------------------------------------

///|
fn build_oracle(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  @scope.ScopeGraph,
) raise {
  let (cst, _errs) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(proj, registry)
  let g = @scope.build(registry, sm)
  (proj, registry, g)
}

/// ---------------------------------------------------------------------------
/// Helpers: per-Var free/bound keyed by source range
/// ---------------------------------------------------------------------------

///|
/// Collect all Var nodes from the registry, keyed by "start:end:name".
/// Source spans are known-unique for Var occurrences within a single parse,
/// so this key is injective. A collision is a structural defect and aborts.
fn collect_var_keys(
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Map[String, @core.NodeId] raise {
  let keys : Map[String, @core.NodeId] = Map([])
  for id, node in registry {
    if node.kind is @ast.Term::Var(name) {
      let key = "\{node.start}:\{node.end}:\{name}"
      guard keys.get(key) is None else {
        fail("Var key \{key} is not injective within a pipeline")
      }
      keys[key] = id
    }
  }
  keys
}

///|
/// Collect all Unbound nodes from the registry, keyed by "start:end:name".
fn collect_unbound_keys(
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Map[String, @core.NodeId] {
  let keys : Map[String, @core.NodeId] = Map([])
  for id, node in registry {
    if node.kind is @ast.Term::Unbound(name) {
      let key = "\{node.start}:\{node.end}:\{name}"
      keys[key] = id
    }
  }
  keys
}

///|
/// Per-Var free/bound status from the scope graph: true = free (no declaration).
fn scope_free_map(
  g : @scope.ScopeGraph,
  var_keys : Map[String, @core.NodeId],
) -> Map[String, Bool] {
  let free : Map[String, Bool] = Map([])
  for key, id in var_keys {
    free[key] = @scope.declaration(g, id) is None
  }
  free
}

///|
/// Per-Unbound status from the scope graph: scope creates a Ref with
/// resolution.decl = None for every Unbound, so it's always "unresolved".
/// Returns true when the scope graph has a Ref for this Unbound node AND
/// that Ref is unresolved (decl = None). False when the scope graph does not
/// record a Ref (should not happen after builder pass 3).
fn scope_unbound_has_unresolved_ref(
  g : @scope.ScopeGraph,
  unbound_keys : Map[String, @core.NodeId],
) -> Map[String, Bool] {
  let status : Map[String, Bool] = Map([])
  for key, id in unbound_keys {
    let has_ref = g.refs.iter().any(fn(r) { r.node_id == id })
    let unresolved = g.refs
      .iter()
      .any(fn(r) { r.node_id == id && r.resolution.decl is None })
    status[key] = has_ref && unresolved
  }
  status
}

/// ---------------------------------------------------------------------------
/// Helpers: free_vars scoping rules mirrored as a ProjNode walk
/// ---------------------------------------------------------------------------

///|
/// Walk a ProjNode tree applying the same scoping rules as `free_vars.mbt`,
/// recording per-Var free status. `env` is the set of names bound at this
/// position. A Var not in `env` is free (true); bound otherwise (false).
/// Unbound nodes are NOT recorded here — they are not Vars and free_vars
/// returns empty for them.
fn free_vars_per_var_go(
  node : @core.ProjNode[@ast.Term],
  env : @immut/hashset.HashSet[String],
  result : Map[@core.NodeId, Bool],
) -> Unit {
  match node.kind {
    @ast.Term::Var(x) => result[node.id()] = !env.contains(x)
    @ast.Term::Lam(param, _) => {
      let inner_env = env.add(param)
      for child in node.children {
        free_vars_per_var_go(child, inner_env, result)
      }
    }
    @ast.Term::Module(defs, _) => {
      let mut cur_env = env
      // children[0..defs.length()) are LetDef nodes; each LetDef has one child (init).
      // children[defs.length()] is the body.
      for i in 0..<defs.length() {
        // Walk the def's init expression with current env, then add def name to env.
        free_vars_per_var_go(node.children[i].children[0], cur_env, result)
        cur_env = cur_env.add(defs[i].0)
      }
      free_vars_per_var_go(node.children[defs.length()], cur_env, result)
    }
    @ast.Term::LetDef(_, _) =>
      for child in node.children {
        free_vars_per_var_go(child, env, result)
      }
    // Structural: App, Bop, If all descend with same env.
    _ =>
      for child in node.children {
        free_vars_per_var_go(child, env, result)
      }
  }
}

///|
/// Run the free_vars walk over the ProjNode root and return per-Var free status
/// by NodeId. When `registry` is supplied it is reused; otherwise a fresh
/// registry is built from the root tree.
fn free_vars_per_var(
  root : @core.ProjNode[@ast.Term],
  registry? : Map[@core.NodeId, @core.ProjNode[@ast.Term]]? = None,
) -> (Map[@core.NodeId, Bool], @immut/hashset.HashSet[String]) {
  let per_node : Map[@core.NodeId, Bool] = Map([])
  free_vars_per_var_go(root, @immut/hashset.new(), per_node)
  let mut free_names : @immut/hashset.HashSet[String] = @immut/hashset.new()
  let reg = match registry {
    Some(r) => r
    None => {
      let m : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
      @core.collect_registry(root, m)
      m
    }
  }
  for id, is_free in per_node {
    guard is_free else { continue }
    guard reg.get(id) is Some(var_node) else { continue }
    if var_node.kind is @ast.Term::Var(name) {
      free_names = free_names.add(name)
    }
  }
  (per_node, free_names)
}

/// ---------------------------------------------------------------------------
/// Helpers: comparison and assertion
/// ---------------------------------------------------------------------------

///|
/// Assert that free_vars walk and scope graph agree on free/bound status for
/// every Var in the fixture. Per-occurrence comparison is strictly stronger
/// than name-set comparison (identical per-key status implies identical name
/// sets), so this is the only check needed.
fn assert_free_var_agreement(source : String, label~ : String) -> Unit raise {
  let (proj, registry, g) = build_oracle(source)
  let var_keys = collect_var_keys(registry)
  let scope_free = scope_free_map(g, var_keys)
  let (fv_per_node, _fv_free_names) = free_vars_per_var(
    proj,
    registry=Some(registry),
  )

  for key, id in var_keys {
    guard fv_per_node.get(id) is Some(fv_is_free) else {
      fail(
        "[\{label}] Var \{key} in registry but missing from free_vars per-node map",
      )
    }
    let sg_is_free = scope_free.get(key).unwrap()
    guard fv_is_free == sg_is_free else {
      fail("[\{label}] Var \{key}: free_vars=\{fv_is_free} scope=\{sg_is_free}")
    }
  }
}

///|
/// Cross-check: `free_vars` on the raw `@ast.Term` produced by the parser
/// agrees with `free_vars_per_var` on the ProjNode tree derived from the same
/// parse. If these diverge the ProjNode walk is not a faithful mirror.
fn assert_name_set_agrees_with_direct_free_vars(
  source : String,
  label~ : String,
) -> Unit raise {
  let (proj, registry, _g) = build_oracle(source)
  let fv_from_walk = free_vars(proj.kind, @immut/hashset.new())
  let (_per_node, fv_from_proj) = free_vars_per_var(
    proj,
    registry=Some(registry),
  )
  inspect(fv_from_walk == fv_from_proj, content="true")
}

/// ---------------------------------------------------------------------------
/// Tests: free_vars vs scope graph — per-occurrence agreement
/// ---------------------------------------------------------------------------

///|
test "diff: simple free Var agrees" {
  // x — a single Var with no binder anywhere.
  assert_free_var_agreement("x", label="simple-free")
  assert_name_set_agrees_with_direct_free_vars("x", label="simple-free")
}

///|
test "diff: Lambda param binds Var" {
  // (x) => x — the inner x is bound by the lambda param.
  assert_free_var_agreement("(x) => x", label="lam-binds")
  assert_name_set_agrees_with_direct_free_vars("(x) => x", label="lam-binds")
}

///|
test "diff: Module def binds body Var" {
  // let x = 0\nx — body x bound by def 0.
  assert_free_var_agreement("let x = 0\nx", label="module-def-binds")
  assert_name_set_agrees_with_direct_free_vars(
    "let x = 0\nx",
    label="module-def-binds",
  )
}

///|
test "diff: Def init cannot see own name" {
  // let x = x\nx — init x is free (def not yet in scope); body x is bound.
  assert_free_var_agreement("let x = x\nx", label="self-ref-init")
  assert_name_set_agrees_with_direct_free_vars(
    "let x = x\nx",
    label="self-ref-init",
  )
}

///|
test "diff: Sequential module visibility" {
  // let x = 0\nlet y = x\ny — y's init sees x; body sees both.
  assert_free_var_agreement(
    "let x = 0\nlet y = x\ny",
    label="sequential-module",
  )
  assert_name_set_agrees_with_direct_free_vars(
    "let x = 0\nlet y = x\ny",
    label="sequential-module",
  )
}

///|
test "diff: Earlier def cannot see later def" {
  // let x = y\nlet y = 0\nx — y in x's init is free; body x is bound.
  assert_free_var_agreement("let x = y\nlet y = 0\nx", label="later-invisible")
  assert_name_set_agrees_with_direct_free_vars(
    "let x = y\nlet y = 0\nx",
    label="later-invisible",
  )
}

///|
test "diff: Nested lambdas shadow" {
  // (x) => (x) => x — innermost x bound by inner lambda.
  assert_free_var_agreement("(x) => (x) => x", label="nested-lam")
  assert_name_set_agrees_with_direct_free_vars(
    "(x) => (x) => x",
    label="nested-lam",
  )
}

///|
test "diff: Lambda param shadows module def" {
  // let x = 0\n(x) => x — inner x bound by lambda param, not module def.
  assert_free_var_agreement("let x = 0\n(x) => x", label="lam-shadows-module")
  assert_name_set_agrees_with_direct_free_vars(
    "let x = 0\n(x) => x",
    label="lam-shadows-module",
  )
}

///|
test "diff: Shadowed module def resolution" {
  // let x = 0\nlet x = 1\nx — body x bound by later def (index 1).
  assert_free_var_agreement(
    "let x = 0\nlet x = 1\nx",
    label="shadowed-def-later",
  )
  assert_name_set_agrees_with_direct_free_vars(
    "let x = 0\nlet x = 1\nx",
    label="shadowed-def-later",
  )
}

///|
test "diff: Later duplicate def init sees earlier def" {
  // let x = 0\nlet x = x\nx
  // def 1's init `x` sees def 0 (cutoff = 1); body `x` sees def 1.
  assert_free_var_agreement(
    "let x = 0\nlet x = x\nx",
    label="dup-def-init-sees-earlier",
  )
  assert_name_set_agrees_with_direct_free_vars(
    "let x = 0\nlet x = x\nx",
    label="dup-def-init-sees-earlier",
  )
}

///|
test "diff: Free name propagates through compound terms" {
  // (f x) — both f and x are free.
  assert_free_var_agreement("(f x)", label="app-free")
  assert_name_set_agrees_with_direct_free_vars("(f x)", label="app-free")
}

///|
test "diff: Mixed bound and free in App" {
  // let f = 0\n(f x) — f bound, x free.
  assert_free_var_agreement("let f = 0\n(f x)", label="app-mixed")
  assert_name_set_agrees_with_direct_free_vars(
    "let f = 0\n(f x)",
    label="app-mixed",
  )
}

///|
test "diff: If collects free from all branches" {
  // (if a then b else c) — a, b, c all free.
  assert_free_var_agreement("(if a then b else c)", label="if-free")
  assert_name_set_agrees_with_direct_free_vars(
    "(if a then b else c)",
    label="if-free",
  )
}

///|
test "diff: Bop collects free from both operands" {
  // a + b — a, b free.
  assert_free_var_agreement("a + b", label="bop-free")
  assert_name_set_agrees_with_direct_free_vars("a + b", label="bop-free")
}

/// ---------------------------------------------------------------------------

///|
/// Unbound divergence: scope graph creates an unresolved Ref for every Unbound
/// node, while free_vars returns empty (Unbound is not a Var).
/// The Lambda parser never produces Unbound from text — Unbound only arises from
/// alpha reification — so we construct the ProjNode tree by hand.
test "diff: Unbound divergence — scope tracks it, free_vars ignores it" {
  let c = Ref(0)
  fn leaf(kind, start, end) -> @core.ProjNode[@ast.Term] {
    @core.ProjNode(kind, start, end, @core.next_proj_node_id(c), [])
  }
  fn branch(kind, start, end, children) -> @core.ProjNode[@ast.Term] {
    @core.ProjNode(kind, start, end, @core.next_proj_node_id(c), children)
  }
  // Module([("x", Unbound("?"))], Var("x")) — Unbound in def init, Var in body.
  let root = branch(
    @ast.Term::Module([("x", @ast.Term::Unbound("?"))], @ast.Term::Var("x")),
    0,
    7,
    [
      branch(@ast.Term::LetDef("x", @ast.Term::Unbound("?")), 0, 6, [
        leaf(@ast.Term::Unbound("?"), 0, 1),
      ]),
      leaf(@ast.Term::Var("x"), 6, 7),
    ],
  )
  let sm = SourceMap::from_ast(root)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(root, registry)
  let g = @scope.build(registry, sm)

  // Scope graph should have an unresolved Ref for the Unbound.
  let unbound_keys = collect_unbound_keys(registry)
  inspect(unbound_keys.length() > 0, content="true")
  for _key, has_unresolved in scope_unbound_has_unresolved_ref(g, unbound_keys) {
    inspect(has_unresolved, content="true")
  }

  // Var x in the body is bound by def 0 — should resolve per scope.
  let var_keys = collect_var_keys(registry)
  inspect(var_keys.length() > 0, content="true")
  for _key, id in var_keys {
    inspect(@scope.declaration(g, id) is Some(_), content="true")
  }

  // free_vars on raw Term: Unbound ignored, Var x is bound → empty set.
  let fv = free_vars(root.kind, @immut/hashset.new())
  inspect(fv.length(), content="0")
}

/// ---------------------------------------------------------------------------
/// Tests: module-end name resolution comparison
/// ---------------------------------------------------------------------------

/// ---------------------------------------------------------------------------
/// Tests: module-end resolution via graph-owned query
/// ---------------------------------------------------------------------------

///|
/// Verify `@scope.declaration_for_name_at_module_end` produces the expected
/// results. These replace the old-vs-new comparison (which pinned agreement
/// with the now-deleted duplicate resolver).

///|
test "diff module-end: root def visible" {
  let (proj, _registry, g) = build_oracle("let x = 0\n0")
  guard @scope.declaration_for_name_at_module_end(g, proj.id(), "x")
    is Some(decl)
  guard decl.kind is @scope.DeclKind::ModuleDef(def_index~)
  inspect(def_index, content="0")
}

///|
test "diff module-end: later def shadows earlier" {
  let (proj, _registry, g) = build_oracle("let x = 0\nlet x = 1\n0")
  guard @scope.declaration_for_name_at_module_end(g, proj.id(), "x")
    is Some(decl)
  guard decl.kind is @scope.DeclKind::ModuleDef(def_index~)
  inspect(def_index, content="1")
}

///|
test "diff module-end: name not bound" {
  let (proj, _registry, g) = build_oracle("let x = 0\nx")
  inspect(
    @scope.declaration_for_name_at_module_end(g, proj.id(), "y") is None,
    content="true",
  )
}

///|
test "diff module-end: block-local NOT visible at root" {
  // let outer = 1\n(let inner = outer\ninner)\nouter
  // "inner" is block-local; not visible at root module end.
  let source = "let outer = 1\n(let inner = outer\ninner)\nouter"
  let (proj, _registry, g) = build_oracle(source)
  inspect(
    @scope.declaration_for_name_at_module_end(g, proj.id(), "inner") is None,
    content="true",
  )
  inspect(
    @scope.declaration_for_name_at_module_end(g, proj.id(), "outer") is Some(_),
    content="true",
  )
}

/// ---------------------------------------------------------------------------
/// Tests: nested block (Module expr) visibility
/// ---------------------------------------------------------------------------

///|
test "diff: Nested block def binds inner body Var" {
  // let x = { let y = 1\ny }\nx
  // Outer: x bound, body x refers to outer x.
  // Inner block: y bound inside, body y refers to inner y.
  // Note: { let y ... } syntax may not be valid lambda — use explicit block.
  // Outer x is free from the block body's perspective (no x in block scope).
  // So scope should say the block body's y is bound; the outer body's x is bound.
  assert_free_var_agreement("let x = (let y = 1\ny)\nx", label="nested-block")
}

///|
test "diff: Block-local def not visible at root module end" {
  // let outer = 1\n(let inner = outer\ninner)\nouter
  // Root module-end query for "inner" should be None (block-local).
  let source = "let outer = 1\n(let inner = outer\ninner)\nouter"
  let (proj, _registry, g) = build_oracle(source)

  // module-end query for "inner" at root level: NOT visible (block-local).
  let result = @scope.declaration_for_name_at_module_end(g, proj.id(), "inner")
  inspect(result is None, content="true")

  // module-end query for "outer" at root level: visible.
  let outer_result = @scope.declaration_for_name_at_module_end(
    g,
    proj.id(),
    "outer",
  )
  inspect(outer_result is Some(_), content="true")
}

///|
test "diff: Same-name root and block binding" {
  // let x = 0\n(let x = 1\nx)\nx
  // Block body x → block-local def (index 0 in block scope).
  // Root body x → root def (index 0 in root scope).
  // free_vars and scope graph should agree both x's are bound.
  assert_free_var_agreement(
    "let x = 0\n(let x = 1\nx)\nx",
    label="same-name-root-and-block",
  )
}
