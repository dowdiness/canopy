///|
fn canvas_source_reply_cmd(
  reply : ((CanvasSourceReply) -> Unit)?,
  result : CanvasSourceReply,
) -> @rabbita.Cmd {
  match reply {
    Some(reply) => @rabbita.effect(() => reply(result))
    None => @rabbita.none
  }
}

///|
/// Runs inside Source's existing parser Failure boundary. UI targets are already
/// captured; use typed backing operations without serializing an FFI request.
fn apply_canvas_source_request(
  handle : Int,
  request : CanvasSourceRequest,
) -> (SourceNoticeOperation, SourceGraphOperationResultJson) raise Failure {
  let operation : SourceNoticeOperation = match request {
    Rename(_, _) => Renamed
    Parameter(_, name, _) => ParameterUpdated(name)
    Insert(_, constructor_name) => Inserted(constructor_name)
    DeleteNodes(_) | Disconnect(_) => Deleted
  }
  guard source_graph_by_handle(handle) is Some(graph) else {
    return (
      operation,
      source_graph_operation_result_json(
        false,
        "",
        [],
        0,
        Some("source graph handle not found"),
      ),
    )
  }
  if graph.parser_failure is Some(failure) {
    raise failure
  }
  let result = match request {
    Rename(node, name) => {
      let result = graph.apply_operation(GraphOperation(RenameNode(node, name)))
      graph.clear_selected_edge()
      result
    }
    Parameter(node, name, value) => {
      let result = graph.apply_operation(
        GraphOperation(SetNodeParam(node, name, value)),
      )
      graph.clear_selected_edge()
      result
    }
    Insert(binding_base, constructor_name) => {
      graph.clear_selected_edge()
      graph.insert_unique_result(binding_base, constructor_name)
    }
    DeleteNodes(nodes) => {
      let result = graph.apply_operation(GraphOperation(DeleteNodes(nodes)))
      {
        ..result,
        message: if result.applied {
          Some("Deleted selected nodes through graph-dsl source.")
        } else {
          result.message
        },
      }
    }
    Disconnect(edge) => graph.disconnect_edge(edge)
  }
  (operation, result)
}
