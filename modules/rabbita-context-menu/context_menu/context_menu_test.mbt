///|
test "context menu opens, exposes anchor, and closes" {
  let closed : @context_menu.Model[String] = @context_menu.Model::new(
    id="test-menu",
  )
  let anchor = @context_menu.Point(x=12.5F, y=34.25F)
  let opened = closed.open(anchor~, items=["rename", "delete"])

  assert_false(closed.is_open())
  assert_true(closed.anchor() is None)
  assert_true(opened.is_open())
  assert_true(opened.anchor() == Some(anchor))

  let dismissed = opened.update(@context_menu.Close)
  assert_false(dismissed.is_open())
  assert_true(dismissed.anchor() is None)
  assert_eq(dismissed.items().length(), 0)
}

///|
test "activation closes while navigation requests focus" {
  let model = @context_menu.Model::new(id="test-menu").open(
    anchor=@context_menu.Point(x=1.0F, y=2.0F),
    items=["rename", "delete"],
  )
  let navigated = model.update(@context_menu.FocusLast)
  assert_true(navigated.is_open())
  assert_true(@context_menu.FocusNext.requests_focus())
  assert_false(@context_menu.FocusItem(1).requests_focus())
  assert_false(navigated.update(@context_menu.Activate(1)).is_open())
}

///|
test "open owns items and close discards them" {
  let source : Array[String] = ["rename", "delete"]
  let model = @context_menu.Model::new(id="test-menu").open(
    anchor=@context_menu.Point(x=1.0F, y=2.0F),
    items=source[:],
  )
  source[0] = "mutated"
  assert_eq(model.item(0), Some("rename"))
  assert_true(model.close().item(0) is None)
}

///|
test "model equality includes focus and owned items" {
  let anchor = @context_menu.Point(x=1.0F, y=2.0F)
  let first = @context_menu.Model::new(id="test-menu").open(anchor~, items=[
    "rename", "delete",
  ])
  let equivalent = @context_menu.Model::new(id="test-menu").open(anchor~, items=[
    "rename", "delete",
  ])
  let focused = first.update(@context_menu.FocusNext)
  let changed = @context_menu.Model::new(id="test-menu").open(anchor~, items=[
    "rename", "duplicate",
  ])
  assert_true(first == equivalent)
  assert_false(first == focused)
  assert_false(first == changed)
}

///|
test "activation and keyboard close paths request focus restore" {
  assert_true(@context_menu.Activate(0).requests_close_focus())
  assert_true(@context_menu.Close.requests_close_focus())
  assert_true(
    @context_menu.Dismiss(@context_menu.EscapeKey).requests_close_focus(),
  )
  // An outside click must leave focus on the control the user clicked.
  assert_false(
    @context_menu.Dismiss(@context_menu.PointerOutside).requests_close_focus(),
  )
}

///|
#cfg(target="js")
extern "js" fn install_shadow_focus_fixture(
  root_id : String,
  item_id : String,
) -> Unit =
  #| (rootId, itemId) => {
  #|   globalThis.__contextMenuFocusLog = [];
  #|   const shadowItem = {
  #|     id: itemId,
  #|     children: [],
  #|     focus() {
  #|       globalThis.__contextMenuFocusLog.push("shadow:" + this.id);
  #|     },
  #|   };
  #|   const documentItem = {
  #|     id: itemId,
  #|     children: [],
  #|     focus() {
  #|       globalThis.__contextMenuFocusLog.push("document:" + this.id);
  #|     },
  #|   };
  #|   const shadowMenu = {
  #|     id: "test-menu",
  #|     children: [shadowItem],
  #|     querySelector(selector) {
  #|       return selector === '[data-active="true"]' ? shadowItem : null;
  #|     },
  #|   };
  #|   const shadowRoot = {
  #|     children: [shadowMenu],
  #|     getElementById(id) { return id === "test-menu" ? shadowMenu : null; },
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
  #| () => (globalThis.__contextMenuFocusLog || []).join(",")

///|
#cfg(target="js")
extern "js" fn clear_focus_fixture() -> Unit =
  #| () => {
  #|   delete globalThis.document;
  #|   delete globalThis.__contextMenuFocusLog;
  #| }

///|
#cfg(target="js")
async test "focus_cmd_within delegates scoped focus to the embedded menu" {
  let model = @context_menu.Model::new(id="test-menu")
    .open(anchor=@context_menu.Point(x=1.0F, y=2.0F), items=["rename", "delete"])
    .update(@context_menu.FocusNext)
  install_shadow_focus_fixture("menu-host", "test-menu-item-1")
  @rabbita_testing.run_cmd(model.focus_cmd_within(root_id="menu-host"))
  let log = focus_log()
  clear_focus_fixture()
  inspect(log, content="shadow:test-menu-item-1")
}
