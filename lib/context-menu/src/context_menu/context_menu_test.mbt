///|
test "context menu opens, exposes anchor, and closes" {
  let model = @context_menu.Model::new(id="test-menu")
  inspect(model.is_open(), content="false")
  guard model.anchor() is None else {
    fail("closed context menu should not expose an anchor")
  }

  let model = model.open(anchor=@context_menu.Point(x=12, y=34), item_count=3)
  inspect(model.is_open(), content="true")
  guard model.anchor() is Some({ x: 12, y: 34 }) else {
    fail("open context menu should expose the supplied anchor")
  }

  let model = model.update(@context_menu.Close)
  inspect(model.is_open(), content="false")
  guard model.anchor() is None else {
    fail("closed context menu should clear the anchor")
  }
}

///|
test "activation closes while navigation requests focus" {
  let model = @context_menu.Model::new(id="test-menu").open(
    anchor=@context_menu.Point(x=1, y=2),
    item_count=2,
  )
  inspect(@context_menu.FocusNext.requests_focus(), content="true")
  inspect(@context_menu.FocusItem(1).requests_focus(), content="false")
  inspect(@context_menu.Activate(0).requests_focus(), content="false")

  let navigated = model.update(@context_menu.FocusLast)
  inspect(navigated.is_open(), content="true")

  let activated = navigated.update(@context_menu.Activate(1))
  inspect(activated.is_open(), content="false")
}
