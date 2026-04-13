///|
/// Convert a NodeId to the string representation used by selected_node.
fn node_id_to_string(id : @canopy_core.NodeId) -> String {
  id.0.to_string()
}

///|
/// Determine a CSS kind class from a tree node label.
fn kind_of(label : String) -> String {
  if label.has_prefix("\u{03BB}") {
    "lambda"
  } else if label == "App" {
    "app"
  } else if label.has_prefix("let ") {
    "let"
  } else if label == "if" {
    "if"
  } else if label == "()" {
    "unit"
  } else if label.has_prefix("Error:") {
    "error"
  } else if label == "Plus" || label == "Minus" {
    "binop"
  } else {
    "term"
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
  dispatch : Dispatch[Msg],
  node : @proj.InteractiveTreeNode[@ast.Term],
  depth : Int,
  model : Model,
  eval_annotations : Map[@canopy_core.NodeId, Array[@lambda.EvalResult]],
) -> Html {
  let kind = kind_of(node.label)
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
  let select_cmd = dispatch(OutlineNodeClicked(node_id_to_string(node.id)))
  // Drag-and-drop event handlers
  let node_id = node.id
  let drag_attrs = @html.Attrs::build()
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
    attrs=drag_attrs,
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
        [@html.p(class="no-tree-note", "\{n} hidden descendants")]
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
fn view_outline_tree(dispatch : Dispatch[Msg], model : Model) -> Html {
  let handle_keydown = fn(kb : @html.Keyboard) {
    let key = kb.key()
    match key {
      "ArrowUp" =>
        match navigate_outline(model, @canopy_core.Direction::Up) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowDown" =>
        match navigate_outline(model, @canopy_core.Direction::Down) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowLeft" =>
        match navigate_outline(model, @canopy_core.Direction::Left) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "ArrowRight" =>
        match navigate_outline(model, @canopy_core.Direction::Right) {
          Some(id) => dispatch(OutlineNavigate(id))
          None => @rabbita.none
        }
      "Enter" =>
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
        if model.overlay.visible {
          dispatch(CloseActionOverlay)
        } else {
          dispatch(OutlineNavigate(""))
        }
      _ => @rabbita.none
    }
  }
  // Build eval annotations map: NodeId → Array[EvalResult]
  let eval_annotations = build_outline_eval_annotations(model)
  match model.outline_state.tree {
    Some(root) =>
      div(
        class="tree-rows",
        on_keydown=handle_keydown,
        attrs=@html.Attrs::build().tabindex(0),
        [view_outline_node(dispatch, root, 0, model, eval_annotations)],
      )
    None => @html.p(class="no-tree-note", "No AST available")
  }
}

///|
/// Render outline content.
fn view_outline_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  js_install_outline_drag_capture()
  view_outline_tree(dispatch, model)
}
