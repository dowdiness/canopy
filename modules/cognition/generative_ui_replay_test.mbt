///|
fn replay_chunk(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
  payload : String,
) -> GenerativeUiInput {
  GenerativeUiInput::chunk(generation_id~, base_revision~, sequence~, payload~)
}

///|
fn replay_final(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
) -> GenerativeUiInput {
  GenerativeUiInput::finalize(generation_id~, base_revision~, sequence~)
}

///|
fn replay_cancel(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
) -> GenerativeUiInput {
  GenerativeUiInput::cancel(generation_id~, base_revision~, sequence~)
}

///|
enum ReplayFixture {
  Complete
  Incomplete
  Duplicated
  OutOfOrder
  Cancelled
} derive(Debug, Eq)

///|
fn replay_fixture_source(
  fixture : ReplayFixture,
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
) -> GenerativeUiReplaySource {
  let events : Array[GenerativeUiInput] = match fixture {
    Complete =>
      [
        replay_chunk(generation_id, base_revision, 0, "<table>"),
        replay_chunk(generation_id, base_revision, 1, "rows"),
        replay_final(generation_id, base_revision, 2),
      ]
    Incomplete => [replay_chunk(generation_id, base_revision, 0, "<table>")]
    Duplicated =>
      [
        replay_chunk(generation_id, base_revision, 0, "<table>"),
        replay_chunk(generation_id, base_revision, 0, "<table>"),
        replay_final(generation_id, base_revision, 1),
      ]
    OutOfOrder => [replay_chunk(generation_id, base_revision, 1, "rows")]
    Cancelled =>
      [
        replay_chunk(generation_id, base_revision, 0, "<table>"),
        replay_cancel(generation_id, base_revision, 1),
      ]
  }
  GenerativeUiReplaySource::GenerativeUiReplaySource(events~)
}

///|
fn drain_replay(
  source : GenerativeUiReplaySource,
  lifecycle : GenerativeUiLifecycle,
) -> (GenerativeUiLifecycle, Array[GenerativeUiTransition]) {
  let transitions : Array[GenerativeUiTransition] = []
  while source.next() is Some(input) {
    transitions.push(lifecycle.dispatch(Input(input)))
  }
  (lifecycle, transitions)
}

///|
test "generative ui replay source is fixed, replayable, and cursor-owned" {
  let generation_id = generative_ui_start_for_test(0).1
  let revision = GenerativeUiRevision::GenerativeUiRevision(0)
  let first = replay_chunk(generation_id, revision, 0, "first")
  let second = replay_final(generation_id, revision, 1)
  let events = [first, second]
  let source = GenerativeUiReplaySource::GenerativeUiReplaySource(events~)
  events.push(replay_cancel(generation_id, revision, 1))

  inspect(source.is_exhausted(), content="false")
  inspect(source.next() == Some(first), content="true")
  inspect(source.next() == Some(second), content="true")
  inspect(source.next() is None, content="true")
  inspect(source.is_exhausted(), content="true")

  source.reset()
  inspect(source.is_exhausted(), content="false")
  inspect(source.next() == Some(first), content="true")
}

///|
test "complete replay reaches validation with the assembled candidate" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let source = replay_fixture_source(Complete, generation_id, revision)
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Validating, content="true")
  inspect(lifecycle.candidate_source(), content="<table>rows")
  inspect(transitions.length(), content="3")
  inspect(source.is_exhausted(), content="true")
}

///|
test "incomplete replay remains receiving and never validates" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let source = replay_fixture_source(Incomplete, generation_id, revision)
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Receiving, content="true")
  inspect(lifecycle.candidate_source(), content="<table>")
  inspect(transitions.length(), content="1")
}

///|
test "duplicated replay preserves one candidate chunk" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let source = replay_fixture_source(Duplicated, generation_id, revision)
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Validating, content="true")
  inspect(lifecycle.candidate_source(), content="<table>")
  inspect(transitions[1] == DuplicateChunk(sequence=0), content="true")
}

///|
test "out-of-order replay follows the rejected gap policy" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let source = replay_fixture_source(OutOfOrder, generation_id, revision)
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Rejected, content="true")
  inspect(
    lifecycle.rejection() == Some(SequenceGap(expected=0, received=1)),
    content="true",
  )
  inspect(
    transitions[0] == Rejected(reason=SequenceGap(expected=0, received=1)),
    content="true",
  )
}

///|
test "cancelled replay terminates before validation" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let source = replay_fixture_source(Cancelled, generation_id, revision)
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Cancelled, content="true")
  inspect(transitions[1] == Cancelled, content="true")
  inspect(lifecycle.candidate_source(), content="<table>")
}

///|
test "late replay from a prior generation is ignored after restart" {
  let (lifecycle, old_generation_id, revision) = generative_ui_start_for_test(0)
  let _ = lifecycle.dispatch(
    generative_ui_cancel(old_generation_id, revision, 0),
  )
  let _ = lifecycle.restart(revision)
  let current_generation_id = lifecycle.generation_id().unwrap()
  let source = GenerativeUiReplaySource::GenerativeUiReplaySource(events=[
    replay_chunk(old_generation_id, revision, 0, "late"),
  ])
  let (lifecycle, transitions) = drain_replay(source, lifecycle)

  inspect(lifecycle.phase() == Receiving, content="true")
  inspect(lifecycle.candidate_source(), content="")
  inspect(transitions[0] == Ignored(reason=StaleGeneration), content="true")
  inspect(current_generation_id != old_generation_id, content="true")
}

///|
test "resumed replay starts from the committed revision" {
  let (lifecycle, first_generation_id, first_revision) = generative_ui_start_for_test(
    0,
  )
  let source = replay_fixture_source(
    Complete,
    first_generation_id,
    first_revision,
  )
  let (lifecycle, _) = drain_replay(source, lifecycle)
  let _ = lifecycle.dispatch(
    CandidateValid(
      generation_id=first_generation_id,
      current_revision=first_revision,
    ),
  )
  let _ = lifecycle.dispatch(DryRunSucceeded(generation_id=first_generation_id))
  let _ = lifecycle.dispatch(
    ApplySucceeded(
      generation_id=first_generation_id,
      revision=GenerativeUiRevision::GenerativeUiRevision(1),
    ),
  )
  let committed_revision = lifecycle.committed_revision().unwrap()
  let _ = lifecycle.restart(committed_revision)
  let resumed_generation_id = lifecycle.generation_id().unwrap()
  let resumed_source = GenerativeUiReplaySource::GenerativeUiReplaySource(events=[
    replay_chunk(resumed_generation_id, committed_revision, 0, "resumed"),
    replay_final(resumed_generation_id, committed_revision, 1),
  ])
  let (lifecycle, _) = drain_replay(resumed_source, lifecycle)

  inspect(lifecycle.base_revision() == Some(committed_revision), content="true")
  inspect(lifecycle.phase() == Validating, content="true")
  inspect(lifecycle.candidate_source(), content="resumed")
}
