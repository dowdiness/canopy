///|
using @html {button, div, p, span, text, textarea}

///|
using @rabbita {type Cmd, type Dispatch, type Html, delay, none}

///|
enum WorkspaceMode {
  Split
  TreeOnly
  TextOnly
} derive(Eq)

///|
enum Msg {
  SetMode(WorkspaceMode)
  ToggleDiagnostics
  TextInput(String)
  RefreshProjection
  TreeEdited(@proj.TreeEditOp)
}

///|
struct Model {
  editor : @editor.SyncEditor[@ast.Term]
  tree_state : @proj.TreeEditorState[@ast.Term]
  text_view : String
  workspace_mode : WorkspaceMode
  diagnostics_open : Bool
  peers : Array[(String, Int)]
  next_timestamp : Int
  projection_dirty : Bool
  refresh_scheduled : Bool
}

///|
struct SelectedNodeDetails {
  label : String
  child_count : Int
} derive(Eq, Show)

// ── Helpers ─────────────────────────────────────────────────────────

///|
fn kind_of(label : String) -> String {
  if label.has_prefix("λ") {
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
fn selected_tree_node(model : Model) -> @proj.InteractiveTreeNode[@ast.Term]? {
  match model.tree_state.selection {
    [node_id, ..] => model.tree_state.get_loaded_node(node_id)
    [] => None
  }
}

///|
fn selected_node_details(model : Model) -> SelectedNodeDetails? {
  match selected_tree_node(model) {
    Some(node) =>
      Some({
        label: node.label,
        child_count: match node.children {
          @proj.Loaded(children) => children.length()
          @proj.Elided(descendant_count) => descendant_count
        },
      })
    None => None
  }
}

///|
fn has_hidden_selection(model : Model) -> Bool {
  not(model.tree_state.selection.is_empty()) &&
  selected_tree_node(model) is None
}

///|
fn tree_node_is_elided(
  state : @proj.TreeEditorState[@ast.Term],
  node_id : @proj.NodeId,
) -> Bool {
  match state.get_loaded_node(node_id) {
    Some(node) =>
      match node.children {
        @proj.Elided(_) => true
        @proj.Loaded(_) => false
      }
    None => false
  }
}

///|
fn can_hydrate_tree_node(model : Model, node_id : @proj.NodeId) -> Bool {
  not(model.projection_dirty) && tree_node_is_elided(model.tree_state, node_id)
}

// ── Init ────────────────────────────────────────────────────────────

///|
fn init_model() -> Model {
  let init_text = "let id = λx.x\nlet apply = λf.λx.f x\napply id 42"
  let editor = @editor.SyncEditor::new_lambda("local")
  editor.set_text(init_text)
  let tree_state : @proj.TreeEditorState[@ast.Term] = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(),
    editor.get_source_map(),
  )
  {
    editor,
    tree_state,
    text_view: init_text,
    workspace_mode: Split,
    diagnostics_open: true,
    peers: [("alice", 18), ("bob", 33)],
    next_timestamp: 1,
    projection_dirty: false,
    refresh_scheduled: false,
  }
}

// ── Update ──────────────────────────────────────────────────────────

///|
fn refresh(model : Model) -> Model {
  // Get text from CRDT (authoritative source)
  let text_view = model.editor.get_text()
  let tree_state = model.tree_state.refresh(
    model.editor.get_proj_node(),
    model.editor.get_source_map(),
  )
  {
    ..model,
    text_view,
    tree_state,
    projection_dirty: false,
    refresh_scheduled: false,
  }
}

///|
let deferred_refresh_ms = 16

///|
fn is_ui_only_tree_edit(op : @proj.TreeEditOp) -> Bool {
  match op {
    @lambda_edits.Select(..)
    | @lambda_edits.SelectRange(..)
    | @lambda_edits.StartEdit(..)
    | @lambda_edits.CancelEdit
    | @lambda_edits.StartDrag(..)
    | @lambda_edits.DragOver(..)
    | @lambda_edits.Collapse(..)
    | @lambda_edits.Expand(..) => true
    _ => false
  }
}

///|
fn update(dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    SetMode(mode) => (none, { ..model, workspace_mode: mode })
    ToggleDiagnostics =>
      (none, { ..model, diagnostics_open: !model.diagnostics_open })
    TextInput(new_text) => {
      let old_text = model.editor.get_text()
      if old_text == new_text {
        (none, model)
      } else {
        let splice = @text_change.compute_text_change(old_text, new_text)
        model.editor.apply_text_edit(
          splice.start,
          splice.delete_len,
          splice.inserted,
          model.next_timestamp,
        )
        let updated = {
          ..model,
          text_view: new_text,
          next_timestamp: model.next_timestamp + 1,
          projection_dirty: true,
        }
        if model.refresh_scheduled {
          (none, updated)
        } else {
          (
            delay(dispatch(RefreshProjection), deferred_refresh_ms),
            { ..updated, refresh_scheduled: true },
          )
        }
      }
    }
    RefreshProjection =>
      if model.projection_dirty {
        (none, refresh(model))
      } else {
        (none, { ..model, refresh_scheduled: false })
      }
    TreeEdited(op) => {
      match op {
        @lambda_edits.Expand(node_id~) => {
          let hydrate_after_expand = can_hydrate_tree_node(model, node_id)
          let tree_state = if hydrate_after_expand {
            model.tree_state.expand_node(
              node_id,
              model.editor.get_proj_node(),
              model.editor.get_source_map(),
            )
          } else {
            model.tree_state.apply_edit(op)
          }
          return (none, { ..model, tree_state, })
        }
        _ => ()
      }
      if is_ui_only_tree_edit(op) {
        let tree_state = model.tree_state.apply_edit(op)
        return (none, { ..model, tree_state, })
      }
      // Round-trip tree edit through text CRDT so ops are broadcastable
      match model.editor.apply_tree_edit(op, model.next_timestamp) {
        Ok(_) => {
          let tree_state = model.tree_state.apply_edit(op)
          let refreshed = refresh({ ..model, tree_state, })
          (none, { ..refreshed, next_timestamp: model.next_timestamp + 1 })
        }
        Err(_) => (none, model)
      }
    }
  }
}

// ── View helpers ────────────────────────────────────────────────────

///|
fn tab(label : String, on_click~ : Cmd, active? : Bool = false) -> Html {
  let class_name = if active { "tab active" } else { "tab" }
  button(class=class_name, on_click~, [text(label)])
}

// ── Tree view ───────────────────────────────────────────────────────

///|
fn view_tree_node(
  dispatch : Dispatch[Msg],
  node : @proj.InteractiveTreeNode[@ast.Term],
  depth : Int,
) -> Html {
  let kind = kind_of(node.label)
  let selected_suffix = if node.selected { " selected" } else { "" }
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
  let toggle_label = if node.collapsed { "▶" } else { "▼" }
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
  if node.selected {
    row_items.push(
      div(class="tree-actions", [
        button(
          class="tree-action",
          on_click=dispatch(
            TreeEdited(
              @lambda_edits.WrapInLambda(node_id=node.id, var_name="x"),
            ),
          ),
          [text("Wrap λ")],
        ),
        button(
          class="tree-action",
          on_click=dispatch(TreeEdited(@lambda_edits.Delete(node_id=node.id))),
          [text("Delete")],
        ),
      ]),
    )
  }
  let select_cmd = dispatch(TreeEdited(@lambda_edits.Select(node_id=node.id)))
  let row = div(class=row_class, on_click=select_cmd, row_items)
  let child_views : Array[Html] = if node.collapsed {
    []
  } else {
    match node.children {
      @proj.Loaded(children) =>
        children.map(fn(child) { view_tree_node(dispatch, child, depth + 1) })
      @proj.Elided(n) => [p(class="no-tree-note", "\{n} hidden descendants")]
    }
  }
  let all : Array[Html] = [row]
  child_views.each(fn(v) { all.push(v) })
  div(class="tree-item", all)
}

// ── Panes ───────────────────────────────────────────────────────────

///|
fn structure_pane(dispatch : Dispatch[Msg], model : Model) -> Html {
  let body = match model.tree_state.tree {
    Some(root) => div(class="tree-rows", [view_tree_node(dispatch, root, 0)])
    None => p(class="no-tree-note", "No AST available")
  }
  div(class="structure-pane", [
    div(class="pane-header", [span(class="pane-label", [text("Structure")])]),
    body,
  ])
}

///|
fn text_pane_view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="text-pane", [
    div(class="pane-header", [span(class="pane-label", [text("Text")])]),
    textarea(
      class="text-editor",
      value=model.text_view,
      rows=20,
      on_input=fn(s) { dispatch(TextInput(s)) },
      "",
    ),
  ])
}

// ── Inspector ───────────────────────────────────────────────────────

///|
fn inspector_node_section(model : Model) -> Html {
  match selected_node_details(model) {
    Some(node) => {
      let kind = kind_of(node.label)
      div(class="inspector-section", [
        p(class="inspector-label", "Selected Node"),
        div(class="inspector-row", [
          span(class="inspector-key", [text("Type")]),
          span(class="inspector-value", [text(kind)]),
        ]),
        div(class="inspector-row", [
          span(class="inspector-key", [text("Label")]),
          span(class="inspector-value", [text(node.label)]),
        ]),
        div(class="inspector-row", [
          span(class="inspector-key", [text("Children")]),
          span(class="inspector-value", [text(node.child_count.to_string())]),
        ]),
      ])
    }
    None =>
      match model.tree_state.tree {
        Some(_) =>
          if has_hidden_selection(model) {
            div(class="inspector-section", [
              p(class="inspector-label", "Selected Node"),
              p(
                class="inspector-copy",
                "Selected node is inside a collapsed subtree.",
              ),
            ])
          } else {
            div(class="inspector-section", [
              p(class="inspector-label", "Selected Node"),
              p(class="inspector-copy", "No node selected."),
            ])
          }
        None =>
          div(class="inspector-section", [
            p(class="inspector-label", "Selected Node"),
            p(class="inspector-copy", "No tree available."),
          ])
      }
  }
}

///|
fn diagnostics_section(model : Model) -> Html {
  let errors = model.editor.get_errors()
  let items = if errors.is_empty() {
    [p(class="diagnostics-item", "No errors.")]
  } else {
    errors.map(fn(e) { p(class="diagnostics-item", e) })
  }
  let body = if model.diagnostics_open {
    div(class="diagnostics-list", items)
  } else {
    p(class="hidden-note", "Diagnostics are hidden.")
  }
  div(class="inspector-section", [
    p(class="inspector-label", "Diagnostics"),
    body,
  ])
}

///|
fn inspector(model : Model) -> Html {
  div(class="inspector", [
    div(class="pane-header", [span(class="pane-label", [text("Inspector")])]),
    inspector_node_section(model),
    diagnostics_section(model),
  ])
}

// ── Workspace & chrome ──────────────────────────────────────────────

///|
fn workspace(dispatch : Dispatch[Msg], model : Model) -> Html {
  let panes = match model.workspace_mode {
    Split =>
      [
        structure_pane(dispatch, model),
        text_pane_view(dispatch, model),
        inspector(model),
      ]
    TreeOnly => [structure_pane(dispatch, model), inspector(model)]
    TextOnly => [text_pane_view(dispatch, model), inspector(model)]
  }
  div(class="workspace", panes)
}

///|
fn top_bar(dispatch : Dispatch[Msg], model : Model) -> Html {
  let peer_items : Array[Html] = model.peers.map(fn(peer) {
    let (name, _pos) = peer
    div(class="peer-indicator", [
      div(class="peer-dot peer-\{name}", [text("")]),
      span(class="peer-name", [text(name)]),
    ])
  })
  let errors = model.editor.get_errors()
  let error_status = if errors.is_empty() {
    div(class="status-indicator", [
      div(class="status-dot status-ok", [text("")]),
      span(class="status-text", [text("No errors")]),
    ])
  } else {
    div(class="status-indicator", [
      div(class="status-dot status-error", [text("")]),
      span(class="status-text", [text("\{errors.length()} errors")]),
    ])
  }
  let bar_items : Array[Html] = [
    span(class="top-bar-title", [text("projectional editor")]),
    div(class="top-bar-spacer", [text("")]),
    div(class="tab-group", [
      tab(
        "Split",
        on_click=dispatch(SetMode(Split)),
        active=model.workspace_mode == Split,
      ),
      tab(
        "Tree",
        on_click=dispatch(SetMode(TreeOnly)),
        active=model.workspace_mode == TreeOnly,
      ),
      tab(
        "Text",
        on_click=dispatch(SetMode(TextOnly)),
        active=model.workspace_mode == TextOnly,
      ),
      tab("Diagnostics", on_click=dispatch(ToggleDiagnostics)),
    ]),
    div(class="top-bar-spacer", [text("")]),
  ]
  peer_items.each(fn(p) { bar_items.push(p) })
  bar_items.push(div(class="divider-v", [text("")]))
  bar_items.push(error_status)
  div(class="top-bar", bar_items)
}

///|
fn status_bar(model : Model) -> Html {
  let selection_text = match selected_node_details(model) {
    Some(node) => node.label
    None => "No selection"
  }
  div(class="status-bar", [
    span(class="status-breadcrumb", [text(selection_text)]),
    div(class="status-bar-spacer", [text("")]),
    span(class="status-info", [text("\{model.peers.length()} peers connected")]),
    div(class="divider-v", [text("")]),
    span(class="status-info", [text("eg-walker")]),
  ])
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="app-shell", [
    top_bar(dispatch, model),
    workspace(dispatch, model),
    status_bar(model),
  ])
}

///|
fn root_node_id_for_test(model : Model) -> @proj.NodeId {
  match model.tree_state.tree {
    Some(root) => root.id
    None => abort("expected initial Rabbita tree")
  }
}

///|
fn node_id_for_label_for_test(
  node : @proj.InteractiveTreeNode[@ast.Term],
  label : String,
) -> @proj.NodeId? {
  if node.label == label {
    return Some(node.id)
  }
  match node.children {
    @proj.Loaded(children) =>
      children.fold(init=None, fn(found, child) {
        match found {
          Some(_) => found
          None => node_id_for_label_for_test(child, label)
        }
      })
    @proj.Elided(_) => None
  }
}

///|
fn selected_node_id_for_test(model : Model, label : String) -> @proj.NodeId {
  match model.tree_state.tree {
    Some(root) =>
      match node_id_for_label_for_test(root, label) {
        Some(node_id) => node_id
        None => abort("expected tree node")
      }
    None => abort("expected initial Rabbita tree")
  }
}

///|
test "TreeEdited Collapse stays local to UI state" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let old_text = model.editor.get_text()
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.Collapse(node_id=root_id)),
    model,
  )
  inspect(updated.editor.get_text(), content=old_text)
  inspect(updated.next_timestamp, content="1")
  inspect(updated.text_view, content=old_text)
  match updated.tree_state.tree {
    Some(root) => inspect(root.collapsed, content="true")
    None => abort("expected collapsed tree")
  }
}

///|
test "TreeEdited Select stays local to UI state" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let old_text = model.editor.get_text()
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.Select(node_id=root_id)),
    model,
  )
  inspect(updated.editor.get_text(), content=old_text)
  inspect(updated.next_timestamp, content="1")
  inspect(updated.tree_state.selection.length(), content="1")
  inspect(updated.tree_state.selection[0] == root_id, content="true")
  match updated.tree_state.tree {
    Some(root) => inspect(root.selected, content="true")
    None => abort("expected selected tree")
  }
  inspect(selected_node_details(updated) is Some(_), content="true")
}

///|
test "TreeEdited StartEdit stays local to UI state" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let old_text = model.editor.get_text()
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.StartEdit(node_id=root_id)),
    model,
  )
  inspect(updated.editor.get_text(), content=old_text)
  inspect(updated.next_timestamp, content="1")
  inspect(updated.tree_state.editing_node == Some(root_id), content="true")
}

///|
test "TreeEdited Expand hydrates an elided subtree without editor refresh" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let old_text = model.editor.get_text()
  let (_, collapsed) = update(
    _ => none,
    TreeEdited(@lambda_edits.Collapse(node_id=root_id)),
    model,
  )
  let elided = refresh(collapsed)
  match elided.tree_state.tree {
    Some(root) =>
      match root.children {
        @proj.Elided(_) => ()
        @proj.Loaded(_) => abort("expected elided subtree after refresh")
      }
    None => abort("expected elided tree")
  }

  let (_, expanded) = update(
    _ => none,
    TreeEdited(@lambda_edits.Expand(node_id=root_id)),
    elided,
  )

  inspect(expanded.editor.get_text(), content=old_text)
  inspect(expanded.next_timestamp, content="1")
  inspect(expanded.text_view, content=old_text)
  match expanded.tree_state.tree {
    Some(root) => {
      inspect(root.collapsed, content="false")
      match root.children {
        @proj.Loaded(children) => inspect(children.length() > 0, content="true")
        @proj.Elided(_) => abort("expected hydrated children")
      }
    }
    None => abort("expected expanded tree")
  }
}

///|
test "TreeEdited Expand does not hydrate elided subtree while projection is dirty" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let (_, collapsed) = update(
    _ => none,
    TreeEdited(@lambda_edits.Collapse(node_id=root_id)),
    model,
  )
  let elided = refresh(collapsed)
  let new_text = "let id = λx.x in let apply = λf.λx.f x in apply id 99"
  let (_, dirty) = update(_ => none, TextInput(new_text), elided)

  let (_, expanded) = update(
    _ => none,
    TreeEdited(@lambda_edits.Expand(node_id=root_id)),
    dirty,
  )

  inspect(expanded.projection_dirty, content="true")
  inspect(expanded.refresh_scheduled, content="true")
  match expanded.tree_state.tree {
    Some(root) => {
      inspect(root.collapsed, content="true")
      match root.children {
        @proj.Elided(descendant_count) =>
          inspect(descendant_count > 0, content="true")
        @proj.Loaded(_) => abort("expected stale tree to remain unhydrated")
      }
    }
    None => abort("expected stale tree")
  }
}

///|
test "Hidden selection stays visible in sidebar context after elision" {
  let model = init_model()
  let literal_id = selected_node_id_for_test(model, "42")
  let (_, selected) = update(
    _ => none,
    TreeEdited(@lambda_edits.Select(node_id=literal_id)),
    model,
  )
  let root_id = root_node_id_for_test(selected)
  let (_, collapsed) = update(
    _ => none,
    TreeEdited(@lambda_edits.Collapse(node_id=root_id)),
    selected,
  )
  let elided = refresh(collapsed)

  inspect(selected_node_details(elided) is None, content="true")
  inspect(has_hidden_selection(elided), content="true")
}

///|
test "TreeEdited WrapInLambda still round-trips through editor" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.WrapInLambda(node_id=root_id, var_name="x")),
    model,
  )
  inspect(updated.next_timestamp, content="2")
  inspect(updated.editor.get_text().contains("λx."), content="true")
}

///|
test "TreeEdited Delete preserves UI state when editor rejects it" {
  let model = init_model()
  let root_id = root_node_id_for_test(model)
  let (_, selected) = update(
    _ => none,
    TreeEdited(@lambda_edits.Select(node_id=root_id)),
    model,
  )
  let old_text = selected.editor.get_text()
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.Delete(node_id=root_id)),
    selected,
  )
  inspect(updated.editor.get_text(), content=old_text)
  inspect(updated.next_timestamp, content="1")
  inspect(updated.tree_state.selection.length(), content="1")
  inspect(updated.tree_state.selection[0] == root_id, content="true")
  match updated.tree_state.tree {
    Some(root) => inspect(root.selected, content="true")
    None => abort("expected selected tree after rejected delete")
  }
}

///|
test "TreeEdited Delete round-trips through editor for non-root node" {
  let model = init_model()
  let literal_id = selected_node_id_for_test(model, "42")
  let (_, updated) = update(
    _ => none,
    TreeEdited(@lambda_edits.Delete(node_id=literal_id)),
    model,
  )
  inspect(updated.next_timestamp, content="2")
  inspect(updated.editor.get_text().contains("42"), content="false")
  inspect(updated.editor.get_text().contains("0"), content="true")
}

///|
test "TextInput defers projection refresh" {
  let model = init_model()
  let new_text = "let id = λx.x in let apply = λf.λx.f x in apply id 99"
  let (_, updated) = update(_ => none, TextInput(new_text), model)
  inspect(updated.text_view, content=new_text)
  inspect(updated.next_timestamp, content="2")
  inspect(updated.projection_dirty, content="true")
  inspect(updated.refresh_scheduled, content="true")
  inspect(updated.editor.get_text(), content=new_text)
}

///|
test "Selected sidebar details stay on the stale tree until RefreshProjection" {
  let model = init_model()
  let literal_id = selected_node_id_for_test(model, "42")
  let (_, selected) = update(
    _ => none,
    TreeEdited(@lambda_edits.Select(node_id=literal_id)),
    model,
  )
  let new_text = "let id = λx.x in let apply = λf.λx.f x in apply id 99"
  let (_, dirty) = update(_ => none, TextInput(new_text), selected)
  match selected_node_details(dirty) {
    Some(details) => {
      inspect(details.label, content="42")
      inspect(details.child_count, content="0")
    }
    None => abort("expected selected node details before refresh")
  }
  let (_, refreshed) = update(_ => none, RefreshProjection, dirty)
  match selected_node_details(refreshed) {
    Some(details) => {
      inspect(details.label, content="99")
      inspect(details.child_count, content="0")
    }
    None => abort("expected selected node details after refresh")
  }
}

///|
test "RefreshProjection clears deferred refresh flags" {
  let model = init_model()
  let new_text = "let id = λx.x in let apply = λf.λx.f x in apply id 99"
  let (_, dirty) = update(_ => none, TextInput(new_text), model)
  let (_, refreshed) = update(_ => none, RefreshProjection, dirty)
  inspect(refreshed.projection_dirty, content="false")
  inspect(refreshed.refresh_scheduled, content="false")
  inspect(refreshed.text_view, content=new_text)
}

// ── Main ────────────────────────────────────────────────────────────

///|
fn main {
  let app = @rabbita.cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
}
