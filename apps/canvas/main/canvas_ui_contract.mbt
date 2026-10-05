///|
/// Requests capture their target at input admission, never at delayed execution.
priv enum CanvasSourceRequest {
  Rename(NodeId, String)
  Parameter(NodeId, String, String)
  Insert(String, String)
  DeleteNodes(Array[NodeId])
  Disconnect(EdgeId)
}

///|
priv enum CanvasSourceReply {
  Applied
  Rejected
  ParserStopped
}

///|
/// Private composition ingress. Receivers queue in the Source host's scheduler.
priv enum CanvasSourceMessage {
  Request(CanvasSourceRequest, ((CanvasSourceReply) -> Unit)?)
  Completed(SourceNoticeOperation, SourceGraphOperationResultJson)
  ParserStopped
}
