///|
/// Button recipes retained from RUI for Sidebar controls.
priv enum ButtonVariant {
  Ghost
}

///|
priv enum ButtonSize {
  IconXs
  IconSm
}

///|
const ButtonBaseStyle : String = "display:inline-flex;flex-shrink:0;align-items:center;justify-content:center;gap:var(--rui-button-gap,0.5rem);--rui-button-base-bg:transparent;--rui-button-base-fg:currentColor;--rui-button-base-border:transparent;--rui-button-base-shadow:none;--rui-button-padding-inline:1rem;--rui-button-icon-size:1rem;border-style:solid;border-color:var(--rui-button-border,var(--rui-button-base-border,transparent));border-top-width:var(--rui-control-border-top-width,var(--rui-control-border-width,1px));border-right-width:var(--rui-control-border-right-width,var(--rui-control-border-width,1px));border-bottom-width:var(--rui-control-border-bottom-width,var(--rui-control-border-width,1px));border-left-width:var(--rui-control-border-left-width,var(--rui-control-border-width,1px));border-top-left-radius:var(--rui-control-radius-top-left,var(--rui-control-radius,calc(var(--rui-radius,0.625rem) - 0.125rem)));border-top-right-radius:var(--rui-control-radius-top-right,var(--rui-control-radius,calc(var(--rui-radius,0.625rem) - 0.125rem)));border-bottom-right-radius:var(--rui-control-radius-bottom-right,var(--rui-control-radius,calc(var(--rui-radius,0.625rem) - 0.125rem)));border-bottom-left-radius:var(--rui-control-radius-bottom-left,var(--rui-control-radius,calc(var(--rui-radius,0.625rem) - 0.125rem)));margin:0;padding-block:0;padding-inline:var(--rui-button-padding-inline);background:var(--rui-button-bg,var(--rui-button-base-bg,transparent));background-clip:padding-box;color:var(--rui-button-fg,var(--rui-button-base-fg,currentColor));box-shadow:var(--rui-button-shadow,var(--rui-button-base-shadow,none));font-size:0.875rem;line-height:1.25rem;font-weight:500;white-space:nowrap;cursor:pointer;user-select:none;appearance:none;-webkit-appearance:none;outline:none;vertical-align:middle"

///|
const ButtonGhostStyle : String = "--rui-button-base-bg:transparent;--rui-button-base-fg:var(--rui-foreground,oklch(0.145 0 0));--rui-button-base-border:transparent;--rui-button-base-shadow:none"

///|
const ButtonSizeIconXsStyle : String = "width:1.5rem;height:1.5rem;--rui-button-padding-inline:0;--rui-button-icon-size:0.75rem"

///|
const ButtonSizeIconSmStyle : String = "width:2rem;height:2rem;--rui-button-padding-inline:0"

///|
fn button_variant_value(variant : ButtonVariant) -> String {
  match variant {
    Ghost => "ghost"
  }
}

///|
fn button_size_value(size : ButtonSize) -> String {
  match size {
    IconXs => "icon-xs"
    IconSm => "icon-sm"
  }
}

///|
fn button_variant_style(variant : ButtonVariant) -> String {
  match variant {
    Ghost => ButtonGhostStyle
  }
}

///|
fn button_size_style(size : ButtonSize) -> String {
  match size {
    IconXs => ButtonSizeIconXsStyle
    IconSm => ButtonSizeIconSmStyle
  }
}
