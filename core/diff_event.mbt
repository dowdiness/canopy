///|
/// Reconciliation trace events — one per decision point in reconcile_children.
/// Raw trace; contains Matched events that the user-facing StructuredChange
/// projection filters out.
pub(all) enum ReconcileTraceEvent {
  Matched(NodeId, Int, Int, NodeId, String)
  Inserted(NodeId, Int, NodeId, String)
  Deleted(NodeId, Int, NodeId, String)
  Wrapped(NodeId, NodeId, String)
  Unwrapped(NodeId, NodeId, String)
  Renamed(NodeId, String)
  Freshened(NodeId, Int, NodeId, String)
} derive(Eq)

///|
/// User-facing structural change — Matched events filtered out.
pub(all) enum StructuredChange {
  Inserted(NodeId, Int, NodeId, String)
  Deleted(NodeId, Int, NodeId, String)
  Wrapped(NodeId, NodeId, String)
  Unwrapped(NodeId, NodeId, String)
  Renamed(NodeId, String)
  Freshened(NodeId, Int, NodeId, String)
} derive(Eq)

///|
/// Filter ReconcileTraceEvent to StructuredChange (drop Matched).
pub fn to_structured_changes(
  events : Array[ReconcileTraceEvent],
) -> Array[StructuredChange] {
  events.filter_map(fn(e) {
    match e {
      Matched(_, _, _, _, _) => None
      Inserted(parent_id, index, node_id, kind_tag) =>
        Some(StructuredChange::Inserted(parent_id, index, node_id, kind_tag))
      Deleted(parent_id, index, node_id, kind_tag) =>
        Some(StructuredChange::Deleted(parent_id, index, node_id, kind_tag))
      Wrapped(inner_id, wrapper_node_id, wrapper_kind) =>
        Some(StructuredChange::Wrapped(inner_id, wrapper_node_id, wrapper_kind))
      Unwrapped(wrapper_id, kept_id, wrapper_kind) =>
        Some(StructuredChange::Unwrapped(wrapper_id, kept_id, wrapper_kind))
      Renamed(node_id, kind_tag) =>
        Some(StructuredChange::Renamed(node_id, kind_tag))
      Freshened(parent_id, index, node_id, kind_tag) =>
        Some(StructuredChange::Freshened(parent_id, index, node_id, kind_tag))
    }
  })
}
