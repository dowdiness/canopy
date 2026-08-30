///|
/// Shared RUI Vega foundations needed by the copied Sidebar source.
const UiFontSans : String = "font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif"

///|
const UiBoxSizing : String = "box-sizing:border-box"

///|
const UiTextRendering : String = "-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility"

///|
const UiTransition : String = "transition:color 150ms ease,background-color 150ms ease,border-color 150ms ease,box-shadow 150ms ease,opacity 150ms ease,transform 150ms ease"

///|
const UiDisabled : String = "cursor:not-allowed;pointer-events:none;opacity:0.5"

///|
/// Base input recipe used by the optional Sidebar input helper.
const InputBaseStyle : String = "display:flex;width:100%;height:2.25rem;min-width:0;--rui-control-base-bg:var(--rui-input-background,transparent);--rui-control-base-fg:var(--rui-foreground,oklch(0.145 0 0));--rui-control-base-border:var(--rui-input,oklch(0.922 0 0));--rui-control-base-shadow:0 1px 2px rgb(0 0 0 / 0.05);border:1px solid transparent;border-color:var(--rui-control-border,var(--rui-control-base-border,var(--rui-input,oklch(0.922 0 0))));border-radius:calc(var(--rui-radius,0.625rem) - 0.125rem);background:var(--rui-control-bg,var(--rui-control-base-bg,var(--rui-input-background,transparent)));padding:0.25rem 0.625rem;color:var(--rui-control-fg,var(--rui-control-base-fg,var(--rui-foreground,oklch(0.145 0 0))));box-shadow:var(--rui-control-shadow,var(--rui-control-base-shadow,0 1px 2px rgb(0 0 0 / 0.05)));font-size:1rem;line-height:1.5rem;outline-offset:2px"

///|
fn ui_disabled_style(disabled : Bool) -> String {
  if disabled {
    UiDisabled
  } else {
    ""
  }
}

///|
fn ui_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn ui_attrs(attrs : @html.Attrs?) -> @html.Attrs {
  if attrs is Some(attrs) {
    attrs.copy()
  } else {
    @html.Attrs::build()
  }
}

///|
fn ui_styles(parts : Array[String], extra : Array[String]) -> Array[String] {
  let styles : Array[String] = []
  for part in parts {
    if part != "" {
      styles.push(part)
    }
  }
  for part in extra {
    if part != "" {
      styles.push(part)
    }
  }
  styles
}
