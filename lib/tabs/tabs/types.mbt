///|
/// Headless tablist behavior state: a stable id prefix, the number of tabs, and
/// the index of the selected tab.
///
/// The behavior is derived, not a store. Durable selection lives in the
/// consumer's own model; a `Model` is rebuilt each render from
/// `(id, tab_count, selected)`. This is automatic-activation (selection follows
/// focus): keyboard navigation reports the tab index that should become
/// selected, and the consumer maps that index onto its own domain.
pub struct Model {
  priv id : String
  priv tab_count : Int
  priv selected : Int
}

///|
fn normalized_count(tab_count : Int) -> Int {
  tab_count.max(0)
}

///|
/// Clamp a selected index into `[0, tab_count - 1]`, falling back to `0` when
/// there are no tabs so downstream getters stay total.
fn clamp_selected(selected : Int, tab_count : Int) -> Int {
  if tab_count <= 0 {
    0
  } else {
    selected.max(0).min(tab_count - 1)
  }
}

///|
fn Model::is_selected(self : Model, index : Int) -> Bool {
  self.selected == index
}

///|
/// Create tab behavior state for a stable id prefix, tab count, and the
/// currently selected tab index. `tab_count` is clamped to non-negative and
/// `selected` into `[0, tab_count - 1]` (`0` when there are no tabs).
pub fn Model::new(id~ : String, tab_count~ : Int, selected~ : Int) -> Model {
  let tab_count = normalized_count(tab_count)
  { id, tab_count, selected: clamp_selected(selected, tab_count) }
}

///|
/// The stable DOM id for the tab button at `index`. Internal: the behavior owns
/// the button-id scheme, so `tab_attrs`/`panel_attrs`/`focus_cmd` stay
/// internally consistent (matches `lib/menu`'s private `item_id`).
fn Model::tab_button_id(self : Model, index : Int) -> String {
  self.id + "-tab-" + index.to_string()
}

///|
/// Map a `keydown` key to the tab index that should become selected, following
/// the horizontal WAI-ARIA tablist model: ArrowLeft / ArrowRight wrap around,
/// Home / End jump to the ends. Returns `None` for keys this behavior does not
/// handle (including ArrowUp / ArrowDown, which APG reserves for scrolling) and
/// when there are no tabs.
pub fn Model::nav_target(self : Model, key : String) -> Int? {
  if self.tab_count <= 0 {
    None
  } else {
    match key {
      "ArrowLeft" => Some((self.selected + self.tab_count - 1) % self.tab_count)
      "ArrowRight" => Some((self.selected + 1) % self.tab_count)
      "Home" => Some(0)
      "End" => Some(self.tab_count - 1)
      _ => None
    }
  }
}
