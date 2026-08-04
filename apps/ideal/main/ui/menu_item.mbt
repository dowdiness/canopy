///|
/// Ideal-local Tailwind menu/item tone recipes.
/// Keep semantic hooks as the first class tokens: the `hook` parameter
/// carries the semantic selector (e.g. `"action-overlay-item"`), and the
/// tone variant adds interactive state classes on top of the base chrome.
priv enum MenuItemTone {
  Normal
  Danger
}

///|
let menu_item_base_class = "flex items-center gap-canopy-sm py-canopy-sm px-canopy-lg cursor-pointer text-canopy-small text-canopy-fg transition-colors duration-(--duration-fast) ease-canopy-out max-[768px]:min-h-[44px] max-[768px]:py-canopy-md max-[768px]:px-canopy-lg"

///|
fn menu_item_tone_class(tone : MenuItemTone) -> String {
  match tone {
    Normal =>
      "hover:bg-[rgba(130,80,223,0.15)] data-[active=true]:bg-[rgba(130,80,223,0.15)]"
    Danger =>
      "danger text-canopy-error-text hover:bg-canopy-error-bg data-[active=true]:bg-canopy-error-bg"
  }
}

///|
pub fn menu_item_class(hook : String) -> String {
  cx([hook, menu_item_base_class, menu_item_tone_class(Normal)])
}

///|
pub fn menu_item_danger_class(hook : String) -> String {
  cx([hook, menu_item_base_class, menu_item_tone_class(Danger)])
}
