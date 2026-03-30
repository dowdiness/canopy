// JSON projection pipeline benchmarks.
// Measures parse → ProjNode → SourceMap → reconcile for JSON documents.

///|
/// Generate a JSON object with N members: {"k0": 0, "k1": 1, ...}
fn json_bench_object(member_count : Int) -> String {
  if member_count == 0 {
    return "{}"
  }
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  for i = 0; i < member_count; i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("  \"k")
    buf.write_string(i.to_string())
    buf.write_string("\": ")
    buf.write_string(i.to_string())
  }
  buf.write_string("\n}")
  buf.to_string()
}

///|
/// Generate a JSON array with N elements: [0, 1, 2, ...]
fn json_bench_array(element_count : Int) -> String {
  if element_count == 0 {
    return "[]"
  }
  let buf = StringBuilder::new()
  buf.write_string("[\n")
  for i = 0; i < element_count; i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("  ")
    buf.write_string(i.to_string())
  }
  buf.write_string("\n]")
  buf.to_string()
}

///|
/// Benchmark: incremental edit on JSON object.
/// Inserts/deletes a character in the last member's value, then re-derives
/// ProjNode + SourceMap.
fn run_json_object_bench(b : @bench.T, member_count : Int) -> Unit {
  let source = json_bench_object(member_count)
  let editor = new_json_editor("bench")
  editor.set_text(source)
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  // Edit position: just before the closing }
  let edit_pos = source.length() - 2
  editor.move_cursor(edit_pos)
  let mut inserted = false
  b.bench(fn() {
    if inserted {
      ignore(editor.backspace())
    } else {
      editor.insert("1") catch {
        _ => ()
      }
    }
    b.keep(editor.get_proj_node())
    b.keep(editor.get_source_map())
    inserted = !inserted
  })
}

///|
/// Benchmark: incremental edit on JSON array.
fn run_json_array_bench(b : @bench.T, element_count : Int) -> Unit {
  let source = json_bench_array(element_count)
  let editor = new_json_editor("bench")
  editor.set_text(source)
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  let edit_pos = source.length() - 2
  editor.move_cursor(edit_pos)
  let mut inserted = false
  b.bench(fn() {
    if inserted {
      ignore(editor.backspace())
    } else {
      editor.insert("1") catch {
        _ => ()
      }
    }
    b.keep(editor.get_proj_node())
    b.keep(editor.get_source_map())
    inserted = !inserted
  })
}

///|
test "json object - incremental keystroke (20 members)" (b : @bench.T) {
  run_json_object_bench(b, 20)
}

///|
test "json object - incremental keystroke (100 members)" (b : @bench.T) {
  run_json_object_bench(b, 100)
}

///|
test "json object - incremental keystroke (500 members)" (b : @bench.T) {
  run_json_object_bench(b, 500)
}

///|
test "json object - incremental keystroke (1000 members)" (b : @bench.T) {
  run_json_object_bench(b, 1000)
}

///|
test "json array - incremental keystroke (20 elements)" (b : @bench.T) {
  run_json_array_bench(b, 20)
}

///|
test "json array - incremental keystroke (100 elements)" (b : @bench.T) {
  run_json_array_bench(b, 100)
}

///|
test "json array - incremental keystroke (500 elements)" (b : @bench.T) {
  run_json_array_bench(b, 500)
}

///|
test "json array - incremental keystroke (1000 elements)" (b : @bench.T) {
  run_json_array_bench(b, 1000)
}
