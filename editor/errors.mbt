///| User-facing error types for editor boundary code.

///|
pub(all) suberror TreeEditError {
  ExpectedJsonObject
  MissingField(field~ : String)
  FieldMustBeString(field~ : String)
  FieldMustBeNumber(field~ : String)
  UnknownBop(name~ : String)
  UnknownOpType(op_type~ : String)
  ProjectionUnavailable
  UnhandledOperation(detail~ : String)
  NodeNotInSourceMap(action~ : String, node_id~ : @core.NodeId)
  NodeNotInRegistry(action~ : String, node_id~ : @core.NodeId)
  TextTransformFailed(detail~ : String)
  ProjectionEdit(detail~ : String)
}

///|
pub fn TreeEditError::message(self : TreeEditError) -> String {
  match self {
    ExpectedJsonObject => "expected JSON object"
    MissingField(field~) => "missing \{field} field"
    FieldMustBeString(field~) => "\{field} must be a string"
    FieldMustBeNumber(field~) => "\{field} must be a number"
    UnknownBop(name~) => "unknown bop: \{name}"
    UnknownOpType(op_type~) => "unknown op type: \{op_type}"
    ProjectionUnavailable => "No projection available"
    UnhandledOperation(detail~) => "Unhandled tree edit op: \{detail}"
    NodeNotInSourceMap(action~, node_id~) =>
      "\{action}: node \{node_id} not in source map"
    NodeNotInRegistry(action~, node_id~) =>
      "\{action}: node \{node_id} not in registry"
    TextTransformFailed(detail~) => "apply_text_transform: \{detail}"
    ProjectionEdit(detail~) => detail
  }
}
