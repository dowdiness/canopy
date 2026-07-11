# Rabbita Tabs

Headless tablist behavior for Rabbita apps. The package owns roving tabindex,
horizontal keyboard navigation (ArrowLeft/Right wrap, Home/End jump), focus
movement, and ARIA roles/relationships; the consumer owns the tab data, panel
ids, selected state, HTML structure, and styling.

The behavior is automatic-activation (selection follows focus) and derived, not a
store: durable selection stays in the consumer's own model, and a `Model` is
rebuilt each render from `(id, tab_count, selected)`. Keyboard navigation reports
the tab index that should become selected; the consumer maps that index onto its
own domain via the `dispatch` callback.

## Use

```mbt nocheck
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let tab_defs = [(Problems, "Problems"), (OpLog, "Op Log")]
  let selected = index_of(model.bottom_tab, tab_defs)
  let tabs = @tabs.Model::new(
    id="canopy-bottom-tabs",
    tab_count=tab_defs.length(),
    selected~,
  )
  let buttons = []
  for i in 0..<tab_defs.length() {
    let (tab, label) = tab_defs[i]
    buttons.push(
      @html.button(
        class="tab",
        attrs=tabs.tab_attrs(
          i,
          panel_id=panel_id(tab),
          dispatch=j => emit(SelectTab(tab_defs[j].0)),
        ),
        label,
      ),
    )
  }
  @html.div(class="tabs", attrs=@tabs.tablist_attrs(label="Sections"), buttons)
}
```

Render the active tabpanel with `Model::panel_attrs(index, panel_id=...)`. After
updating the selected tab in the consumer model, return `Model::focus_cmd()` so
roving tabindex moves actual DOM focus once Rabbita patches the view.

**Invariant — the consumer owns panel ids and must pass the same `panel_id` for a
given tab to both `tab_attrs` and `panel_attrs`.** `tab_attrs` emits
`aria-controls=panel_id` on the selected tab and `panel_attrs` emits that id as
the panel's `id`; the library can't enforce that they agree, so a mismatch
silently breaks the tab↔panel ARIA relationship with no compile error. (Tab
*button* ids are owned by the library, so `aria-labelledby` always round-trips.)

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/rabbita/html/{attrs.mbt,attrs_event.mbt,README.mbt.md}`
- `rabbita/doc/002_writing_html/readme.mbt.md`
- `rabbita/doc/004_using_command/readme.mbt.md`
- `rabbita/rabbita/cmd/commands.mbt`
