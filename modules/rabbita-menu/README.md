# Rabbita Menu

Headless action-menu behavior for Rabbita apps. The package owns menu state,
keyboard navigation, activation messages, focus attributes, and ARIA roles; the
consumer owns item data, grouping, domain execution, HTML structure, and styling.

## Use

```mbt nocheck
struct Model {
  menu : @menu.Model
}

enum Msg {
  Menu(@menu.Msg)
}

fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(
    class="menu-panel",
    attrs=model.menu
      .panel_attrs(msg => emit(Menu(msg)))
      .aria_label("Actions"),
    [
      @html.div(
        class="menu-item",
        attrs=model.menu.item_attrs(0, msg => emit(Menu(msg))),
        "Rename",
      ),
    ],
  )
}
```

Handle `Activate(index)`, `Close`, and `Key(key)` in the consumer update. Apply
navigation messages with `Model::update`; when `Msg::requests_focus()` is true,
return `Model::focus_cmd()` after the model is updated so roving tabindex moves
actual DOM focus after Rabbita patches the view.

## Focus scope

`Model::focus_cmd()` uses Rabbita's after-render command hook and focuses the
active item with document-level `getElementById`. Use it for normal light-DOM
menus whose generated item ids are document-unique.

For menus rendered inside a scoped container or an open shadow root, use
`Model::focus_cmd_within(root_id=...)` instead. `root_id` is resolved from the
document; if that element has `shadowRoot`, lookup happens inside the shadow
root, otherwise lookup happens under the root element. Closed shadow roots or
roots that cannot be found by document id need a consumer-owned custom command.

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/rabbita/html/{attrs.mbt,attrs_event.mbt,README.mbt.md}`
- `rabbita/rabbita/dom/{keyboard_event.mbt,event.mbt,Document.mbt,html_element.mbt}`
- `rabbita/rabbita/cmd/commands.mbt`
