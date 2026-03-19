///|
pub enum EditorMode {
  Text
  Structure
} derive(Eq)

///|
pub enum BottomTab {
  Problems
  OpLog
  CrdtState
  Graphviz
} derive(Eq)

///|
pub enum PanelId {
  Outline
  Inspector
  Bottom
} derive(Eq)

///|
pub struct CursorInfo {
  line : Int
  col : Int
  offset : Int
}

///|
pub struct WorkspaceLayout {
  outline_visible : Bool
  inspector_visible : Bool
  bottom_visible : Bool
}

///|
pub struct Model {
  editor : @editor.SyncEditor
  outline_state : @proj.TreeEditorState
  mode : EditorMode
  workspace : WorkspaceLayout
  cursor : CursorInfo?
  selected_node : String?
  diagnostics_open : Bool
  next_timestamp : Int
  projection_dirty : Bool
  refresh_scheduled : Bool
  bottom_tab : BottomTab
}
