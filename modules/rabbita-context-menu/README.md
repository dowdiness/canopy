# Rabbita Context Menu

Headless context-menu behavior for Rabbita apps. The package owns open/closed
state, client-coordinate anchoring, menu ARIA attrs, keyboard navigation,
focus commands, and the items supplied when opening. It copies the input items,
so callers may safely reuse or mutate their source array after `open`. This is a
shallow copy: item values should themselves be immutable when used as reactive
state. `Model[T]` implements value equality when `T` implements `Eq`.

## Use

```mbt nocheck
struct Model {
  context_menu : @context_menu.Model[String]
} derive(Eq)

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

fn subscriptions(model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  model.context_menu.subscriptions(emit.map(msg => ContextMenu(msg)))
}
```

Open with `model.context_menu.open(anchor=point, items=items[:])`, then return
`@rabbita.batch([model.context_menu.position_cmd(), model.context_menu.focus_cmd()])`.
Handle `Activate(index)`, `Close`, `Dismiss(reason)`, and `Key(key)` in the
consumer. For navigation messages, call `Model::update`; when
`Msg::requests_focus()` is true, return `Model::focus_cmd()` after updating the
model.

`Model::focus_cmd_within(root_id=...)` only scopes active-item focus through the
same lookup strategy as `modules/rabbita-menu`. It does not make the full context-menu flow
shadow-root-ready: `position_cmd()` and `subscriptions()` still resolve the panel
from `document.getElementById(self.id)`, so context-menu panels should remain
document-visible until scoped positioning and dismissal APIs exist.

Pass the subscriptions function to `create_state(..., subscriptions~)`.
Rabbita calls it with `(model, emit)` and maintains its lifetime as state changes.
The subscription is present only while the menu is open. It emits
`Dismiss(PointerOutside)` for outside pointer
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

## State and action ownership

`Model[T]` owns one closed/open state. An open model contains its anchor, copied
items, and roving focus; a closed model contains none of them. Item count is
derived from the items rather than supplied separately. Render with `items()`
and resolve raw `Activate(index)` input with `item(index)` **before** closing.
Only an existing item can produce a domain operation.

Consumers still own action meaning, hit testing, styling, and mutation. Put a
complete operation in each item instead of pairing a separate optional target
with a generic action. Keep callbacks and mutable hosts outside reactive models.
Use `create_state` updates to return `(next_model, Cmd)`, execute mutations in
commands, and send their results back through `Emit`.

Canvas is a consumer example in `apps/canvas/main/context_menu.mbt` and
`context_menu_operations.mbt`:

- Runtime and Source operations carry only capabilities valid for that backing.
  Runtime insertion captures a world point; arrangement captures at least two
  node IDs. Current viewport or selection changes do not retarget the operation.
- Choosing an item closes the menu before its operation runs. Further activation
  while closed is ignored. Navigation and dismissal use the headless model's
  own messages and update function.
- Domain owners resolve liveness at execution. A removed target is an explicit
  expired outcome; source rejection and applied changes are distinct outcomes.
  Source failure DTOs remain failures, including raised graph errors. Disconnect
  also clears ephemeral selection on rejection; that change requests a redraw,
  not a successful source-edit notification.
  Source context-menu disconnect delegates to `SourceBackedGraph::disconnect_edge`,
  shared with keyboard deletion, after checking the captured edge's endpoints.
- Operation results update feedback and notify the host. There is no opening
  generation or special routing for delayed results.
- Invalid opening input reports a problem without consuming the existing menu
  or its selected target.

Dismissal of an already closed menu and unhandled keys remain normal
no-change transitions. They are not error suppression.

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
