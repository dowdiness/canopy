// Projection pipeline benchmarks — measures to_flat_proj + reconcile + to_proj_node
// Uses single-char insert/delete to avoid CRDT set_text overhead.

///|
fn run_projection_incremental_bench(b : @bench.T, let_count : Int) -> Unit {
  let source = parser_bench_source(let_count, "0")
  let editor = SyncEditor::new("bench")
  editor.set_text(source)
  ignore(editor.get_proj_node()) // warm up — initial parse + project
  ignore(editor.get_source_map())
  let edit_pos = source.length() - 2
  editor.move_cursor(edit_pos)
  let mut inserted = false
  b.bench(() => {
    if inserted {
      ignore(editor.backspace())
    } else {
      editor.insert("1") catch {
        _ => ()
      }
    }
    b.keep(editor.get_proj_node())
    b.keep(editor.get_source_map())
    inserted = not(inserted)
  })
}

///|
test "projection pipeline - incremental keystroke (20 defs)" (b : @bench.T) {
  run_projection_incremental_bench(b, 20)
}

///|
test "projection pipeline - incremental keystroke (80 defs)" (b : @bench.T) {
  run_projection_incremental_bench(b, 80)
}

///|
test "projection pipeline - incremental keystroke (320 defs)" (b : @bench.T) {
  run_projection_incremental_bench(b, 320)
}

// 500-def benchmark omitted: FugueTree::traverse_tree hits stack overflow
// at ~500 nodes (pre-existing CRDT limitation, not projection-related).

// Parser-only benchmarks — measures parse layer without projection

///|
priv struct ParserBenchScenario {
  source : String
  edited_source : String
  forward_edit : @parser.Edit
  backward_edit : @parser.Edit
}

///|
fn parser_bench_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = 0")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal}")
  segments.push("x\{let_count - 1}")
  segments.join("\n")
}

///|
fn parser_bench_scenario(let_count : Int) -> ParserBenchScenario {
  let source = parser_bench_source(let_count, "0")
  let edited_source = parser_bench_source(let_count, "1")
  {
    source,
    edited_source,
    forward_edit: compute_edit(source, edited_source),
    backward_edit: compute_edit(edited_source, source),
  }
}

///|
test "parser benchmark - reactive full reparse medium" (b : @bench.T) {
  let scenario = parser_bench_scenario(80)
  let parser = @loom.new_reactive_parser(
    scenario.source,
    @parser.lambda_grammar,
  )
  ignore(parser.term())
  let mut use_edited = true
  b.bench(() => {
    let next_source = if use_edited {
      scenario.edited_source
    } else {
      scenario.source
    }
    parser.set_source(next_source)
    b.keep(parser.term())
    use_edited = !use_edited
  })
}

///|
test "parser benchmark - imperative incremental medium" (b : @bench.T) {
  let scenario = parser_bench_scenario(80)
  let parser = @loom.new_imperative_parser(
    scenario.source,
    @parser.lambda_grammar,
  )
  ignore(parser.parse())
  let mut use_edited = true
  b.bench(() => {
    let edit = if use_edited {
      scenario.forward_edit
    } else {
      scenario.backward_edit
    }
    let next_source = if use_edited {
      scenario.edited_source
    } else {
      scenario.source
    }
    b.keep(parser.edit(edit, next_source))
    use_edited = !use_edited
  })
}

///|
test "parser benchmark - reactive full reparse large" (b : @bench.T) {
  let scenario = parser_bench_scenario(320)
  let parser = @loom.new_reactive_parser(
    scenario.source,
    @parser.lambda_grammar,
  )
  ignore(parser.term())
  let mut use_edited = true
  b.bench(() => {
    let next_source = if use_edited {
      scenario.edited_source
    } else {
      scenario.source
    }
    parser.set_source(next_source)
    b.keep(parser.term())
    use_edited = !use_edited
  })
}

///|
test "parser benchmark - imperative incremental large" (b : @bench.T) {
  let scenario = parser_bench_scenario(320)
  let parser = @loom.new_imperative_parser(
    scenario.source,
    @parser.lambda_grammar,
  )
  ignore(parser.parse())
  let mut use_edited = true
  b.bench(() => {
    let edit = if use_edited {
      scenario.forward_edit
    } else {
      scenario.backward_edit
    }
    let next_source = if use_edited {
      scenario.edited_source
    } else {
      scenario.source
    }
    b.keep(parser.edit(edit, next_source))
    use_edited = !use_edited
  })
}
