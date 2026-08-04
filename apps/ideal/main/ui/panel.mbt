///|
/// Ideal-local Tailwind panel chrome recipes.
/// Keep semantic hooks as the first class tokens: tests and integration code
/// use hooks such as `panel-label`, `panel-section`, `inspector-label`, and
/// `inspector-section`, while Tailwind owns the visual declarations.
priv enum PanelVariant {
  Default
  Inspector
}

///|
let panel_label_chrome_class = "text-canopy-label font-semibold text-canopy-dim tracking-[0.1em] uppercase leading-[var(--leading-tight)]"

///|
let panel_section_chrome_class = "py-canopy-md px-canopy-lg border-t border-solid border-canopy-border mt-auto"

///|
fn panel_label_hook(variant : PanelVariant) -> String {
  match variant {
    Default => "panel-label"
    Inspector => "panel-label inspector-label"
  }
}

///|
fn panel_section_hook(variant : PanelVariant) -> String {
  match variant {
    Default => "panel-section"
    Inspector => "panel-section inspector-section"
  }
}

///|
pub fn panel_label_class() -> String {
  cx([panel_label_hook(Default), panel_label_chrome_class])
}

///|
pub fn panel_section_class() -> String {
  cx([panel_section_hook(Default), panel_section_chrome_class])
}

///|
pub fn inspector_label_class() -> String {
  cx([panel_label_hook(Inspector), panel_label_chrome_class])
}

///|
pub fn inspector_section_class() -> String {
  cx([panel_section_hook(Inspector), panel_section_chrome_class])
}
