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
/// `changes` is a per-entry snapshot of `StructuredChange` events captured
/// at the edit point, so historical display shows the right diff for each
/// entry — not the latest reconcile's trace.
pub(all) struct PatchEntry {
  op_label : String
  edits : Array[@canopy_core.SpanEdit]
  changes : Array[@canopy_core.StructuredChange]
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
using @overlay {
  type OverlayMode,
  type OverlayState,
  type OverlayMsg,
  type OverlayOutput,
  type OverlayEffect,
  type OverlayUpdate,
  type OverlayError,
  format_overlay_error,
}

///|
struct ActionOverlayHost {
  active : (@lambda_edits.ActionContext, OverlayState, Int)?
  next_token : Int
}

///|
fn ActionOverlayHost::empty() -> ActionOverlayHost {
  { active: None, next_token: 1 }
}

///|
fn ActionOverlayHost::mount(
  self : ActionOverlayHost,
  context : @lambda_edits.ActionContext,
  state : OverlayState,
) -> ActionOverlayHost {
  {
    active: Some((context, state, self.next_token)),
    next_token: self.next_token + 1,
  }
}

///|
fn ActionOverlayHost::set_state(
  self : ActionOverlayHost,
  state : OverlayState,
) -> ActionOverlayHost {
  match self.active {
    Some((context, _, token)) =>
      { ..self, active: Some((context, state, token)) }
    None => self
  }
}

///|
fn ActionOverlayHost::active_for_token(
  self : ActionOverlayHost,
  token : Int,
) -> (@lambda_edits.ActionContext, OverlayState, Int)? {
  match self.active {
    Some((context, state, active_token)) =>
      if active_token == token {
        Some((context, state, active_token))
      } else {
        None
      }
    None => None
  }
}

///|
fn ActionOverlayHost::close(self : ActionOverlayHost) -> ActionOverlayHost {
  { ..self, active: None }
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
  scope_map : Map[@canopy_core.NodeId, @scope.ScopeAnnotation]
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
