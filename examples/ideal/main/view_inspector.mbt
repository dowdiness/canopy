///|
/// Find a node by its string ID in the interactive tree.
fn find_node_by_id(
  node : @proj.InteractiveTreeNode,
  target_id : String,
) -> @proj.InteractiveTreeNode? {
  if node_id_to_string(node.id) == target_id {
    return Some(node)
  }
  match node.children {
    @proj.Loaded(children) => {
      for child in children {
        match find_node_by_id(child, target_id) {
          Some(found) => return Some(found)
          None => continue
        }
      }
      None
    }
    @proj.Elided(_) => None
  }
}

///|
/// Count children of a tree node.
fn children_count(node : @proj.InteractiveTreeNode) -> Int {
  match node.children {
    @proj.Loaded(children) => children.length()
    @proj.Elided(n) => n
  }
}

///|
/// Render the node details section of the inspector.
fn view_node_details(node : @proj.InteractiveTreeNode) -> Html {
  let kind = kind_of(node.label)
  let count = children_count(node)
  div(class="panel-section", [
    span(class="panel-label", [text("NODE")]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Kind")]),
      span(class="inspector-value kind-\{kind}", [text(kind)]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Label")]),
      span(class="inspector-value", [text(node.label)]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Children")]),
      span(class="inspector-value", [text(count.to_string())]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("ID")]),
      span(class="inspector-value", [text(node_id_to_string(node.id))]),
    ]),
  ])
}

///|
/// Render the actions section of the inspector.
fn view_actions(dispatch : Dispatch[Msg], node_id_str : String) -> Html {
  div(class="panel-section", [
    span(class="panel-label", [text("ACTIONS")]),
    div(class="inspector-actions", [
      button(
        class="action-btn",
        on_click=dispatch(
          StructuralEditRequested(op="WrapInLambda", node_id=node_id_str),
        ),
        [text("Wrap in \u{03BB}")],
      ),
      button(
        class="action-btn danger",
        on_click=dispatch(
          StructuralEditRequested(op="Delete", node_id=node_id_str),
        ),
        [text("Delete")],
      ),
    ]),
  ])
}

///|
/// Render the CRDT info section of the inspector.
fn view_crdt_info(model : Model) -> Html {
  div(class="panel-section", [
    span(class="panel-label", [text("CRDT")]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Agent")]),
      span(class="inspector-value", [text("local")]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Timestamp")]),
      span(class="inspector-value", [text(model.next_timestamp.to_string())]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Text length")]),
      span(class="inspector-value", [
        text(model.editor.get_text().length().to_string()),
      ]),
    ]),
  ])
}

///|
/// Render the full inspector panel.
fn view_inspector(dispatch : Dispatch[Msg], model : Model) -> Html {
  let node_section : Html = match model.selected_node {
    Some(sel_id) => {
      let found = match model.outline_state.tree {
        Some(root) => find_node_by_id(root, sel_id)
        None => None
      }
      match found {
        Some(node) =>
          @html.fragment([
            view_node_details(node),
            view_actions(dispatch, sel_id),
          ])
        None => p(class="no-tree-note", "No matching node")
      }
    }
    None => p(class="no-tree-note", "No selection")
  }
  div(class="inspector-panel", [
    div(class="panel-header", [span(class="panel-label", [text("INSPECTOR")])]),
    node_section,
    view_crdt_info(model),
  ])
}
