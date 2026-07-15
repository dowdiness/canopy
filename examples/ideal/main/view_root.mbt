///|
let examples : Array[(String, String)] = [
  ("Basics", "fn double(x : Int) {\n  x + x\n}\nlet result = double 5\nresult"),
  (
    "Composition", "fn inc(n : Int) { n + 1 }\nfn twice(f : Int -> Int, x : Int) {\n  f (f x)\n}\nlet result = twice inc 0\nresult",
  ),
  (
    "Currying", "fn add(x : Int, y : Int) { x + y }\nlet add5 = add 5\nlet sum = add5 10\nsum",
  ),
  (
    "Conditional", "fn choose(x : Int) { if x then {\n  x + 1\n} else {\n  42\n} }\nlet a = choose 0\nlet b = choose 5\na + b",
  ),
  (
    "Pipeline", "fn compose(f : Int -> Int, g : Int -> Int, x : Int) {\n  f (g x)\n}\nfn double(x : Int) { x + x }\nfn inc(x : Int) { x + 1 }\nlet f = compose inc double\nf 5",
  ),
]

///|
fn view_toolbar(dispatch : Emit[Msg], model : Model) -> Html {
  let example_buttons : Array[Html] = examples.map(fn(pair) {
    let (label, code) = pair
    button(
      class=@ui.toolbar_example_button_class(),
      on_click=dispatch(LoadExample(code)),
      [text(label)],
    )
  })
  let toolbar_items : Array[Html] = [
    span(class=toolbar_title_class, [text("Canopy Editor")]),
    div(class=toolbar_spacer_class, [text("")]),
    button(
      class=@ui.toolbar_tab_class(model.mode == Text),
      on_click=dispatch(SetMode(Text)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.mode == Text {
          "true"
        } else {
          "false"
        },
      ),
      [text("Text")],
    ),
    button(
      class=@ui.toolbar_tab_class(model.mode == Structure),
      on_click=dispatch(SetMode(Structure)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.mode == Structure {
          "true"
        } else {
          "false"
        },
      ),
      [text("Structure")],
    ),
    div(class=toolbar_spacer_class, [text("")]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(Undo), [
      text("Undo"),
    ]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(Redo), [
      text("Redo"),
    ]),
    div(class=toolbar_spacer_class, [text("")]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(OpenFile), [
      text("Open"),
    ]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(SaveFile), [
      text("Save"),
    ]),
    div(class=toolbar_spacer_class, [text("")]),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.outline_visible),
      on_click=dispatch(TogglePanel(Outline)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.outline_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Outline")],
    ),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.inspector_visible),
      on_click=dispatch(TogglePanel(Inspector)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.inspector_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Inspector")],
    ),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.bottom_visible),
      on_click=dispatch(TogglePanel(Bottom)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.bottom_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Panels")],
    ),
    div(class=toolbar_spacer_class, [text("")]),
  ]
  example_buttons.each(fn(b) { toolbar_items.push(b) })
  div(class=toolbar_class, toolbar_items)
}

///|
fn view_peer_status(model : Model) -> Html {
  let (label, tone) : (String, @status.Tone) = match model.sync_status {
    Connected => ("You (connected)", @status.Success)
    Connecting => ("Connecting\u{2026}", @status.Info)
    Offline => ("Offline \u{2014} reconnecting\u{2026}", @status.Info)
    Error => ("Connection error", @status.Error)
  }
  div(class=peer_item_class, attrs=tone.attrs(), [
    div(
      class=peer_dot_class(model.sync_status),
      attrs=@html.Attrs::build().aria_hidden("true"),
      [text("")],
    ),
    span(class="peer-label", [text(label)]),
  ])
}

///|
fn outline_panel_attrs(workspace : WorkspaceLayout) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .role("navigation")
    .aria_label("AST outline")
    .style("--outline-panel-width", workspace.outline_width_px())
  if workspace.outline_resize.is_resizing() {
    attrs.style("user-select", "none")
  } else {
    attrs
  }
}

///|
fn view_outline_resize_handle(
  dispatch : Emit[Msg],
  workspace : WorkspaceLayout,
) -> Html {
  div(
    class=outline_resize_handle_class,
    attrs=workspace.outline_resize.handle_attrs(@resizable.Edge::East, msg => {
      dispatch(OutlineResize(msg))
    }),
    [text("")],
  )
}

///|
fn view(dispatch : Emit[Msg], model : Model) -> Html {
  // Always render panels — toggle visibility via CSS class
  // so CSS transitions work for both enter and exit.
  let outline_class = if model.workspace.outline_visible {
    "outline-panel panel-visible"
  } else {
    "outline-panel panel-hidden"
  }
  let inspector_class = if model.workspace.inspector_visible {
    "inspector-panel panel-visible"
  } else {
    "inspector-panel panel-hidden"
  }
  let bottom_class = if model.workspace.bottom_visible {
    "bottom-panel panel-visible"
  } else {
    "bottom-panel panel-hidden"
  }
  let outline_attrs = outline_panel_attrs(model.workspace)
  let inspector_attrs = @html.Attrs::build()
    .role("complementary")
    .aria_label("Node inspector")
  // Scrim visible when either side panel is open (used on mobile as drawer backdrop)
  let scrim_class = if model.workspace.outline_visible ||
    model.workspace.inspector_visible {
    "panel-scrim"
  } else {
    "panel-scrim scrim-hidden"
  }
  div(class="app-shell", [
    view_toolbar(dispatch, model),
    div(class="workspace", [
      div(
        class=scrim_class,
        on_click=dispatch(DismissPanels),
        attrs=@html.Attrs::build().aria_hidden("true"),
        [text("")],
      ),
      div(class=outline_class, attrs=outline_attrs, [
        div(class=panel_header_class(), [
          span(class=@ui.panel_label_class(), [text("OUTLINE")]),
        ]),
        view_outline_content(dispatch, model),
        div(class=@ui.panel_section_class(), [
          span(class=@ui.panel_label_class(), [text("PEERS")]),
          view_peer_status(model),
        ]),
        view_outline_resize_handle(dispatch, model.workspace),
      ]),
      view_editor(dispatch, model),
      div(class=inspector_class, attrs=inspector_attrs, [
        view_inspector_content(dispatch, model),
      ]),
    ]),
    div(class=bottom_class, [view_bottom_content(dispatch, model)]),
    match model.overlay.active {
      Some((_, state, token)) =>
        @overlay_view.view_overlay(
          msg => dispatch(ActionOverlayMsg(token~, msg)),
          state,
        )
      None => @html.nothing
    },
  ])
}
