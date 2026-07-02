///|
/// Tests for `references_outside_subtree` and `declaration_for_name_at_module_end`
/// — the two graph-owned queries added in Plan C (#129) step 2.
/// Builds a ScopeGraph from parsed Lambda source, constructs subtree NodeId
/// sets, and verifies the query results against hand-derived expectations.

///|
/// Compute the full subtree NodeId set from a ProjNode root.
fn subtree_ids(
  root : @core.ProjNode[@ast.Term],
) -> @immut/hashset.HashSet[@core.NodeId] {
  let m : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, m)
  @immut/hashset.HashSet::from_iter(m.keys())
}
/// Tests: references_outside_subtree
/// ---------------------------------------------------------------------------

///|
test "references_outside_subtree: single free Var" {
  let (proj, registry, source_map) = build_fixture("x")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  inspect(result.length(), content="1")
  inspect(result[0].name, content="x")
  inspect(result[0].resolution.decl is None, content="true")
}

///|
test "references_outside_subtree: lambda param shadows — Var is inside" {
  // (x) => x — the Var x resolves to the LamParam inside the subtree.
  let (proj, registry, source_map) = build_fixture("(x) => x")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  inspect(result.length(), content="0")
}

///|
test "references_outside_subtree: module def — body Var is inside" {
  // let x = 0\nx — body x resolves to ModuleDef inside the subtree.
  let (proj, registry, source_map) = build_fixture("let x = 0\nx")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  inspect(result.length(), content="0")
}

///|
test "references_outside_subtree: self-referential init — one free, one bound" {
  // let x = x\nx — init x is unresolved (free), body x is bound.
  let (proj, registry, source_map) = build_fixture("let x = x\nx")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  // Exactly one ref outside: the init Var x (unresolved). Body Var x is inside.
  inspect(result.length(), content="1")
  inspect(result[0].name, content="x")
  inspect(result[0].resolution.decl is None, content="true")
}

///|
test "references_outside_subtree: mixed bound and free" {
  // let f = 0\n(f x) — f bound (inside), x free (outside).
  let (proj, registry, source_map) = build_fixture("let f = 0\n(f x)")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  inspect(result.length(), content="1")
  inspect(result[0].name, content="x")
}

///|
test "references_outside_subtree: earlier def cannot see later — free" {
  // let x = y\nlet y = 0\nx — y in first init is free (later def not yet visible).
  let (proj, registry, source_map) = build_fixture("let x = y\nlet y = 0\nx")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  inspect(result.length(), content="1")
  inspect(result[0].name, content="y")
}

///|
test "references_outside_subtree: nested lambda, outer is free" {
  // (x) => (y) => x + y — x in inner lambda body resolves to outer LamParam (IN
  // the subtree if outer Lam is inside subtree); y resolves to inner LamParam.
  // With the whole tree as subtree, both params are inside.
  let (proj, registry, source_map) = build_fixture("(x) => (y) => x + y")
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  // Both x and y resolve to lam params inside the tree — no outside refs.
  inspect(result.length(), content="0")
}

///|
test "references_outside_subtree: nested block — block-local is inside" {
  // let z = { let x = 1\nx }\nz
  // Block body x resolves to block-local def (inside the subtree).
  let (proj, registry, source_map) = build_fixture(
    "let z = { let x = 1\nx }\nz",
  )
  let g = build(registry, source_map)
  let ids = subtree_ids(proj)
  let result = references_outside_subtree(g, ids)
  // All refs resolve inside — z → def 0, x → block def.
  inspect(result.length(), content="0")
}

///|
test "references_outside_subtree: empty subtree" {
  let (_proj, registry, source_map) = build_fixture("let x = 0\nx")
  let g = build(registry, source_map)
  let empty : @immut/hashset.HashSet[@core.NodeId] = @immut/hashset.new()
  let result = references_outside_subtree(g, empty)
  inspect(result.length(), content="0")
}

///|
test "references_outside_subtree: subtree is just the body — def init refs excluded" {
  // let x = y\nlet y = 0\nx — subtree = only the body expression "x".
  // The body x resolves to def 0 (the first definition).
  // The init "y" in def 0 is NOT in this subtree.
  let (proj, registry, source_map) = build_fixture("let x = y\nlet y = 0\nx")
  let g = build(registry, source_map)
  let body = proj.children[proj.children.length() - 1]
  let body_ids = subtree_ids(body)
  let result = references_outside_subtree(g, body_ids)
  // body x resolves to def 0 (outside the body-only subtree) → it IS an outside ref.
  // This is the "free relative to subtree" semantics: from the body's perspective,
  // x is free.
  inspect(result.length(), content="1")
  inspect(result[0].name, content="x")
}

/// ---------------------------------------------------------------------------
/// Tests: declaration_for_name_at_module_end
/// ---------------------------------------------------------------------------

///|
test "declaration_for_name_at_module_end: root def visible" {
  let (proj, registry, source_map) = build_fixture("let x = 0\n0")
  let g = build(registry, source_map)
  guard declaration_for_name_at_module_end(g, proj.id(), "x") is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="0")
}

///|
test "declaration_for_name_at_module_end: name not bound" {
  let (proj, registry, source_map) = build_fixture("let x = 0\n0")
  let g = build(registry, source_map)
  inspect(
    declaration_for_name_at_module_end(g, proj.id(), "y") is None,
    content="true",
  )
}

///|
test "declaration_for_name_at_module_end: shadowed — later wins" {
  // let x = 0\nlet x = 1\n0 — at module end, x resolves to def 1.
  let (proj, registry, source_map) = build_fixture("let x = 0\nlet x = 1\n0")
  let g = build(registry, source_map)
  guard declaration_for_name_at_module_end(g, proj.id(), "x") is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="1")
}

///|
test "declaration_for_name_at_module_end: block-local NOT visible at root" {
  // let outer = 1\n(let inner = outer\ninner)\nouter
  // "inner" is block-local; not visible at root module end.
  let (proj, registry, source_map) = build_fixture(
    "let outer = 1\n(let inner = outer\ninner)\nouter",
  )
  let g = build(registry, source_map)
  inspect(
    declaration_for_name_at_module_end(g, proj.id(), "inner") is None,
    content="true",
  )
  // "outer" IS visible at root.
  inspect(
    declaration_for_name_at_module_end(g, proj.id(), "outer") is Some(_),
    content="true",
  )
}

///|
test "declaration_for_name_at_module_end: block module — block-local visible" {
  // let z = { let x = 1\nx }\nz
  // At the block's module end, x resolves to block-local def 0.
  // z is NOT visible here: the block is z's init, where z's own cutoff
  // excludes it (sequential scoping: a def can't see itself).
  let (proj, registry, source_map) = build_fixture(
    "let z = { let x = 1\nx }\nz",
  )
  let g = build(registry, source_map)
  let block = proj.children[0].children[0]
  guard declaration_for_name_at_module_end(g, block.id(), "x") is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="0")
  // z not visible — block is inside z's init, cutoff excludes own def.
  inspect(
    declaration_for_name_at_module_end(g, block.id(), "z") is None,
    content="true",
  )
}
