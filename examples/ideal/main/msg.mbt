///|
#warnings("-unused_constructor")
pub enum Msg {
  // Mode & layout
  SetMode(EditorMode)
  TogglePanel(PanelId)
  SelectBottomTab(BottomTab)
  // From Web Component events (inspector panel dispatch)
  StructuralEditRequested(op~ : String, node_id~ : String)
  // Undo/redo
  Undo
  Redo
  // Tree editing (outline collapse/expand)
  TreeEdited(@lambda_edits.TreeEditOp)
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
  SyncStatusChanged(String)
  // Action overlay
  OpenActionOverlayForNode(String)
  CloseActionOverlay
  ActionMenu(@menu.Msg)
  ActionKeyPressed(String)
  NamePromptInput(String)
  NamePromptSubmit
  NamePromptCancel
  LongPressTriggeredForNode(String)
  // Outline drag-and-drop
  OutlineDragStart(@canopy_core.NodeId)
  OutlineDragOver(@canopy_core.NodeId, @canopy_core.DropPosition)
  OutlineDragLeave
  OutlineDrop(@canopy_core.NodeId, @canopy_core.DropPosition)
  OutlineDragEnd
  // Structure-mode Web Component communication.
  StructureNodeSelected(String)
  StructureStructuralEdit(op~ : String, node_id~ : String)
  ExternalCrdtChanged
  CmMounted
  CmDocChanged(String)
  CmSelectionChanged(@cm.SelRange)
  CmFocusChanged(Bool)
}
