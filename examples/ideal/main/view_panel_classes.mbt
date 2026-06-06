///|
// Tailwind utility bundles for light-DOM panel header/section chrome.
// Keep semantic hooks as the first class tokens. Inspector helpers keep the
// existing generic `panel-*` hooks first while also exposing inspector-specific
// hooks as stable tokens.
let panel_label_chrome_class = "text-canopy-label font-semibold text-canopy-dim tracking-[0.1em] uppercase leading-[var(--leading-tight)]"

///|
let panel_section_chrome_class = "py-canopy-md px-canopy-lg border-t border-solid border-canopy-border mt-auto"

///|
fn panel_header_class() -> String {
  "panel-header pt-canopy-lg px-canopy-lg pb-canopy-md"
}

///|
fn panel_label_class() -> String {
  "panel-label " + panel_label_chrome_class
}

///|
fn panel_section_class() -> String {
  "panel-section " + panel_section_chrome_class
}

///|
fn inspector_label_class() -> String {
  "panel-label inspector-label " + panel_label_chrome_class
}

///|
fn inspector_section_class() -> String {
  "panel-section inspector-section " + panel_section_chrome_class
}
