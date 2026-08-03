///|
/// Resolve transient application selection only through the typed snapshot.
fn active_block(model : DriverModel) -> @markdown.MarkdownBlockSnapshot? {
  match model.active_block_key {
    None => None
    Some(key) =>
      model.document
      .blocks()
      .fold(init=None, (selected, block) => {
        match selected {
          Some(_) => selected
          None => if block.key() == key { Some(block) } else { None }
        }
      })
  }
}

///|
/// Resolve a keyboard event's stable typed target before falling back to the
/// toolbar selection, whose focus event may still be queued.
fn block_format_target(
  model : DriverModel,
  selection : BlockSelection?,
) -> @markdown.MarkdownBlockSnapshot? {
  match selection {
    None => active_block(model)
    Some(selection) => {
      let exact = model.document
        .blocks()
        .fold(init=None, (selected, block) => {
          match selected {
            Some(_) => selected
            None =>
              if block.key() == selection.key {
                Some(block)
              } else {
                None
              }
          }
        })
      match exact {
        Some(_) => exact
        None => active_block(model)
      }
    }
  }
}

///|
fn heading_toolbar_button(
  level : Int,
  selected_level : Int?,
  disabled : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @html.Html {
  let shortcut = "Control+" + level.to_string()
  let label = "Heading " + level.to_string() + ", Ctrl+" + level.to_string()
  @rui.button(
    id="loomark-heading-" + level.to_string(),
    variant=@rui.Ghost,
    size=@rui.Sm,
    disabled~,
    title=label,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .aria_keyshortcuts(shortcut)
      .aria_pressed((selected_level == Some(level)).to_string()),
    on_click=emit(BlockHeading(level, None)),
    "H" + level.to_string(),
  )
}

///|
fn list_toolbar_button(
  selected : Bool,
  disabled : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @html.Html {
  let label = "Toggle list, Ctrl+Shift+L"
  @rui.button(
    id="loomark-toggle-list",
    variant=@rui.Ghost,
    size=@rui.Sm,
    disabled~,
    title=label,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .aria_keyshortcuts("Control+Shift+L")
      .aria_pressed(selected.to_string()),
    on_click=emit(BlockToggleList(None)),
    mode_icon("M6 6h11M6 10h11M6 14h11M3 6h.01M3 10h.01M3 14h.01"),
  )
}

///|
fn delete_toolbar_button(
  disabled : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @html.Html {
  @rui.button(
    id="loomark-delete-block",
    variant=@rui.Ghost,
    size=@rui.IconSm,
    disabled~,
    title="Delete block",
    attrs=@html.Attrs::build().aria_label("Delete selected block"),
    on_click=emit(BlockDelete),
    mode_icon("M4 6h12M8 3h4l1 3H7l1-3M6 6l.7 11h6.6L14 6M8.5 9v5M11.5 9v5"),
  )
}

///|
fn block_format_toolbar(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @html.Html {
  let selected = active_block(model)
  let selected_level = selected.bind(block => {
    match block.kind() {
      @markdown.Heading(level~) => Some(level)
      _ => None
    }
  })
  let heading_allowed = selected
    .map(block => block_allows_heading(block.kind()))
    .unwrap_or(false)
  let selected_list = selected
    .map(block => {
      match block.kind() {
        @markdown.UnorderedListItem | @markdown.OrderedListItem(..) => true
        _ => false
      }
    })
    .unwrap_or(false)
  let list_allowed = selected
    .map(block => block_allows_list(block.kind()))
    .unwrap_or(false)
  let delete_disabled = selected is None
  @html.div(
    attrs=@html.Attrs::build().role("toolbar").aria_label("Block formatting"),
    style=[
      "display:flex;min-height:3.75rem;box-sizing:border-box;align-items:center;justify-content:space-between;padding:0.75rem 1rem;border-bottom:1px solid var(--rui-border)",
    ],
    [
      @rui.button_group(aria_label="Block style", [
        heading_toolbar_button(1, selected_level, !heading_allowed, emit),
        heading_toolbar_button(2, selected_level, !heading_allowed, emit),
        heading_toolbar_button(3, selected_level, !heading_allowed, emit),
        @rui.button_group_separator(),
        list_toolbar_button(selected_list, !list_allowed, emit),
      ]),
      @rui.button_group(aria_label="Block actions", [
        delete_toolbar_button(delete_disabled, emit),
      ]),
    ],
  )
}
