# Rabbita TreeView

Headless WAI-ARIA tree behavior for Rabbita apps. The package owns the tree's
ARIA scheme (`role="tree"`/`"treeitem"`, `aria-level`, `aria-selected`,
`aria-expanded`, and the active-descendant relationship) plus a small, tested
keyboard vocabulary; the consumer owns the tree data, node labels, selection and
expansion state, navigation logic, click/drag handling, HTML structure, and
styling.

The behavior is **derived, not a store**: there is no `Msg`/`update` loop and no
durable state. Selection and expansion live in the consumer's own model and are
passed in per render — a `Model` only carries the stable id prefix so the
container's `aria-activedescendant` and each row's `id` agree. This mirrors
`lib/tabs`. It works because the tree's navigation target is necessarily
domain-specific (it depends on the consumer's tree shape), so the behavior never
needs to hold the tree; it reports a *command* and the consumer maps it onto its
own domain.

## Active-descendant, not roving tabindex

This package implements the **active-descendant** WAI-ARIA tree pattern: focus
stays on the tree container (`tabindex="0"`), and the active row is tracked by
`aria-activedescendant` rather than by moving DOM focus between rows. Pass the
selected node's key to `tree_attrs(active_node_key?=...)`; omit it when there is
no selection (or when the selected node is not currently rendered, e.g. inside a
collapsed subtree).

## Keyboard model is direction-named (compatibility mode)

`command_for_key` decodes a `keydown` key into a `TreeCommand`:

| Key | `TreeCommand` |
|-----|---------------|
| ArrowUp | `NavUp` |
| ArrowDown | `NavDown` |
| ArrowLeft | `NavLeft` |
| ArrowRight | `NavRight` |
| Enter | `Activate` |
| anything else | `None` (falls through to the consumer's own keys) |

The four `Nav*` commands are **direction-named on purpose**. The package does
*not* bake in the WAI-ARIA APG arrow model (ArrowRight = expand-or-first-child,
ArrowLeft = collapse-or-parent). A consumer is free to assign that meaning, but
it can also map the arrows onto pure domain navigation — which is what Canopy's
Ideal outline does (the arrows drive `navigate_proj` parent/child/sibling moves,
and `Activate` toggles collapse/expand). Keeping the commands direction-named is
what lets a single behavior serve both interpretations.

## Use

```mbt nocheck
fn outline_model() -> @treeview.Model {
  @treeview.Model::new(id="canopy-outline")
}

// Container: focus holder + active-descendant.
@html.div(
  class="tree-rows",
  on_keydown=fn(kb) {
    match @treeview.command_for_key(kb.key()) {
      Some(@treeview.NavUp) => navigate(Up)
      Some(@treeview.NavDown) => navigate(Down)
      // ... NavLeft / NavRight / Activate ...
      None => handle_app_key(kb.key()) // Delete, Escape, typeahead, ...
    }
  },
  attrs=outline_model().tree_attrs(label="Outline tree", active_node_key?=selected),
  rows,
)

// Each row: ARIA only; selection/click/drag stay yours.
@html.div(
  class="tree-row",
  on_click=select_cmd,
  attrs=outline_model()
    .treeitem_attrs(node_key=key, level=depth + 1, selected~, expansion~)
    .draggable("true"), // chain your own handlers on
  row_items,
)
```

**Invariant — the consumer must pass the same `id` prefix to every `Model` it
builds for one tree, and the `active_node_key` passed to `tree_attrs` must equal
the `node_key` of the selected row.** The library owns the treeitem id scheme
(`<id>-treeitem-<node_key>`), so `aria-activedescendant` round-trips to a row
`id` only when the keys match. `aria-level` is 1-based per the WAI-ARIA APG —
pass `depth + 1` for a zero-based depth. `Leaf` nodes emit no `aria-expanded`.

## Scope boundaries

Behavior-only, like `lib/tabs`:

- **Not owned:** node data, labels, selection/expansion state, navigation target
  computation, click/drag/structural-edit (Delete/Backspace) handling, drag-drop
  position detection, any tree data-structure.
- **Not implemented (deliberate):** WAI-ARIA APG arrow expand/collapse, Home/End,
  typeahead, multi-select. These can be added when a consumer needs them; the
  Ideal outline's navigation is directional/domain, not flat-list, so first/last
  and arrow-expand have no single correct meaning here yet.

## Verified Rabbita APIs

Checked against the vendored Rabbita source:

- `rabbita/rabbita/html/pkg.generated.mbti` — `Attrs::{role, tabindex, id,
  aria_label, aria_activedescendant, aria_level, aria_selected, aria_expanded}`.
- `rabbita/doc/002_writing_html/readme.mbt.md` — `Attrs::build()` chaining.
