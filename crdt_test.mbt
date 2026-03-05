// Test simulating the exact web editor scenario

///|
test "Web scenario: error persistence bug" {
  // Simulate web editor usage
  let editor_ref : Ref[@editor.SyncEditor?] = { val: None }
  editor_ref.val = Some(@editor.SyncEditor::new("web-user"))

  // Type "x"
  match editor_ref.val {
    Some(ed) => try! ed.insert("x")
    None => ()
  }

  // Get errors (like web UI does)
  let errors1 = match editor_ref.val {
    Some(ed) => ed.get_errors()
    None => abort("No editor")
  }
  println("After typing 'x':")
  println("  Errors: " + errors1.length().to_string())
  inspect(errors1.length(), content="0")

  // Type "+" making it "x+"
  match editor_ref.val {
    Some(ed) => try! ed.insert("+")
    None => ()
  }

  // Get errors
  let errors2 = match editor_ref.val {
    Some(ed) => ed.get_errors()
    None => abort("No editor")
  }
  println("After typing 'x+':")
  println("  Errors: " + errors2.length().to_string())
  inspect(errors2.length() > 0, content="true")

  // Type " 1" making it "x+ 1"
  match editor_ref.val {
    Some(ed) => try! ed.insert(" 1")
    None => ()
  }

  // Get errors
  let errors3 = match editor_ref.val {
    Some(ed) => ed.get_errors()
    None => abort("No editor")
  }
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
