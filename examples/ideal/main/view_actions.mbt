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
  dispatch : @rabbita.Emit[Msg],
  menu : @menu.Model,
  index : Int,
  action : @lambda_edits.Action,
) -> @rabbita.Html {
  let is_danger = action.id == "delete" || action.id == "binding_delete"
  let item_class = if is_danger {
    "action-overlay-item danger"
  } else {
    "action-overlay-item"
  }
  @html.div(
    class=item_class,
    attrs=menu.item_attrs(index, msg => dispatch(ActionMenu(msg))),
    [
      @html.span(class="action-mnemonic", [@html.text(action.mnemonic)]),
      @html.span(class="action-label-text", [@html.text(action.label)]),
    ],
  )
}

///|
/// Render the main action list grouped by Core / Wrap / Binding / Module.
fn view_action_list(
  dispatch : @rabbita.Emit[Msg],
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
            class="action-group-label",
            attrs=@html.Attrs::build().role("separator"),
            [@html.text(group_label(action.group))],
          ),
        )
      }
    }
    items.push(view_action_item(dispatch, menu, index, action))
  }
  @html.div(class="action-overlay-list", items)
}

///|
/// Render the name prompt input.
fn view_name_prompt(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let prompt_label = match model.overlay.mode {
    NamePrompt(action) =>
      match action.id {
        "rename" | "binding_rename" => "New name"
        "extract_to_let" => "Variable name"
        "wrap_lambda" => "Parameter name"
        "add_binding" => "Binding name"
        _ => action.label
      }
    _ => "Enter name"
  }
  let error_el : @rabbita.Html = if model.overlay.name_error != "" {
    @html.div(
      class="name-prompt-error",
      attrs=@html.Attrs::build().role("alert").aria_live("polite"),
      [@html.text(model.overlay.name_error)],
    )
  } else {
    @html.nothing
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
      ),
    ]),
    error_el,
  ])
}

///|
/// Render submenu choices (e.g., Plus/Minus for change_op, left/right for unwrap).
fn view_submenu_choices(
  dispatch : @rabbita.Emit[Msg],
  menu : @menu.Model,
  action : @lambda_edits.Action,
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
    let (label, _) = choice
    items.push(
      @html.div(
        class="action-overlay-item",
        attrs=menu.item_attrs(i, msg => dispatch(ActionMenu(msg))),
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
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  if !model.overlay.is_open() {
    return @html.nothing
  }
  // Position the overlay panel using inline style from the anchor rect
  let top = model.overlay.anchor_top
  let left = model.overlay.anchor_left
  let position_style = "top: \{top}px; left: \{left}px;"
  // Determine content: name prompt, submenu, or main action list
  let content : @rabbita.Html = match model.overlay.mode {
    NamePrompt(_) => view_name_prompt(dispatch, model)
    Submenu(sub_action) =>
      match model.overlay.node_context {
        Some(ctx) =>
          view_submenu_choices(
            dispatch,
            model.overlay.menu,
            sub_action,
            ctx.kind,
          )
        None =>
          view_action_list(dispatch, model.overlay.menu, model.overlay.actions)
      }
    MainMenu | Closed =>
      view_action_list(dispatch, model.overlay.menu, model.overlay.actions)
  }
  @html.fragment([
    // Scrim: click-catching backdrop
    @html.div(
      class="action-overlay-scrim",
      attrs=@menu.scrim_attrs(dispatch(CloseActionOverlay)),
      @html.nothing,
    ),
    // Overlay panel — roving focus moves to the active menu item after render.
    @html.div(
      class="action-overlay-panel",
      attrs=model.overlay.menu
        .panel_attrs(msg => dispatch(ActionMenu(msg)))
        .aria_label("Structural editing actions")
        .style_attr(position_style),
      [content],
    ),
  ])
}
