# Rabbita Context Menu

Headless context-menu behavior for Rabbita apps. The package owns open/closed
state, client-coordinate anchoring, menu ARIA attrs, keyboard navigation, and
focus commands. It composes over `dowdiness/rabbita-menu/menu`; consumers still
own item data, rendering, hit-testing, styling, and action execution.

## Use

```mbt nocheck
struct Model {
  context_menu : @context_menu.Model
}

enum Msg {
  OpenMenu(@context_menu.Point)
  ContextMenu(@context_menu.Msg)
}

fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div([
    @html.div(
      attrs=model.context_menu.trigger_attrs(point => emit(OpenMenu(point))),
      "Right-click me",
    ),
    if model.context_menu.is_open() {
      @html.div(
        attrs=model.context_menu
          .panel_attrs(msg => emit(ContextMenu(msg)))
          .aria_label("Actions"),
        [
          @html.button(
            type_="button",
            attrs=model.context_menu.item_attrs(0, msg => emit(ContextMenu(msg))),
            "Rename",
          ),
        ],
      )
    } else {
      @html.nothing
    },
  ])
}

fn subscriptions(emit : @rabbita.Emit[Msg], model : Model) -> @sub.Sub {
  model.context_menu.subscriptions(emit.map(msg => ContextMenu(msg)))
}
```

Open with `model.context_menu.open(anchor=point, item_count=items.length())`,
then return `model.context_menu.focus_cmd()`. Handle `Activate(index)`, `Close`,
and `Key(key)` in the consumer. For navigation messages, call
`Model::update`; when `Msg::requests_focus()` is true, return
`Model::focus_cmd()` after updating the model.

Return `model.context_menu.subscriptions(...)` from the owning cell's
subscriptions callback to install reusable dismissal behavior while the menu is
open. The subscription emits `Close` for outside pointer presses and for Escape
when focus is outside the menu panel; Escape inside the panel is handled by
`panel_attrs`.

`Point` is in viewport/client coordinates, including fractional browser
coordinates when available. `panel_attrs` uses those coordinates for fixed
`left`/`top` anchoring.

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/rabbita/html/README.mbt.md`
- `rabbita/rabbita/html/attrs_event.mbt`
- `rabbita/rabbita/dom/mouse_event.mbt`
- `rabbita/doc/using_subscriptions/readme.mbt.md`
- `rabbita/rabbita/sub/README.mbt.md`
- `rabbita/rabbita/sub/design.md`
- `rabbita/rabbita/dom/README.mbt.md`
- `rabbita/rabbita/cmd/commands.mbt`
