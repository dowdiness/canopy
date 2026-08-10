///|
fn resolve_benchmark_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    let number = index.to_string()
    "## Heading " +
    number +
    "\n\nParagraph " +
    number +
    " with **bold** and [link](https://example.com/" +
    number +
    ").\n"
  }).join("\n")
}

///|
fn resolve_benchmark_middle_edit(source : String, block_count : Int) -> String {
  let target = "Paragraph " + (block_count / 2).to_string() + " with"
  match source.find(target) {
    Some(position) =>
      source[:position].to_owned() +
      "Paragraph 125 changed" +
      source[position + target.length():].to_owned()
    None => abort("resolve benchmark target not found")
  }
}

///|
test "perf: resolve known ASCII edit fast path (250 blocks)" (b : @bench.T) {
  let old_source = resolve_benchmark_source(250)
  let new_source = resolve_benchmark_middle_edit(old_source, 250)
  let known_edit = compute_edit(old_source, new_source)
  b.bench(() => {
    let resolved = try! resolve_applied_edit(
      old_source,
      new_source,
      Some(known_edit),
    )
    b.keep(resolved)
  })
}

///|
test "perf: resolve divergent edit fallback (250 blocks)" (b : @bench.T) {
  let old_source = resolve_benchmark_source(250)
  let new_source = resolve_benchmark_middle_edit(old_source, 250)
  let divergent_source = "Q" + new_source
  let known_edit = compute_edit(old_source, new_source)
  b.bench(() => {
    let resolved = try! resolve_applied_edit(
      old_source,
      divergent_source,
      Some(known_edit),
    )
    b.keep(resolved)
  })
}
