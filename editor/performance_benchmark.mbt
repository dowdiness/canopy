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
