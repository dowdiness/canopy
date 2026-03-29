///|
/// Convert a NodeId to the string representation used by selected_node.
fn node_id_to_string(id : @proj.NodeId) -> String {
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

///|
/// Render a single outline tree node with collapse/expand and selection.
fn view_outline_node(
  dispatch : Dispatch[Msg],
  node : @proj.InteractiveTreeNode[@ast.Term],
  depth : Int,
  selected_node : String?,
) -> Html {
  let kind = kind_of(node.label)
  let is_selected = match selected_node {
    Some(sel) => sel == node_id_to_string(node.id)
    None => false
  }
  let selected_suffix = if is_selected { " selected" } else { "" }
  let row_class = "tree-row depth-\{depth} kind-\{kind}\{selected_suffix}"
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
  let row_items : Array[Html] = [
    div(class="tree-accent", [text("")]),
    toggle,
    span(class="tree-label-text", [text(node.label)]),
  ]
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
  let row = div(class=row_class, on_click=select_cmd, row_items)
  let child_views : Array[Html] = if node.collapsed {
    []
  } else {
    match node.children {
      @proj.Loaded(children) =>
        children.map(fn(child) {
          view_outline_node(dispatch, child, depth + 1, selected_node)
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
/// Render outline tree content (without wrapper — wrapper is in view()).
fn view_outline_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.outline_state.tree {
    Some(root) =>
      div(class="tree-rows", [
        view_outline_node(dispatch, root, 0, model.selected_node),
      ])
    None => @html.p(class="no-tree-note", "No AST available")
  }
}
