///|
/// Phase of a public `incr` memo recompute event.
pub(all) enum IncrMemoEventPhase {
  IncrEntering
  IncrCompleted
  IncrAborted
}

///|
/// Compact memo-event record captured by `IncrMemoEventTap`.
pub struct IncrMemoEventRecord {
  cell_id : @incr.CellId
  phase : IncrMemoEventPhase
  started_revision : @incr.Revision
  elapsed_ns : Int64?
  verified_at : @incr.Revision?
  changed_at : @incr.Revision?
  backdated : Bool
}

///|
/// Snapshot node enriched from `Runtime::cell_info`.
pub struct IncrSnapshotNode {
  id : @incr.CellId
  label : String?
  changed_at : @incr.Revision
  verified_at : @incr.Revision
}

///|
/// Snapshot edge from dependency to dependent cell.
pub struct IncrSnapshotEdge {
  from : @incr.CellId
  to : @incr.CellId
}

///|
/// Point-in-time graph and event snapshot for an `incr` runtime.
pub struct IncrSnapshot {
  nodes : Array[IncrSnapshotNode]
  edges : Array[IncrSnapshotEdge]
  events : Array[IncrMemoEventRecord]
}

///|
/// Driver-owned tap that records public `incr` memo events for visualization.
pub struct IncrMemoEventTap {
  priv rt : @incr.Runtime
  priv active : Ref[Bool]
  priv mut events : Array[IncrMemoEventRecord]
  priv cells : Array[@incr.CellId]
}

///|
fn contains_cell_id(ids : Array[@incr.CellId], id : @incr.CellId) -> Bool {
  for cell_id in ids {
    if cell_id == id {
      return true
    }
  }
  false
}

///|
fn remember_cell(ids : Array[@incr.CellId], id : @incr.CellId) -> Unit {
  if !contains_cell_id(ids, id) {
    ids.push(id)
  }
}

///|
fn copy_events(
  events : Array[IncrMemoEventRecord],
) -> Array[IncrMemoEventRecord] {
  let out : Array[IncrMemoEventRecord] = []
  for event in events {
    out.push(event)
  }
  out
}

///|
fn event_from_memo_event(evt : @incr.MemoEvent) -> IncrMemoEventRecord {
  match evt {
    EnteringCompute(e) =>
      {
        cell_id: e.cell_id,
        phase: IncrEntering,
        started_revision: e.started_revision,
        elapsed_ns: None,
        verified_at: None,
        changed_at: None,
        backdated: false,
      }
    Completed(e) =>
      {
        cell_id: e.cell_id,
        phase: IncrCompleted,
        started_revision: e.started_revision,
        elapsed_ns: Some(e.elapsed_ns),
        verified_at: Some(e.verified_at),
        changed_at: Some(e.changed_at),
        backdated: e.backdated,
      }
    Aborted(e) =>
      {
        cell_id: e.cell_id,
        phase: IncrAborted,
        started_revision: e.started_revision,
        elapsed_ns: Some(e.elapsed_ns),
        verified_at: None,
        changed_at: None,
        backdated: false,
      }
  }
}

///|
fn IncrMemoEventTap::record(
  self : IncrMemoEventTap,
  evt : @incr.MemoEvent,
) -> Unit {
  guard self.active.val else { return }
  let record = event_from_memo_event(evt)
  remember_cell(self.cells, record.cell_id)
  self.events.push(record)
}

///|
fn snapshot_ids(tap : IncrMemoEventTap) -> Array[@incr.CellId] {
  let ids : Array[@incr.CellId] = []
  for id in tap.cells {
    remember_cell(ids, id)
  }
  let mut i = 0
  while i < ids.length() {
    let id = ids[i]
    match tap.rt.cell_info(id) {
      Some(info) => {
        for dep in info.dependencies {
          remember_cell(ids, dep)
        }
        for sub in info.subscribers {
          remember_cell(ids, sub)
        }
      }
      None => ()
    }
    i = i + 1
  }
  ids
}

///|
fn visual_cell_id(id : @incr.CellId) -> String {
  "cell_" + id.runtime_id.to_string() + "_" + id.id.to_string()
}

///|
fn snapshot_node_label(node : IncrSnapshotNode) -> String {
  match node.label {
    Some(label) => label
    None => "cell " + node.id.id.to_string()
  }
}

///|
fn snapshot_node_detail(node : IncrSnapshotNode) -> String {
  "changed " +
  node.changed_at.value.to_string() +
  ", verified " +
  node.verified_at.value.to_string()
}

///|
fn status_for_cell(
  events : Array[IncrMemoEventRecord],
  id : @incr.CellId,
) -> VisualNodeStatus {
  let mut status = Neutral
  for event in events {
    if event.cell_id == id {
      status = match event.phase {
        IncrEntering => Active
        IncrCompleted => if event.backdated { Neutral } else { Changed }
        IncrAborted => Failed
      }
    }
  }
  status
}

///|
/// Attach an event tap to `rt`.
///
/// `incr` allows one memo-event listener per runtime, so attaching replaces
/// any previous listener owned by the same runtime.
pub fn IncrMemoEventTap::attach(
  rt : @incr.Runtime,
) -> IncrMemoEventTap raise Failure {
  let tap = { rt, active: Ref(true), events: [], cells: [] }
  rt.on_memo_event(evt => tap.record(evt))
  tap
}

///|
/// Stop this tap from recording future events.
///
/// `incr` exposes replacement and clearing for the runtime listener, but not
/// listener identity. Deactivating this tap's closure keeps stale handles from
/// clearing a newer tap that replaced them.
pub fn IncrMemoEventTap::detach(self : IncrMemoEventTap) -> Unit {
  self.active.val = false
}

///|
/// Drain captured events in arrival order.
pub fn IncrMemoEventTap::drain_events(
  self : IncrMemoEventTap,
) -> Array[IncrMemoEventRecord] {
  let drained = copy_events(self.events)
  self.events = []
  drained
}

///|
/// Capture the current known dependency graph plus buffered event history.
pub fn IncrMemoEventTap::snapshot(self : IncrMemoEventTap) -> IncrSnapshot {
  let ids = snapshot_ids(self)
  let nodes : Array[IncrSnapshotNode] = []
  let edges : Array[IncrSnapshotEdge] = []
  for id in ids {
    match self.rt.cell_info(id) {
      Some(info) => {
        nodes.push({
          id,
          label: info.label,
          changed_at: info.changed_at,
          verified_at: info.verified_at,
        })
        for dep in info.dependencies {
          edges.push({ from: dep, to: id })
        }
      }
      None => ()
    }
  }
  { nodes, edges, events: copy_events(self.events) }
}

///|
/// Convert an `incr` runtime snapshot to the renderer-neutral visual graph.
pub fn IncrSnapshot::to_visual_graph(self : IncrSnapshot) -> VisualGraph {
  let graph = VisualGraph(id="incr")
  for node in self.nodes {
    graph.add_node(
      VisualNode(
        visual_cell_id(node.id),
        label=snapshot_node_label(node),
        detail=snapshot_node_detail(node),
        status=status_for_cell(self.events, node.id),
      ),
    )
  }
  for edge in self.edges {
    graph.add_edge(
      VisualEdge(visual_cell_id(edge.from), visual_cell_id(edge.to)),
    )
  }
  graph
}
