///|
fn parse_syntax(text : String) -> @seam.SyntaxNode {
  let (cst, _) = @parser.parse_cst(text) catch { _ => abort("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "to_flat_proj: single expression" {
  let syntax = parse_syntax("42")
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="0")
  inspect(
    fp.final_expr.map(fn(n) { n.kind.to_string() }),
    content="Some(\"Int(42)\")",
  )
}

///|
test "to_flat_proj: single let def + expression" {
  let syntax = parse_syntax("let x = 1\nx")
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="1")
  inspect(fp.defs[0].0, content="x")
  inspect(fp.defs[0].1.kind, content="Int(1)")
  inspect(
    fp.final_expr.map(fn(n) { n.kind.to_string() }),
    content="Some(\"Var(\\\"x\\\")\")",
  )
}

///|
test "to_flat_proj: multiple let defs" {
  let syntax = parse_syntax("let x = 1\nlet y = 2\nx + y")
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="2")
  inspect(fp.defs[0].0, content="x")
  inspect(fp.defs[1].0, content="y")
}

///|
test "to_flat_proj: no final expression defaults to None" {
  let syntax = parse_syntax("let x = 1\n")
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="1")
  inspect(fp.final_expr, content="None")
}

///|
test "to_flat_proj: empty document" {
  let syntax = parse_syntax("")
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="0")
  inspect(fp.final_expr, content="None")
}

///|
test "reconcile_flat_proj: unchanged defs preserve IDs" {
  let syntax = parse_syntax("let x = 1\nlet y = 2\nx")
  let counter = Ref::new(0)
  let old = to_flat_proj(syntax, counter)
  let old_ids = old.defs.map(fn(d) { d.3 })

  // Simulate reparse (same text, fresh IDs)
  let syntax2 = parse_syntax("let x = 1\nlet y = 2\nx")
  let new_fp = to_flat_proj(syntax2, counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  let new_ids = reconciled.defs.map(fn(d) { d.3 })
  inspect(new_ids == old_ids, content="true")
}

///|
test "reconcile_flat_proj: changed init gets reconciled children" {
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("let x = 1\nx"), counter)
  let old_id = old.defs[0].3

  let new_fp = to_flat_proj(parse_syntax("let x = 2\nx"), counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  // Def NodeId preserved (same name, same position)
  inspect(reconciled.defs[0].3 == old_id, content="true")
  // Init value changed
  inspect(reconciled.defs[0].1.kind, content="Int(2)")
}

///|
test "reconcile_flat_proj: insertion gets fresh ID" {
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("let x = 1\nx"), counter)
  let old_x_id = old.defs[0].3

  let new_fp = to_flat_proj(parse_syntax("let x = 1\nlet y = 2\nx"), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  inspect(reconciled.defs.length(), content="2")
  // x preserved
  inspect(reconciled.defs[0].3 == old_x_id, content="true")
  // y is new — different ID from old x
  inspect(reconciled.defs[1].3 != old_x_id, content="true")
}

///|
test "reconcile_flat_proj: final_expr reconciled" {
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("42"), counter)
  let old_final_id = old.final_expr.unwrap().node_id

  let new_fp = to_flat_proj(parse_syntax("99"), counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  // Same kind (Int) → old ID preserved
  inspect(
    reconciled.final_expr.unwrap().node_id == old_final_id,
    content="true",
  )
  // Value changed
  inspect(reconciled.final_expr.unwrap().kind, content="Int(99)")
}

///|
test "print_flat_proj: single expression" {
  let fp = to_flat_proj(parse_syntax("42"), Ref::new(0))
  inspect(print_flat_proj(fp), content="42")
}

///|
test "print_flat_proj: single let + expression" {
  let fp = to_flat_proj(parse_syntax("let x = 1\nx"), Ref::new(0))
  inspect(print_flat_proj(fp), content="let x = 1\nx")
}

///|
test "print_flat_proj: multiple lets" {
  let fp = to_flat_proj(
    parse_syntax("let x = 1\nlet y = 2\nx + y"),
    Ref::new(0),
  )
  inspect(print_flat_proj(fp), content="let x = 1\nlet y = 2\n(x + y)")
}

///|
test "print_flat_proj: defs only (no final expression)" {
  let fp = to_flat_proj(parse_syntax("let x = 1\n"), Ref::new(0))
  inspect(print_flat_proj(fp), content="let x = 1\n()")
}

///|
test "print_flat_proj: equivalence with print_term on nested spine" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let syntax = parse_syntax(text)
  let counter = Ref::new(0)
  let nested = to_proj_node(syntax, counter)
  let counter2 = Ref::new(0)
  let flat = to_flat_proj(parse_syntax(text), counter2)
  inspect(print_flat_proj(flat) == @ast.print_term(nested.kind), content="true")
}

///|
test "FlatProj::to_proj_node: single expression" {
  let fp = to_flat_proj(parse_syntax("42"), Ref::new(0))
  let proj = fp.to_proj_node(Ref::new(100))
  inspect(proj.kind, content="Int(42)")
}

///|
test "FlatProj::to_proj_node: let defs reconstruct Module" {
  let fp = to_flat_proj(
    parse_syntax("let x = 1\nlet y = 2\nx + y"),
    Ref::new(0),
  )
  let proj = fp.to_proj_node(Ref::new(100))
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1)), ("y", Int(2))], Bop(Plus, Var("x"), Var("y")))
    ),
  )
}

///|
test "FlatProj::to_proj_node: Module node gets fresh ID (not def ID)" {
  let fp = to_flat_proj(parse_syntax("let x = 1\nx"), Ref::new(0))
  let def_id = fp.defs[0].3
  let proj = fp.to_proj_node(Ref::new(100))
  // Module node gets a fresh counter ID, not the first def's stored ID
  inspect(proj.node_id == def_id.0, content="false")
}

///|
test "FlatProj::from_proj_node: extracts Module defs" {
  let (proj, _) = parse_to_proj_node("let x = 1\nlet y = 2\nx + y")
  let fp = FlatProj::from_proj_node(proj)
  inspect(fp.defs.length(), content="2")
  inspect(fp.defs[0].0, content="x")
  inspect(fp.defs[1].0, content="y")
}

///|
test "FlatProj::from_proj_node: single expression (no Module)" {
  let (proj, _) = parse_to_proj_node("42")
  let fp = FlatProj::from_proj_node(proj)
  inspect(fp.defs.length(), content="0")
}

///|
test "FlatProj roundtrip: to_flat_proj -> to_proj_node matches to_proj_node" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let counter1 = Ref::new(0)
  let nested = to_proj_node(parse_syntax(text), counter1)

  let counter2 = Ref::new(0)
  let flat = to_flat_proj(parse_syntax(text), counter2)
  let roundtripped = flat.to_proj_node(Ref::new(100))

  // Same structure (kind matches)
  inspect(
    @ast.print_term(roundtripped.kind) == @ast.print_term(nested.kind),
    content="true",
  )
}

///|
test "FlatProj roundtrip: from_proj_node -> to_proj_node preserves text" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let roundtripped = fp.to_proj_node(Ref::new(100))
  inspect(
    @ast.print_term(roundtripped.kind) == @ast.print_term(proj.kind),
    content="true",
  )
}

///|
test "reconcile_flat_proj: duplicate/shadowed names preserve correct IDs" {
  // old: let x = 1, let x = 2, x  →  new: let x = 1, let x = 2, x
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("let x = 1\nlet x = 2\nx"), counter)
  let old_id_0 = old.defs[0].3 // first x
  let old_id_1 = old.defs[1].3 // second x

  let new_fp = to_flat_proj(parse_syntax("let x = 1\nlet x = 2\nx"), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  // Both IDs preserved in correct positions
  inspect(reconciled.defs[0].3 == old_id_0, content="true")
  inspect(reconciled.defs[1].3 == old_id_1, content="true")
}

///|
test "reconcile_flat_proj: shadow with insertion preserves first x ID" {
  // old: [x=1], x  →  new: [x=1, x=2], x
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("let x = 1\nx"), counter)
  let old_x_id = old.defs[0].3

  let new_fp = to_flat_proj(parse_syntax("let x = 1\nlet x = 2\nx"), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  inspect(reconciled.defs.length(), content="2")
  // First x preserves old ID
  inspect(reconciled.defs[0].3 == old_x_id, content="true")
  // Second x gets a fresh ID (different from first)
  inspect(reconciled.defs[1].3 != old_x_id, content="true")
}

///|
test "reconcile_flat_proj: empty old defs" {
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("42"), counter)

  let new_fp = to_flat_proj(parse_syntax("let x = 1\n42"), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  inspect(reconciled.defs.length(), content="1")
  inspect(reconciled.defs[0].0, content="x")
}

///|
test "reconcile_flat_proj: empty new defs" {
  let counter = Ref::new(0)
  let old = to_flat_proj(parse_syntax("let x = 1\n42"), counter)

  let new_fp = to_flat_proj(parse_syntax("42"), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  inspect(reconciled.defs.length(), content="0")
}

///|
test "print_flat_proj: defs-only roundtrips through tree edit" {
  let text = "let x = 1\nlet y = 2\n"
  let fp = to_flat_proj(parse_syntax(text), Ref::new(0))
  let printed = print_flat_proj(fp)
  // Reconstruct via nested spine and verify equivalence
  let proj = fp.to_proj_node(Ref::new(100))
  inspect(printed == @ast.print_term(proj.kind), content="true")
}

///|
test "FlatProj::to_proj_node: Module node_id is stable across rebuilds" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let counter = Ref::new(0)
  let fp1 = to_flat_proj(parse_syntax(text), counter)
  let proj1 = fp1.to_proj_node(counter)
  let module_id_1 = proj1.node_id

  // Rebuild with same text — should preserve Module node_id when seeded
  let counter2 = Ref::new(counter.val)
  let fp2 = to_flat_proj(parse_syntax(text), counter2)
  let proj2 = fp2.to_proj_node_with_prev_module_id(counter2, Some(module_id_1))
  let module_id_2 = proj2.node_id

  inspect(module_id_1 == module_id_2, content="true")
}

///|
test "FlatProj::to_proj_node: Module node_id seeded None still allocates fresh" {
  let text = "let x = 1\nx"
  let counter = Ref::new(0)
  let fp = to_flat_proj(parse_syntax(text), counter)
  let proj = fp.to_proj_node_with_prev_module_id(counter, None)
  // Without seed: fresh ID allocated from counter (>=0, valid)
  inspect(proj.node_id >= 0, content="true")
}

///|
test "to_flat_proj_incremental: changed_indices records non-reused defs" {
  // NodeInterner deduplicates by structure: unchanged def x=1 gets the same
  // interned CstNode even across independent parses, so physical_equal = true.
  // Only the changed def (y=3 vs y=2) fails physical_equal → index 1 recorded.
  let counter = Ref::new(0)
  let old_root = parse_syntax("let x = 1\nlet y = 2\nx")
  let old_fp = to_flat_proj(old_root, counter)
  let new_root = parse_syntax("let x = 1\nlet y = 3\nx")
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    new_root,
    old_root,
    old_fp,
    counter,
    changed_indices=changed,
  )
  ignore(result)
  // x=1 is structurally identical → reused (not recorded)
  // y=3 differs from y=2 → not reused → index 1 recorded
  inspect(changed.val, content="[1]")
}

///|
test "to_flat_proj_incremental: same root means zero changed" {
  let counter = Ref::new(0)
  let root = parse_syntax("let x = 1\nlet y = 2\nx")
  let fp = to_flat_proj(root, counter)
  // Same SyntaxNode — physical_equal succeeds for all children
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    root,
    root,
    fp,
    counter,
    changed_indices=changed,
  )
  ignore(result)
  inspect(changed.val.length(), content="0")
}

///|
test "to_flat_proj_incremental: final_expr change recorded as -1" {
  let counter = Ref::new(0)
  let old_root = parse_syntax("let x = 1\n42")
  let old_fp = to_flat_proj(old_root, counter)
  let new_root = parse_syntax("let x = 1\n99")
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    new_root,
    old_root,
    old_fp,
    counter,
    changed_indices=changed,
  )
  ignore(result)
  // x=1 is structurally identical → reused (not recorded)
  // final_expr 99 differs from 42 → recorded as -1
  inspect(changed.val, content="[-1]")
}
