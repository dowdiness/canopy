// JSON edit operations — structural edits on JSON documents.

///|
using @core {type NodeId}

///|
pub(all) enum JsonType {
  JNull
  JBool
  JNumber
  JString
  JArray
  JObject
} derive(Show, Eq)

///|
pub(all) enum JsonEditOp {
  Delete(node_id~ : NodeId)
  AddMember(object_id~ : NodeId, key~ : String)
  AddElement(array_id~ : NodeId)
  WrapInArray(node_id~ : NodeId)
  WrapInObject(node_id~ : NodeId, key~ : String)
  Unwrap(node_id~ : NodeId)
  ChangeType(node_id~ : NodeId, new_type~ : JsonType)
  RenameKey(object_id~ : NodeId, key_index~ : Int, new_key~ : String)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
} derive(Show, Eq)
