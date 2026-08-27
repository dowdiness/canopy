///|
fn preview_cycle_fixture(
  block_count : Int,
  interior~ : Bool,
) -> (String, Array[(@text_change.TextChange, String)]) {
  let source = StringBuilder::StringBuilder()
  let positions : Array[Int] = []
  let mut source_offset = 0
  for index = 0; index < block_count / 2; index = index + 1 {
    let unit = "## Heading \{index}\n\nParagraph \{index} with **bold**, [link](https://example.com/\{index}), and 日本語 😀.\n\n"
    guard unit.find("Paragraph") is Some(paragraph_offset) else {
      abort("benchmark paragraph missing")
    }
    let relative_offset = if interior { 3 } else { 0 }
    positions.push(source_offset + paragraph_offset + relative_offset)
    source.write_string(unit)
    source_offset += unit.length()
  }
  let initial = source.to_string()
  let operations : Array[(@text_change.TextChange, String)] = []
  let selected : Array[Int] = Array::makei(16, index => {
    positions[index * positions.length() / 16]
  })
  let mut current = initial
  for position in selected {
    let inserted = if interior { "A" } else { "p" }
    let change = @text_change.ReplaceRange(
      start=position,
      delete_len=1,
      inserted~,
    )
    guard change.apply(current) is Some(next) else {
      abort("benchmark forward edit failed")
    }
    operations.push((change, next))
    current = next
  }
  for index = selected.length() - 1; index >= 0; index = index - 1 {
    let inserted = if interior { "a" } else { "P" }
    let change = @text_change.ReplaceRange(
      start=selected[index],
      delete_len=1,
      inserted~,
    )
    guard change.apply(current) is Some(next) else {
      abort("benchmark reverse edit failed")
    }
    operations.push((change, next))
    current = next
  }
  guard current == initial else { abort("benchmark edit cycle did not close") }
  (initial, operations)
}

///|
fn benchmark_preview_cycle(
  b : @bench.T,
  block_count : Int,
  interior~ : Bool,
) -> Unit {
  let (initial, operations) = preview_cycle_fixture(block_count, interior~)
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(initial) is Ok(_) else {
    abort("benchmark Preview preparation failed")
  }
  let mut operation_index = 0
  b.bench(() => {
    let (change, source) = operations[operation_index]
    guard engine.apply(change, source) is Ok(_) else {
      abort("benchmark Parser transition failed")
    }
    guard engine.refresh(source) is Ok(output) else {
      abort("benchmark Preview refresh failed")
    }
    b.keep(output)
    operation_index = (operation_index + 1) % operations.length()
  })
}

///|
test "Loomark Preview cycle: practical 500-block boundary edits" (b : @bench.T) {
  benchmark_preview_cycle(b, 500, interior=false)
}

///|
test "Loomark Preview cycle: practical 500-block interior edits" (b : @bench.T) {
  benchmark_preview_cycle(b, 500, interior=true)
}

///|
test "Loomark Preview cycle: scaling 2500-block boundary edits" (b : @bench.T) {
  benchmark_preview_cycle(b, 2500, interior=false)
}

///|
test "Loomark Preview cycle: scaling 2500-block interior edits" (b : @bench.T) {
  benchmark_preview_cycle(b, 2500, interior=true)
}
