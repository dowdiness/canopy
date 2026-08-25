///|
/// PROTOTYPE — the practical #1156 corpus without complete-source diff.
fn practical_text_edit_fixture() -> String {
  Array::makei(250, index => {
    let number = index.to_string()
    "## Heading " +
    number +
    "\n\nParagraph " +
    number +
    " with **bold**, [link](https://example.com/" +
    number +
    "), and 日本語 😀.\n"
  }).join("\n")
}

///|
priv enum BenchOperation {
  Insert
  Delete
  Replace
}

///|
fn bench_changes(
  source : String,
  blocks : Array[Int],
  operation : BenchOperation,
) -> Array[@text_change.TextChange] {
  blocks.map(block => {
    let marker = "Paragraph " + block.to_string()
    let start = source.find(marker).unwrap()
    match operation {
      Insert => { start, delete_len: 0, inserted: "x" }
      Delete => { start, delete_len: 1, inserted: "" }
      Replace => { start, delete_len: 1, inserted: "x" }
    }
  })
}

///|
fn measure_apply(
  b : @bench.T,
  blocks : Array[Int],
  operation : BenchOperation,
) -> Unit {
  let source = practical_text_edit_fixture()
  let changes = bench_changes(source, blocks, operation)
  let mut index = 0
  b.bench(() => {
    let change = changes[index % changes.length()]
    index += 1
    b.keep(apply_change(source, change))
  })
}

///|
test "range transition: insert near beginning" (b : @bench.T) {
  measure_apply(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Insert)
}

///|
test "range transition: insert near middle" (b : @bench.T) {
  measure_apply(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Insert)
}

///|
test "range transition: insert near end" (b : @bench.T) {
  measure_apply(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Insert)
}

///|
test "range transition: delete near beginning" (b : @bench.T) {
  measure_apply(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Delete)
}

///|
test "range transition: delete near middle" (b : @bench.T) {
  measure_apply(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Delete)
}

///|
test "range transition: delete near end" (b : @bench.T) {
  measure_apply(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Delete)
}

///|
test "range transition: replace near beginning" (b : @bench.T) {
  measure_apply(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Replace)
}

///|
test "range transition: replace near middle" (b : @bench.T) {
  measure_apply(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Replace)
}

///|
test "range transition: replace near end" (b : @bench.T) {
  measure_apply(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Replace)
}
