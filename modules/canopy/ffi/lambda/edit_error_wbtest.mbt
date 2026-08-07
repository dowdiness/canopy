///|
test "FFI edit error mapping preserves Resolve action" {
  let id = @core.NodeId::from_int(42)
  let mapped = map_edit_error(
    @core.EditError::NodeNotInSourceMap(action="Resolve", node_id=id),
  )
  inspect(
    mapped.message(),
    content="Resolve: node NodeId(42) not in source map",
  )
}

///|
test "FFI edit error mapping preserves projection-unavailable wording" {
  let mapped = map_edit_error(@core.EditError::ProjectionUnavailable)
  inspect(mapped.message(), content="No projection available")
}
