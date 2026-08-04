# Rabbita Resizable

Headless resize behavior for Rabbita apps. The package owns resize state,
messages, accessibility attributes, and document-level drag subscriptions; the
consumer owns all HTML structure and styling.

## Use

```mbt nocheck
// In your app model:
struct Model {
  panel : @resizable.Model
}

// In view:
@html.div(
  class="panel",
  attrs=model.panel.container_attrs(),
  [
    @html.div("content"),
    @html.div(
      class="panel-handle",
      attrs=model.panel.handle_attrs(
        @resizable.Edge::East,
        msg => emit(PanelResize(msg)),
      ),
      @html.nothing,
    ),
  ],
)

// In subscriptions:
model.panel.subscriptions(msg => emit(PanelResize(msg)))
```

`Model::new` requires `1 <= min <= max` on both axes and clamps the initial
size into the constraint bounds.

## Design question report

- **Q1 Packaging:** keep this as a standalone module (`dowdiness/rabbita-resizable`) for v1. It can move upstream once the API shape has real consumers.
- **Q2 Custom `mouseup` sub:** keep it isolated in `subscriptions.mbt` now. Recommendation: upstream `@sub.on_mouse_up` later, because `mousemove` already exists and the symmetry belongs in Rabbita.
- **Q3 Edge granularity:** ship `East`, `South`, and `SouthEast` only. The `Msg` payload already carries an `Edge`, so adding origin-moving edges later is source-compatible for message routing, but consumers will need new layout/repositioning logic.
- **Q4 Keyboard step:** v1 uses a fixed 8px step and orientation-specific arrows, with no Shift multiplier. Recommendation: add configurable step/large-step options only after consumer feedback.
- **Q5 Subscriptions surface:** keep `Model::subscriptions` as a helper. It removes boilerplate for one instance; consumers with several active instances must batch helpers and should ensure only one resize is active at a time because Rabbita subscription keys are singleton-style.

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/rabbita/tea.mbt`
- `rabbita/rabbita/html/{attrs.mbt,attrs_event.mbt,html.mbt,children.mbt}`
- `rabbita/rabbita/dom/{mouse_event.mbt,keyboard_event.mbt,event_target.mbt}`
- `rabbita/rabbita/sub/{sub.mbt,design.md,README.mbt.md}`
- `rabbita/rabbita/websocket/listen.mbt`
