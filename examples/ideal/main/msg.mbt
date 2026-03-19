///|
pub enum Msg {
  // Mode & layout
  SetMode(EditorMode)
  TogglePanel(PanelId)
  SelectBottomTab(BottomTab)
  // From Web Component events
  NodeSelected(String)
  StructuralEditRequested(op~ : String, node_id~ : String)
  // Projection
  RefreshProjection
  // Undo/redo
  Undo
  Redo
  // UI
  LoadExample(String)
  OutlineNodeClicked(String)
}
