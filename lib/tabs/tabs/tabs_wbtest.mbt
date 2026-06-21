///|
fn assert_selected(model : Model, expected : Int) -> Unit raise {
  assert_eq(model.selected, expected)
}

///|
test "new clamps negative tab counts to zero" {
  let model = Model::new(id="tabs", tab_count=-3, selected=1)
  assert_eq(model.tab_count, 0)
  assert_selected(model, 0)
}

///|
test "new clamps selected into range" {
  assert_selected(Model::new(id="tabs", tab_count=4, selected=2), 2)
  assert_selected(Model::new(id="tabs", tab_count=4, selected=9), 3)
  assert_selected(Model::new(id="tabs", tab_count=4, selected=-1), 0)
  assert_selected(Model::new(id="tabs", tab_count=0, selected=2), 0)
}

///|
test "tab_button_id uses index suffix" {
  let model = Model::new(id="canopy-bottom-tabs", tab_count=3, selected=0)
  assert_eq(model.tab_button_id(0), "canopy-bottom-tabs-tab-0")
  assert_eq(model.tab_button_id(2), "canopy-bottom-tabs-tab-2")
}

///|
test "nav_target wraps around with arrows" {
  let model = Model::new(id="tabs", tab_count=3, selected=0)
  inspect(model.nav_target("ArrowRight") is Some(1), content="true")
  inspect(model.nav_target("ArrowLeft") is Some(2), content="true")
  let last = Model::new(id="tabs", tab_count=3, selected=2)
  inspect(last.nav_target("ArrowRight") is Some(0), content="true")
}

///|
test "nav_target jumps to ends with Home and End" {
  let model = Model::new(id="tabs", tab_count=5, selected=2)
  inspect(model.nav_target("Home") is Some(0), content="true")
  inspect(model.nav_target("End") is Some(4), content="true")
}

///|
test "nav_target ignores vertical arrows and other keys" {
  let model = Model::new(id="tabs", tab_count=3, selected=1)
  inspect(model.nav_target("ArrowUp") is None, content="true")
  inspect(model.nav_target("ArrowDown") is None, content="true")
  inspect(model.nav_target("Enter") is None, content="true")
  inspect(model.nav_target(" ") is None, content="true")
  inspect(model.nav_target("a") is None, content="true")
}

///|
test "nav_target is empty-safe with no tabs" {
  let model = Model::new(id="tabs", tab_count=0, selected=0)
  inspect(model.nav_target("ArrowRight") is None, content="true")
  inspect(model.nav_target("Home") is None, content="true")
}

///|
test "nav_target on a single tab stays put" {
  let model = Model::new(id="tabs", tab_count=1, selected=0)
  inspect(model.nav_target("ArrowRight") is Some(0), content="true")
  inspect(model.nav_target("ArrowLeft") is Some(0), content="true")
  inspect(model.nav_target("End") is Some(0), content="true")
}
