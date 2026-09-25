///|
fn preview_fallback_source(block_count : Int, references~ : Bool) -> String {
  let out = StringBuilder::StringBuilder()
  if references {
    out.write_string("[ref]: /a\n\n")
  }
  for index in 0..<block_count {
    if references {
      out.write_string("Paragraph ")
      out.write_string(index.to_string())
      out.write_string(" uses [x][ref].\n\n")
    } else {
      out.write_string("Paragraph ")
      out.write_string(index.to_string())
      out.write_string(" remains stable.\n\n")
    }
  }
  out.to_string()
}

///|
fn benchmark_preview_fallback_operations(
  b : @bench.T,
  initial : String,
  operations : Array[(@text_change.TextChange, String)],
) -> Unit {
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(initial) is Ok(initial_output) else {
    abort("preview fallback benchmark preparation failed")
  }
  guard engine.accept(initial_output) else {
    abort("preview fallback benchmark initial acceptance failed")
  }
  let mut index = 0
  b.bench(() => {
    let (change, source) = operations[index]
    guard engine.apply(change, source) is Ok(_) else {
      abort("preview fallback benchmark transition failed")
    }
    guard engine.refresh(source) is Ok(output) else {
      abort("preview fallback benchmark refresh failed")
    }
    guard engine.accept(output) else {
      abort("preview fallback benchmark acceptance failed")
    }
    b.keep(output)
    index = (index + 1) % operations.length()
  })
}

///|
test "Loomark Preview cycle: 2500-block insertion fallback" (b : @bench.T) {
  let initial = preview_fallback_source(2500, references=false)
  let position = initial.find("Paragraph 1250").unwrap()
  let inserted = "Inserted block.\n\n"
  let changed = initial[:position].to_owned() +
    inserted +
    initial[position:].to_owned()
  benchmark_preview_fallback_operations(b, initial, [
    (
      @text_change.ReplaceRange(start=position, delete_len=0, inserted~),
      changed,
    ),
    (
      @text_change.ReplaceRange(
        start=position,
        delete_len=inserted.length(),
        inserted="",
      ),
      initial,
    ),
  ])
}

///|
test "Loomark Preview cycle: 2500-block definition fallback" (b : @bench.T) {
  let initial = preview_fallback_source(2500, references=true)
  let position = initial.find("/a").unwrap() + 1
  let changed = initial[:position].to_owned() +
    "b" +
    initial[position + 1:].to_owned()
  benchmark_preview_fallback_operations(b, initial, [
    (
      @text_change.ReplaceRange(start=position, delete_len=1, inserted="b"),
      changed,
    ),
    (
      @text_change.ReplaceRange(start=position, delete_len=1, inserted="a"),
      initial,
    ),
  ])
}

///|
test "Loomark Preview cycle: 2500-block recovery fallback" (b : @bench.T) {
  let initial = preview_fallback_source(2500, references=false)
  let position = initial.find("Paragraph 1250").unwrap()
  let inserted = "```\n"
  let changed = initial[:position].to_owned() +
    inserted +
    initial[position:].to_owned()
  benchmark_preview_fallback_operations(b, initial, [
    (
      @text_change.ReplaceRange(start=position, delete_len=0, inserted~),
      changed,
    ),
    (
      @text_change.ReplaceRange(
        start=position,
        delete_len=inserted.length(),
        inserted="",
      ),
      initial,
    ),
  ])
}
