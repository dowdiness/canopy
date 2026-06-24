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

///|
#cfg(target="js")
struct FocusCmdTestScheduler {
  mut after_render_count : Int
  hooks : @cmd.Hooks
}

///|
#cfg(target="js")
fn FocusCmdTestScheduler::new() -> FocusCmdTestScheduler {
  { after_render_count: 0, hooks: { url_request: None, url_changed: None } }
}

///|
#cfg(target="js")
impl @cmd.Scheduler for FocusCmdTestScheduler with fn run_effect(self, kind, f) {
  match kind {
    Immediately => f(self)
    AfterRender => {
      self.after_render_count = self.after_render_count + 1
      f(self)
    }
  }
}

///|
#cfg(target="js")
impl @cmd.Scheduler for FocusCmdTestScheduler with fn queue_message(
  self,
  _id,
  _send_message,
) {
  ignore(self)
}

///|
#cfg(target="js")
impl @cmd.Scheduler for FocusCmdTestScheduler with fn drain_message(self) {
  ignore(self)
}

///|
#cfg(target="js")
impl @cmd.Scheduler for FocusCmdTestScheduler with fn hooks(self) {
  self.hooks
}

///|
#cfg(target="js")
extern "js" fn install_shadow_focus_fixture(
  root_id : String,
  item_id : String,
) -> Unit =
  #| (rootId, itemId) => {
  #|   globalThis.__menuFocusLog = [];
  #|   const shadowItem = {
  #|     id: itemId,
  #|     children: [],
  #|     focus() { globalThis.__menuFocusLog.push("shadow:" + this.id); },
  #|   };
  #|   const documentItem = {
  #|     id: itemId,
  #|     children: [],
  #|     focus() { globalThis.__menuFocusLog.push("document:" + this.id); },
  #|   };
  #|   const shadowRoot = {
  #|     children: [shadowItem],
  #|     getElementById(id) { return id === itemId ? shadowItem : null; },
  #|   };
  #|   const host = { id: rootId, children: [], shadowRoot };
  #|   globalThis.document = {
  #|     getElementById(id) {
  #|       if (id === rootId) return host;
  #|       if (id === itemId) return documentItem;
  #|       return null;
  #|     },
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn focus_log() -> String =
  #| () => (globalThis.__menuFocusLog || []).join(",")

///|
#cfg(target="js")
extern "js" fn clear_focus_fixture() -> Unit =
  #| () => {
  #|   delete globalThis.document;
  #|   delete globalThis.__menuFocusLog;
  #| }

///|
#cfg(target="js")
test "focus_cmd_within searches a shadow host before document duplicates" {
  let model = Model::new(id="menu", item_count=2).update(FocusNext)
  install_shadow_focus_fixture("menu-host", "menu-item-1")
  let scheduler = FocusCmdTestScheduler::new()
  scheduler.add(model.focus_cmd_within(root_id="menu-host"))
  let log = focus_log()
  clear_focus_fixture()
  inspect(scheduler.after_render_count, content="1")
  inspect(log, content="shadow:menu-item-1")
}
