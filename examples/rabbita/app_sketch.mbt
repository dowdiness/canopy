// Rabbita projectional editor sketch.
//
// This file is a design artifact, not a buildable package in the current repo.
// It shows the intended Rabbita shape after the editor facade is consolidated
// around an AST-first incremental core.

///|
/// Sketch: the actual implementation would import Rabbita and the projection
/// package once this example becomes a real module.

// using @html {
//   button, code, div, h2, h3, li, p, pre, span, textarea, ul, fragment, nothing
// }
// using @projection {
//   type InteractiveTreeNode,
//   type NodeId,
//   type TreeEditOp,
//   type TreeEditorState,
// }

///|
/// Placeholder types for the eventual integrated editor facade.
#declaration_only
type SyncEditor

///|
#declaration_only
type SyncMessage

///|
#declaration_only
type Html

///|
#declaration_only
type Dispatch[M]

///|
/// Which projection is emphasized in the workspace.
pub enum WorkspaceMode {
  Split
  TreeOnly
  TextOnly
} derive(Eq, Show)

///|
/// Derived selection data shown in the inspector.
pub struct SelectionSummary {
  node_label : String
  range_start : Int
  range_end : Int
} derive(Show)

///|
/// UI shell model. The source of truth remains the editor core.
pub struct Model {
  editor : SyncEditor
  tree_state : TreeEditorState
  text_view : String
  diagnostics : Array[String]
  peer_cursors : Map[String, Int]
  workspace_mode : WorkspaceMode
  diagnostics_open : Bool
  selection_summary : SelectionSummary?
}

///|
/// UI events and editor intents.
pub enum Msg {
  TextInput(String)
  TreeEdited(TreeEditOp)
  SelectNode(NodeId)
  Undo
  Redo
  ToggleDiagnostics
  SetWorkspaceMode(WorkspaceMode)
  ApplyRemote(SyncMessage)
  NoOp
} derive(Show)

///|
/// Build the initial model from the editor core.
pub fn init(editor : SyncEditor) -> Model {
  {
    editor,
    tree_state: read_tree_state(editor),
    text_view: read_text(editor),
    diagnostics: read_diagnostics(editor),
    peer_cursors: read_peer_cursors(editor),
    workspace_mode: Split,
    diagnostics_open: true,
    selection_summary: read_selection_summary(editor),
  }
}

///|
/// Rabbita update function.
///
/// Key discipline:
/// - text input is an explicit message
/// - tree gestures are explicit `TreeEditOp`
/// - the view never mutates editor state directly
/// - the DOM is a catamorphism over `Model`
pub fn update(msg : Msg, model : Model) -> Model {
  match msg {
    TextInput(new_text) => {
      let editor = apply_text_input(model.editor, new_text)
      refresh(model, editor)
    }
    TreeEdited(op) => {
      let editor = apply_tree_edit(model.editor, op)
      refresh(model, editor)
    }
    SelectNode(node_id) => {
      let editor = select_node(model.editor, node_id)
      refresh(model, editor)
    }
    Undo => {
      let editor = undo(model.editor)
      refresh(model, editor)
    }
    Redo => {
      let editor = redo(model.editor)
      refresh(model, editor)
    }
    ToggleDiagnostics => {
      { ..model, diagnostics_open: !model.diagnostics_open }
    }
    SetWorkspaceMode(workspace_mode) => {
      { ..model, workspace_mode }
    }
    ApplyRemote(sync_message) => {
      let editor = apply_remote(model.editor, sync_message)
      refresh(model, editor)
    }
    NoOp => model
  }
}

///|
/// Recompute derived projections after the editor core changes.
fn refresh(model : Model, editor : SyncEditor) -> Model {
  {
    ..model,
    editor,
    tree_state: read_tree_state(editor),
    text_view: read_text(editor),
    diagnostics: read_diagnostics(editor),
    peer_cursors: read_peer_cursors(editor),
    selection_summary: read_selection_summary(editor),
  }
}

///|
/// Rabbita view sketch.
pub fn view(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  shell([
    toolbar(dispatch, model),
    workspace(dispatch, model),
    inspector(dispatch, model),
  ])
}

///|
/// Top-level workspace layout.
fn workspace(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  match model.workspace_mode {
    Split =>
      row([
        tree_panel(dispatch, model),
        text_panel(dispatch, model),
      ])
    TreeOnly => tree_panel(dispatch, model)
    TextOnly => text_panel(dispatch, model)
  }
}

///|
/// Tree-first editing surface.
///
/// This is the primary projectional UI. Nodes are keyed by persistent IDs and
/// gestures become `TreeEditOp` values.
fn tree_panel(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  panel(
    title="Tree",
    body=match model.tree_state.tree {
      Some(root) => view_tree_node(dispatch, root)
      None => empty_state("No AST available")
    },
  )
}

///|
fn view_tree_node(
  dispatch : (Msg) -> Dispatch[Msg],
  node : InteractiveTreeNode,
) -> Html {
  let children =
    if node.collapsed {
      []
    } else {
      node.children.map(fn(child) { view_tree_node(dispatch, child) })
    }

  tree_card(
    label=node.label,
    selected=node.selected,
    editing=node.editing,
    collapsed=node.collapsed,
    drop_target=node.drop_target,
    on_select=dispatch(SelectNode(node.id)),
    on_toggle=dispatch(
      TreeEdited(
        if node.collapsed {
          Expand(node_id=node.id)
        } else {
          Collapse(node_id=node.id)
        },
      ),
    ),
    on_delete=dispatch(TreeEdited(Delete(node_id=node.id))),
    on_wrap_lambda=dispatch(
      TreeEdited(WrapInLambda(node_id=node.id, var_name="x")),
    ),
    children,
  )
}

///|
/// Synchronized text pane.
///
/// This exists as a secondary projection and debugging surface. It should not
/// be the only editor surface.
fn text_panel(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  panel(
    title="Text",
    body=text_editor(
      value=model.text_view,
      on_change=fn(text) { dispatch(TextInput(text)) },
    ),
  )
}

///|
/// Right-hand inspector for derived information.
fn inspector(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  let _ = dispatch
  sidebar([
    selection_section(model.selection_summary),
    diagnostics_section(model.diagnostics_open, model.diagnostics),
    peers_section(model.peer_cursors),
  ])
}

///|
fn toolbar(dispatch : (Msg) -> Dispatch[Msg], model : Model) -> Html {
  let _ = model
  topbar([
    toolbar_button(label="Undo", on_click=dispatch(Undo)),
    toolbar_button(label="Redo", on_click=dispatch(Redo)),
    toolbar_button(
      label="Split",
      on_click=dispatch(SetWorkspaceMode(Split)),
    ),
    toolbar_button(
      label="Tree",
      on_click=dispatch(SetWorkspaceMode(TreeOnly)),
    ),
    toolbar_button(
      label="Text",
      on_click=dispatch(SetWorkspaceMode(TextOnly)),
    ),
    toolbar_button(
      label="Diagnostics",
      on_click=dispatch(ToggleDiagnostics),
    ),
  ])
}

///|
/// Placeholder HTML helpers. A real Rabbita example would replace these with
/// `@html` constructors and attributes.
#declaration_only
fn shell(Array[Html]) -> Html

///|
#declaration_only
fn row(Array[Html]) -> Html

///|
#declaration_only
fn sidebar(Array[Html]) -> Html

///|
#declaration_only
fn panel(title~ : String, body~ : Html) -> Html

///|
#declaration_only
fn empty_state(String) -> Html

///|
#declaration_only
fn topbar(Array[Html]) -> Html

///|
#declaration_only
fn toolbar_button(label~ : String, on_click~ : Dispatch[Msg]) -> Html

///|
#declaration_only
fn tree_card(
  label~ : String,
  selected~ : Bool,
  editing~ : Bool,
  collapsed~ : Bool,
  drop_target~ : Bool,
  on_select~ : Dispatch[Msg],
  on_toggle~ : Dispatch[Msg],
  on_delete~ : Dispatch[Msg],
  on_wrap_lambda~ : Dispatch[Msg],
  children~ : Array[Html],
) -> Html

///|
#declaration_only
fn text_editor(value~ : String, on_change~ : (String) -> Dispatch[Msg]) -> Html

///|
#declaration_only
fn selection_section(SelectionSummary?) -> Html

///|
#declaration_only
fn diagnostics_section(Bool, Array[String]) -> Html

///|
#declaration_only
fn peers_section(Map[String, Int]) -> Html

///|
/// Placeholder editor-core integration points.
///
/// These should be implemented against the eventual AST-first facade. They are
/// kept explicit so the UI never reaches around the intermediate structure and
/// never does retrospective diffing on its own.
#declaration_only
fn read_text(SyncEditor) -> String

///|
#declaration_only
fn read_tree_state(SyncEditor) -> TreeEditorState

///|
#declaration_only
fn read_diagnostics(SyncEditor) -> Array[String]

///|
#declaration_only
fn read_peer_cursors(SyncEditor) -> Map[String, Int]

///|
#declaration_only
fn read_selection_summary(SyncEditor) -> SelectionSummary?

///|
#declaration_only
fn apply_text_input(SyncEditor, String) -> SyncEditor

///|
#declaration_only
fn apply_tree_edit(SyncEditor, TreeEditOp) -> SyncEditor

///|
#declaration_only
fn select_node(SyncEditor, NodeId) -> SyncEditor

///|
#declaration_only
fn apply_remote(SyncEditor, SyncMessage) -> SyncEditor

///|
#declaration_only
fn undo(SyncEditor) -> SyncEditor

///|
#declaration_only
fn redo(SyncEditor) -> SyncEditor
