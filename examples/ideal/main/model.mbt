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
struct OverlayState {
  visible : Bool
  actions : Array[@proj.Action]
  node_context : NodeActionContext?
  submenu : @proj.Action?
  pending_action : @proj.Action?
  name_value : String
  name_error : String
  anchor_top : Int
  anchor_left : Int
}

///|
struct NodeActionContext {
  node_id : @proj.NodeId
  kind : @ast.Term
  is_let_binding : Bool
  binding_node_id : @proj.NodeId?
  binding_def_index : Int?
  module_node_id : @proj.NodeId?
}

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
  overlay : OverlayState
}
