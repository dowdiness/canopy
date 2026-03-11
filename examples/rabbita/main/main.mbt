///|
using @html {button, div, h1, h2, li, p, span, text, textarea, ul}

///|
using @rabbita {type Cmd, type Dispatch, type Html}

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
}

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
fn find_selected(
  node : @proj.InteractiveTreeNode
) -> @proj.InteractiveTreeNode? {
  if node.selected {
    return Some(node)
  }
  node.children.fold(init=None, fn(acc, child) {
    match acc {
      Some(_) => acc
      None => find_selected(child)
    }
  })
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
  { ..model, text_view, tree_state }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    SetMode(mode) => { ..model, workspace_mode: mode }
    ToggleDiagnostics =>
      { ..model, diagnostics_open: !model.diagnostics_open }
    TextInput(new_text) => {
      let old_text = model.editor.get_text()
      if old_text == new_text {
        model
      } else {
        let splice = @editor.compute_text_splice(old_text, new_text)
        model.editor.apply_text_edit(
          splice.start,
          splice.delete_len,
          splice.inserted,
          model.next_timestamp,
        )
        let refreshed = refresh(model)
        { ..refreshed, next_timestamp: model.next_timestamp + 1 }
      }
    }
    TreeEdited(op) => {
      // Update UI state (selection, collapse, drag)
      let tree_state = model.tree_state.apply_edit(op)
      let model = { ..model, tree_state }
      // Round-trip tree edit through text CRDT so ops are broadcastable
      match model.editor.apply_tree_edit(op, model.next_timestamp) {
        Ok(_) => {
          let refreshed = refresh(model)
          { ..refreshed, next_timestamp: model.next_timestamp + 1 }
        }
        Err(_) => model
      }
    }
  }
}

// ── View helpers ────────────────────────────────────────────────────

///|
fn control(
  label : String,
  on_click~ : Cmd,
  active~ : Bool = false
) -> Html {
  let class_name = if active { "control active" } else { "control" }
  div(class=class_name, on_click~, [text(label)])
}

// ── Tree view ───────────────────────────────────────────────────────

///|
fn view_tree_node(
  dispatch : Dispatch[Msg],
  node : @proj.InteractiveTreeNode
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
  } else if node.children.is_empty() {
    div(class="hidden-note", [text("Leaf node")])
  } else {
    div(
      class="tree-children",
      node.children.map(fn(child) { view_tree_node(dispatch, child) }),
    )
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
  let content = match model.tree_state.tree {
    Some(tree) =>
      match find_selected(tree) {
        Some(node) =>
          div(class="sidebar-detail", [
            p(class="sidebar-copy", "Node: \{node.label}"),
            p(class="sidebar-copy", "Kind: \{kind_of(node.label)}"),
            p(class="sidebar-copy", "Children: \{node.children.length()}"),
          ])
        None => p(class="sidebar-copy", "No node selected.")
      }
    None => p(class="sidebar-copy", "No tree available.")
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

// ── Main ────────────────────────────────────────────────────────────

///|
fn main {
  let app = @rabbita.simple_cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
}
