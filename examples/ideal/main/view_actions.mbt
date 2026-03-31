///|
/// Group label for each ActionGroup.
fn group_label(group : @proj.ActionGroup) -> String {
  match group {
    Core => "Core"
    Wrap => "Wrap"
    Binding => "Binding"
    Module => "Module"
  }
}

///|
/// Render a single action row with mnemonic badge and label.
fn view_action_item(
  dispatch : @rabbita.Dispatch[Msg],
  action : @proj.Action,
) -> @rabbita.Html {
  let is_danger = action.id == "delete" || action.id == "binding_delete"
  let item_class = if is_danger {
    "action-overlay-item danger"
  } else {
    "action-overlay-item"
  }
  @html.div(
    class=item_class,
    on_click=dispatch(ActionTapped(action.id)),
    attrs=@html.Attrs::build().role("menuitem").tabindex(0),
    [
      @html.span(class="action-mnemonic", [@html.text(action.mnemonic)]),
      @html.span(class="action-label-text", [@html.text(action.label)]),
    ],
  )
}

///|
/// Render the main action list grouped by Core / Wrap / Binding / Module.
fn view_action_list(
  dispatch : @rabbita.Dispatch[Msg],
  actions : Array[@proj.Action],
) -> @rabbita.Html {
  let items : Array[@rabbita.Html] = []
  let mut current_group : @proj.ActionGroup? = None
  actions.each(fn(action) {
    let need_header = match current_group {
      None => true
      Some(g) => g != action.group
    }
    if need_header {
      current_group = Some(action.group)
      // Don't show header for Core (it's the default first group)
      if action.group != Core {
        items.push(
          @html.div(
            class="action-group-label",
            attrs=@html.Attrs::build().role("separator"),
            [@html.text(group_label(action.group))],
          ),
        )
      }
    }
    items.push(view_action_item(dispatch, action))
  })
  @html.div(class="action-overlay-list", items)
}

///|
/// Render the name prompt input.
fn view_name_prompt(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let prompt_label = match model.overlay.pending_action {
    Some(action) =>
      match action.id {
        "rename" | "binding_rename" => "New name"
        "extract_to_let" => "Variable name"
        "wrap_lambda" => "Parameter name"
        "add_binding" => "Binding name"
        _ => action.label
      }
    None => "Enter name"
  }
  let error_el : @rabbita.Html = if model.overlay.name_error != "" {
    @html.div(
      class="name-prompt-error",
      attrs=@html.Attrs::build().role("alert").aria_live("polite"),
      [@html.text(model.overlay.name_error)],
    )
  } else {
    @html.text("")
  }
  let on_keydown_handler = fn(kb : @html.Keyboard) {
    let key = kb.key()
    if key == "Enter" {
      dispatch(NamePromptSubmit)
    } else if key == "Escape" {
      dispatch(NamePromptCancel)
    } else {
      @rabbita.none
    }
  }
  @html.div(class="name-prompt-container", [
    @html.div(class="name-prompt-label", [@html.text(prompt_label)]),
    @html.div(class="name-prompt-input-row", on_keydown=on_keydown_handler, [
      @html.input(
        input_type=@html.InputType::Text,
        class="name-prompt-input",
        placeholder="name\u{2026}",
        value=model.overlay.name_value,
        autofocus=true,
        on_input=fn(value) { dispatch(NamePromptInput(value)) },
        attrs=@html.Attrs::build().aria_label(prompt_label),
        [@html.text("")],
      ),
    ]),
    error_el,
  ])
}

///|
/// Render submenu choices (e.g., Plus/Minus for change_op, left/right for unwrap).
fn view_submenu_choices(
  dispatch : @rabbita.Dispatch[Msg],
  action : @proj.Action,
  kind : @ast.Term,
) -> @rabbita.Html {
  let choices = get_submenu_choices(action.id, kind)
  let items : Array[@rabbita.Html] = []
  items.push(
    @html.div(
      class="action-group-label",
      attrs=@html.Attrs::build().role("separator"),
      [@html.text(action.label)],
    ),
  )
  for i, choice in choices {
    let (label, value) = choice
    items.push(
      @html.div(
        class="action-overlay-item",
        on_click=dispatch(ActionTapped(action.id + ":" + value)),
        attrs=@html.Attrs::build().role("menuitem").tabindex(0),
        [
          @html.span(class="action-mnemonic", [@html.text((i + 1).to_string())]),
          @html.span(class="action-label-text", [@html.text(label)]),
        ],
      ),
    )
  }
  @html.div(class="action-overlay-list", items)
}

///|
/// Render the action overlay: scrim + positioned panel.
/// Returns nothing if the overlay is not visible.
fn view_action_overlay(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  if !(model.overlay.visible) {
    return @html.text("")
  }
  // Position the overlay panel using inline style from the anchor rect
  let top = model.overlay.anchor_top
  let left = model.overlay.anchor_left
  let position_style = "top: \{top}px; left: \{left}px;"
  // Determine content: name prompt, submenu, or main action list
  let content : @rabbita.Html = if !(model.overlay.pending_action is None) {
    view_name_prompt(dispatch, model)
  } else if !(model.overlay.submenu is None) {
    match (model.overlay.submenu, model.overlay.node_context) {
      (Some(sub_action), Some(ctx)) =>
        view_submenu_choices(dispatch, sub_action, ctx.kind)
      _ => view_action_list(dispatch, model.overlay.actions)
    }
  } else {
    view_action_list(dispatch, model.overlay.actions)
  }
  @html.fragment([
    // Scrim: click-catching backdrop, also handles Escape via keydown
    @html.div(
      class="action-overlay-scrim",
      on_click=dispatch(CloseActionOverlay),
      on_keydown=fn(kb : @html.Keyboard) {
        if kb.key() == "Escape" {
          dispatch(CloseActionOverlay)
        } else {
          @rabbita.none
        }
      },
      attrs=@html.Attrs::build().aria_hidden("true").tabindex(-1),
      [@html.text("")],
    ),
    // Overlay panel — receives focus on open via after_render in main.mbt
    @html.div(
      class="action-overlay-panel",
      on_keydown=fn(kb : @html.Keyboard) {
        let key = kb.key()
        if key == "Escape" {
          dispatch(CloseActionOverlay)
        } else if key.length() == 1 {
          // Only forward single-char keys (mnemonics & digit choices).
          // Ignore navigation keys (ArrowUp, Tab, Enter, etc.) that would
          // incorrectly close submenus.
          dispatch(ActionKeyPressed(key))
        } else {
          @rabbita.none
        }
      },
      attrs=@html.Attrs::build()
        .role("menu")
        .aria_label("Structural editing actions")
        .tabindex(-1)
        .style_attr(position_style),
      [content],
    ),
  ])
}
