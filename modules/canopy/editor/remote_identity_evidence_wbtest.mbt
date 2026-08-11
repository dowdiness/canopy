// White-box characterization oracle for remote identity evidence.
//
// Production remote admission taints a queued local structural hint with
// Opaque. The Preserve path below is comparison-only: it is an exact copy of
// the admission shell with only that taint call removed. No production
// behavior is changed by this file. The projection assertions exercise
// TestExpr's generic reconcile adapter; they do not execute Lambda directly.

///|
/// Test-only admission shell used to compare Preserve against production
/// `admit`. It intentionally mirrors `admit_with_policy` line-for-line except
/// for the omitted `taint_pending_transforms` call.
fn[T : Eq] SyncEditor::admit_preserving_identity_evidence(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
  limits : @sync.Limits?,
) -> @text.SyncReport raise {
  self.ensure_parser_healthy()
  let old_source = self.doc.text()
  self.undo.set_tracking(false)
  let report_result : Result[@text.SyncReport, @text.TextError] = Ok(
    match limits {
      None => self.doc.sync().apply(msg)
      Some(limits) => self.doc.sync().apply_with_limits(msg, limits)
    },
  ) catch {
    error => Err(error)
  }
  // Restore tracking before any shell/parser work, including when admission
  // raised. This is part of the production admission contract.
  self.undo.set_tracking(true)
  let new_source = self.doc.text()
  self.adjust_cursor()
  self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
  self.sync_parser_after_text_change(old_source, new_source, None)
  let report = match report_result {
    Ok(report) => report
    Err(error) => raise error
  }
  if report.pending_operations() == 0 {
    self.session.note_sync_applied()
  }
  report
}

///|
enum RemoteIdentityEvidenceKind {
  DuplicateOnly
  FirstPendingOnly
  SecondPending
  ApplicableNetZero
  ApplicableVisibleChange
}

///|
fn remote_identity_evidence_kind_name(
  kind : RemoteIdentityEvidenceKind,
) -> String {
  match kind {
    DuplicateOnly => "duplicate-only"
    FirstPendingOnly => "first-pending-only"
    SecondPending => "second-pending-queue-1-to-2"
    ApplicableNetZero => "applicable-insert-delete-net-zero"
    ApplicableVisibleChange => "applicable-visible-change"
  }
}

///|
fn production_opaque_count(kind : RemoteIdentityEvidenceKind) -> Int {
  if kind is SecondPending {
    2
  } else {
    1
  }
}

///|
struct RemoteIdentityEvidenceSide {
  name : String
  replica_id : String
  editor : SyncEditor[@probe.TestExpr]
  consumed_hint_batches : Ref[Array[Array[@core.IdentityTransform]]]
  trace_ref : Ref[Array[@core.ReconcileTraceEvent]]
  projection_transition_count : Ref[Int]
}

///|
fn new_remote_identity_evidence_side(
  name : String,
  replica_id : String,
) -> RemoteIdentityEvidenceSide raise {
  let (editor, consumed_hint_batches, trace_ref, projection_transition_count) = @probe.new_remote_identity_evidence_test_editor(
    replica_id,
  )
  {
    name,
    replica_id,
    editor,
    consumed_hint_batches,
    trace_ref,
    projection_transition_count,
  }
}

///|
struct RemoteIdentityEvidenceFixture {
  source : SyncEditor[@probe.TestExpr]
  baseline : @text.SyncMessage
  baseline_version : @text.Version
  production : RemoteIdentityEvidenceSide
  preserve : RemoteIdentityEvidenceSide
  opaque_old_leaf : @core.NodeId
  preserve_old_leaf : @core.NodeId
}

///|
fn initial_leaf_id(side : RemoteIdentityEvidenceSide) -> @core.NodeId raise {
  guard side.editor.get_proj_node() is Some(root) else {
    fail("baseline projection is missing")
  }
  guard root.children.get(0) is Some(leaf) else {
    fail("baseline projection has no leaf")
  }
  guard leaf.kind is @probe.TestExpr::Leaf(_) else {
    fail("baseline projection child is not a leaf")
  }
  leaf.id()
}

///|
fn reset_remote_identity_evidence_instrumentation(
  side : RemoteIdentityEvidenceSide,
) -> Unit {
  // The editor constructor's watched projection may have evaluated the empty
  // document before the shared baseline was admitted. Keep the characterization
  // counters focused on post-baseline admission and deferred local demand.
  side.consumed_hint_batches.val = []
  side.trace_ref.val = []
  side.projection_transition_count.val = 0
}

///|
/// Serialize the causal DAG plus its frontier. Version-vector equality alone
/// does not prove that the operation ancestry is equal, so the comparison also
/// records every operation's replica, sequence, and parent local versions.
fn causal_state_signature(snapshot : @history.CausalSnapshot) -> String {
  let entries = [
    for lv in 0..<snapshot.op_count() => {
      match snapshot.entry(lv) {
        Some(entry) =>
          lv.to_string() +
          ":" +
          entry.agent() +
          ":" +
          entry.seq().to_string() +
          "<-" +
          entry.parents().map(parent => parent.to_string()).join(",")
        None => lv.to_string() + ":missing"
      }
    }
  ]
  "ops=" +
  entries.join(";") +
  "|frontier=" +
  snapshot.frontier().map(lv => lv.to_string()).join(",")
}

///|
/// The two controls intentionally share one replica ID. Assert exact causal
/// operation exports and DAG/VV state before any case-specific remote message
/// is admitted; equal NodeIds alone are not sufficient evidence.
fn assert_pre_admission_causal_parity(
  left : RemoteIdentityEvidenceSide,
  right : RemoteIdentityEvidenceSide,
) -> Unit raise {
  assert_true(left.replica_id == right.replica_id)
  assert_true(left.editor.get_peer_id() == left.replica_id)
  assert_true(right.editor.get_peer_id() == right.replica_id)
  assert_true(left.editor.get_version() == right.editor.get_version())
  assert_true(
    causal_state_signature(left.editor.causal_snapshot()) ==
    causal_state_signature(right.editor.causal_snapshot()),
  )
  assert_true(
    left.editor.export_all().to_canonical_bytes() ==
    right.editor.export_all().to_canonical_bytes(),
  )
}

///|
/// Establish the common CRDT baseline, force exactly the initial projection,
/// then queue the same exact local Wrap hint on both sides without demanding a
/// projection afterward.
fn make_remote_identity_evidence_fixture(
  name : String,
) -> RemoteIdentityEvidenceFixture raise {
  let source = @probe.new_test_editor(name + "-source")
  source.set_text("x")
  let baseline = source.export_all()
  let baseline_version = source.get_version()
  let target_replica_id = name + "-target"
  let production = new_remote_identity_evidence_side(
    name + "-Invalidate",
    target_replica_id,
  )
  let preserve = new_remote_identity_evidence_side(
    name + "-Preserve",
    target_replica_id,
  )
  let opaque_baseline = production.editor.admit(baseline)
  let preserve_baseline = preserve.editor.admit_preserving_identity_evidence(
    baseline,
    None,
  )
  assert_true(opaque_baseline.applied_operations() == 1)
  assert_true(preserve_baseline.applied_operations() == 1)
  assert_true(production.editor.get_text() == "x")
  assert_true(preserve.editor.get_text() == "x")
  let opaque_old_leaf = initial_leaf_id(production)
  let preserve_old_leaf = initial_leaf_id(preserve)
  // The neutral projection allocator is per parser and both sides started from
  // the same baseline, so this is only a projection-fixture sanity check.
  // NodeId equality alone is not the causal evidence asserted below.
  assert_true(opaque_old_leaf == preserve_old_leaf)
  reset_remote_identity_evidence_instrumentation(production)
  reset_remote_identity_evidence_instrumentation(preserve)
  let wrap_edits : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 0, inserted: "f(" },
    { start: 1, delete_len: 0, inserted: ")" },
  ]
  production.editor.apply_span_edits(
    wrap_edits,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Wrap(inner=opaque_old_leaf),
  )
  preserve.editor.apply_span_edits(
    wrap_edits,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Wrap(inner=preserve_old_leaf),
  )
  assert_true(production.editor.get_text() == "f(x)")
  assert_true(preserve.editor.get_text() == "f(x)")
  assert_true(production.editor.pending_transforms.val.length() == 1)
  assert_true(preserve.editor.pending_transforms.val.length() == 1)
  // The local structural operation is also identical because both controls
  // use the same replica ID. This is the pre-admission causal baseline for
  // every comparison case.
  assert_pre_admission_causal_parity(production, preserve)
  {
    source,
    baseline,
    baseline_version,
    production,
    preserve,
    opaque_old_leaf,
    preserve_old_leaf,
  }
}

///|
/// Known EGW JSON is deliberately confined to missing-parent operations. All
/// applicable deltas in this oracle are made by a source editor and exported
/// with `export_since`.
fn known_missing_parent_message(sequence : Int) -> @text.SyncMessage raise {
  let parent = sequence - 1
  @text.SyncMessage::from_json_string(
    "{\"schema\":1,\"format\":\"event-graph-walker/text-sync\",\"operations\":[" +
    "{\"id\":{\"replica_id\":\"remote-pending\",\"sequence\":" +
    sequence.to_string() +
    "},\"parents\":[{\"replica_id\":\"remote-pending\",\"sequence\":" +
    parent.to_string() +
    "}],\"kind\":\"insert\",\"content\":\"p\",\"origin_left\":null,\"origin_right\":null}],\"heads\":[" +
    "{\"replica_id\":\"remote-pending\",\"sequence\":" +
    sequence.to_string() +
    "}]}",
  )
}

///|
fn applicable_delta_from_source(
  fixture : RemoteIdentityEvidenceFixture,
  kind : RemoteIdentityEvidenceKind,
) -> @text.SyncMessage raise {
  match kind {
    ApplicableNetZero => {
      fixture.source.move_cursor(fixture.source.get_text().length())
      fixture.source.insert("y")
      guard fixture.source.backspace() else {
        fail("source insert-delete did not delete its inserted character")
      }
      // The source is visibly back at the baseline before the two-op delta is
      // exported; only its causal version has advanced.
      assert_true(fixture.source.get_text() == "x")
      let delta = fixture.source.export_since(fixture.baseline_version)
      assert_true(delta.op_count() == 2)
      delta
    }
    ApplicableVisibleChange => {
      fixture.source.move_cursor(fixture.source.get_text().length())
      fixture.source.insert("y")
      let delta = fixture.source.export_since(fixture.baseline_version)
      assert_true(delta.op_count() == 1)
      delta
    }
    _ => fail("requested an applicable delta for a non-applicable case")
  }
}

///|
struct RemoteIdentityEvidenceAdmission {
  side : String
  operation : String
  report : String
  version_before : String
  version_after : String
  version_relation : String
  text_before : String
  text_after : String
  text_relation : String
  pending_before : Int
  pending_after : Int
  hint_queue_before : Int
  hint_queue_after : Int
  causal_before : String
  causal_after : String
  projection_transitions_before : Int
  projection_transitions_after : Int
}

///|
fn sync_report_signature(report : @text.SyncReport) -> String {
  "applied=" +
  report.applied_operations().to_string() +
  ",duplicate=" +
  report.duplicate_operations().to_string() +
  ",pending=" +
  report.pending_operations().to_string()
}

///|
fn capture_admission(
  side : RemoteIdentityEvidenceSide,
  operation : String,
  preserve : Bool,
  message : @text.SyncMessage,
) -> RemoteIdentityEvidenceAdmission raise {
  let before_version = side.editor.get_version()
  let before_text = side.editor.get_text()
  let before_pending = side.editor.doc.sync().pending_sync_count()
  let before_hints = side.editor.pending_transforms.val.length()
  let before_causal = causal_state_signature(side.editor.causal_snapshot())
  let before_transitions = side.projection_transition_count.val
  assert_true(before_transitions == 0)
  let report = if preserve {
    side.editor.admit_preserving_identity_evidence(message, None)
  } else {
    side.editor.admit(message)
  }
  let after_version = side.editor.get_version()
  let after_text = side.editor.get_text()
  let after_pending = side.editor.doc.sync().pending_sync_count()
  let after_hints = side.editor.pending_transforms.val.length()
  let after_causal = causal_state_signature(side.editor.causal_snapshot())
  let after_transitions = side.projection_transition_count.val
  // Admission only changes causal/text state and hint storage. Projection
  // reconciliation remains deferred until a later local demand.
  assert_true(after_transitions == 0)
  {
    side: side.name,
    operation,
    report: sync_report_signature(report),
    version_before: before_version.to_json_string(),
    version_after: after_version.to_json_string(),
    version_relation: if before_version == after_version {
      "same"
    } else {
      "changed"
    },
    text_before: before_text,
    text_after: after_text,
    text_relation: if before_text == after_text {
      "same"
    } else {
      "changed"
    },
    pending_before: before_pending,
    pending_after: after_pending,
    hint_queue_before: before_hints,
    hint_queue_after: after_hints,
    causal_before: before_causal,
    causal_after: after_causal,
    projection_transitions_before: before_transitions,
    projection_transitions_after: after_transitions,
  }
}

///|
fn print_admission(observation : RemoteIdentityEvidenceAdmission) -> Unit {
  println(
    "REMOTE_IDENTITY_EVIDENCE admission side=" +
    observation.side +
    " operation=" +
    observation.operation +
    " report=" +
    observation.report +
    " pending_queue=" +
    observation.pending_before.to_string() +
    "->" +
    observation.pending_after.to_string() +
    " version=" +
    observation.version_relation +
    " text=" +
    observation.text_relation +
    " hint_queue=" +
    observation.hint_queue_before.to_string() +
    "->" +
    observation.hint_queue_after.to_string() +
    " admission_projection_transitions=" +
    observation.projection_transitions_before.to_string() +
    "->" +
    observation.projection_transitions_after.to_string(),
  )
  println("  version_before=" + observation.version_before)
  println("  version_after=" + observation.version_after)
  println("  text_before=" + observation.text_before)
  println("  text_after=" + observation.text_after)
  println("  causal_before=" + observation.causal_before)
  println("  causal_after=" + observation.causal_after)
}

///|
fn identity_hint_signature(hint : @core.IdentityTransform) -> String {
  match hint {
    @core.IdentityTransform::Wrap(inner=id) => "Wrap(" + id.to_string() + ")"
    @core.IdentityTransform::Unwrap(wrapper=id, keep=kept) =>
      "Unwrap(" + id.to_string() + "," + kept.to_string() + ")"
    @core.IdentityTransform::Move(subtree=id) => "Move(" + id.to_string() + ")"
    @core.IdentityTransform::Replace(old=id) =>
      "Replace(" + id.to_string() + ")"
    @core.IdentityTransform::RenameLeaf(node=id) =>
      "RenameLeaf(" + id.to_string() + ")"
    @core.IdentityTransform::InsertSubtree(parent=id, index~) =>
      "InsertSubtree(" + id.to_string() + "," + index.to_string() + ")"
    @core.IdentityTransform::DeleteSubtree(node=id) =>
      "DeleteSubtree(" + id.to_string() + ")"
    @core.IdentityTransform::Opaque => "Opaque"
  }
}

///|
fn identity_hints_signature(hints : Array[@core.IdentityTransform]) -> String {
  hints.map(identity_hint_signature).join(",")
}

///|
fn identity_hint_batches_signature(
  batches : Array[Array[@core.IdentityTransform]],
) -> String {
  batches.map(batch => "[" + identity_hints_signature(batch) + "]").join(";")
}

///|
fn identity_hint_entry_count(
  batches : Array[Array[@core.IdentityTransform]],
) -> Int {
  batches.fold(init=0, (total, batch) => total + batch.length())
}

///|
fn reconcile_trace_event_signature(event : @core.ReconcileTraceEvent) -> String {
  match event {
    @core.ReconcileTraceEvent::Matched(parent, old_index, new_index, node, kind) =>
      "Matched(" +
      parent.to_string() +
      "," +
      old_index.to_string() +
      "," +
      new_index.to_string() +
      "," +
      node.to_string() +
      "," +
      kind +
      ")"
    @core.ReconcileTraceEvent::Inserted(parent, index, node, kind) =>
      "Inserted(" +
      parent.to_string() +
      "," +
      index.to_string() +
      "," +
      node.to_string() +
      "," +
      kind +
      ")"
    @core.ReconcileTraceEvent::Deleted(parent, index, node, kind) =>
      "Deleted(" +
      parent.to_string() +
      "," +
      index.to_string() +
      "," +
      node.to_string() +
      "," +
      kind +
      ")"
    @core.ReconcileTraceEvent::Wrapped(inner, wrapper, kind) =>
      "Wrapped(" +
      inner.to_string() +
      "," +
      wrapper.to_string() +
      "," +
      kind +
      ")"
    @core.ReconcileTraceEvent::Unwrapped(wrapper, kept, kind) =>
      "Unwrapped(" +
      wrapper.to_string() +
      "," +
      kept.to_string() +
      "," +
      kind +
      ")"
    @core.ReconcileTraceEvent::Renamed(node, kind) =>
      "Renamed(" + node.to_string() + "," + kind + ")"
    @core.ReconcileTraceEvent::Freshened(parent, index, node, kind) =>
      "Freshened(" +
      parent.to_string() +
      "," +
      index.to_string() +
      "," +
      node.to_string() +
      "," +
      kind +
      ")"
  }
}

///|
fn reconcile_trace_signature(
  events : Array[@core.ReconcileTraceEvent],
) -> String {
  events.map(reconcile_trace_event_signature).join(";")
}

///|
fn preorder_node_ids(root : @core.ProjNode[@probe.TestExpr]?) -> String {
  match root {
    None => "None"
    Some(root) => {
      let ids : Array[String] = []
      root.walk_preorder(node => ids.push(node.id().to_string()))
      ids.join("->")
    }
  }
}

///|
fn root_node_id(root : @core.ProjNode[@probe.TestExpr]?) -> String {
  match root {
    None => "None"
    Some(root) => root.id().to_string()
  }
}

///|
fn sorted_registry_entries(
  registry : Map[@core.NodeId, @core.ProjNode[@probe.TestExpr]],
) -> Array[(@core.NodeId, @core.ProjNode[@probe.TestExpr])] {
  let entries = registry.to_array()
  entries.sort_by((left, right) => left.0.compare(right.0))
  entries
}

///|
fn registry_signature(
  registry : Map[@core.NodeId, @core.ProjNode[@probe.TestExpr]],
) -> String {
  sorted_registry_entries(registry)
  .map(pair => {
    let (id, node) = pair
    id.to_string() +
    ":" +
    @loom_core.Renderable::kind_tag(node.kind) +
    "[" +
    node.start.to_string() +
    ".." +
    node.end.to_string() +
    "]"
  })
  .join(";")
}

///|
fn source_map_signature(
  registry : Map[@core.NodeId, @core.ProjNode[@probe.TestExpr]],
  source_map : @core.SourceMap,
) -> String {
  sorted_registry_entries(registry)
  .map(pair => {
    let id = pair.0
    let range = match source_map.get_range(id) {
      Some(range) => range.start.to_string() + ".." + range.end.to_string()
      None => "missing"
    }
    id.to_string() + "=" + range
  })
  .join(";")
}

///|
struct RemoteIdentityEvidenceProjection {
  side : String
  version : String
  text : String
  pending_queue : Int
  hint_queue : Int
  causal_state : String
  root : String
  preorder : String
  registry : String
  source_map : String
  trace : String
  hint_batches : String
  hint_invocations : Int
  hint_entries : Int
  projection_transitions : Int
}

///|
fn capture_projection(
  side : RemoteIdentityEvidenceSide,
) -> RemoteIdentityEvidenceProjection raise {
  let root = side.editor.get_proj_node()
  let registry = side.editor.get_registry()
  let source_map = side.editor.get_source_map()
  let batches = side.consumed_hint_batches.val
  {
    side: side.name,
    version: side.editor.get_version().to_json_string(),
    text: side.editor.get_text(),
    pending_queue: side.editor.doc.sync().pending_sync_count(),
    hint_queue: side.editor.pending_transforms.val.length(),
    causal_state: causal_state_signature(side.editor.causal_snapshot()),
    root: root_node_id(root),
    preorder: preorder_node_ids(root),
    registry: registry_signature(registry),
    source_map: source_map_signature(registry, source_map),
    trace: reconcile_trace_signature(side.trace_ref.val),
    hint_batches: identity_hint_batches_signature(batches),
    hint_invocations: batches.length(),
    hint_entries: identity_hint_entry_count(batches),
    projection_transitions: side.projection_transition_count.val,
  }
}

///|
fn print_projection(observation : RemoteIdentityEvidenceProjection) -> Unit {
  println(
    "REMOTE_IDENTITY_EVIDENCE projection side=" +
    observation.side +
    " version=" +
    observation.version +
    " text=" +
    observation.text +
    " pending_queue=" +
    observation.pending_queue.to_string() +
    " hint_queue=" +
    observation.hint_queue.to_string() +
    " hint_invocations=" +
    observation.hint_invocations.to_string() +
    " hint_entries=" +
    observation.hint_entries.to_string() +
    " deferred_local_projection_transitions=" +
    observation.projection_transitions.to_string(),
  )
  println("  causal_state=" + observation.causal_state)
  println("  root=" + observation.root)
  println("  preorder=" + observation.preorder)
  println("  registry=" + observation.registry)
  println("  source_map=" + observation.source_map)
  println("  reconcile_trace=" + observation.trace)
  println("  consumed_hint_batches=" + observation.hint_batches)
}

///|
fn projection_outputs_equal(
  left : RemoteIdentityEvidenceProjection,
  right : RemoteIdentityEvidenceProjection,
) -> Bool {
  left.root == right.root &&
  left.preorder == right.preorder &&
  left.registry == right.registry &&
  left.source_map == right.source_map &&
  left.trace == right.trace
}

///|
fn admission_results_equal(
  left : RemoteIdentityEvidenceAdmission,
  right : RemoteIdentityEvidenceAdmission,
) -> Bool {
  // Compare only the exact admission result: report, version, visible text,
  // and remote pending-operation queue. Hint telemetry is intentionally not
  // part of this parity check.
  left.report == right.report &&
  left.version_before == right.version_before &&
  left.version_after == right.version_after &&
  left.text_before == right.text_before &&
  left.text_after == right.text_after &&
  left.pending_before == right.pending_before &&
  left.pending_after == right.pending_after
}

///|
/// Compare causal state only. The controls are expected to differ in hint
/// telemetry and projection identity output, so neither is admitted into this
/// helper's parity decision.
fn causal_state_equal(
  left : RemoteIdentityEvidenceAdmission,
  right : RemoteIdentityEvidenceAdmission,
  left_projection : RemoteIdentityEvidenceProjection,
  right_projection : RemoteIdentityEvidenceProjection,
) -> Bool {
  left.version_before == right.version_before &&
  left.version_after == right.version_after &&
  left.causal_before == right.causal_before &&
  left.causal_after == right.causal_after &&
  left_projection.version == right_projection.version &&
  left_projection.causal_state == right_projection.causal_state
}

///|
fn has_opaque_hint(side : RemoteIdentityEvidenceSide) -> Bool {
  side.consumed_hint_batches.val.any(batch => {
    batch.any(hint => hint is @core.IdentityTransform::Opaque)
  })
}

///|
fn has_wrap_hint(
  side : RemoteIdentityEvidenceSide,
  old_leaf : @core.NodeId,
) -> Bool {
  side.consumed_hint_batches.val.any(batch => {
    batch.any(hint => {
      hint is @core.IdentityTransform::Wrap(inner=id) && id == old_leaf
    })
  })
}

///|
fn wrapped_inner_id(
  root : @core.ProjNode[@probe.TestExpr]?,
) -> @core.NodeId raise {
  guard root is Some(root) else { fail("projection root is missing") }
  guard root.children.get(0) is Some(wrapper) else {
    fail("wrapped projection has no wrapper")
  }
  guard wrapper.children.get(0) is Some(inner) else {
    fail("wrapped projection has no inner leaf")
  }
  inner.id()
}

///|
fn has_wrapped_trace(
  side : RemoteIdentityEvidenceSide,
  old_leaf : @core.NodeId,
) -> Bool {
  side.trace_ref.val.any(event => {
    event is @core.ReconcileTraceEvent::Wrapped(id, _, _) && id == old_leaf
  })
}

///|
/// Demand the deferred local projection once, then prove the identity-hint
/// consumer drained the queue. This is deliberately not reported as a remote
/// projection transition: admission stayed at zero and this local demand is
/// what performs the one reconcile.
fn demand_deferred_local_projection(
  side : RemoteIdentityEvidenceSide,
) -> Unit raise {
  let before = side.projection_transition_count.val
  assert_true(before == 0)
  side.editor.mark_dirty()
  let _ = side.editor.get_proj_node()
  assert_true(side.projection_transition_count.val == before + 1)
  assert_true(side.editor.pending_transforms.val.is_empty())
}

///|
fn assert_exact_hint_batch(
  side : RemoteIdentityEvidenceSide,
  old_leaf : @core.NodeId,
  opaque_count : Int,
  projection : RemoteIdentityEvidenceProjection,
) -> Unit raise {
  let expected : Array[@core.IdentityTransform] = [
    @core.IdentityTransform::Wrap(inner=old_leaf),
  ]
  for _ in 0..<opaque_count {
    expected.push(@core.IdentityTransform::Opaque)
  }
  assert_true(projection.hint_invocations == 1)
  assert_true(projection.hint_entries == 1 + opaque_count)
  assert_true(
    projection.hint_batches == "[" + identity_hints_signature(expected) + "]",
  )
  assert_true(side.editor.pending_transforms.val.is_empty())
}

///|
fn assert_production_invalidated(
  side : RemoteIdentityEvidenceSide,
  old_leaf : @core.NodeId,
  opaque_count : Int,
  projection : RemoteIdentityEvidenceProjection,
) -> Unit raise {
  assert_true(has_opaque_hint(side))
  assert_exact_hint_batch(side, old_leaf, opaque_count, projection)
  assert_true(projection.projection_transitions == 1)
  // The queued Wrap remains observable beside Opaque; the production Invalidate
  // policy invalidates the whole batch rather than deleting the earlier hint.
  assert_true(has_wrap_hint(side, old_leaf))
  assert_true(!has_wrapped_trace(side, old_leaf))
  assert_true(projection.root != "None")
  assert_true(wrapped_inner_id(side.editor.get_proj_node()) != old_leaf)
}

///|
fn assert_preserved_evidence(
  side : RemoteIdentityEvidenceSide,
  old_leaf : @core.NodeId,
  projection : RemoteIdentityEvidenceProjection,
) -> Unit raise {
  assert_true(!has_opaque_hint(side))
  assert_true(has_wrap_hint(side, old_leaf))
  assert_exact_hint_batch(side, old_leaf, 0, projection)
  assert_true(projection.projection_transitions == 1)
  assert_true(wrapped_inner_id(side.editor.get_proj_node()) == old_leaf)
  assert_true(has_wrapped_trace(side, old_leaf))
}

///|
fn print_comparison(
  kind : RemoteIdentityEvidenceKind,
  production : RemoteIdentityEvidenceProjection,
  preserve : RemoteIdentityEvidenceProjection,
  opaque_admission : RemoteIdentityEvidenceAdmission,
  preserve_admission : RemoteIdentityEvidenceAdmission,
) -> Unit {
  let projections_differ = !projection_outputs_equal(production, preserve)
  let causal_equal = causal_state_equal(
    opaque_admission, preserve_admission, production, preserve,
  )
  let results_equal = admission_results_equal(
    opaque_admission, preserve_admission,
  )
  println(
    "REMOTE_IDENTITY_EVIDENCE comparison case=" +
    remote_identity_evidence_kind_name(kind) +
    " causal_state_equal=" +
    causal_equal.to_string() +
    " admission_results_equal=" +
    results_equal.to_string() +
    " projection_outputs_differ=" +
    projections_differ.to_string(),
  )
}

///|
fn run_remote_identity_evidence_case(
  kind : RemoteIdentityEvidenceKind,
) -> Unit raise {
  let fixture = make_remote_identity_evidence_fixture(
    "remote-identity-" + remote_identity_evidence_kind_name(kind),
  )
  let (opaque_admission, preserve_admission) = match kind {
    DuplicateOnly => {
      let production = capture_admission(
        fixture.production,
        "duplicate-only",
        false,
        fixture.baseline,
      )
      let preserve = capture_admission(
        fixture.preserve,
        "duplicate-only",
        true,
        fixture.baseline,
      )
      assert_true(production.report == "applied=0,duplicate=1,pending=0")
      assert_true(preserve.report == "applied=0,duplicate=1,pending=0")
      assert_true(production.pending_after == 0)
      assert_true(preserve.pending_after == 0)
      assert_true(production.version_relation == "same")
      assert_true(preserve.version_relation == "same")
      assert_true(production.text_relation == "same")
      assert_true(preserve.text_relation == "same")
      (production, preserve)
    }
    FirstPendingOnly => {
      let message = known_missing_parent_message(1)
      let production = capture_admission(
        fixture.production,
        "first-pending-only",
        false,
        message,
      )
      let preserve = capture_admission(
        fixture.preserve,
        "first-pending-only",
        true,
        message,
      )
      assert_true(production.report == "applied=0,duplicate=0,pending=1")
      assert_true(preserve.report == "applied=0,duplicate=0,pending=1")
      assert_true(production.pending_before == 0)
      assert_true(production.pending_after == 1)
      assert_true(preserve.pending_before == 0)
      assert_true(preserve.pending_after == 1)
      assert_true(production.version_relation == "same")
      assert_true(preserve.version_relation == "same")
      assert_true(production.text_relation == "same")
      assert_true(preserve.text_relation == "same")
      (production, preserve)
    }
    SecondPending => {
      let first_message = known_missing_parent_message(1)
      let first_opaque = capture_admission(
        fixture.production,
        "first-pending-only",
        false,
        first_message,
      )
      let first_preserve = capture_admission(
        fixture.preserve,
        "first-pending-only",
        true,
        first_message,
      )
      assert_true(first_opaque.report == "applied=0,duplicate=0,pending=1")
      assert_true(first_preserve.report == "applied=0,duplicate=0,pending=1")
      // The first pending admission is itself non-projecting: both sides
      // remain text/version-identical and the remote pending queue goes 0→1.
      assert_true(first_opaque.version_before == first_opaque.version_after)
      assert_true(first_preserve.version_before == first_preserve.version_after)
      assert_true(first_opaque.text_before == first_opaque.text_after)
      assert_true(first_preserve.text_before == first_preserve.text_after)
      assert_true(first_opaque.pending_before == 0)
      assert_true(first_opaque.pending_after == 1)
      assert_true(first_preserve.pending_before == 0)
      assert_true(first_preserve.pending_after == 1)
      assert_true(admission_results_equal(first_opaque, first_preserve))
      let second_message = known_missing_parent_message(2)
      let production = capture_admission(
        fixture.production,
        "second-pending",
        false,
        second_message,
      )
      let preserve = capture_admission(
        fixture.preserve,
        "second-pending",
        true,
        second_message,
      )
      assert_true(production.report == "applied=0,duplicate=0,pending=2")
      assert_true(preserve.report == "applied=0,duplicate=0,pending=2")
      assert_true(production.pending_before == 1)
      assert_true(production.pending_after == 2)
      assert_true(preserve.pending_before == 1)
      assert_true(preserve.pending_after == 2)
      assert_true(production.version_relation == "same")
      assert_true(preserve.version_relation == "same")
      assert_true(production.text_relation == "same")
      assert_true(preserve.text_relation == "same")
      (production, preserve)
    }
    ApplicableNetZero | ApplicableVisibleChange => {
      let delta = applicable_delta_from_source(fixture, kind)
      let production = capture_admission(
        fixture.production,
        "applicable",
        false,
        delta,
      )
      let preserve = capture_admission(
        fixture.preserve,
        "applicable",
        true,
        delta,
      )
      if kind is ApplicableNetZero {
        assert_true(production.report == "applied=2,duplicate=0,pending=0")
        assert_true(preserve.report == "applied=2,duplicate=0,pending=0")
        assert_true(production.version_relation == "changed")
        assert_true(preserve.version_relation == "changed")
        assert_true(production.text_relation == "same")
        assert_true(preserve.text_relation == "same")
        assert_true(production.text_before == "f(x)")
        assert_true(preserve.text_before == "f(x)")
        assert_true(production.text_after == "f(x)")
        assert_true(preserve.text_after == "f(x)")
        assert_true(production.version_before != production.version_after)
        assert_true(preserve.version_before != preserve.version_after)
        assert_true(production.projection_transitions_before == 0)
        assert_true(production.projection_transitions_after == 0)
        assert_true(preserve.projection_transitions_before == 0)
        assert_true(preserve.projection_transitions_after == 0)
      } else {
        assert_true(production.report == "applied=1,duplicate=0,pending=0")
        assert_true(preserve.report == "applied=1,duplicate=0,pending=0")
        assert_true(production.version_relation == "changed")
        assert_true(preserve.version_relation == "changed")
        assert_true(production.text_relation == "changed")
        assert_true(preserve.text_relation == "changed")
      }
      (production, preserve)
    }
  }
  // Every admission above asserted zero projection transitions. Demand the
  // local projection once afterward; this is the sole deferred reconcile.
  assert_true(admission_results_equal(opaque_admission, preserve_admission))
  demand_deferred_local_projection(fixture.production)
  demand_deferred_local_projection(fixture.preserve)
  let opaque_projection = capture_projection(fixture.production)
  let preserve_projection = capture_projection(fixture.preserve)
  // Exact text/version/pending parity is independent of intentionally
  // different hint and projection telemetry.
  assert_true(opaque_projection.version == preserve_projection.version)
  assert_true(opaque_projection.text == preserve_projection.text)
  assert_true(
    opaque_projection.pending_queue == preserve_projection.pending_queue,
  )
  assert_true(
    causal_state_equal(
      opaque_admission, preserve_admission, opaque_projection, preserve_projection,
    ),
  )
  print_admission(opaque_admission)
  print_admission(preserve_admission)
  print_projection(opaque_projection)
  print_projection(preserve_projection)
  print_comparison(
    kind, opaque_projection, preserve_projection, opaque_admission, preserve_admission,
  )
  assert_production_invalidated(
    fixture.production,
    fixture.opaque_old_leaf,
    production_opaque_count(kind),
    opaque_projection,
  )
  match kind {
    DuplicateOnly | FirstPendingOnly | SecondPending | ApplicableNetZero =>
      assert_preserved_evidence(
        fixture.preserve,
        fixture.preserve_old_leaf,
        preserve_projection,
      )
    ApplicableVisibleChange =>
      // Preserve is comparison-only for a visible remote change, not
      // candidate target semantics. Production Invalidate remains expected;
      // this control explicitly records the alternate Wrap evidence.
      assert_preserved_evidence(
        fixture.preserve,
        fixture.preserve_old_leaf,
        preserve_projection,
      )
  }
  // The controls have identical causal/result state, but their projection
  // outputs intentionally differ. This applies to the visible comparison too.
  assert_true(!projection_outputs_equal(opaque_projection, preserve_projection))
}

///|
test "remote identity evidence: duplicate-only" {
  run_remote_identity_evidence_case(DuplicateOnly)
}

///|
test "remote identity evidence: first pending-only" {
  run_remote_identity_evidence_case(FirstPendingOnly)
}

///|
test "remote identity evidence: second pending grows queue 1 to 2" {
  run_remote_identity_evidence_case(SecondPending)
}

///|
test "remote identity evidence: applicable insert-delete net-zero" {
  run_remote_identity_evidence_case(ApplicableNetZero)
}

///|
test "remote identity evidence: applicable visible change" {
  run_remote_identity_evidence_case(ApplicableVisibleChange)
}
