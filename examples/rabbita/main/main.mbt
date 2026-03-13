///|
using @html {button, div, h1, h2, li, p, span, text, textarea, ul}

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
  editor : @editor.SyncEditor
  tree_state : @proj.TreeEditorState
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
fn selected_tree_node(model : Model) -> @proj.InteractiveTreeNode? {
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
  state : @proj.TreeEditorState,
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
  let init_text = "let id = λx.x in let apply = λf.λx.f x in apply id 42"
  let editor = @editor.SyncEditor::new("local")
  editor.set_text(init_text)
  let tree_state = @proj.TreeEditorState::from_projection(
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
    @proj.Select(..)
    | @proj.SelectRange(..)
    | @proj.StartEdit(..)
    | @proj.CancelEdit
    | @proj.StartDrag(..)
    | @proj.DragOver(..)
    | @proj.Collapse(..)
    | @proj.Expand(..) => true
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
        let splice = @editor.compute_text_splice(old_text, new_text)
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
        @proj.Expand(node_id~) => {
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
fn control(label : String, on_click~ : Cmd, active? : Bool = false) -> Html {
  let class_name = if active { "control active" } else { "control" }
  div(class=class_name, on_click~, [text(label)])
}

// ── Tree view ───────────────────────────────────────────────────────

///|
fn view_tree_node(
  dispatch : Dispatch[Msg],
  node : @proj.InteractiveTreeNode,
) -> Html {
  let class_name = if node.selected {
    "tree-node selected"
  } else {
    "tree-node"
  }
  let toggle_cmd = if node.collapsed {
    dispatch(TreeEdited(@proj.Expand(node_id=node.id)))
  } else {
    dispatch(TreeEdited(@proj.Collapse(node_id=node.id)))
  }
  let toggle_label = if node.collapsed { "▶" } else { "▼" }
  let children_view = if node.collapsed {
    div(class="tree-collapsed", [text("…")])
  } else {
    match node.children {
      @proj.Loaded(children) =>
        if children.is_empty() {
          div(class="hidden-note", [text("Leaf node")])
        } else {
          div(
            class="tree-children",
            children.map(fn(child) { view_tree_node(dispatch, child) }),
          )
        }
      @proj.Elided(descendant_count) =>
        div(class="hidden-note", [
          text("\{descendant_count} hidden descendants"),
        ])
    }
  }
  div(class=class_name, [
    div(
      class="tree-label",
      on_click=dispatch(TreeEdited(@proj.Select(node_id=node.id))),
      [
        button(class="tree-toggle", on_click=toggle_cmd, [text(toggle_label)]),
        span(class="tree-text", [text(node.label)]),
        span(class="tree-kind", [text(kind_of(node.label))]),
      ],
    ),
    div(class="tree-tools", [
      button(
        class="tree-tool",
        on_click=dispatch(
          TreeEdited(@proj.WrapInLambda(node_id=node.id, var_name="x")),
        ),
        [text("Wrap λ")],
      ),
      button(
        class="tree-tool",
        on_click=dispatch(TreeEdited(@proj.Delete(node_id=node.id))),
        [text("Delete")],
      ),
    ]),
    children_view,
  ])
}

// ── Panels ──────────────────────────────────────────────────────────

///|
fn panel(title : String, meta : String, body : Html) -> Html {
  div(class="panel", [
    div(class="panel-header", [
      h2(class="panel-title", title),
      div(class="panel-meta", meta),
    ]),
    div(class="panel-body", [body]),
  ])
}

///|
fn tree_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  let body = match model.tree_state.tree {
    Some(root) => div(class="tree-root", [view_tree_node(dispatch, root)])
    None => div(class="hidden-note", [text("No AST available")])
  }
  panel("Tree", "projection-first editing surface", body)
}

///|
fn text_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  panel(
    "Text",
    "secondary synchronized projection",
    textarea(
      class="text-editor",
      value=model.text_view,
      rows=12,
      on_input=fn(s) { dispatch(TextInput(s)) },
      "",
    ),
  )
}

// ── Sidebar ─────────────────────────────────────────────────────────

///|
fn selection_section(model : Model) -> Html {
  let content = match selected_node_details(model) {
    Some(node) =>
      div(class="sidebar-detail", [
        p(class="sidebar-copy", "Node: \{node.label}"),
        p(class="sidebar-copy", "Children: \{node.child_count}"),
      ])
    None =>
      match model.tree_state.tree {
        Some(_) =>
          if has_hidden_selection(model) {
            p(
              class="sidebar-copy",
              "Selected node is inside a collapsed subtree.",
            )
          } else {
            p(class="sidebar-copy", "No node selected.")
          }
        None => p(class="sidebar-copy", "No tree available.")
      }
  }
  div(class="sidebar-section", [
    h2(class="sidebar-title", "Selection"),
    content,
    p(
      class="sidebar-copy",
      "Persistent IDs keep UI focus stable across projections.",
    ),
  ])
}

///|
fn diagnostics_section(model : Model) -> Html {
  let errors = model.editor.get_errors()
  let items = if errors.is_empty() {
    [li(class="sidebar-item", "No errors.")]
  } else {
    errors.map(fn(e) { li(class="sidebar-item", e) })
  }
  let body = if model.diagnostics_open {
    ul(class="sidebar-list", items)
  } else {
    p(class="hidden-note", "Diagnostics are hidden.")
  }
  div(class="sidebar-section", [h2(class="sidebar-title", "Diagnostics"), body])
}

///|
fn peers_section(model : Model) -> Html {
  div(class="sidebar-section", [
    h2(class="sidebar-title", "Peers"),
    ul(
      class="sidebar-list",
      model.peers.map(fn(peer) {
        let (name, pos) = peer
        li(class="sidebar-item", "\{name} cursor at \{pos}")
      }),
    ),
  ])
}

///|
fn sidebar(model : Model) -> Html {
  div(class="sidebar", [
    selection_section(model),
    diagnostics_section(model),
    peers_section(model),
  ])
}

// ── Workspace & chrome ──────────────────────────────────────────────

///|
fn workspace_class(mode : WorkspaceMode) -> String {
  match mode {
    Split => "workspace split"
    TreeOnly => "workspace tree-only"
    TextOnly => "workspace text-only"
  }
}

///|
fn workspace(dispatch : Dispatch[Msg], model : Model) -> Html {
  let panes = match model.workspace_mode {
    Split =>
      [tree_panel(dispatch, model), text_panel(dispatch, model), sidebar(model)]
    TreeOnly => [tree_panel(dispatch, model), sidebar(model)]
    TextOnly => [text_panel(dispatch, model), sidebar(model)]
  }
  div(class=workspace_class(model.workspace_mode), panes)
}

///|
fn toolbar(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="toolbar", [
    control(
      "Split",
      on_click=dispatch(SetMode(Split)),
      active=model.workspace_mode == Split,
    ),
    control(
      "Tree",
      on_click=dispatch(SetMode(TreeOnly)),
      active=model.workspace_mode == TreeOnly,
    ),
    control(
      "Text",
      on_click=dispatch(SetMode(TextOnly)),
      active=model.workspace_mode == TextOnly,
    ),
    control("Diagnostics", on_click=dispatch(ToggleDiagnostics)),
  ])
}

///|
fn hero() -> Html {
  div(class="hero", [
    p(class="eyebrow", "Rabbita Projectional Editor"),
    h1(
      class="hero-title",
      "Projectional editor shell with a tree-first workspace",
    ),
    p(
      class="hero-copy",
      "Tree and text are synchronized through a canonical AST model. Edit either projection and both update.",
    ),
  ])
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="app-shell", [
    hero(),
    toolbar(dispatch, model),
    workspace(dispatch, model),
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
  node : @proj.InteractiveTreeNode,
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
    TreeEdited(@proj.Collapse(node_id=root_id)),
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
    TreeEdited(@proj.Select(node_id=root_id)),
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
    TreeEdited(@proj.StartEdit(node_id=root_id)),
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
    TreeEdited(@proj.Collapse(node_id=root_id)),
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
    TreeEdited(@proj.Expand(node_id=root_id)),
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
    TreeEdited(@proj.Collapse(node_id=root_id)),
    model,
  )
  let elided = refresh(collapsed)
  let new_text = "let id = λx.x in let apply = λf.λx.f x in apply id 99"
  let (_, dirty) = update(_ => none, TextInput(new_text), elided)

  let (_, expanded) = update(
    _ => none,
    TreeEdited(@proj.Expand(node_id=root_id)),
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
    TreeEdited(@proj.Select(node_id=literal_id)),
    model,
  )
  let root_id = root_node_id_for_test(selected)
  let (_, collapsed) = update(
    _ => none,
    TreeEdited(@proj.Collapse(node_id=root_id)),
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
    TreeEdited(@proj.WrapInLambda(node_id=root_id, var_name="x")),
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
    TreeEdited(@proj.Select(node_id=root_id)),
    model,
  )
  let old_text = selected.editor.get_text()
  let (_, updated) = update(
    _ => none,
    TreeEdited(@proj.Delete(node_id=root_id)),
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
    TreeEdited(@proj.Delete(node_id=literal_id)),
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
    TreeEdited(@proj.Select(node_id=literal_id)),
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
