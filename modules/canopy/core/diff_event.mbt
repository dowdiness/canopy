///|
/// Reconciliation trace events — one per decision point in reconcile_children.
/// Raw trace; contains Matched events that the user-facing StructuredChange
/// projection filters out.
#derive(Eq)
pub(all) enum ReconcileTraceEvent {
  Matched(NodeId, Int32, Int32, NodeId, String)
  Inserted(NodeId, Int32, NodeId, String)
  Deleted(NodeId, Int32, NodeId, String)
  Wrapped(NodeId, NodeId, String)
  Unwrapped(NodeId, NodeId, String)
  Renamed(NodeId, String)
  Freshened(NodeId, Int32, NodeId, String)
}

///|
/// User-facing structural change — Matched events filtered out.
#derive(Eq)
pub(all) enum StructuredChange {
  Inserted(NodeId, Int32, NodeId, String)
  Deleted(NodeId, Int32, NodeId, String)
  Wrapped(NodeId, NodeId, String)
  Unwrapped(NodeId, NodeId, String)
  Renamed(NodeId, String)
  Freshened(NodeId, Int32, NodeId, String)
}

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

///|
pub extend ReconcileTraceEvent with Eq::{equal, not_equal}

///|
pub extend StructuredChange with Eq::{equal, not_equal}
