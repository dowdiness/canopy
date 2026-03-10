///|
using @html {div, h1, h2, li, p, pre, text, ul}

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
  SelectNode(String)
}

///|
struct TreeNode {
  id : String
  kind : String
  label : String
  children : Array[TreeNode]
}

///|
struct Model {
  workspace_mode : WorkspaceMode
  diagnostics_open : Bool
  selected_node : String
  text_view : String
  diagnostics : Array[String]
  peers : Array[(String, Int)]
  tree : TreeNode
}

///|
fn init_model() -> Model {
  {
    workspace_mode: Split,
    diagnostics_open: true,
    selected_node: "root",
    text_view:
      "let id = λx.x in\n" +
      "let apply = λf.λx.f x in\n" +
      "apply id 42\n",
    diagnostics: [
      "Selection is still local UI state in this prototype.",
      "Tree gestures should become explicit TreeEditOp messages.",
      "Text pane is secondary; the projectional tree should be primary.",
    ],
    peers: [("alice", 18), ("bob", 33)],
    tree: {
      id: "root",
      kind: "let",
      label: "let apply = ...",
      children: [
        {
          id: "lambda-id",
          kind: "lambda",
          label: "λx.x",
          children: [
            { id: "var-x", kind: "var", label: "x", children: [] },
          ],
        },
        {
          id: "lambda-apply",
          kind: "lambda",
          label: "λf.λx.f x",
          children: [
            { id: "var-f", kind: "var", label: "f", children: [] },
            { id: "var-x-2", kind: "var", label: "x", children: [] },
          ],
        },
        {
          id: "call",
          kind: "app",
          label: "apply id 42",
          children: [
            { id: "var-apply", kind: "var", label: "apply", children: [] },
            { id: "var-id", kind: "var", label: "id", children: [] },
            { id: "int-42", kind: "int", label: "42", children: [] },
          ],
        },
      ],
    },
  }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    SetMode(workspace_mode) => { ..model, workspace_mode }
    ToggleDiagnostics => { ..model, diagnostics_open: !model.diagnostics_open }
    SelectNode(node_id) => { ..model, selected_node: node_id }
  }
}

///|
fn control(
  label : String,
  on_click~ : Cmd,
  active~ : Bool = false,
) -> Html {
  let class_name = if active { "control active" } else { "control" }
  div(class=class_name, on_click~, [text(label)])
}

///|
fn tree_tool(label : String) -> Html {
  div(class="tree-tool", [text(label)])
}

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
fn view_tree_node(dispatch : Dispatch[Msg], model : Model, node : TreeNode) -> Html {
  let class_name =
    if model.selected_node == node.id {
      "tree-node selected"
    } else {
      "tree-node"
    }
  let child_views = node.children.map(fn(child) { view_tree_node(dispatch, model, child) })
  div(class=class_name, [
    div(class="tree-label", [
      text(node.label),
      div(class="tree-kind", [text(node.kind)]),
    ]),
    div(class="tree-tools", [
      control("Select", on_click=dispatch(SelectNode(node.id))),
      tree_tool("Wrap λ"),
      tree_tool("Insert"),
      tree_tool("Delete"),
    ]),
    if child_views.length() == 0 {
      div(class="hidden-note", [text("Leaf node")])
    } else {
      div(class="tree-children", child_views)
    },
  ])
}

///|
fn tree_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  panel(
    "Tree",
    "projection-first editing surface",
    div(class="tree-root", [view_tree_node(dispatch, model, model.tree)]),
  )
}

///|
fn text_panel(model : Model) -> Html {
  panel(
    "Text",
    "secondary synchronized projection",
    pre(class="text-pane", model.text_view),
  )
}

///|
fn selection_section(model : Model) -> Html {
  div(class="sidebar-section", [
    h2(class="sidebar-title", "Selection"),
    div(class="sidebar-copy", [
      text("Selected node: "),
      div(class="sidebar-inline-code", [text(model.selected_node)]),
    ]),
    p(class="sidebar-copy", "Persistent IDs keep UI focus stable across projections."),
  ])
}

///|
fn diagnostics_section(model : Model) -> Html {
  let body =
    if model.diagnostics_open {
      ul(
        class="sidebar-list",
        model.diagnostics.map(fn(item) {
          li(class="sidebar-item", item)
        }),
      )
    } else {
      p(class="hidden-note", "Diagnostics are hidden.")
    }
  div(class="sidebar-section", [
    h2(class="sidebar-title", "Diagnostics"),
    body,
  ])
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
    Split => [tree_panel(dispatch, model), text_panel(model), sidebar(model)]
    TreeOnly => [tree_panel(dispatch, model), sidebar(model)]
    TextOnly => [text_panel(model), sidebar(model)]
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
    control(
      "Toggle Diagnostics",
      on_click=dispatch(ToggleDiagnostics),
    ),
  ])
}

///|
fn hero() -> Html {
  div(class="hero", [
    p(class="eyebrow", "Rabbita Template Setup"),
    h1(class="hero-title", "Projectional editor shell with a tree-first workspace"),
    p(
      class="hero-copy",
      "This Rabbita app is the projection layer only. The editor core should own text, AST, sync, and undo state; the UI should dispatch explicit edit messages and render derived projections.",
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
fn main {
  let app = @rabbita.simple_cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
}
