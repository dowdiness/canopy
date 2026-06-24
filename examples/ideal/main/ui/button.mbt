///|
// Ideal-local Tailwind button recipes.
// Keep semantic hooks as the first class tokens: tests and integration code use
// hooks such as `toolbar-btn` and `action-btn`, while Tailwind owns the
// visual declarations for migrated button chrome.
priv enum ButtonTone {
  Neutral
  Accent
  Surface
  Danger
}

///|
let button_chrome_base_class = "ideal-button font-canopy-ui font-medium cursor-pointer transition-colors duration-(--duration-fast) ease-canopy-out"

///|
let toolbar_button_base_class : String = button_chrome_base_class +
  " text-canopy-caption py-canopy-sm px-canopy-md border-0 rounded-canopy-sm min-h-[32px] max-[768px]:min-h-[44px] max-[768px]:min-w-[44px] max-[768px]:py-canopy-md max-[768px]:px-canopy-md"

///|
fn toolbar_button_tone_class(tone : ButtonTone) -> String {
  match tone {
    Neutral =>
      "bg-transparent text-canopy-dim hover:bg-canopy-surface hover:text-canopy-secondary"
    Accent =>
      "bg-canopy-accent text-canopy-fg-inverse hover:bg-canopy-accent hover:text-canopy-fg-inverse"
    Surface =>
      "bg-canopy-surface text-canopy-fg hover:bg-canopy-surface hover:text-canopy-fg"
    Danger =>
      "bg-transparent text-canopy-error-text hover:bg-canopy-error-bg hover:text-canopy-error-text"
  }
}

///|
fn toolbar_button_recipe_class(tone : ButtonTone) -> String {
  toolbar_button_base_class + " " + toolbar_button_tone_class(tone)
}

///|
pub fn toolbar_button_class() -> String {
  "toolbar-btn " + toolbar_button_recipe_class(Neutral)
}

///|
pub fn toolbar_example_button_class() -> String {
  "toolbar-btn example-btn " +
  toolbar_button_recipe_class(Neutral) +
  " max-[768px]:hidden"
}

///|
pub fn toolbar_panel_toggle_class(active : Bool) -> String {
  if active {
    "panel-toggle active " + toolbar_button_recipe_class(Surface)
  } else {
    "panel-toggle " + toolbar_button_recipe_class(Neutral)
  }
}

///|
let action_button_base_class : String = button_chrome_base_class +
  " text-canopy-small py-canopy-sm px-canopy-md bg-canopy-surface border border-solid border-transparent rounded-canopy-md text-left"

///|
fn action_button_tone_class(tone : ButtonTone) -> String {
  match tone {
    Danger =>
      "text-canopy-error-text hover:bg-canopy-error-bg hover:border-canopy-error-border hover:text-canopy-error-text"
    _ =>
      "text-canopy-secondary hover:bg-canopy-accent-hover hover:border-canopy-accent-border hover:text-canopy-accent-text"
  }
}

///|
pub fn action_button_class() -> String {
  "action-btn " +
  action_button_base_class +
  " " +
  action_button_tone_class(Neutral)
}

///|
pub fn action_button_danger_class() -> String {
  "action-btn danger " +
  action_button_base_class +
  " " +
  action_button_tone_class(Danger)
}
