// Whitebox tests for the `failures()` derived view. Reuses `build_fixture`
// from `graph_wbtest.mbt` (same whitebox test module).

///|
test "failures: free variable is surfaced with a populated witness" {
  let (_proj, registry, source_map) = build_fixture("(x) => y")
  let g = build(registry, source_map)
  let fs = failures(g, source_map)
  inspect(fs.length(), content="1")
  inspect(fs[0].name, content="y")
  // y was searched against the lambda-param scope and the root scope and bound
  // by neither — the witness records that negative observation.
  inspect(fs[0].witness.length() >= 1, content="true")
  inspect(fs[0].location is Some(_), content="true")
}

///|
test "failures: a fully-resolved program has no failures" {
  let (_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet y = x\nx + y",
  )
  let g = build(registry, source_map)
  inspect(failures(g, source_map).length(), content="0")
}

///|
test "failures: self-reference in a def init is a reachable failure" {
  let (_proj, registry, source_map) = build_fixture("let x = x\nx")
  let g = build(registry, source_map)
  let fs = failures(g, source_map)
  // The init `x` cannot see its own not-yet-bound def (sequential cutoff); the
  // body `x` resolves. Exactly one failure, and it is the init reference.
  inspect(fs.length(), content="1")
  inspect(fs[0].name, content="x")
}

// ── diff ─────────────────────────────────────────────────────────────────────

///|
test "diff: rebuild with identical source gives empty diff (non-spurious)" {
  // Two independent builds of the same text must produce identical keys so the
  // diff is empty — the acceptance criterion for semantics-preserving rebuilds.
  let (_p1, reg1, sm1) = build_fixture("(x) => y")
  let g1 = build(reg1, sm1)
  let (_p2, reg2, sm2) = build_fixture("(x) => y")
  let g2 = build(reg2, sm2)
  let d = diff(failures(g1, sm1), failures(g2, sm2))
  inspect(d.newly_reachable.length(), content="0")
  inspect(d.resolved.length(), content="0")
}

///|
test "diff: introducing a free variable appears in newly_reachable" {
  let (_p1, reg1, sm1) = build_fixture("(x) => x")
  let g1 = build(reg1, sm1)
  let (_p2, reg2, sm2) = build_fixture("(x) => y")
  let g2 = build(reg2, sm2)
  let d = diff(failures(g1, sm1), failures(g2, sm2))
  inspect(d.newly_reachable.length(), content="1")
  inspect(d.newly_reachable[0].name, content="y")
  inspect(d.resolved.length(), content="0")
}

///|
test "diff: fixing a free variable appears in resolved" {
  let (_p1, reg1, sm1) = build_fixture("(x) => y")
  let g1 = build(reg1, sm1)
  let (_p2, reg2, sm2) = build_fixture("(x) => x")
  let g2 = build(reg2, sm2)
  let d = diff(failures(g1, sm1), failures(g2, sm2))
  inspect(d.newly_reachable.length(), content="0")
  inspect(d.resolved.length(), content="1")
  inspect(d.resolved[0].name, content="y")
}

///|
test "diff: simultaneous introduce and fix" {
  // Rename: free variable changes from `y` to `z`. Both sides are non-empty.
  let (_p1, reg1, sm1) = build_fixture("(x) => y")
  let g1 = build(reg1, sm1)
  let (_p2, reg2, sm2) = build_fixture("(x) => z")
  let g2 = build(reg2, sm2)
  let d = diff(failures(g1, sm1), failures(g2, sm2))
  inspect(d.newly_reachable.length(), content="1")
  inspect(d.newly_reachable[0].name, content="z")
  inspect(d.resolved.length(), content="1")
  inspect(d.resolved[0].name, content="y")
}

///|
test "diff: None-location key falls back to name; same name collapses" {
  // Exercises the `None => "?:\{name}"` branch of failure_key.
  // Two location-less failures with the same name hash to the same key and are
  // treated as the same failure — the known limitation documented in failure_key.
  let f_before = ReachableFailure(name="x", location=None, witness=[])
  let f_after = ReachableFailure(name="x", location=None, witness=[ScopeId(1)])
  let d = diff([f_before], [f_after])
  inspect(d.newly_reachable.length(), content="0")
  inspect(d.resolved.length(), content="0")
}
