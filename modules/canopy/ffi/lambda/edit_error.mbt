///|
/// Convert the language SPI's structured edit error to the legacy
/// user-facing editor error at the FFI quarantine boundary.
fn map_edit_error(e : @core.EditError) -> @editor.TreeEditError {
  match e {
    @core.EditError::ProjectionUnavailable =>
      @editor.TreeEditError::ProjectionUnavailable
    @core.EditError::NodeNotFound(action~, node_id~)
    | @core.EditError::NodeNotInRegistry(action~, node_id~) =>
      @editor.TreeEditError::NodeNotInRegistry(action~, node_id~)
    @core.EditError::NodeNotInSourceMap(action~, node_id~) =>
      @editor.TreeEditError::NodeNotInSourceMap(action~, node_id~)
    @core.EditError::BindingNotFound(..)
    | @core.EditError::InvalidTarget(..)
    | @core.EditError::UnsupportedOperation(..)
    | @core.EditError::CaptureViolation(..)
    | @core.EditError::ScopeViolation(..)
    | @core.EditError::ParseFailed(..)
    | @core.EditError::SourceSpanMissing(..)
    | @core.EditError::Invariant(..) =>
      @editor.TreeEditError::ProjectionEdit(detail=e.message())
  }
}
