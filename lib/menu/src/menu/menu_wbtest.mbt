///|
fn assert_focus(model : Model, expected : Int?) -> Unit raise {
  match (model.focused, expected) {
    (Some(actual), Some(expected)) => assert_eq(actual, expected)
    (None, None) => ()
    (Some(actual), None) => fail("expected no focus, got \{actual}")
    (None, Some(expected)) => fail("expected focus \{expected}, got none")
  }
}

///|
test "new clamps empty item counts" {
  let model = Model::new(id="menu", item_count=-3)
  assert_focus(model, None)
}

///|
test "new focuses first item when present" {
  let model = Model::new(id="menu", item_count=3)
  assert_focus(model, Some(0))
}

///|
test "arrow navigation wraps" {
  let model = Model::new(id="menu", item_count=3)
  assert_focus(model.update(FocusNext), Some(1))
  assert_focus(model.update(FocusPrevious), Some(2))
}

///|
test "home and end focus boundaries" {
  let model = Model::new(id="menu", item_count=4).update(FocusNext)
  assert_focus(model.update(FocusLast), Some(3))
  assert_focus(model.update(FocusFirst), Some(0))
}

///|
test "focus item ignores out of range indices" {
  let model = Model::new(id="menu", item_count=2)
  assert_focus(model.update(FocusItem(1)), Some(1))
  assert_focus(model.update(FocusItem(4)), Some(0))
  assert_focus(model.update(FocusItem(-1)), Some(0))
}

///|
test "activation close and text keys are output-only" {
  let model = Model::new(id="menu", item_count=2).update(FocusNext)
  assert_focus(model.update(Activate(1)), Some(1))
  assert_focus(model.update(Close), Some(1))
  assert_focus(model.update(Key("r")), Some(1))
}

///|
test "reset returns to first item" {
  let model = Model::new(id="menu", item_count=3).update(FocusLast)
  assert_focus(model.reset(item_count=2), Some(0))
  assert_focus(model.reset(item_count=0), None)
}

///|
test "keydown mapping covers menu keys" {
  let model = Model::new(id="menu", item_count=2).update(FocusNext)
  inspect(model.keydown_msg("ArrowDown") is Some(FocusNext), content="true")
  inspect(model.keydown_msg("ArrowUp") is Some(FocusPrevious), content="true")
  inspect(model.keydown_msg("Home") is Some(FocusFirst), content="true")
  inspect(model.keydown_msg("End") is Some(FocusLast), content="true")
  inspect(model.keydown_msg("Enter") is Some(Activate(1)), content="true")
  inspect(model.keydown_msg(" ") is Some(Activate(1)), content="true")
  inspect(model.keydown_msg("Escape") is Some(Close), content="true")
  inspect(model.keydown_msg("r") is Some(Key("r")), content="true")
}

///|
test "text keys are ignored for empty menus" {
  let model = Model::new(id="menu", item_count=0)
  inspect(model.keydown_msg("r") is None, content="true")
  inspect(model.keydown_msg("Enter") is None, content="true")
}
