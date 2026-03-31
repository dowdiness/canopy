///|
pub enum Msg {
  // Mode & layout
  SetMode(EditorMode)
  TogglePanel(PanelId)
  SelectBottomTab(BottomTab)
  // From Web Component events
  NodeSelected(String)
  StructuralEditRequested(op~ : String, node_id~ : String)
  // Undo/redo
  Undo
  Redo
  // Tree editing (outline collapse/expand)
  TreeEdited(@proj.TreeEditOp)
  // UI
  DismissPanels
  LoadExample(String)
  OutlineNodeClicked(String)
  // Keyboard navigation in outline — updates selection without stealing editor focus
  OutlineNavigate(String)
  // Keyboard structural edit in outline — CRDT round-trip
  OutlineStructuralEdit(@lambda_edits.TreeEditOp)
  // Open action overlay anchored to outline row, node from model.selected_node
  OpenActionOverlayFromOutline
  // Sync
  TextChangedFromEditor
  SyncStatusChanged(String)
  // Action overlay
  OpenActionOverlay
  CloseActionOverlay
  ActionKeyPressed(String)
  ActionTapped(String)
  NamePromptInput(String)
  NamePromptSubmit
  NamePromptCancel
  LongPressTriggered
}
