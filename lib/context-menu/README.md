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

fn new_model() -> Model {
  {
    context_menu: @context_menu.Model::new(id="actions-menu")
      .with_close_focus_id("menu-origin"),
  }
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
then return `@rabbita.batch([model.context_menu.position_cmd(), model.context_menu.focus_cmd()])`.
Handle `Activate(index)`, `Close`, `Dismiss(reason)`, and `Key(key)` in the
consumer. For navigation messages, call `Model::update`; when
`Msg::requests_focus()` is true, return `Model::focus_cmd()` after updating the
model. If the context menu is rendered under a scoped container or open shadow
root, use `Model::focus_cmd_within(root_id=...)` instead so item focus is looked
up through the same scoped menu strategy as `lib/menu`.

Return `model.context_menu.subscriptions(...)` from the owning cell's
subscriptions callback to install reusable dismissal behavior while the menu is
open. The subscription emits `Dismiss(PointerOutside)` for outside pointer
presses and `Dismiss(EscapeKey)` for Escape when focus is outside the menu panel;
Escape inside the panel is handled by `panel_attrs` as `Close`.

Call `model.context_menu.with_close_focus_id(...)` when a close path should be
able to restore focus to a stable origin. After handling `Activate`, `Close`, or
a dismissal message, use `Msg::requests_close_focus()` to decide whether to batch
`model.context_menu.close_focus_cmd()` with the consumer's close effects. Pointer
outside dismissal deliberately does not request close-focus restoration, so a
click into another control can keep focus there.

`Point` is in viewport/client coordinates, including fractional browser
coordinates when available. `panel_attrs` uses those coordinates for initial
fixed `left`/`top` anchoring. `Model::position_cmd(positioning?)` can then
measure the rendered panel after render and apply `Positioning` options:

- `offset_x` / `offset_y` add a visual offset from the anchor.
- `viewport_margin` controls the minimum gap from viewport edges.
- `collision=ClampToViewport` keeps the measured panel visible; use
  `NoCollisionHandling` to keep raw anchor positioning.

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/rabbita/internal/runtime/README.mbt.md`
- `rabbita/rabbita/html/README.mbt.md`
- `rabbita/rabbita/html/attrs_event.mbt`
- `rabbita/rabbita/dom/mouse_event.mbt`
- `rabbita/doc/using_subscriptions/readme.mbt.md`
- `rabbita/rabbita/sub/README.mbt.md`
- `rabbita/rabbita/sub/design.md`
- `rabbita/rabbita/dom/README.mbt.md`
- `rabbita/rabbita/cmd/commands.mbt`
