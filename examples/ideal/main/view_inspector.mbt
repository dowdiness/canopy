///|
/// Find a node by its string ID in the interactive tree.
fn find_node_by_id(
  node : @proj.InteractiveTreeNode[@ast.Term],
  target_id : String,
) -> @proj.InteractiveTreeNode[@ast.Term]? {
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
/// Resolve a selected node from the loaded outline tree, falling back to the
/// full projection when the matching branch is currently elided.
fn resolve_selected_node(
  model : Model,
  target_id : String,
) -> @proj.InteractiveTreeNode[@ast.Term]? {
  let loaded = match model.outline_state.tree {
    Some(root) => find_node_by_id(root, target_id)
    None => None
  }
  match loaded {
    Some(node) => Some(node)
    None => {
      let node_id_int = @strconv.parse_int(target_id) catch { _ => return None }
      let node_id = @proj.NodeId::from_int(node_id_int)
      match model.editor.get_node(node_id) {
        Some(node) => {
          let itn : @proj.InteractiveTreeNode[@ast.Term] = @proj.InteractiveTreeNode::from_term_node(
            node,
            model.editor.get_source_map(),
          )
          Some(itn)
        }
        None => None
      }
    }
  }
}

///|
/// Count children of a tree node.
fn children_count(node : @proj.InteractiveTreeNode[@ast.Term]) -> Int {
  match node.children {
    @proj.Loaded(children) => children.length()
    @proj.Elided(n) => n
  }
}

///|
/// Render the node details section of the inspector.
fn view_node_details(node : @proj.InteractiveTreeNode[@ast.Term]) -> Html {
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
/// Render inspector content (without wrapper — wrapper is in view()).
fn view_inspector_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  let node_section : Html = match model.selected_node {
    Some(sel_id) => {
      let found = resolve_selected_node(model, sel_id)
      match found {
        Some(node) =>
          @html.fragment([
            view_node_details(node),
            view_actions(dispatch, sel_id),
          ])
        None => p(class="no-tree-note", "No matching node")
      }
    }
    None =>
      div(class="empty-state", [
        p(
          class="empty-state-text",
          "Click a node in the outline or editor to inspect it",
        ),
      ])
  }
  @html.fragment([
    div(class="panel-header", [span(class="panel-label", [text("INSPECTOR")])]),
    node_section,
    view_crdt_info(model),
  ])
}
