///|
/// Convert a NodeId to the string representation used by selected_node.
fn node_id_to_string(id : @canopy_core.NodeId) -> String {
  id.0.to_string()
}

///|
/// Headless `@treeview` behavior for the outline. The id prefix is the single
/// source of the treeitem DOM-id scheme, so the container's
/// `aria-activedescendant` and each row's `id` round-trip. Rebuilt per use —
/// the behavior is stateless; selection/expansion live in `model`.
fn outline_tree_model() -> @treeview.Model {
  @treeview.Model::new(id="canopy-outline")
}

///|
/// Whether the row for `key` is currently rendered, i.e. reachable from the
/// outline root without descending through a collapsed node. Mirrors exactly
/// what `view_outline_node` emits (collapsed subtrees render no children), so the
/// caller never points `aria-activedescendant` at a non-rendered id.
fn outline_row_rendered(
  node : @proj.InteractiveTreeNode[@ast.Term],
  key : String,
) -> Bool {
  if node_id_to_string(node.id) == key {
    return true
  }
  if node.collapsed {
    return false
  }
  match node.children {
    @proj.Loaded(children) =>
      children.iter().any(child => outline_row_rendered(child, key))
    @proj.Elided(_) => false
  }
}

///|
/// The selected node's key, but only when its row is actually rendered. Drives
/// `aria-activedescendant`: a selection that has scrolled out of the rendered
/// tree (e.g. an ancestor collapsed, or a re-projection dropped the node) yields
/// `None` rather than an active descendant that resolves to nothing.
fn outline_active_node_key(model : Model) -> String? {
  let sel = match model.selected_node {
    Some(s) => s
    None => return None
  }
  let root = match model.outline_state.tree {
    Some(r) => r
    None => return None
  }
  if outline_row_rendered(root, sel) {
    Some(sel)
  } else {
    None
  }
}

// NOTE: Position detection (Before/After/Inside) based on mouse-Y is not yet
// implemented for the outline panel. Rabbita's @html.DragEvent is package-private,
// so we can't pass it to extern "js" for bounding-rect computation.
// TODO: Add position detection once Rabbita exports DragEvent or @dom is added as dep.

///|
/// Initialize drag data on a dragstart event via JS global capture.
/// Called from on_dragstart to ensure dataTransfer is populated (required by browsers).
extern "js" fn js_init_drag(node_id : Int) -> Unit =
  #|(id) => {
  #|  window.__canopy_outline_drag_source = id;
  #|}

///|
/// Inject a dragstart listener on the outline container that sets dataTransfer.
/// Must be called once at page load. Rabbita's on_dragstart can't set dataTransfer
/// because the DragEvent type is package-private, so we use a capturing listener.
extern "js" fn js_install_outline_drag_capture() -> Unit =
  #|() => {
  #|  if (window.__canopy_outline_drag_installed) return;
  #|  window.__canopy_outline_drag_installed = true;
  #|  document.addEventListener("dragstart", (e) => {
  #|    const row = e.target.closest && e.target.closest(".tree-row[draggable]");
  #|    if (!row) return;
  #|    const id = window.__canopy_outline_drag_source;
  #|    if (id != null) {
  #|      e.dataTransfer.setData("application/x-canopy-node", String(id));
  #|      e.dataTransfer.effectAllowed = "move";
  #|    }
  #|  }, true);
  #|}

///|
/// Render a single outline tree node with collapse/expand, selection, and drag-and-drop.
fn view_outline_node(
  dispatch : Emit[Msg],
  node : @proj.InteractiveTreeNode[@ast.Term],
  depth : Int,
  model : Model,
  eval_annotations : Map[@canopy_core.NodeId, Array[@lambda.EvalResult]],
) -> Html {
  let kind = @lambda_proj.term_css_class(node.kind)
  let is_selected = match model.selected_node {
    Some(sel) => sel == node_id_to_string(node.id)
    None => false
  }
  let selected_suffix = if is_selected { " selected" } else { "" }
  // Scope highlight class (highlighted/dimmed based on binder selection)
  let hl_suffix = if model.highlight_set.is_empty() {
    ""
  } else if model.highlight_set.contains(node.id) {
    " scope-highlighted"
  } else {
    " scope-dimmed"
  }
  // Drag state classes
  let drag_suffix = if model.drag_source == Some(node.id) {
    " outline-dragging"
  } else {
    ""
  }
  let drop_suffix = if model.drop_target_id == Some(node.id) {
    match model.drop_position {
      Some(@canopy_core.DropPosition::Before) => " outline-drop-before"
      Some(@canopy_core.DropPosition::After) => " outline-drop-after"
      Some(@canopy_core.DropPosition::Inside) => " outline-drop-inside"
      None => ""
    }
  } else {
    ""
  }
  let row_class = "tree-row depth-\{depth} kind-\{kind}\{selected_suffix}\{hl_suffix}\{drag_suffix}\{drop_suffix}"
  let is_leaf = match node.children {
    @proj.Loaded(children) => children.is_empty()
    @proj.Elided(_) => false
  }
  let toggle_cmd = if node.collapsed {
    dispatch(TreeEdited(@lambda_edits.Expand(node_id=node.id)))
  } else {
    dispatch(TreeEdited(@lambda_edits.Collapse(node_id=node.id)))
  }
  let toggle_label = if node.collapsed { "\u{25B6}" } else { "\u{25BC}" }
  let toggle : Html = if is_leaf {
    div(class="tree-toggle", [text("")])
  } else {
    button(class="tree-toggle", on_click=toggle_cmd, [text(toggle_label)])
  }
  // Binder color class for the label
  let binder_cls = match model.scope_map.get(node.id) {
    Some(ann) => {
      let color = " binder-" + ann.color_index.to_string()
      let weight = if ann.is_definition { " def-site" } else { "" }
      color + weight
    }
    None => ""
  }
  let row_items : Array[Html] = [
    div(class="tree-accent", [text("")]),
    toggle,
    span(class="tree-label-text\{binder_cls}", [text(node.label)]),
  ]
  // Eval annotation badge
  match eval_annotations.get(node.id) {
    Some(results) =>
      for result in results {
        match result {
          @lambda.EvalResult::Value(s) =>
            row_items.push(span(class="eval-badge", [text("  \u{2192} " + s)]))
          @lambda.EvalResult::Stuck(s) =>
            row_items.push(
              span(class="eval-badge eval-error", [text("  \u{2192} " + s)]),
            )
          @lambda.EvalResult::Suppressed => ()
        }
      }
    None => ()
  }
  if node.collapsed {
    let count = match node.children {
      @proj.Elided(n) => n
      @proj.Loaded(children) => children.length()
    }
    if count > 0 {
      row_items.push(span(class="collapsed-badge", [text(count.to_string())]))
    }
  }
  let node_key = node_id_to_string(node.id)
  let select_cmd = dispatch(OutlineNodeClicked(node_key))
  // WAI-ARIA treeitem state (role / id / level / selected / expanded) from the
  // headless `@treeview` behavior. `aria-level` is 1-based per the APG, so we
  // pass `depth + 1`. A `Loaded`-but-empty node is a leaf (no `aria-expanded`);
  // `Elided` children mean the subtree exists but isn't materialized, so it is
  // expandable, not a leaf.
  let expansion : @treeview.Expansion = if is_leaf {
    Leaf
  } else if node.collapsed {
    Collapsed
  } else {
    Expanded
  }
  // Drag-and-drop event handlers chain onto the treeitem ARIA attrs. Selection,
  // click, and drag stay app-owned; the behavior contributes ARIA only.
  let node_id = node.id
  let row_attrs = outline_tree_model()
    .treeitem_attrs(
      node_key~,
      level=depth + 1,
      selected=is_selected,
      expansion~,
    )
    .draggable("true")
    .on_dragstart(fn(e) {
      e.stop_propagation()
      js_init_drag(node_id.0)
      dispatch(OutlineDragStart(node_id))
    })
    .on_dragover(fn(e) {
      e.prevent_default()
      e.stop_propagation()
      dispatch(OutlineDragOver(node_id, @canopy_core.DropPosition::Inside))
    })
    .on_dragleave(fn(_e) { dispatch(OutlineDragLeave) })
    .on_drop(fn(e) {
      e.prevent_default()
      e.stop_propagation()
      dispatch(OutlineDrop(node_id, @canopy_core.DropPosition::Inside))
    })
    .on_dragend(fn(_e) { dispatch(OutlineDragEnd) })
  let row = div(
    class=row_class,
    on_click=select_cmd,
    attrs=row_attrs,
    row_items,
  )
  let child_views : Array[Html] = if node.collapsed {
    []
  } else {
    match node.children {
      @proj.Loaded(children) =>
        children.map(fn(child) {
          view_outline_node(dispatch, child, depth + 1, model, eval_annotations)
        })
      @proj.Elided(n) =>
        [@html.p(class=no_tree_note_class, "\{n} hidden descendants")]
    }
  }
  let all : Array[Html] = [row]
  child_views.each(fn(v) { all.push(v) })
  div(class="tree-item", all)
}

///|
/// Compute structural navigation from the current selection.
fn navigate_outline(
  model : Model,
  direction : @canopy_core.Direction,
) -> String? {
  let node_id_str = match model.selected_node {
    Some(s) => s
    None => return None
  }
  let node_id = match parse_node_id(node_id_str) {
    Some(id) => id
    None => return None
  }
  let proj_root = match model.editor.get_proj_node() {
    Some(p) => p
    None => return None
  }
  match @canopy_core.navigate_proj(node_id, direction, proj_root) {
    Some(new_id) => Some(node_id_to_string(new_id))
    None => None
  }
}

///|
/// Get the NodeId of the currently selected outline node.
fn get_selected_node_id(model : Model) -> @canopy_core.NodeId? {
  let s = match model.selected_node {
    Some(s) => s
    None => return None
  }
  parse_node_id(s)
}

///|
/// Build a NodeId → EvalResult map for the outline tree.
/// Maps eval results to ProjNode children by definition index.
fn build_outline_eval_annotations(
  model : Model,
) -> Map[@canopy_core.NodeId, Array[@lambda.EvalResult]] {
  let annotations : Map[@canopy_core.NodeId, Array[@lambda.EvalResult]] = {}
  let eval_results = model.companion.get_eval_results()
  if eval_results.is_empty() {
    return annotations
  }
  let proj_node = match model.editor.get_proj_node() {
    Some(p) => p
    None => return annotations
  }
  let children = proj_node.children
  for i, result in eval_results {
    match result {
      @lambda.EvalResult::Suppressed => continue
      _ =>
        if i < children.length() {
          annotations[children[i].id()] = [result]
        } else {
          annotations[proj_node.id()] = [result]
        }
    }
  }
  annotations
}

///|
/// Render outline tree view with keyboard navigation (original tree mode).
fn view_outline_tree(dispatch : Emit[Msg], model : Model) -> Html {
  let navigate = fn(direction : @canopy_core.Direction) {
    match navigate_outline(model, direction) {
      Some(id) => dispatch(OutlineNavigate(id))
      None => @rabbita.none
    }
  }
  // The headless `@treeview` behavior owns the tree keyboard vocabulary. The
  // four directional commands map onto domain `navigate_proj`; Activate (Enter)
  // toggles collapse/expand. Keys the behavior does not claim — Delete/Backspace
  // (structural edit), "." (action overlay), Escape — fall through unchanged.
  //
  // Compatibility mode: arrows drive *domain* navigation (parent/child/sibling
  // via `navigate_proj`), NOT the WAI-ARIA APG expand/collapse-on-arrow model.
  // The locked outline E2E asserts these navigate_proj semantics; `@treeview`
  // keeps its `TreeCommand`s direction-named precisely so this consumer can
  // assign that meaning. See `lib/treeview` for the rationale.
  let handle_keydown = fn(kb : @html.Keyboard) {
    let key = kb.key()
    match @treeview.command_for_key(key) {
      Some(NavUp) => navigate(@canopy_core.Direction::Up)
      Some(NavDown) => navigate(@canopy_core.Direction::Down)
      Some(NavLeft) => navigate(@canopy_core.Direction::Left)
      Some(NavRight) => navigate(@canopy_core.Direction::Right)
      Some(Activate) =>
        match get_selected_node_id(model) {
          Some(nid) => {
            let op = if model.outline_state.collapsed_nodes.contains(nid) {
              @lambda_edits.Expand(node_id=nid)
            } else {
              @lambda_edits.Collapse(node_id=nid)
            }
            dispatch(TreeEdited(op))
          }
          None => @rabbita.none
        }
      None =>
        match key {
          "Delete" | "Backspace" =>
            match get_selected_node_id(model) {
              Some(nid) =>
                dispatch(
                  OutlineStructuralEdit(
                    @lambda_edits.TreeEditOp::Delete(node_id=nid),
                  ),
                )
              None => @rabbita.none
            }
          "." =>
            match model.selected_node {
              Some(_) => dispatch(OpenActionOverlayFromOutline)
              None => @rabbita.none
            }
          "Escape" =>
            if model.overlay.is_open() {
              dispatch(ActionOverlay(NameCancel))
            } else {
              dispatch(OutlineNavigate(""))
            }
          _ => @rabbita.none
        }
    }
  }
  // Build eval annotations map: NodeId → Array[EvalResult]
  let eval_annotations = build_outline_eval_annotations(model)
  match model.outline_state.tree {
    Some(root) =>
      div(
        class="tree-rows",
        on_keydown=handle_keydown,
        // `role="tree"` + roving-free active-descendant: focus stays on this
        // container (tabindex=0) and the selected row is tracked by id, matching
        // the pre-existing container-focus model the E2E relies on. The label is
        // deliberately distinct from the ancestor "AST outline" region so
        // accessibility-name lookups stay unambiguous.
        attrs=outline_tree_model().tree_attrs(
          label="Outline tree",
          active_node_key?=outline_active_node_key(model),
        ),
        [view_outline_node(dispatch, root, 0, model, eval_annotations)],
      )
    None => @html.p(class=no_tree_note_class, "No AST available")
  }
}

///|
/// Render outline content.
fn view_outline_content(dispatch : Emit[Msg], model : Model) -> Html {
  js_install_outline_drag_capture()
  view_outline_tree(dispatch, model)
}
