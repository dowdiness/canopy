///|
test "context menu opens, exposes anchor, and closes" {
  let model = @context_menu.Model::new(id="test-menu")
  inspect(model.is_open(), content="false")
  guard model.anchor() is None else {
    fail("closed context menu should not expose an anchor")
  }

  let model = model.open(
    anchor=@context_menu.Point(x=12.5F, y=34.25F),
    item_count=3,
  )
  inspect(model.is_open(), content="true")
  match model.anchor() {
    Some(point) => {
      inspect(point.x, content="12.5")
      inspect(point.y, content="34.25")
    }
    None => fail("open context menu should expose the supplied anchor")
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
    anchor=@context_menu.Point(x=1.0F, y=2.0F),
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

///|
test "positioning defaults and custom strategies are public values" {
  let default_positioning = @context_menu.Positioning::default()
  guard default_positioning == @context_menu.Positioning() else {
    fail("expected default positioning to match the default constructor")
  }

  let custom_positioning = @context_menu.Positioning(
    offset_x=4.5F,
    offset_y=6.25F,
    viewport_margin=12.0F,
    collision=@context_menu.NoCollisionHandling,
  )
  guard custom_positioning != default_positioning else {
    fail("expected custom positioning options to differ from defaults")
  }
}

///|
test "activation and keyboard close paths request focus restore" {
  let model = @context_menu.Model::new(id="test-menu").open(
    anchor=@context_menu.Point(x=1.0F, y=2.0F),
    item_count=2,
  )

  inspect(@context_menu.Activate(0).requests_close_focus(), content="true")
  inspect(@context_menu.Close.requests_close_focus(), content="true")
  inspect(
    @context_menu.Dismiss(@context_menu.EscapeKey).requests_close_focus(),
    content="true",
  )
  inspect(
    @context_menu.Dismiss(@context_menu.PointerOutside).requests_close_focus(),
    content="false",
  )

  inspect(model.update(@context_menu.Activate(0)).is_open(), content="false")
  inspect(
    model.update(@context_menu.Dismiss(@context_menu.EscapeKey)).is_open(),
    content="false",
  )
  inspect(
    model.update(@context_menu.Dismiss(@context_menu.PointerOutside)).is_open(),
    content="false",
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
    .open(anchor=@context_menu.Point(x=1.0F, y=2.0F), item_count=2)
    .update(@context_menu.FocusNext)
  install_shadow_focus_fixture("menu-host", "test-menu-item-1")
  @rabbita_testing.run_cmd(model.focus_cmd_within(root_id="menu-host"))
  let log = focus_log()
  clear_focus_fixture()
  inspect(log, content="shadow:test-menu-item-1")
}
