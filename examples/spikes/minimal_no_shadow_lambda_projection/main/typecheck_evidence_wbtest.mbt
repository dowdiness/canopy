///|
test "P2a Runtime-free whole-module typecheck owner graph" {
  run_p2a_typecheck_evidence()
}

///|
test "P2a exact CST conversion preserves typed lambda annotation" {
  let shell = try! MinimalLambdaProjectionShell("(x : Int) => x")
  let result = p2a_read_typecheck(shell)
  inspect(result.body_type.typ, content="Int -> Int")
  inspect(result.body_type.had_error, content="false")
  inspect(result.def_types.length(), content="0")
  inspect(result.all_diagnostics.length(), content="0")
  ignore(shell.close())
}

///|
test "P2a production resolution rejects forward definition reference" {
  let shell = try! MinimalLambdaProjectionShell("let x = y\nlet y = 1\nx")
  let result = p2a_read_typecheck(shell)
  inspect(result.def_types[0].0, content="x")
  inspect(result.def_types[0].1.had_error, content="true")
  inspect(result.def_types[1].0, content="y")
  inspect(result.def_types[1].1.had_error, content="false")
  // Public pure inference drops detailed diagnostics; this remains an explicit
  // P2a parity gap rather than fabricating a diagnostic channel.
  inspect(result.all_diagnostics.length(), content="0")
  ignore(shell.close())
}
