///|
/// `format_elapsed_ns` selects an ASCII unit (ns/us/ms) by magnitude so the
/// unit switch itself reads as a hotspot cue. Wall-clock timing is
/// non-deterministic, so the formatting logic is pinned here with fixed
/// inputs rather than through a live tap.
test "format_elapsed_ns_picks_unit_by_magnitude" {
  inspect(format_elapsed_ns(0L), content="0ns")
  inspect(format_elapsed_ns(500L), content="500ns")
  // 1000ns is the ns→us boundary; truncating division drops sub-us digits.
  inspect(format_elapsed_ns(1000L), content="1us")
  inspect(format_elapsed_ns(1500L), content="1us")
  inspect(format_elapsed_ns(999_999L), content="999us")
  // 1_000_000ns is the us→ms boundary.
  inspect(format_elapsed_ns(1_000_000L), content="1ms")
  inspect(format_elapsed_ns(2_500_000L), content="2ms")
}

///|
/// End-to-end wiring with a controlled `elapsed_ns`: the recomputed cell's
/// duration reaches its node detail, while a node with no event record shows
/// no timing. Constructed directly (not via a live tap) so the formatted value
/// is deterministic — wall-clock timing can't be asserted from a real run.
test "to_visual_graph surfaces latest elapsed_ns on the recomputed cell only" {
  let timed_cell : @incr.CellId = { id: 1, runtime_id: @incr.RuntimeId(0) }
  let untimed_cell : @incr.CellId = { id: 2, runtime_id: @incr.RuntimeId(0) }
  // Revision construction is closed since incr 0.14.0; build 3 and 4 by
  // stepping from the initial revision (0).
  let rev3 : @incr.Revision = @incr.Revision::initial().next().next().next()
  let rev4 : @incr.Revision = rev3.next()
  let timed_node : RecomputeSnapshotNode = {
    id: timed_cell,
    label: Some("sum"),
    changed_at: rev4,
    verified_at: rev4,
  }
  let untimed_node : RecomputeSnapshotNode = {
    id: untimed_cell,
    label: Some("input"),
    changed_at: rev3,
    verified_at: rev3,
  }
  let event : RecomputeRecord = {
    cell_id: timed_cell,
    phase: RecomputePhase::Completed,
    started_revision: rev3,
    elapsed_ns: Some(5000L),
    verified_at: Some(rev4),
    changed_at: Some(rev4),
    backdated: false,
  }
  let snapshot : RecomputeSnapshot = {
    nodes: [timed_node, untimed_node],
    edges: [],
    events: [event],
  }
  let dot = snapshot.to_visual_graph().to_dot()
  // Timed cell: detail carries the formatted duration (5000ns → "5us").
  inspect(dot.contains("verified 4, 5us"), content="true")
  // Untimed cell: bare detail, no appended ", <unit>" timing segment.
  inspect(dot.contains("changed 3, verified 3"), content="true")
  inspect(dot.contains("verified 3, "), content="false")
}
