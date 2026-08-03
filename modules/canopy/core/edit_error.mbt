///| Typed errors for language edit computation.

///|

///| Replaces the `String`-based error model in `lang/runtime.LanguageSpec`

///| and per-language edit paths. Raised from compute-edit handlers and

///| caught at editor/FFI boundaries for structured mapping into

///| `@editor.TreeEditError` or string rendering.

///|

///| Variants are semantic, not per-site: grouped by catch-site needs with

///| `Invariant(detail)` as the escape hatch for assertion failures that

///|
/// should not happen in correct editor state.
pub(all) suberror EditError {
  /// No projection tree available for edit computation.
  ProjectionUnavailable
  /// A node ID had no entry in the projection tree or registry.
  NodeNotFound(action~ : String, node_id~ : NodeId)
  /// A node ID had no span in the source map.
  NodeNotInSourceMap(action~ : String, node_id~ : NodeId)
  /// A node ID was not present in the incremental-parser registry.
  NodeNotInRegistry(action~ : String, node_id~ : NodeId)
  /// A binding name could not be resolved to a declaration.
  BindingNotFound(action~ : String, node_id~ : NodeId)
  /// The edit target is the wrong AST node kind.
  InvalidTarget(detail~ : String)
  /// The requested operation is not supported for this target.
  UnsupportedOperation(detail~ : String)
  /// The edit would cause a variable capture (free variable would become
  /// bound after the edit).
  CaptureViolation(detail~ : String)
  /// The edit would violate scope ordering rules (binding would escape
  /// its scope or shadow a visible binding).
  ScopeViolation(detail~ : String)
  /// Source text could not be parsed or a token could not be recognised.
  ParseFailed(detail~ : String)
  /// A required source-span token or range is absent from the source map.
  SourceSpanMissing(detail~ : String)
  /// Something that should never happen given correct editor state.
  Invariant(detail~ : String)
}

///|
/// Human-readable message for user-facing error display.
/// Output MUST match the legacy string-error format for existing tests
/// unless a test is deliberately updated to assert variants.
pub fn EditError::message(self : EditError) -> String {
  match self {
    ProjectionUnavailable => "no projection available"
    NodeNotFound(action~, node_id~) => "\{action}: node \{node_id} not found"
    NodeNotInSourceMap(action~, node_id~) =>
      "\{action}: node \{node_id} not in source map"
    NodeNotInRegistry(action~, node_id~) =>
      "\{action}: node \{node_id} not in registry"
    BindingNotFound(action~, node_id~) => "\{action}: node \{node_id} not found"
    InvalidTarget(detail~) => detail
    UnsupportedOperation(detail~) => detail
    CaptureViolation(detail~) => detail
    ScopeViolation(detail~) => detail
    ParseFailed(detail~) => detail
    SourceSpanMissing(detail~) => detail
    Invariant(detail~) => detail
  }
}
