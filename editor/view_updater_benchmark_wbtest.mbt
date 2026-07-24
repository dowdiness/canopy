// ViewNode serialization benchmark — validates JSON transport performance.
// Drives the generic editor/protocol serialization + patch path (which this
// package owns) over a realistically *nested* TestExpr tree, so the numbers
// reflect a representative projection rather than a flat token stream.
//
// Each "def" emits `def{i}(add{i}(x{i} n{i}))`, which the neutral grammar folds
// to Branch("def{i}", [Branch("add{i}", [Leaf("x{i}"), Leaf("n{i}")])]) — a
// name + nested body, mirroring the shape (not the meaning) of a language
// definition. Feeding lambda syntax here would parse as loose
// identifiers/gaps under the neutral grammar and measure the wrong tree.

///|
fn bench_source(def_count : Int) -> String {
  let segments : Array[String] = []
  for i in 0..<def_count {
    segments.push("def\{i}(add\{i}(x\{i} n\{i}))")
  }
  segments.push("f0")
  segments.join("\n")
}

///|
fn bench_setup(let_count : Int) -> @protocol.ViewNode {
  let editor = try! @probe.new_test_editor("bench")
  editor.set_text(bench_source(let_count))
  let proj_node = editor.get_proj_node().unwrap()
  let source_map = editor.get_source_map()
  @protocol.proj_to_view_node(proj_node, source_map)
}

///|
test "viewnode serialization (100 defs)" (b : @bench.T) {
  let view_node = bench_setup(100)
  let node_count = view_node.node_count()
  println("node count: \{node_count}")
  b.bench(() => {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "viewnode serialization (200 defs)" (b : @bench.T) {
  let view_node = bench_setup(200)
  let node_count = view_node.node_count()
  println("node count: \{node_count}")
  b.bench(() => {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "viewnode serialization (500 defs)" (b : @bench.T) {
  let view_node = bench_setup(500)
  let node_count = view_node.node_count()
  println("node count: \{node_count}")
  b.bench(() => {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "compute_view_patches (100 defs, single edit)" (b : @bench.T) {
  let editor = try! @probe.new_test_editor("bench")
  editor.set_text(bench_source(100))
  let state = ViewUpdateState::ViewUpdateState()
  // Initial full tree
  let _ = compute_view_patches(state, editor)
  // Benchmark: single character edit + patch computation
  b.bench(() => {
    editor.set_text(bench_source(100))
    b.keep(compute_view_patches(state, editor))
  })
}
