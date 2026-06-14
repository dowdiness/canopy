// Failing tests for docs/TODO.md §20 "Teach edits/ resolvers about nested-block
// scopes". RFA Step 1 (#636) made the scope-graph builder model nested-block
// (`Module`) scopes, and #645 taught rename. Inline still converts the
// block-aware `@scope.Decl` back to a root-relative `def_index`, so a block-local
// binding is mis-resolved against the root module's `defs`.
//
// Two independent unsoundnesses, one test each:
//   A — def lookup: `module_projection.defs[def_index]` reads the ROOT def at a
//       block-relative index (root def wins at a shared index).
//   B — capture analysis: `def_cutoff_at_node` applies ONE root-relative cutoff
//       to every module scope on the chain, so a free var in the inlined init is
//       resolved with the wrong cutoff at the nested use site.
//
// Both navigate the ProjNode tree structurally (confirmed layout); assertions are
// substring-based so they are robust to inline whitespace normalization.

///|
/// Problem A. A block-local `x` shadows a root `x` at the SAME def_index (0).
/// Inlining the block-local `x` must use the BLOCK init (`2`) and delete the
/// BLOCK binding — never the root def at index 0.
///
/// Buggy path: `@scope.declaration` resolves the body `x` to the block-local
/// decl `ModuleDef(def_index=0)`, then `module_projection.defs[0]` yields the
/// ROOT `x` (init `1`); `module_def_references(g, 0)` matches the first decl at
/// index 0 (also root). Result deletes `let x = 1` and inlines `1` — the root
/// binding is destroyed and the wrong value substituted.
test "InlineDefinition: block-local binding does not resolve to root def at shared index" {
  let text = "let x = 1\nlet y = { let x = 2\n  x }\ny"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  // proj.children = [LetDef(x), LetDef(y), body Var(y)]
  // let_y.children[0] = block Module; block.children = [LetDef(x), body Var(x)]
  let block = proj.children[1].children[0]
  let block_body_x = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=block_body_x.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Sound: root `let x = 1` survives; the block binding `let x = 2` is the
      // one removed by the sole-usage inline.
      let sound = new_text.contains("let x = 1") &&
        !new_text.contains("let x = 2")
      inspect(sound, content="true")
    }
    Ok(None) => fail("expected inline edits, got None")
    Err(e) => fail("expected inline edits, got Err: " + e)
  }
}

///|
/// Problem B. The inlined init carries a free var whose resolution depends on the
/// per-scope cutoff. The block-local `b = a` is inlined into the block body; its
/// free `a` must resolve to the block-local `a` at the use site exactly as it did
/// at the binding site, so the inline is SOUND and must be allowed.
///
/// Buggy path (after Problem A is fixed): `def_cutoff_at_node` for the block body
/// finds the ROOT def whose range contains it — root def 0 (`r`) — so the cutoff
/// is 0 and is wrongly applied to the BLOCK scope too. With cutoff 0 the block's
/// own `a` (block-index 0) is gated out (`0 < 0` is false), so `a` resolves to
/// None at the target while it resolves to the block-local `a` at the source.
/// The capture check therefore sees a spurious rebind and REJECTS a sound inline.
/// Passing requires resolving `a` with the block's own cutoff (the builder's
/// per-(node,scope) `node_cutoffs`), not a single root cutoff.
test "InlineDefinition: free var in block-local init keeps its nested-scope resolution" {
  let text = "let r = { let a = 1\n  let b = a\n  b }\nlet z = 0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  // proj.children = [LetDef(r), LetDef(z), body]
  // r.children[0] = block Module; block.children = [LetDef(a), LetDef(b), body Var(b)]
  let block = proj.children[0].children[0]
  let block_body_b = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=block_body_b.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Sound: `b` is inlined to `a` and its binding removed; `a` and `z` bindings
      // are untouched. (A spurious capture rejection returns Err, failing below.)
      let sound = new_text.contains("let a = 1") &&
        new_text.contains("let z = 0") &&
        !new_text.contains("let b")
      inspect(sound, content="true")
    }
    Ok(None) => fail("expected inline edits, got None")
    Err(e) =>
      fail("expected inline edits (sound inline wrongly rejected): " + e)
  }
}

///|
/// Problem B, occurrence filter. The inlined init `g + { let g = 1\n  g }` has a
/// FREE `g` (resolving to the root `g`) and a block-local `g` bound inside a
/// nested block in the init. Only the free `g` can rebind; the block-local one is
/// unaffected by the move. The old capture check enumerated occurrences with
/// `collect_var_usages`, which stops at lambda shadowing but NOT nested-`Module`
/// shadowing, so it visited the block-local `g`, saw it resolve differently from
/// the target, and falsely REJECTED a sound inline. The subtree filter excludes
/// occurrences bound inside the init, so the inline is allowed.
test "InlineDefinition: nested-block shadow inside an inlined init is not a false capture" {
  let text = "let g = 5\nlet f = g + { let g = 1\n  g }\nf"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let body_f = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body_f.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Sound: the init is inlined (so a `+` appears in the body) and the root
      // `g` binding is untouched. The block-local `g` must not cause a rejection.
      let sound = new_text.contains("let g = 5") && new_text.contains("+")
      inspect(sound, content="true")
    }
    Ok(None) => fail("expected inline edits, got None")
    Err(e) => fail("expected inline edits (false nested-block capture): " + e)
  }
}

///|
/// Capability extension. Binding ops entered via the root-only `find_def_index`,
/// which returned `Err` for a block-local binder. Resolving the binder to its
/// scope-graph decl lets duplicate REACH a block-local `x`: the copy is inserted
/// INSIDE the block (a second binding), not rejected and not placed at root.
///
/// We assert only that block-scoped insertion (this PR's contribution) by
/// re-parsing and counting the block's bindings. We do NOT assert the copy's name
/// or the re-parsed body: the `_copy` suffix is not lexable in this language, so
/// the output does not round-trip — a pre-existing, all-bindings defect tracked
/// in #649. The count survives that fix (it stays two bindings).
test "DuplicateBinding: reaches a block-local binding (copy inserted in the block)" {
  let text = "let y = { let x = 1\n  x }\ny"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  // proj.children[0] = LetDef(y); .children[0] = block; .children[0] = LetDef(x)
  let block_let_x = proj.children[0].children[0].children[0]
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=block_let_x.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      let (np, _) = parse_to_proj_node(new_text)
      // np.children[0] = LetDef(y); .children[0] = block (y's init).
      let block_defs = np.children[0].children[0].children
        .iter()
        .filter(fn(c) { c.kind is @ast.Term::LetDef(_, _) })
        .count()
      inspect(block_defs, content="2")
    }
    Ok(None) => fail("expected duplicate edits, got None")
    Err(e) => fail("expected duplicate edits on block-local binding: " + e)
  }
}

///|
/// Extract inserts the new `let` at the ROOT module, so extracting an expression
/// that references a BLOCK-LOCAL binding must be rejected — at root the name is
/// unbound, so the extracted let would change meaning. The capture check resolves
/// the free name at root-module-end (`resolve_at_module_root_end` → None for a
/// block-local) and sees the rebind. Guards the extract path's module-end target.
test "ExtractToLet: rejects extracting an expression that captures a block-local binding" {
  let text = "let r = { let a = 1\n  a + a }\nlet z = 0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  // proj.children[0] = LetDef(r); .children[0] = block;
  // block.children = [LetDef(a), body Bop(a + a)]
  let block = proj.children[0].children[0]
  let block_body = block.children[block.children.length() - 1]
  let result = compute_text_edit(
    ExtractToLet(node_id=block_body.id(), var_name="t"),
    make_edit_ctx(text, source_map, registry, fp),
  )
  inspect(result is Err(_), content="true")
}

///|
/// Capability extension. Move-up resolves the binder block-locally and swaps
/// same-scope siblings (`sibling_def_decl`), so a block-local binding moves within
/// its own block. Under the old root-only `find_def_index` this returned `Err`.
test "MoveBindingUp: swaps two block-local bindings" {
  let text = "let r = { let a = 1\n  let b = 2\n  a }\nlet z = 0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  // block.children = [LetDef(a), LetDef(b), body Var(a)]
  let block = proj.children[0].children[0]
  let block_let_b = block.children[1]
  let result = compute_text_edit(
    MoveBindingUp(binding_node_id=block_let_b.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Assert the re-parsed STRUCTURE, not the byte text: `b` now precedes `a`
      // within the block and the root stays `[r, z]`. The position-based span
      // swap leaves malformed leading indentation (cosmetic — re-parses to 0
      // errors, correct AST), tracked in #650; a structure assertion survives
      // that fix where a byte snapshot would not.
      let (np, _) = parse_to_proj_node(new_text)
      let label = fn(c : ProjNode[@ast.Term]) -> String {
        match c.kind {
          @ast.Term::LetDef(n, _) => "def:" + n
          @ast.Term::Var(v) => "var:" + v
          _ => "other"
        }
      }
      let root = np.children.map(label)
      let block = np.children[0].children[0].children.map(label)
      inspect(
        root.join(",") + " | " + block.join(","),
        content="def:r,def:z,other | def:b,def:a,var:a",
      )
    }
    Ok(None) => fail("expected move edits, got None")
    Err(e) => fail("expected move on block-local binding: " + e)
  }
}

///|
/// Capability extension. InlineAllUsages resolves the binder block-locally and
/// reads its references via `@scope.references(g, decl.id)`, so a block-local
/// binding's uses are inlined without conflation with a root def at the same index.
test "InlineAllUsages: works on a block-local binding" {
  let text = "let r = { let a = 1\n  a + a }\nlet z = 0"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = ModuleProjection::from_proj_node(proj)
  let block = proj.children[0].children[0]
  let block_let_a = block.children[0]
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=block_let_a.id()),
    make_edit_ctx(text, source_map, registry, fp),
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // The block binding is gone and its uses replaced by `1`; root `z` untouched.
      let inlined = !new_text.contains("let a = 1") &&
        new_text.contains("1") &&
        new_text.contains("let z = 0")
      inspect(inlined, content="true")
    }
    Ok(None) => fail("expected inline-all edits, got None")
    Err(e) => fail("expected inline-all on block-local binding: " + e)
  }
}
