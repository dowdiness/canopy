///|
/// PROTOTYPE — isolates the complete-source diff stage from Issue #1156.
fn practical_preview_fixture() -> String {
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
priv enum DiffOperation {
  Insert
  Delete
  Replace
}

///|
fn diff_operand(
  source : String,
  block : Int,
  operation : DiffOperation,
) -> String {
  let paragraph = "Paragraph " + block.to_string()
  match operation {
    Insert => source.replace(old=paragraph, new=paragraph + " changed")
    Delete =>
      source
      .replace(old=paragraph, new=paragraph + " changed")
      .replace(old=paragraph + " changed", new=paragraph)
    Replace =>
      source.replace(
        old=paragraph + " with **bold**",
        new=paragraph + " with **strong**",
      )
  }
}

///|
fn diff_pairs(
  blocks : Array[Int],
  operation : DiffOperation,
) -> Array[(String, String)] {
  let source = practical_preview_fixture()
  blocks.map(block => {
    let changed = diff_operand(source, block, operation)
    match operation {
      Delete =>
        (
          source.replace(
            old="Paragraph " + block.to_string(),
            new="Paragraph " + block.to_string() + " changed",
          ),
          changed,
        )
      Insert | Replace => (source, changed)
    }
  })
}

///|
fn measure_diff(
  b : @bench.T,
  blocks : Array[Int],
  operation : DiffOperation,
) -> Unit {
  let pairs = diff_pairs(blocks, operation)
  let mut index = 0
  b.bench(() => {
    let (old_text, new_text) = pairs[index % pairs.length()]
    index += 1
    b.keep(@text_change.compute_text_change(old_text, new_text))
  })
}

///|
test "isolate: insert near beginning of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Insert)
}

///|
test "isolate: insert near middle of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Insert)
}

///|
test "isolate: insert near end of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Insert)
}

///|
test "isolate: delete near beginning of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Delete)
}

///|
test "isolate: delete near middle of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Delete)
}

///|
test "isolate: delete near end of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Delete)
}

///|
test "isolate: replace near beginning of practical Preview corpus" (
  b : @bench.T,
) {
  measure_diff(b, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], Replace)
}

///|
test "isolate: replace near middle of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [120, 121, 122, 123, 124, 125, 126, 127, 128, 129], Replace)
}

///|
test "isolate: replace near end of practical Preview corpus" (b : @bench.T) {
  measure_diff(b, [240, 241, 242, 243, 244, 245, 246, 247, 248, 249], Replace)
}
