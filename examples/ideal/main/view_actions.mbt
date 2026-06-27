///|
/// Group label for each ActionGroup.
fn group_label(group : @lambda_edits.ActionGroup) -> String {
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
  emit : @rabbita.Emit[OverlayMsg],
  menu : @menu.Model,
  index : Int,
  action : @lambda_edits.Action,
) -> @rabbita.Html {
  let is_danger = action.id == "delete" || action.id == "binding_delete"
  let item_class = if is_danger {
    action_overlay_item_danger_class
  } else {
    action_overlay_item_class
  }
  @html.div(
    class=item_class,
    attrs=menu.item_attrs(index, msg => emit(Menu(msg))),
    [
      @html.span(class=action_mnemonic_class, [@html.text(action.mnemonic)]),
      @html.span(class=action_label_text_class, [@html.text(action.label)]),
    ],
  )
}

///|
/// Render the main action list grouped by Core / Wrap / Binding / Module.
fn view_action_list(
  emit : @rabbita.Emit[OverlayMsg],
  menu : @menu.Model,
  actions : Array[@lambda_edits.Action],
) -> @rabbita.Html {
  let items : Array[@rabbita.Html] = []
  let mut current_group : @lambda_edits.ActionGroup? = None
  for index, action in actions {
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
            class=action_group_label_class,
            attrs=@html.Attrs::build().role("separator"),
            [@html.text(group_label(action.group))],
          ),
        )
      }
    }
    items.push(view_action_item(emit, menu, index, action))
  }
  @html.div(class=action_overlay_list_class, items)
}

///|
fn name_prompt_label(action : @lambda_edits.Action) -> String {
  match action.id {
    "rename" | "binding_rename" => "New name"
    "extract_to_let" => "Variable name"
    "wrap_lambda" => "Parameter name"
    "add_binding" => "Binding name"
    _ => action.label
  }
}

///|
/// Render the name prompt input.
fn view_name_prompt(
  emit : @rabbita.Emit[OverlayMsg],
  state : OverlayState,
) -> @rabbita.Html {
  let (prompt_label, name_value) = match state.mode {
    NamePrompt(action, value~) => (name_prompt_label(action), value)
    _ => ("Enter name", "")
  }
  let on_keydown_handler = fn(kb : @html.Keyboard) {
    let key = kb.key()
    if key == "Enter" {
      emit(NameSubmit)
    } else if key == "Escape" {
      emit(NameCancel)
    } else {
      @rabbita.none
    }
  }
  @html.div(class=name_prompt_container_class, [
    @html.div(class=name_prompt_label_class, [@html.text(prompt_label)]),
    @html.div(
      class=name_prompt_input_row_class,
      on_keydown=on_keydown_handler,
      [
        @html.input(
          input_type=@html.InputType::Text,
          class=name_prompt_input_class,
          placeholder="name\u{2026}",
          value=name_value,
          autofocus=true,
          on_input=fn(value) { emit(NameInput(value)) },
          attrs=@html.Attrs::build().aria_label(prompt_label),
        ),
      ],
    ),
  ])
}

///|
/// Render submenu choices (e.g., Plus/Minus for change_op, left/right for unwrap).
fn view_submenu_choices(
  emit : @rabbita.Emit[OverlayMsg],
  menu : @menu.Model,
  action : @lambda_edits.Action,
  kind : @ast.Term,
) -> @rabbita.Html {
  let choices = get_submenu_choices(action.id, kind)
  let items : Array[@rabbita.Html] = []
  items.push(
    @html.div(
      class=action_group_label_class,
      attrs=@html.Attrs::build().role("separator"),
      [@html.text(action.label)],
    ),
  )
  for i, choice in choices {
    let (label, _) = choice
    items.push(
      @html.div(
        class=action_overlay_item_class,
        attrs=menu.item_attrs(i, msg => emit(Menu(msg))),
        [
          @html.span(class=action_mnemonic_class, [
            @html.text((i + 1).to_string()),
          ]),
          @html.span(class=action_label_text_class, [@html.text(label)]),
        ],
      ),
    )
  }
  @html.div(class=action_overlay_list_class, items)
}

///|
/// Render an overlay-wide error. Actions can fail from any open overlay mode
/// (MainMenu, Submenu, or NamePrompt), so errors live at the panel top.
fn view_action_overlay_error(err : OverlayError?) -> @rabbita.Html {
  match err {
    None => @html.nothing
    Some(e) =>
      @html.div(
        class=action_overlay_error_class,
        attrs=@html.Attrs::build().role("alert").aria_live("polite"),
        [@html.text(format_overlay_error(e))],
      )
  }
}

///|
/// Render the action overlay: scrim + positioned panel.
/// Returns nothing if the overlay is not visible.
fn view_overlay(
  emit : @rabbita.Emit[OverlayMsg],
  state : OverlayState,
) -> @rabbita.Html {
  if !state.is_open() {
    return @html.nothing
  }
  // Position the overlay panel using inline style from the anchor rect
  let top = state.anchor_top
  let left = state.anchor_left
  let position_style = "top: \{top}px; left: \{left}px;"
  // Determine content: name prompt, submenu, or main action list
  let content : @rabbita.Html = match state.mode {
    NamePrompt(_, ..) => view_name_prompt(emit, state)
    Submenu(sub_action) =>
      view_submenu_choices(emit, state.menu, sub_action, state.kind)
    MainMenu => view_action_list(emit, state.menu, state.actions)
  }
  let panel_attrs = match state.mode {
    NamePrompt(_, ..) =>
      @html.Attrs::build()
      .role("dialog")
      .aria_label("Structural editing name prompt")
      .style_attr(position_style)
    _ =>
      state.menu
      .panel_attrs(msg => emit(Menu(msg)))
      .aria_label("Structural editing actions")
      .style_attr(position_style)
  }
  @html.fragment([
    // Scrim: click-catching backdrop
    @html.div(
      class=action_overlay_scrim_class,
      attrs=@menu.scrim_attrs(emit(NameCancel)),
      @html.nothing,
    ),
    // Overlay panel — roving focus moves to the active menu item after render.
    @html.div(class=action_overlay_panel_class, attrs=panel_attrs, [
      view_action_overlay_error(state.error),
      content,
    ]),
  ])
}
