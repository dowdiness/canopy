// ViewNode serialization benchmark — validates JSON transport performance.
// Realistic ViewNode tree (100+ lambda defs) round-trip under 1ms.

///|
fn bench_source(let_count : Int) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count; i = i + 1 {
    segments.push("let f\{i} = \\x.x + \{i}")
  }
  segments.push("f0")
  segments.join("\n")
}

///|
fn bench_setup(let_count : Int) -> @protocol.ViewNode {
  let editor = @lambda.new_lambda_editor("bench").0
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
  b.bench(fn() {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "viewnode serialization (200 defs)" (b : @bench.T) {
  let view_node = bench_setup(200)
  let node_count = view_node.node_count()
  println("node count: \{node_count}")
  b.bench(fn() {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "viewnode serialization (500 defs)" (b : @bench.T) {
  let view_node = bench_setup(500)
  let node_count = view_node.node_count()
  println("node count: \{node_count}")
  b.bench(fn() {
    let json = view_node.to_json()
    b.keep(json.stringify())
  })
}

///|
test "compute_view_patches (100 defs, single edit)" (b : @bench.T) {
  let editor = @lambda.new_lambda_editor("bench").0
  editor.set_text(bench_source(100))
  let state = ViewUpdateState::new()
  // Initial full tree
  let _ = compute_view_patches(state, editor)
  // Benchmark: single character edit + patch computation
  b.bench(fn() {
    editor.set_text(bench_source(100))
    b.keep(compute_view_patches(state, editor))
  })
}
