///|
pub enum EditorMode {
  Text
  Structure
} derive(Eq)

///|
pub enum BottomTab {
  Problems
  OpLog
  Patch
  History
  CrdtState
  Graphviz
  IncrGraph
} derive(Eq)

///|
/// One row group in the Patch panel: a structural intent (op label, same
/// shape as the Op Log entry) paired with the `SpanEdit`s that the editor
/// produced for it. Empty `edits` is legal — pure navigation ops like
/// `Select` resolve to zero text changes.
pub(all) struct PatchEntry {
  op_label : String
  edits : Array[@canopy_core.SpanEdit]
}

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
  outline_resize : @resizable.Model
}

///|
pub enum SyncStatus {
  Offline
  Connecting
  Connected
  Error
} derive(Eq)

///|
/// The overlay's mode: exactly one of three open states. Replaces the former
/// implicit `(visible, submenu, pending_action)` encoding so that illegal
/// combinations — a closed overlay with a pending action, or a submenu and a
/// name prompt active at once — are unrepresentable.
enum OverlayMode {
  MainMenu
  Submenu(@lambda_edits.Action)
  // `value` is the text typed into the name prompt — genuinely prompt-local,
  // so it lives in the variant rather than as a flat OverlayState field.
  NamePrompt(@lambda_edits.Action, value~ : String)
}

///|
struct OverlayState {
  mode : OverlayMode
  actions : Array[@lambda_edits.Action]
  kind : @ast.Term
  // The most recent failure to act. Overlay-wide, not prompt-specific: an
  // action can fail to apply from MainMenu or Submenu just as from NamePrompt,
  // so the error is rendered in the panel for any open mode (view_actions.mbt).
  // None unambiguously means "no error"; Some(e) means a specific typed failure.
  error : OverlayError?
  anchor_top : Int
  anchor_left : Int
  menu : @menu.Model
}

///|
struct NodeActionContext {
  node_id : @canopy_core.NodeId
  kind : @ast.Term
  is_let_binding : Bool
  binding_node_id : @canopy_core.NodeId?
  binding_def_index : Int?
  module_node_id : @canopy_core.NodeId?
}

///|
pub struct Model {
  editor : @editor.SyncEditor[@ast.Term]
  // FFI handle for this editor, used to drive handle-keyed FFI (file I/O).
  handle : Int
  companion : @lambda.LambdaCompanion
  outline_state : @proj.TreeEditorState[@ast.Term]
  cm_id : String
  mounted : Bool
  mode : EditorMode
  workspace : WorkspaceLayout
  selected_node : String?
  diagnostics_open : Bool
  next_timestamp : Int
  bottom_tab : BottomTab
  sync_status : SyncStatus
  overlay : ActionOverlayHost
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation]
  highlight_set : @immut/hashset.HashSet[@canopy_core.NodeId]
  // Outline drag-and-drop state
  drag_source : @canopy_core.NodeId?
  // Cached navigation path between consecutive arrow key presses.
  // Cleared on any non-navigation event (structural edit, click, etc.).
  mut nav_path : Array[Int]?
  drop_target_id : @canopy_core.NodeId?
  drop_position : @canopy_core.DropPosition?
  // Inspector traceability: rolling log of structural intents (most recent last).
  // Mutated in place; capped to MAX_INTENT_LOG entries to keep render cheap.
  intent_log : Array[String]
  // Inspector traceability: rolling log of (op, SpanEdits) pairs, most recent
  // last. Capped to MAX_PATCH_LOG. Populated by the direct-apply dispatch
  // sites that route through `apply_lambda_tree_edit`; the
  // `StructureStructuralEdit` FFI path (main.mbt::update) cannot contribute —
  // the typed payload is consumed by `handle_structural_intent` FFI before
  // MoonBit sees the message, so no `SpanEdit` array is available to record.
  patch_log : Array[PatchEntry]
  // Model-owned tap on the parser's incr Runtime. Created once at init so it
  // observes memo events across the whole session, not per render. Reads via
  // `snapshot()` for the IncrGraph bottom-panel tab.
  incr_tap : @visualizer.RecomputeTap
}
