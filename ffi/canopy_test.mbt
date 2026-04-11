// Test simulating the exact web editor scenario

///|
test "Web scenario: error persistence bug" {
  // Simulate web editor usage
  let editor_ref : Ref[@editor.SyncEditor[@ast.Term]?] = { val: None }
  editor_ref.val = Some(@lambda.new_lambda_editor("web-user").0)

  // Type "x"
  match editor_ref.val {
    Some(ed) => try! ed.insert("x")
    None => ()
  }

  // Get errors (like web UI does)
  guard editor_ref.val is Some(ed1)
  let errors1 = ed1.get_errors()
  println("After typing 'x':")
  println("  Errors: " + errors1.length().to_string())
  inspect(errors1.length(), content="0")

  // Type "+" making it "x+"
  match editor_ref.val {
    Some(ed) => try! ed.insert("+")
    None => ()
  }

  // Get errors
  guard editor_ref.val is Some(ed2)
  let errors2 = ed2.get_errors()
  println("After typing 'x+':")
  println("  Errors: " + errors2.length().to_string())
  inspect(errors2.length() > 0, content="true")

  // Type " 1" making it "x+ 1"
  match editor_ref.val {
    Some(ed) => try! ed.insert(" 1")
    None => ()
  }

  // Get errors
  guard editor_ref.val is Some(ed3)
  let errors3 = ed3.get_errors()
  println("After typing 'x+ 1':")
  let text = match editor_ref.val {
    Some(ed) => ed.get_text()
    None => ""
  }
  println("  Text: " + text)
  println("  Errors: " + errors3.length().to_string())

  // THIS IS THE KEY TEST - errors should be CLEARED
  inspect(errors3.length(), content="0")
}

///|
test "get_diagnostics_json: unbound variable produces warning" {
  let (editor, companion) = @lambda.new_lambda_editor("test-diag")
  editor.set_text("x")
  // Parse errors
  let errors = editor.get_errors()
  inspect(errors.length(), content="0") // "x" is syntactically valid
  // Eval results
  let eval_results = companion.get_eval_results()
  inspect(eval_results.length() > 0, content="true")
  // Check that Stuck result exists
  let has_stuck = eval_results
    .iter()
    .any(fn(r) {
      match r {
        @lambda.EvalResult::Stuck(_) => true
        _ => false
      }
    })
  inspect(has_stuck, content="true")
}

///|
test "get_diagnostics_json FFI: unbound variable" {
  let handle = create_editor("test-diag-ffi")
  set_text(handle, "x")
  let json = get_diagnostics_json(handle)
  println("diagnostics JSON: " + json)
  // Should contain warning
  inspect(json.contains("warning"), content="true")
  inspect(json.contains("unbound"), content="true")
  destroy_editor(handle)
}
