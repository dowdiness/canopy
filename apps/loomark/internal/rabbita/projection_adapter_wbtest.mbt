///|
fn projection_test_limits(
  count? : Int = 4,
  encoded_bytes? : Int = 512,
  source_effect_bytes? : Int = 256,
) -> ProjectionAdapterLimits {
  {
    max_advance_count: count,
    max_encoded_bytes: encoded_bytes,
    max_source_effect_bytes: source_effect_bytes,
  }
}

///|
fn projection_test_stamp(
  generation : Int,
  sequence : Int,
  source_revision : Int,
  version? : String = "v" + sequence.to_string(),
  block_intent? : Int = sequence,
) -> ProjectionStamp {
  {
    generation,
    sequence,
    source_revision,
    causal_version: version,
    block_intent,
  }
}

///|
fn projection_test_demand(
  block? : Bool = true,
  preview? : Bool = true,
  diagnostics? : Bool = true,
) -> ProjectionDemand {
  { block, preview, diagnostics }
}

///|
fn projection_test_seed(
  adapter : ProjectionAdapter,
  generation? : Int = 1,
  sequence? : Int = 1,
  source_revision? : Int = 1,
  source? : String = "# Seed\n",
  demand? : ProjectionDemand = projection_test_demand(),
) -> (ProjectionAdapter, Array[ProjectionEffect]) {
  adapter.reduce(
    Seed(
      projection_test_stamp(generation, sequence, source_revision),
      source,
      demand,
    ),
  )
}

///|
fn projection_effect_work_ids(effects : Array[ProjectionEffect]) -> Array[Int] {
  let ids : Array[Int] = []
  for effect in effects {
    match effect {
      StartGroupWork(work_id~, ..) => ids.push(work_id)
      _ => ()
    }
  }
  ids
}

///|
fn projection_terminal_effects(
  effects : Array[ProjectionEffect],
) -> Array[(Int, ProjectionTerminalOutcome)] {
  let outcomes : Array[(Int, ProjectionTerminalOutcome)] = []
  for effect in effects {
    match effect {
      RecordTerminalOutcome(work_id~, outcome~, ..) =>
        outcomes.push((work_id, outcome))
      _ => ()
    }
  }
  outcomes
}

///|
fn projection_has_capture(
  effects : Array[ProjectionEffect],
  generation : Int,
  sequence : Int,
) -> Bool {
  effects.any(effect => {
    match effect {
      CaptureLatestSeed(stamp~) =>
        stamp.generation == generation && stamp.sequence == sequence
      _ => false
    }
  })
}

///|
fn projection_test_block_artifact(label : String) -> ProjectionArtifact {
  BlockArtifact({
    source: label,
    blocks: [],
    node_keys: [],
    roles: [],
    resolver_evidence: [],
  })
}

///|
fn projection_test_materialized(
  adapter : ProjectionAdapter,
  work_id : Int,
  stamp : ProjectionStamp,
  group : ProjectionConsistencyGroup,
  label : String,
) -> (ProjectionAdapter, Array[ProjectionEffect]) {
  adapter.reduce(
    GroupMaterialized({
      work_id,
      stamp,
      group,
      artifact: projection_test_block_artifact(label),
    }),
  )
}

///|
test "projection adapter accepts a positive caller generation then requires exact cutover increment" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, initial) = projection_test_seed(adapter, generation=19)
  assert_false(initial.any(effect => effect is RejectCommand(_)))
  assert_eq(adapter.generation(), 19)
  let (same, skipped) = projection_test_seed(
    adapter,
    generation=21,
    sequence=2,
    source_revision=2,
  )
  assert_true(
    skipped.any(effect => effect is RejectCommand(InvalidInitialStamp)),
  )
  assert_eq(same.generation(), 19)
  let (cutover, accepted) = projection_test_seed(
    adapter,
    generation=20,
    sequence=2,
    source_revision=2,
  )
  assert_false(accepted.any(effect => effect is RejectCommand(_)))
  assert_eq(cutover.generation(), 20)
}

///|
test "projection adapter generation cutover invalidates all old paths without resetting lifetime sequence" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, seed_effects) = projection_test_seed(adapter)
  let old_ids = projection_effect_work_ids(seed_effects)
  assert_eq(old_ids, [1, 2, 3])
  let old_stamp = projection_test_stamp(1, 1, 1)
  let (adapter, materialized_effects) = projection_test_materialized(
    adapter,
    old_ids[0],
    old_stamp,
    Block,
    "old",
  )
  assert_true(materialized_effects.any(effect => effect is AdoptArtifact(..)))

  let (adapter, cutover_effects) = projection_test_seed(
    adapter,
    generation=2,
    sequence=2,
    source_revision=2,
    source="# Replacement\n",
  )
  assert_eq(adapter.generation(), 2)
  assert_eq(adapter.sequence(), 2)
  let terminal = projection_terminal_effects(cutover_effects)
  assert_true(
    terminal.any(pair => pair.0 == old_ids[0] && pair.1 is GenerationInvalidated),
  )
  assert_true(
    terminal.any(pair => pair.0 == old_ids[1] && pair.1 is GenerationInvalidated),
  )
  assert_true(
    terminal.any(pair => pair.0 == old_ids[2] && pair.1 is GenerationInvalidated),
  )

  let (adapter, delayed_effects) = projection_test_materialized(
    adapter,
    old_ids[0],
    old_stamp,
    Block,
    "delayed-old",
  )
  assert_true(delayed_effects.any(effect => effect is RejectCallback(_)))
  assert_true(projection_terminal_effects(delayed_effects).is_empty())
  assert_eq(adapter.generation(), 2)
}

///|
test "projection adapter lifetime sequence is exact-next non-wrapping across generation changes" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, _) = projection_test_seed(adapter)
  let (same, duplicate) = projection_test_seed(adapter)
  assert_true(duplicate.any(effect => effect is RejectCommand(_)))
  assert_eq(same.sequence(), 1)

  let (same, gap) = same.reduce(
    Advance(
      projection_test_stamp(1, 3, 2),
      ReplaceProjectionSource("# Gap\n"),
      projection_test_demand(),
    ),
  )
  assert_true(projection_has_capture(gap, 2, 2))
  let capture = same.pending_seed_stamp().unwrap()
  assert_eq(capture.sequence, 2)
  assert_eq(capture.generation, 2)

  let exhausted = {
    ..ProjectionAdapter::ProjectionAdapter(projection_test_limits()),
    last_sequence: 2147483647,
  }
  let (_, overflow) = projection_test_seed(exhausted)
  assert_true(overflow.any(effect => effect is RejectCommand(CounterExhausted)))
}

///|
test "source-equal causal advance preserves revision and restamps reused payload" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, seed_effects) = projection_test_seed(
    adapter,
    demand=projection_test_demand(preview=false, diagnostics=false),
  )
  let seed_work = projection_effect_work_ids(seed_effects)[0]
  let seed_stamp = projection_test_stamp(1, 1, 1)
  let (adapter, adopted) = projection_test_materialized(
    adapter,
    seed_work,
    seed_stamp,
    Block,
    "same-source",
  )
  assert_true(adopted.any(effect => effect is AdoptArtifact(..)))
  let (adapter, presented) = adapter.reduce(
    GroupsPresented(presentation_id=1, work_ids=[seed_work]),
  )
  assert_true(
    projection_terminal_effects(presented).any(pair => {
      pair.0 == seed_work && pair.1 is Presented(1)
    }),
  )
  let next_stamp = projection_test_stamp(
    1,
    2,
    1,
    version="causal-v2",
    block_intent=2,
  )
  let (adapter, queued) = adapter.reduce(
    Advance(
      next_stamp,
      ProjectionSourceUnchanged,
      projection_test_demand(preview=false, diagnostics=false),
    ),
  )
  assert_true(queued.any(effect => effect is QueueAdvance(_)))
  assert_eq(adapter.source_revision(), 1)
  let (adapter, dispatched) = adapter.reduce(DispatchNextAdvance)
  assert_true(
    dispatched.any(effect => {
      match effect {
        AdoptArtifact(stamp~, artifact=BlockArtifact(payload), ..) =>
          stamp == next_stamp && payload.source == "same-source"
        _ => false
      }
    }),
  )
  assert_false(dispatched.any(effect => effect is StartGroupWork(..)))
  assert_true(projection_terminal_effects(dispatched).is_empty())
  assert_eq(adapter.source_revision(), 1)

  let (same, stale_intent) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 3, 1, version="causal-v3", block_intent=1),
      ProjectionSourceUnchanged,
      projection_test_demand(preview=false, diagnostics=false),
    ),
  )
  assert_true(
    stale_intent.any(effect => effect is RejectCommand(StaleBlockIntent)),
  )
  assert_eq(same.sequence(), 2)
}

///|
test "queued Advances validate against the admitted tail without regressing active state" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, _) = projection_test_seed(adapter)
  let (adapter, first) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 2, 2),
      ReplaceProjectionSource("changed"),
      projection_test_demand(),
    ),
  )
  assert_true(first.any(effect => effect is QueueAdvance(_)))
  let third = projection_test_stamp(
    1,
    3,
    2,
    version="causal-v3",
    block_intent=3,
  )
  let (adapter, second) = adapter.reduce(
    Advance(third, ProjectionSourceUnchanged, projection_test_demand()),
  )
  assert_true(second.any(effect => effect is QueueAdvance(_)))
  assert_false(second.any(effect => effect is CaptureLatestSeed(..)))
  assert_eq(adapter.queued_advance_count(), 2)
  assert_eq(adapter.source_revision(), 1)

  let (adapter, _) = adapter.reduce(DispatchNextAdvance)
  assert_eq(adapter.source_revision(), 2)
  assert_eq(adapter.sequence(), 3)
  let (adapter, dispatched) = adapter.reduce(DispatchNextAdvance)
  assert_eq(adapter.source_revision(), 2)
  assert_true(
    dispatched.any(effect => {
      match effect {
        StartGroupWork(stamp~, ..) => stamp == third
        _ => false
      }
    }),
  )
}

///|
test "advance queue bounds coalesce overflow into one allocated latest Seed" {
  let limits = projection_test_limits(
    count=1,
    encoded_bytes=1024,
    source_effect_bytes=1024,
  )
  let adapter = ProjectionAdapter::ProjectionAdapter(limits)
  let (adapter, _) = projection_test_seed(adapter)
  let (adapter, first) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 2, 2),
      ReplaceProjectionSource("12345678"),
      projection_test_demand(),
    ),
  )
  assert_true(first.any(effect => effect is QueueAdvance(_)))
  assert_eq(adapter.queued_advance_count(), 1)
  assert_true(adapter.queued_encoded_bytes() <= limits.max_encoded_bytes)
  assert_eq(
    adapter.queued_source_effect_bytes(),
    source_effect_bytes(ReplaceProjectionSource("12345678")),
  )

  let (adapter, overflow) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 3, 3),
      ReplaceProjectionSource("latest-source"),
      projection_test_demand(preview=false),
    ),
  )
  assert_true(projection_has_capture(overflow, 2, 3))
  assert_eq(adapter.queued_advance_count(), 0)
  assert_eq(adapter.queued_encoded_bytes(), 0)
  assert_eq(adapter.queued_source_effect_bytes(), 0)
  let allocated = adapter.pending_seed_stamp().unwrap()

  let (adapter, coalesced) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 99, 4, version="latest-v4", block_intent=4),
      ReplaceProjectionSource("newest-source"),
      projection_test_demand(block=true, preview=false, diagnostics=false),
    ),
  )
  assert_false(coalesced.any(effect => effect is CaptureLatestSeed(..)))
  assert_eq(adapter.pending_seed_stamp(), Some(allocated))
  assert_eq(adapter.pending_seed_source_revision(), Some(4))

  let (adapter, installed) = adapter.reduce(
    SeedCaptured(
      {
        ..allocated,
        source_revision: 4,
        causal_version: "latest-v4",
        block_intent: 4,
      },
      "newest-source",
      projection_test_demand(block=true, preview=false, diagnostics=false),
    ),
  )
  assert_false(installed.any(effect => effect is RejectCommand(_)))
  assert_eq(adapter.sequence(), 3)
  assert_eq(adapter.generation(), 2)
  assert_eq(adapter.current_source(), Some("newest-source"))
}

///|
test "encoded payload bytes independently bound the pending Advance queue" {
  let adapter = ProjectionAdapter::ProjectionAdapter(
    projection_test_limits(count=8, encoded_bytes=1, source_effect_bytes=1024),
  )
  let (adapter, _) = projection_test_seed(adapter)
  let (adapter, effects) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 2, 2),
      ReplaceProjectionSource("x"),
      projection_test_demand(),
    ),
  )
  assert_true(projection_has_capture(effects, 2, 2))
  assert_eq(adapter.queued_advance_count(), 0)
  assert_eq(adapter.queued_encoded_bytes(), 0)
}

///|
test "encoded byte accounting includes JSON escaping and UTF-8 payload bytes" {
  let stamp = projection_test_stamp(1, 2, 2)
  let effect = ReplaceProjectionSource("猫\n\"quoted\"")
  let exact = advance_encoded_bytes(stamp, effect)
  assert_true(exact > source_effect_bytes(effect))
  let adapter = ProjectionAdapter::ProjectionAdapter(
    projection_test_limits(
      count=8,
      encoded_bytes=exact - 1,
      source_effect_bytes=1024,
    ),
  )
  let (adapter, _) = projection_test_seed(adapter)
  let (_, effects) = adapter.reduce(
    Advance(stamp, effect, projection_test_demand()),
  )
  assert_true(projection_has_capture(effects, 2, 2))
}

///|
test "retained source-effect bytes independently bound the pending Advance queue" {
  let adapter = ProjectionAdapter::ProjectionAdapter(
    projection_test_limits(count=8, encoded_bytes=1024, source_effect_bytes=1),
  )
  let (adapter, _) = projection_test_seed(adapter)
  let (adapter, effects) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 2, 2),
      ReplaceProjectionSource("xx"),
      projection_test_demand(),
    ),
  )
  assert_true(projection_has_capture(effects, 2, 2))
  assert_eq(adapter.queued_advance_count(), 0)
  assert_eq(adapter.queued_source_effect_bytes(), 0)
}

///|
test "work-id exhaustion rejects a demanded group set atomically" {
  let adapter = {
    ..ProjectionAdapter::ProjectionAdapter(projection_test_limits()),
    next_work_id: 2147483646,
  }
  let (_, effects) = projection_test_seed(adapter)
  assert_true(effects.any(effect => effect is RejectCommand(CounterExhausted)))
  assert_false(effects.any(effect => effect is StartGroupWork(..)))
}

///|
test "gap recovery rejects nonmatching capture and installs only the allocated Seed" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, _) = projection_test_seed(adapter)
  let (adapter, effects) = adapter.reduce(
    Advance(
      projection_test_stamp(1, 8, 2),
      ReplaceProjectionSource("# Latest\n"),
      projection_test_demand(),
    ),
  )
  assert_true(projection_has_capture(effects, 2, 2))
  let allocated = adapter.pending_seed_stamp().unwrap()
  let (same, rejected) = adapter.reduce(
    SeedCaptured(
      { ..allocated, sequence: 8 },
      "# Latest\n",
      projection_test_demand(),
    ),
  )
  assert_true(
    rejected.any(effect => effect is RejectCommand(SeedCaptureMismatch)),
  )
  assert_eq(same.pending_seed_stamp(), Some(allocated))

  let (installed, _) = same.reduce(
    SeedCaptured(
      { ..allocated, source_revision: 2, causal_version: "v8", block_intent: 8 },
      "# Latest\n",
      projection_test_demand(),
    ),
  )
  assert_eq(installed.generation(), 2)
  assert_eq(installed.sequence(), 2)
  assert_eq(installed.current_source(), Some("# Latest\n"))
}

///|
test "consistency groups adopt independently and one presentation closes several work items" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, effects) = projection_test_seed(adapter)
  let ids = projection_effect_work_ids(effects)
  let stamp = projection_test_stamp(1, 1, 1)
  let (adapter, preview) = projection_test_materialized(
    adapter,
    ids[1],
    stamp,
    Preview,
    "preview",
  )
  assert_true(preview.any(effect => effect is AdoptArtifact(group=Preview, ..)))
  assert_true(adapter.has_pending_group(Block))
  assert_false(adapter.has_pending_group(Preview))
  assert_true(adapter.has_pending_group(Diagnostics))

  let (adapter, block) = projection_test_materialized(
    adapter,
    ids[0],
    stamp,
    Block,
    "block",
  )
  assert_true(block.any(effect => effect is AdoptArtifact(group=Block, ..)))
  let (adapter, presented) = adapter.reduce(
    GroupsPresented(presentation_id=7, work_ids=[ids[1], ids[0]]),
  )
  let terminal = projection_terminal_effects(presented)
  assert_true(terminal.any(pair => pair == (ids[0], Presented(7))))
  assert_true(terminal.any(pair => pair == (ids[1], Presented(7))))
  assert_true(adapter.has_pending_group(Diagnostics))
}

///|
test "NoDemand allocates no work and hidden groups never block Block" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, no_demand) = projection_test_seed(
    adapter,
    demand=projection_test_demand(block=false, preview=false, diagnostics=false),
  )
  assert_true(projection_effect_work_ids(no_demand).is_empty())
  assert_true(
    no_demand.any(effect => effect is RecordRequestDisposition(NoDemand)),
  )

  let stamp = projection_test_stamp(1, 1, 1)
  let (adapter, block_only) = adapter.reduce(
    Demand(
      stamp,
      projection_test_demand(block=true, preview=false, diagnostics=false),
    ),
  )
  let work = projection_effect_work_ids(block_only)
  assert_eq(work.length(), 1)
  let (_, adopted) = projection_test_materialized(
    adapter,
    work[0],
    stamp,
    Block,
    "block-only",
  )
  assert_true(adopted.any(effect => effect is AdoptArtifact(group=Block, ..)))
}

///|
test "every issued work item receives exactly one explicit terminal outcome" {
  let adapter = ProjectionAdapter::ProjectionAdapter(projection_test_limits())
  let (adapter, effects) = projection_test_seed(adapter)
  let ids = projection_effect_work_ids(effects)
  let stamp = projection_test_stamp(1, 1, 1)
  let (adapter, _) = projection_test_materialized(
    adapter,
    ids[0],
    stamp,
    Block,
    "adopted",
  )
  let (adapter, removed) = adapter.reduce(
    Demand(
      stamp,
      projection_test_demand(block=false, preview=true, diagnostics=true),
    ),
  )
  assert_true(
    projection_terminal_effects(removed).any(pair => {
      pair.0 == ids[0] && pair.1 is AdoptedNotPresented(DemandRemoved)
    }),
  )
  let (adapter, failed) = adapter.reduce(
    GroupFailed(
      work_id=ids[1],
      stamp~,
      group=Preview,
      failure=ProjectionExecutionFailed("preview failed"),
    ),
  )
  assert_true(
    projection_terminal_effects(failed).any(pair => {
      pair.0 == ids[1] && pair.1 is Failed
    }),
  )
  let (adapter, disposed) = adapter.reduce(DisposeProjectionAdapter)
  assert_true(
    projection_terminal_effects(disposed).any(pair => {
      pair.0 == ids[2] && pair.1 is Disposed
    }),
  )
  let (_, duplicate) = adapter.reduce(
    GroupFailed(
      work_id=ids[2],
      stamp~,
      group=Diagnostics,
      failure=ProjectionExecutionFailed("late"),
    ),
  )
  assert_true(duplicate.any(effect => effect is RejectCallback(_)))
  assert_true(projection_terminal_effects(duplicate).is_empty())
}

///|
test "Projection Session adopts an allocated Seed stamp before its next Advance" {
  let session = try! ProjectionSession::ProjectionSession(
    agent_id="seed-restamp",
    source="# Before\n",
  )
  defer session.dispose()
  session.sequence = 2
  try! session.advance(ReplaceProjectionSource("# After\n"))
  assert_eq(session.generation, 2)
  assert_eq(session.sequence, 2)
  assert_eq(session.adapter.generation(), 2)
  assert_eq(session.adapter.pending_seed_stamp(), None)

  try! session.advance(ProjectionSourceUnchanged)
  assert_eq(session.generation, 2)
  assert_eq(session.sequence, 3)
  assert_eq(session.adapter.generation(), 2)
  assert_eq(session.adapter.sequence(), 3)
}

///|
test "retained Projection Session matches an independent fresh oracle across observable groups" {
  let cases : Array[(String, String)] = [
    ("unicode", "# 猫 🐈\n\nParagraph *強い* text.\n"),
    ("recovery", "# Broken\n\n[link](\n\n```moonbit\nlet x = 1\n"),
    ("containers", "> quote\n\n- first\n- second\n"),
  ]
  for item in cases {
    let (label, source) = item
    let session = try! ProjectionSession::ProjectionSession(
      agent_id="retained-" + label,
      source~,
    )
    defer session.dispose()
    let retained = try! session.normalized_observables()
    let fresh = try! fresh_projection_observables(
      source,
      agent_id="fresh-" + label,
    )
    assert_eq(retained, fresh)
    assert_eq(try! session.normalized_protocol_observables(), fresh)

    let edited = source + "\nTail `code`.\n"
    try! session.advance(ReplaceProjectionSource(edited))
    let retained_after = try! session.normalized_observables()
    let fresh_after = try! fresh_projection_observables(
      edited,
      agent_id="fresh-after-" + label,
    )
    assert_eq(retained_after, fresh_after)
    assert_eq(try! session.normalized_protocol_observables(), fresh_after)

    try! session.advance(ProjectionSourceUnchanged)
    assert_eq(try! session.normalized_observables(), retained_after)
    assert_eq(try! session.normalized_protocol_observables(), retained_after)
  }
}
