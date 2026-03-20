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
pub struct WorkspaceLayout {
  outline_visible : Bool
  inspector_visible : Bool
  bottom_visible : Bool
}

///|
pub enum SyncStatus {
  Offline
  Connecting
  Connected
  Error
} derive(Eq)

///|
pub struct Model {
  editor : @editor.SyncEditor
  outline_state : @proj.TreeEditorState
  mode : EditorMode
  workspace : WorkspaceLayout
  selected_node : String?
  diagnostics_open : Bool
  next_timestamp : Int
  bottom_tab : BottomTab
  sync_status : SyncStatus
}
