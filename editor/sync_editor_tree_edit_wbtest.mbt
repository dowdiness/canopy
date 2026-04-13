// Whitebox tests for generic Tier-2 tree edit methods.
// Uses SyncEditor[@ast.Term] via the lambda convenience constructor.

///|
test "delete_node replaces span with placeholder" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("(λx. x)")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.delete_node(root.id(), 0)
  inspect(result is Ok(_), content="true")
}

///|
test "commit_edit replaces span with new text" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "y", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="y")
}

///|
test "apply_text_transform wraps node in lambda" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.apply_text_transform(
    root.id(),
    fn(src, s, e) { Ok("(λy. " + src[s:e].to_string() + ")") },
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(λy. x)")
}

///|
test "delete_node returns error for unknown node_id" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  let _ = editor.get_proj_node()
  let bad_id = @core.NodeId::from_int(99999)
  let result = editor.delete_node(bad_id, 0)
  inspect(result is Err(_), content="true")
}

///|
test "commit_edit returns error for unknown node_id" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  let _ = editor.get_proj_node()
  let bad_id = @core.NodeId::from_int(99999)
  let result = editor.commit_edit(bad_id, "y", 0)
  inspect(result is Err(_), content="true")
}

///|
test "is_dirty set after set_text" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  inspect(editor.is_dirty(), content="true")
}

///|
test "is_dirty set after insert/backspace" {
  let editor = @lambda.new_lambda_editor("test").0
  // Consume initial dirty from construction
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // insert goes through apply_local_text_change → set_parser_signals
  editor.insert("x") catch {
    _ => ()
  }
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // backspace also sets dirty
  editor.move_cursor(1)
  let _ = editor.backspace()
  inspect(editor.is_dirty(), content="true")
}

///|
test "refresh clears dirty flag and further edits are accepted" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("x")
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // further edits work normally after refresh
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "y", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="y")
  inspect(editor.is_dirty(), content="true")
}

///|
test "move_node moves source before target and adjusts text" {
  // "1 2" parses as App(Int(1), Int(2))
  // children[0] = Int(1) at [0:1], children[1] = Int(2) at [2:3]
  // Move Int(2) Before Int(1):
  //   step 1: replace [2:3] with placeholder("0") → "1 0"
  //   step 2: insert unparse("2") + " " at 0 → "2 1 0"
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("1 2")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  // Need 2 children for App
  if root.children.length() < 2 {
    fail("expected App with 2 children, got \{root.children.length()}")
  }
  let src_id = root.children[1].id() // Int(2)
  let tgt_id = root.children[0].id() // Int(1)
  let result = editor.move_node(src_id, tgt_id, @lambda.DropPosition::Before, 0)
  inspect(result is Ok(_), content="true")
  // source node no longer at its original span; text has changed
  inspect(editor.get_text() == "1 2", content="false")
  // dirty flag set after move
  inspect(editor.is_dirty(), content="true")
}

///|
test "move_node exchange (Inside) swaps two expressions" {
  // "1 2" parses as App(Int(1), Int(2))
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("1 2")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let child0 = root.children[0] // Int(1)
  let child1 = root.children[1] // Int(2)
  // Debug: check ranges
  let sm = editor.get_source_map()
  let r0 = sm.get_range(child0.id())
  let r1 = sm.get_range(child1.id())
  inspect(
    r0,
    content=(
      #|Some({ start: 0, end: 1 })
    ),
  )
  inspect(
    r1,
    content=(
      #|Some({ start: 1, end: 3 })
    ),
  )
  let result = editor.move_node(
    child0.id(),
    child1.id(),
    @lambda.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="2 1")
}

///|
test "move_node exchange swaps two let-definitions" {
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("let x = 1\nlet y = 2\nx")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  // Module has children: LetDef(x=1), LetDef(y=2), Var(x)
  // Exchange the two let-defs as whole units
  let let_x = root.children[0] // let x = 1
  let let_y = root.children[1] // let y = 2
  let result = editor.move_node(
    let_x.id(),
    let_y.id(),
    @lambda.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(
    editor.get_text(),
    content=(
      #|let x = 2
      #|let y = 1
      #|x
    ),
  )
}

///|
test "move_node exchange: variable and number in application" {
  // "f 42" = App(Var("f"), Int(42))
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("f 42")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let var_f = root.children[0] // Var("f")
  let int_42 = root.children[1] // Int(42)
  // Debug: check ranges and spans
  let sm = editor.get_source_map()
  let r0 = sm.get_range(var_f.id())
  let r1 = sm.get_range(int_42.id())
  inspect(
    r0,
    content=(
      #|Some({ start: 0, end: 1 })
    ),
  )
  inspect(
    r1,
    content=(
      #|Some({ start: 1, end: 4 })
    ),
  )
  let result = editor.move_node(
    var_f.id(),
    int_42.id(),
    @lambda.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="42 f")
}

///|
test "move_node exchange: number and lambda body" {
  // "\x. 42" = Lam("x", Int(42))
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text("(\\x. 42) 1")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let lam = root.children[0] // Lam
  let int_1 = root.children[1] // Int(1)
  // Debug: check ranges
  let sm = editor.get_source_map()
  let r0 = sm.get_range(lam.id())
  let r1 = sm.get_range(int_1.id())
  inspect(
    r0,
    content=(
      #|Some({ start: 0, end: 8 })
    ),
  )
  inspect(
    r1,
    content=(
      #|Some({ start: 8, end: 10 })
    ),
  )
  let result = editor.move_node(
    lam.id(),
    int_1.id(),
    @lambda.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(
    editor.get_text(),
    content=(
      #|1 (\x. 42)
    ),
  )
}

///|
test "move_node exchange: int with var in real editor text" {
  // Mimics the default editor text
  let editor = @lambda.new_lambda_editor("test").0
  editor.set_text(
    "let id = \\x. { x }\nlet apply = \\f. \\x. { f x }\napply id 42",
  )
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  // root is Module with 3 children: let id, let apply, "apply id 42"
  let app_expr = root.children[2] // "apply id 42" = App(App(Var("apply"), Var("id")), Int(42))
  // app_expr.children[0] = App(Var("apply"), Var("id"))
  // app_expr.children[1] = Int(42)
  let inner_app = app_expr.children[0] // App(apply, id)
  let int_42 = app_expr.children[1] // Int(42)
  // inner_app.children[1] = Var("id")
  let var_id = inner_app.children[1] // Var("id")
  // Show ranges
  let sm = editor.get_source_map()
  inspect(
    sm.get_range(var_id.id()),
    content=(
      #|Some({ start: 52, end: 55 })
    ),
  )
  inspect(
    sm.get_range(int_42.id()),
    content=(
      #|Some({ start: 55, end: 58 })
    ),
  )
  // Exchange id <-> 42
  let result = editor.move_node(
    var_id.id(),
    int_42.id(),
    @lambda.DropPosition::Inside,
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(
    editor.get_text(),
    content=(
      #|let id = \x. { x }
      #|let apply = \f. \x. { f x }
      #|apply 42 id
    ),
  )
}
