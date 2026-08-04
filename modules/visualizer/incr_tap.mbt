///|
/// Phase of a public `incr` memo recompute event.
pub(all) enum RecomputePhase {
  Entering
  Completed
  Aborted
}

///|
/// Compact memo-event record captured by `RecomputeTap`.
pub struct RecomputeRecord {
  cell_id : @incr.CellId
  phase : RecomputePhase
  started_revision : @incr.Revision
  elapsed_ns : Int64?
  verified_at : @incr.Revision?
  changed_at : @incr.Revision?
  backdated : Bool
}

///|
/// Snapshot node enriched from `Runtime::cell_info`.
pub struct RecomputeSnapshotNode {
  id : @incr.CellId
  label : String?
  changed_at : @incr.Revision
  verified_at : @incr.Revision
}

///|
/// Snapshot edge from dependency to dependent cell.
pub struct RecomputeSnapshotEdge {
  from : @incr.CellId
  to : @incr.CellId
}

///|
/// Point-in-time graph and event snapshot for an `incr` runtime.
pub struct RecomputeSnapshot {
  nodes : Array[RecomputeSnapshotNode]
  edges : Array[RecomputeSnapshotEdge]
  events : Array[RecomputeRecord]
}

///|
/// Driver-owned tap that records public `incr` memo events for visualization.
pub struct RecomputeTap {
  priv rt : @incr.Runtime
  priv active : Ref[Bool]
  // Keep-last-per-cell status buffer: bounded by the number of distinct cells
  // that fired events since the last drain, not by the total event count.
  // Status coloring only needs each cell's most recent event, so retaining
  // the latest per cell loses nothing while bounding memory.
  priv events : @hashmap.HashMap[@incr.CellId, RecomputeRecord]
  priv cells : Array[@incr.CellId]
  // Mirrors `cells` for O(1)-expected dedup as events arrive. It is not
  // drained, because `cells` is the persistent frontier for graph snapshots.
  priv seen_cells : Set[@incr.CellId]
}

///|
fn remember_cell(
  ids : Array[@incr.CellId],
  seen : Set[@incr.CellId],
  id : @incr.CellId,
) -> Unit {
  if seen.add_and_check(id) {
    ids.push(id)
  }
}

///|
fn event_from_memo_event(evt : @incr.DerivedEvent) -> RecomputeRecord {
  match evt {
    EnteringCompute(e) =>
      {
        cell_id: e.cell_id,
        phase: RecomputePhase::Entering,
        started_revision: e.started_revision,
        elapsed_ns: None,
        verified_at: None,
        changed_at: None,
        backdated: false,
      }
    Completed(e) =>
      {
        cell_id: e.cell_id,
        phase: RecomputePhase::Completed,
        started_revision: e.started_revision,
        elapsed_ns: Some(e.elapsed_ns),
        verified_at: Some(e.verified_at),
        changed_at: Some(e.changed_at),
        backdated: e.backdated,
      }
    Aborted(e) =>
      {
        cell_id: e.cell_id,
        phase: RecomputePhase::Aborted,
        started_revision: e.started_revision,
        elapsed_ns: Some(e.elapsed_ns),
        verified_at: None,
        changed_at: None,
        backdated: false,
      }
  }
}

///|
fn RecomputeTap::record(self : RecomputeTap, evt : @incr.DerivedEvent) -> Unit {
  guard self.active.val else { return }
  let record = event_from_memo_event(evt)
  remember_cell(self.cells, self.seen_cells, record.cell_id)
  self.events.set(record.cell_id, record)
}

///|
fn RecomputeTap::snapshot_ids(self : RecomputeTap) -> Array[@incr.CellId] {
  let ids : Array[@incr.CellId] = []
  let seen : Set[@incr.CellId] = Set([])
  for id in self.cells {
    remember_cell(ids, seen, id)
  }
  // Queue-style traversal is intentional: the frontier grows as dependencies
  // and subscribers are discovered from `Runtime::cell_info`.
  let mut i = 0
  while i < ids.length() {
    let id = ids[i]
    match self.rt.cell_info(id) {
      Some(info) => {
        for dep in info.dependencies {
          remember_cell(ids, seen, dep)
        }
        for sub in info.subscribers {
          remember_cell(ids, seen, sub)
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
fn snapshot_node_label(node : RecomputeSnapshotNode) -> String {
  match node.label {
    Some(label) => label
    None => "cell " + node.id.id.to_string()
  }
}

///|
/// Render a captured recompute duration with an ASCII unit chosen by magnitude
/// (ns / us / ms). Truncating division drops sub-unit digits; the unit switch
/// is the point — an `ms` node stands out against `us` neighbors as a hotspot.
fn format_elapsed_ns(ns : Int64) -> String {
  if ns < 1000L {
    ns.to_string() + "ns"
  } else if ns < 1_000_000L {
    (ns / 1000L).to_string() + "us"
  } else {
    (ns / 1_000_000L).to_string() + "ms"
  }
}

///|
fn snapshot_node_detail(
  node : RecomputeSnapshotNode,
  elapsed_ns : Int64?,
) -> String {
  let base = "changed " +
    node.changed_at.value.to_string() +
    ", verified " +
    node.verified_at.value.to_string()
  // Only recomputed cells carry a timing; pure dependency nodes that never
  // fired an event omit it rather than show a misleading zero.
  match elapsed_ns {
    Some(ns) => base + ", " + format_elapsed_ns(ns)
    None => base
  }
}

///|
fn record_status(record : RecomputeRecord?) -> VisualNodeStatus {
  match record {
    Some(event) =>
      match event.phase {
        RecomputePhase::Entering => Active
        RecomputePhase::Completed =>
          if event.backdated {
            Neutral
          } else {
            Changed
          }
        RecomputePhase::Aborted => Failed
      }
    None => Neutral
  }
}

///|
/// Attach an event tap to `rt`.
///
/// `incr` allows one memo-event listener per runtime, so attaching replaces
/// any previous listener owned by the same runtime.
pub fn RecomputeTap::attach(rt : @incr.Runtime) -> RecomputeTap raise Failure {
  let tap = {
    rt,
    active: Ref(true),
    events: @hashmap.HashMap([]),
    cells: [],
    seen_cells: Set([]),
  }
  rt.on_derived_event(evt => tap.record(evt))
  tap
}

///|
/// Stop this tap from recording future events.
///
/// `incr` exposes replacement and clearing for the runtime listener, but not
/// listener identity. Deactivating this tap's closure keeps stale handles from
/// clearing a newer tap that replaced them.
pub fn RecomputeTap::detach(self : RecomputeTap) -> Unit {
  self.active.val = false
}

///|
/// Drain the retained events — the most recent record per cell since the last
/// drain — and clear the buffer. Order is unspecified (keyed by cell, not
/// arrival); callers that only need per-cell status are unaffected.
pub fn RecomputeTap::drain_events(
  self : RecomputeTap,
) -> Array[RecomputeRecord] {
  let drained = self.events.values().to_array()
  self.events.clear()
  drained
}

///|
/// Capture the current known dependency graph plus buffered event history.
pub fn RecomputeTap::snapshot(self : RecomputeTap) -> RecomputeSnapshot {
  let ids = self.snapshot_ids()
  let nodes : Array[RecomputeSnapshotNode] = []
  let edges : Array[RecomputeSnapshotEdge] = []
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
  { nodes, edges, events: self.events.values().to_array() }
}

///|
fn RecomputeSnapshot::events_by_cell(
  self : RecomputeSnapshot,
) -> @hashmap.HashMap[@incr.CellId, RecomputeRecord] {
  let events_by_cell : @hashmap.HashMap[@incr.CellId, RecomputeRecord] = @hashmap.HashMap(
    [],
    capacity=self.events.length(),
  )
  for event in self.events {
    events_by_cell.set(event.cell_id, event)
  }
  events_by_cell
}

///|
/// Convert an `incr` runtime snapshot to the renderer-neutral visual graph.
pub fn RecomputeSnapshot::to_visual_graph(
  self : RecomputeSnapshot,
) -> VisualGraph {
  let graph = VisualGraph(id="incr")
  let events_by_cell = self.events_by_cell()
  for node in self.nodes {
    let record = events_by_cell.get(node.id)
    let elapsed_ns = match record {
      Some(event) => event.elapsed_ns
      None => None
    }
    graph.add_node(
      VisualNode(
        visual_cell_id(node.id),
        label=snapshot_node_label(node),
        detail=snapshot_node_detail(node, elapsed_ns),
        status=record_status(record),
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
