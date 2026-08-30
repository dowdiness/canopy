///|
/// Shared native control used by the copied Sidebar actions.
fn[C : @html.IsChildren] dialog_control_button(
  slot~ : String,
  command~ : @cmd.Cmd,
  variant~ : ButtonVariant,
  size~ : ButtonSize,
  disabled~ : Bool,
  id~ : String?,
  class~ : String?,
  title~ : String?,
  aria_label~ : String?,
  on_click~ : @cmd.Cmd?,
  attrs~ : @html.Attrs?,
  style~ : Array[String],
  children : C,
) -> @html.Html {
  let control_attrs = ui_attrs(attrs)
    .data_set("slot", slot)
    .data_set("variant", button_variant_value(variant))
    .data_set("size", button_size_value(size))
  ignore(control_attrs.aria_disabled(ui_bool(disabled)))
  if aria_label is Some(label) {
    ignore(control_attrs.aria_label(label))
  }
  if disabled {
    ignore(control_attrs.data_set("disabled", ""))
  } else {
    if on_click is Some(on_click) {
      ignore(control_attrs.on_click(_ => on_click))
    }
    ignore(control_attrs.on_click(_ => command))
  }
  @html.button(
    style=ui_styles(
      [
        UiBoxSizing,
        UiFontSans,
        UiTextRendering,
        UiTransition,
        ButtonBaseStyle,
        button_variant_style(variant),
        button_size_style(size),
        ui_disabled_style(disabled),
      ],
      style,
    ),
    id?,
    class?,
    title?,
    type_="button",
    disabled~,
    attrs=control_attrs,
    children,
  )
}
