///|
/// A single tab entry.
pub(all) struct Tab {
  id : String
  label : String
}

///|
// Canopy tab chrome recipes.
// Mirrors `ui/button.mbt`: a shared chrome base, then per-variant base + tone
// functions, exposed through public recipe helpers.

///|
/// Shared base for all tab variants (cursor, transition, font).
let tab_chrome_base_class = "ideal-tab font-canopy-ui font-medium cursor-pointer transition-colors duration-(--duration-fast) ease-canopy-out"

///|
/// Structural class for underline tabs: bottom border acts as the indicator.
let underline_tab_base_class : String = tab_chrome_base_class +
  " text-canopy-caption py-canopy-sm px-canopy-md border-x-0 border-t-0 border-b-2 border-solid rounded-none min-h-[32px] pb-[calc(var(--space-sm)_-_2px)] max-[768px]:min-h-[44px] max-[768px]:min-w-[44px] max-[768px]:py-canopy-md max-[768px]:px-canopy-md max-[768px]:pb-[calc(var(--space-md)_-_2px)]"

///|
/// Tone (color + hover + active underline) for underline tabs.
fn underline_tab_tone_class(active : Bool) -> String {
  if active {
    "bg-transparent text-canopy-accent-text border-b-canopy-accent"
  } else {
    "bg-transparent text-canopy-dim border-b-transparent hover:bg-canopy-surface hover:text-canopy-secondary"
  }
}

///|
/// Public recipe for a single underline tab trigger.
pub fn tab_class(active : Bool) -> String {
  let hook = if active { "tab active " } else { "tab " }
  hook + underline_tab_base_class + " " + underline_tab_tone_class(active)
}

///|
/// Structural class for the tablist container.
fn tabs_container_base_class() -> String {
  "bottom-tabs flex items-center border-b border-solid border-canopy-border"
}

///|
/// Sizing/spacing class for the tablist container.
fn tabs_container_size_class() -> String {
  "px-canopy-md gap-canopy-xs h-[36px] max-[768px]:h-auto max-[768px]:min-h-[44px]"
}

///|
/// Public recipe for the tablist container.
pub fn tabs_container_class() -> String {
  tabs_container_base_class() + " " + tabs_container_size_class()
}

///|
/// Bundle of visual recipes for a tablist. Consumers keep selection in their
/// own model and pass these recipes to `tablist_view` / `tab_trigger_view`.
pub(all) struct TabStyle {
  container_class : String
  tab_class : (Bool) -> String
}

///|
/// Default Canopy underline style (used by the bottom panel).
pub fn underline_tab_style() -> TabStyle {
  { container_class: tabs_container_class(), tab_class }
}

///|
/// Public recipe for a single toolbar tab button. Moved from `button.mbt`
/// because it is a tab trigger, not a generic button.
pub fn toolbar_tab_class(active : Bool) -> String {
  if active {
    "tab active " + toolbar_button_recipe_class(Accent)
  } else {
    "tab " + toolbar_button_recipe_class(Neutral)
  }
}

///|
/// Create the headless tabs behavior state.
pub fn behavior(id~ : String, tab_count~ : Int, selected~ : Int) -> @tabs.Model {
  @tabs.Model::new(id~, tab_count~, selected~)
}

///|
/// Render the tablist container. Children are typically `tab_trigger_view`
/// elements.
pub fn tablist_view(
  label~ : String,
  class~ : String,
  children : Array[@html.Html],
) -> @html.Html {
  @html.div(class~, attrs=@tabs.tablist_attrs(label~), children)
}

///|
/// Render a single tab trigger button. `dispatch` receives the *target* tab
/// index (from keyboard navigation) and must produce the command that updates
/// selection, e.g. `fn(j) { emit(on_select(tabs[j].id)) }`.
pub fn tab_trigger_view(
  behavior : @tabs.Model,
  index : Int,
  tab : Tab,
  panel_id~ : String,
  active : Bool,
  dispatch : (Int) -> @rabbita.Cmd,
  tab_class : (Bool) -> String,
) -> @html.Html {
  @html.button(
    class=tab_class(active),
    attrs=behavior.tab_attrs(index, panel_id~, dispatch~),
    [@html.text(tab.label)],
  )
}

///|
/// Render a tabpanel container.
pub fn tab_panel_view(
  behavior : @tabs.Model,
  index : Int,
  panel_id~ : String,
  class~ : String,
  children : Array[@html.Html],
) -> @html.Html {
  @html.div(class~, attrs=behavior.panel_attrs(index, panel_id~), children)
}
