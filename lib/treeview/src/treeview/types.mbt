///|
/// A semantic keyboard intent for a tree, decoded from a raw `keydown` key.
///
/// The behavior reports the *intent*; the consumer maps it onto its own domain.
/// The four `Nav*` commands are directional moves whose meaning (move to
/// parent / child / sibling, or expand / collapse) is decided by the consumer,
/// because the target depends on the consumer's tree structure — a headless
/// behavior cannot compute it. `Activate` is the Enter intent (the Ideal outline
/// maps it to toggle collapse/expand).
///
/// This is a deliberate *compatibility mode*: the Ideal outline drives its arrows
/// through domain navigation (`@canopy_core.navigate_proj`), not the WAI-ARIA APG
/// arrow model (ArrowRight = expand-or-first-child, ArrowLeft = collapse-or-parent).
/// The commands stay direction-named so a consumer is free to assign either
/// meaning; the package does not bake the APG arrow semantics in.
pub(all) enum TreeCommand {
  NavUp
  NavDown
  NavLeft
  NavRight
  Activate
} derive(Eq, Debug)

///|
/// Decode a `keydown` key string into the tree command it should trigger, or
/// `None` for keys this behavior does not own. Returning `None` lets the
/// consumer's own keys (Delete / Backspace / Escape / typeahead / etc.) fall
/// through unchanged.
pub fn command_for_key(key : String) -> TreeCommand? {
  match key {
    "ArrowUp" => Some(NavUp)
    "ArrowDown" => Some(NavDown)
    "ArrowLeft" => Some(NavLeft)
    "ArrowRight" => Some(NavRight)
    "Enter" => Some(Activate)
    _ => None
  }
}

///|
/// The disclosure state of a tree node, controlling `aria-expanded`.
///
/// `Leaf` nodes have no children and emit no `aria-expanded` (per WAI-ARIA, the
/// attribute is meaningless on a node that can never expand). `Collapsed` and
/// `Expanded` emit `"false"` / `"true"`.
pub(all) enum Expansion {
  Leaf
  Collapsed
  Expanded
} derive(Eq, Debug)

///|
/// The `aria-expanded` value for an expansion state, or `None` when the
/// attribute must be omitted (leaves).
pub fn expanded_value(expansion : Expansion) -> String? {
  match expansion {
    Leaf => None
    Collapsed => Some("false")
    Expanded => Some("true")
  }
}

///|
/// Headless tree behavior: owns only the stable treeitem DOM-id scheme.
///
/// Like `lib/tabs`, the behavior is derived, not a store. There is no durable
/// state here — selection and expansion live in the consumer's own model and are
/// passed in per render. `Model` carries just the id prefix so the
/// container's `aria-activedescendant` and each row's `id` stay internally
/// consistent (mirrors `lib/tabs`' private `tab_button_id`).
pub struct Model {
  priv id : String
}

///|
/// Create tree behavior state for a stable id prefix.
pub fn Model::new(id~ : String) -> Model {
  { id, }
}

///|
/// The stable DOM id for the treeitem identified by `node_key`. Internal: the
/// behavior owns the id scheme, so `tree_attrs` (via `aria-activedescendant`) and
/// `treeitem_attrs` (via `id`) always agree. `node_key` is a consumer-owned
/// stable string per node (e.g. a stringified NodeId); the behavior never
/// interprets it.
fn Model::treeitem_id(self : Model, node_key : String) -> String {
  self.id + "-treeitem-" + node_key
}
