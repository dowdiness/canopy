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
