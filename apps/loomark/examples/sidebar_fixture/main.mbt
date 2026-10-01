///|
/// Test-only entry: the production browser entry never imports this package.
fn fixture() -> @rabbita.Val[@html.Html] {
  @sidebar.sidebar_provider(default_mobile_open=false, scope => {
    @html.fragment([
      @sidebar.sidebar_trigger(
        scope,
        mobile=true,
        controls="loomark-sidebar-fixture",
        aria_label="Open test navigation",
        "Open navigation",
      ),
      @sidebar.sidebar(
        scope,
        mobile=true,
        id="loomark-sidebar-fixture",
        aria_label="Test mobile navigation",
        [
          @html.button(
            on_click=@sidebar.sidebar_close_mobile(scope),
            @html.span("Close navigation"),
          ),
          @html.button(disabled=true, "Unavailable action"),
          @html.button(@html.span("Middle action")),
          @html.button(@html.span("Last action")),
        ],
      ),
    ])
  })
}

///|
fn main {
  @rabbita.new(fixture).mount("app")
}
