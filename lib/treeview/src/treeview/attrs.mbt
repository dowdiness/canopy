///|
fn bool_attr(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// ARIA attrs for the tree container element.
///
/// Sets `role="tree"`, a `tabindex="0"` so the container is the single focus
/// holder (the active-descendant pattern: focus stays on the container, the
/// active row is tracked by id rather than by moving DOM focus), and a label.
/// `aria-activedescendant` points at the selected row's treeitem id when
/// `active_node_key` is `Some` and is omitted otherwise (no selection, or the
/// selected node is not currently rendered).
///
/// `label` must NOT duplicate an `aria-label` already on an ancestor region, or
/// accessibility-tree name lookups become ambiguous; give the tree its own name.
pub fn Model::tree_attrs(
  self : Model,
  label~ : String,
  active_node_key? : String,
) -> @html.Attrs {
  let attrs = @html.Attrs::build().role("tree").aria_label(label).tabindex(0)
  match active_node_key {
    Some(key) => attrs.aria_activedescendant(self.treeitem_id(key))
    None => attrs
  }
}

///|
/// ARIA attrs for a single treeitem row.
///
/// Sets the behavior-owned `id`, `role="treeitem"`, `aria-level` (1-based per
/// WAI-ARIA APG — the consumer passes `depth + 1`), `aria-selected`, and
/// `aria-expanded` only for non-leaf nodes. Selection, click, drag, and keyboard
/// handling stay consumer-owned: the consumer spreads these attrs onto its row
/// and chains its own handlers on, and reads keys through `command_for_key` in
/// its container-level `on_keydown`.
pub fn Model::treeitem_attrs(
  self : Model,
  node_key~ : String,
  level~ : Int,
  selected~ : Bool,
  expansion~ : Expansion,
) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .id(self.treeitem_id(node_key))
    .role("treeitem")
    .aria_level(level.to_string())
    .aria_selected(bool_attr(selected))
  match expanded_value(expansion) {
    Some(value) => attrs.aria_expanded(value)
    None => attrs
  }
}
