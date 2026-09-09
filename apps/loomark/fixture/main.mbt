///| Toggle is deliberately outside the switch_by branch. The branch owns the

///|
/// complete Loomark app scope, so switching it exercises Rabbita disposal.
priv enum Toggle {
  Mounted
  Unmounted
} derive(Eq)

///|
priv enum Msg {
  ToggleApp
}

///|
fn fixture() -> @rabbita.Val[@rabbita.Html] {
  let (mounted, emit) = @rabbita.create_state(Toggle::Mounted, update=(
    mounted,
    msg,
    _,
  ) => {
    match msg {
      ToggleApp =>
        (
          match mounted {
            Mounted => Unmounted
            Unmounted => Mounted
          },
          @rabbita.none,
        )
    }
  })
  let app = mounted.switch_by(
    mounted => {
      match mounted {
        Mounted => @app.app()
        Unmounted => @rabbita.Val::constant(@html.nothing)
      }
    },
    by=mounted => {
      match mounted {
        Mounted => "mounted"
        Unmounted => "unmounted"
      }
    },
  )
  app.map(content => {
    @html.div([
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Toggle Loomark app"),
        on_click=emit(ToggleApp),
        "Toggle Loomark app",
      ),
      content,
    ])
  })
}

///|
fn main {
  @rabbita.new(fixture).mount("fixture")
}
