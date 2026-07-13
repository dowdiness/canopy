///|
fn inspect_transition(
  actual : GenerativeUiTransition,
  expected : GenerativeUiTransition,
) -> Unit raise {
  inspect(actual == expected, content="true")
}

///|
fn generative_ui_start_for_test(
  base_revision : Int,
) -> (GenerativeUiLifecycle, GenerativeUiGenerationId, GenerativeUiRevision) {
  let lifecycle = GenerativeUiLifecycle::GenerativeUiLifecycle()
  let revision = GenerativeUiRevision::GenerativeUiRevision(base_revision)
  let transition = lifecycle.dispatch(Start(base_revision=revision))
  match transition {
    Started(generation_id~) => (lifecycle, generation_id, revision)
    _ => abort("expected generation to start")
  }
}

///|
fn generative_ui_chunk(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
  payload : String,
) -> GenerativeUiEvent {
  Input(
    GenerativeUiInput::chunk(
      generation_id~,
      base_revision~,
      sequence~,
      payload~,
    ),
  )
}

///|
fn generative_ui_finalize(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
) -> GenerativeUiEvent {
  Input(GenerativeUiInput::finalize(generation_id~, base_revision~, sequence~))
}

///|
fn generative_ui_cancel(
  generation_id : GenerativeUiGenerationId,
  base_revision : GenerativeUiRevision,
  sequence : Int,
) -> GenerativeUiEvent {
  Input(GenerativeUiInput::cancel(generation_id~, base_revision~, sequence~))
}

///|
test "generative ui starts with an allocated identity and accepts chunks once" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(7)
  inspect(generation_id.to_int(), content="1")
  inspect(lifecycle.phase() == Receiving, content="true")
  inspect(lifecycle.next_sequence(), content="0")

  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, 0, "<table>"),
    ),
    ChunkAccepted(sequence=0),
  )
  inspect(lifecycle.phase() == Receiving, content="true")
  inspect(lifecycle.next_sequence(), content="1")
  inspect(lifecycle.candidate_source(), content="<table>")
}

///|
test "generative ui duplicate chunks are idempotent" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let chunk = generative_ui_chunk(generation_id, revision, 0, "alpha")
  let _ = lifecycle.dispatch(chunk)
  let before = lifecycle.candidate_source()
  inspect_transition(lifecycle.dispatch(chunk), DuplicateChunk(sequence=0))
  inspect(lifecycle.phase() == Receiving, content="true")
  inspect(lifecycle.next_sequence(), content="1")
  inspect(lifecycle.candidate_source(), content=before)
}

///|
test "generative ui rejects gaps and conflicting duplicates" {
  let (gap_lifecycle, gap_id, gap_revision) = generative_ui_start_for_test(0)
  inspect_transition(
    gap_lifecycle.dispatch(generative_ui_chunk(gap_id, gap_revision, 1, "late")),
    Rejected(reason=SequenceGap(expected=0, received=1)),
  )
  inspect(gap_lifecycle.phase() == Rejected, content="true")

  let (duplicate_lifecycle, duplicate_id, duplicate_revision) = generative_ui_start_for_test(
    0,
  )
  let _ = duplicate_lifecycle.dispatch(
    generative_ui_chunk(duplicate_id, duplicate_revision, 0, "alpha"),
  )
  inspect_transition(
    duplicate_lifecycle.dispatch(
      generative_ui_chunk(duplicate_id, duplicate_revision, 0, "beta"),
    ),
    Rejected(reason=ConflictingDuplicate(sequence=0)),
  )
  inspect(duplicate_lifecycle.candidate_source(), content="alpha")
}

///|
test "generative ui final freezes input and rejects later chunks" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(2)
  let _ = lifecycle.dispatch(
    generative_ui_chunk(generation_id, revision, 0, "candidate"),
  )
  inspect_transition(
    lifecycle.dispatch(generative_ui_finalize(generation_id, revision, 1)),
    Finalized,
  )
  inspect(lifecycle.phase() == Validating, content="true")
  inspect_transition(
    lifecycle.dispatch(generative_ui_chunk(generation_id, revision, 1, "late")),
    Ignored(reason=EventNotAcceptedInPhase),
  )
  inspect(lifecycle.candidate_source(), content="candidate")
}

///|
test "generative ui rejects stale candidates without advancing revision" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(4)
  let _ = lifecycle.dispatch(generative_ui_finalize(generation_id, revision, 0))
  let stale_revision = GenerativeUiRevision::GenerativeUiRevision(5)
  inspect_transition(
    lifecycle.dispatch(
      CandidateValid(generation_id~, current_revision=stale_revision),
    ),
    Rejected(
      reason=BaseRevisionMismatch(
        expected=GenerativeUiRevision::GenerativeUiRevision(4),
        received=stale_revision,
      ),
    ),
  )
  inspect(lifecycle.phase() == Rejected, content="true")
  inspect(lifecycle.committed_revision() is None, content="true")
}

///|
test "generative ui validates, dry-runs, and commits exactly once" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(9)
  let _ = lifecycle.dispatch(generative_ui_finalize(generation_id, revision, 0))
  inspect_transition(
    lifecycle.dispatch(
      CandidateValid(generation_id~, current_revision=revision),
    ),
    DryRunStarted,
  )
  inspect(lifecycle.phase() == DryRunning, content="true")
  inspect_transition(
    lifecycle.dispatch(DryRunSucceeded(generation_id~)),
    ApplyStarted,
  )
  inspect(lifecycle.phase() == Applying, content="true")
  inspect_transition(
    lifecycle.dispatch(
      ApplySucceeded(
        generation_id~,
        revision=GenerativeUiRevision::GenerativeUiRevision(10),
      ),
    ),
    Committed(revision=GenerativeUiRevision::GenerativeUiRevision(10)),
  )
  inspect(lifecycle.phase() == Committed, content="true")
  match lifecycle.committed_revision() {
    Some(revision) => inspect(revision.to_int(), content="10")
    None => inspect(false, content="true")
  }
  inspect_transition(
    lifecycle.dispatch(
      ApplySucceeded(
        generation_id~,
        revision=GenerativeUiRevision::GenerativeUiRevision(10),
      ),
    ),
    Ignored(reason=TerminalState),
  )
}

///|
test "generative ui cancellation wins before applying and is too late during applying" {
  let (cancelled, cancelled_id, cancelled_revision) = generative_ui_start_for_test(
    0,
  )
  inspect_transition(
    cancelled.dispatch(
      generative_ui_cancel(cancelled_id, cancelled_revision, 0),
    ),
    Cancelled,
  )
  inspect(cancelled.phase() == Cancelled, content="true")
  inspect_transition(
    cancelled.dispatch(
      generative_ui_finalize(cancelled_id, cancelled_revision, 0),
    ),
    Ignored(reason=TerminalState),
  )

  let (validating, validating_id, validating_revision) = generative_ui_start_for_test(
    1,
  )
  let _ = validating.dispatch(
    generative_ui_finalize(validating_id, validating_revision, 0),
  )
  inspect_transition(
    validating.dispatch(
      generative_ui_cancel(validating_id, validating_revision, 0),
    ),
    Cancelled,
  )

  let (dry_running, dry_running_id, dry_running_revision) = generative_ui_start_for_test(
    2,
  )
  let _ = dry_running.dispatch(
    generative_ui_finalize(dry_running_id, dry_running_revision, 0),
  )
  let _ = dry_running.dispatch(
    CandidateValid(
      generation_id=dry_running_id,
      current_revision=dry_running_revision,
    ),
  )
  inspect_transition(
    dry_running.dispatch(
      generative_ui_cancel(dry_running_id, dry_running_revision, 0),
    ),
    Cancelled,
  )

  let (applying, applying_id, applying_revision) = generative_ui_start_for_test(
    3,
  )
  let _ = applying.dispatch(
    generative_ui_finalize(applying_id, applying_revision, 0),
  )
  let _ = applying.dispatch(
    CandidateValid(
      generation_id=applying_id,
      current_revision=applying_revision,
    ),
  )
  let _ = applying.dispatch(DryRunSucceeded(generation_id=applying_id))
  inspect_transition(
    applying.dispatch(generative_ui_cancel(applying_id, applying_revision, 0)),
    Ignored(reason=CancellationTooLate),
  )
  inspect(applying.phase() == Applying, content="true")
  inspect_transition(
    applying.dispatch(
      ApplySucceeded(
        generation_id=applying_id,
        revision=GenerativeUiRevision::GenerativeUiRevision(4),
      ),
    ),
    Committed(revision=GenerativeUiRevision::GenerativeUiRevision(4)),
  )
}

///|
test "generative ui cancellation, invalid candidates, dry-run failures, and apply failures preserve commit" {
  let (invalid, invalid_id, invalid_revision) = generative_ui_start_for_test(0)
  let _ = invalid.dispatch(
    generative_ui_finalize(invalid_id, invalid_revision, 0),
  )
  inspect_transition(
    invalid.dispatch(
      CandidateInvalid(generation_id=invalid_id, message="unsafe component"),
    ),
    Rejected(reason=InvalidCandidate(message="unsafe component")),
  )
  inspect(invalid.committed_revision() is None, content="true")

  let (dry_run, dry_run_id, dry_run_revision) = generative_ui_start_for_test(1)
  let _ = dry_run.dispatch(
    generative_ui_finalize(dry_run_id, dry_run_revision, 0),
  )
  let _ = dry_run.dispatch(
    CandidateValid(generation_id=dry_run_id, current_revision=dry_run_revision),
  )
  inspect_transition(
    dry_run.dispatch(
      DryRunFailed(generation_id=dry_run_id, message="model mismatch"),
    ),
    Rejected(reason=DryRunFailed(message="model mismatch")),
  )
  inspect(dry_run.committed_revision() is None, content="true")

  let (apply, apply_id, apply_revision) = generative_ui_start_for_test(2)
  let _ = apply.dispatch(generative_ui_finalize(apply_id, apply_revision, 0))
  let _ = apply.dispatch(
    CandidateValid(generation_id=apply_id, current_revision=apply_revision),
  )
  let _ = apply.dispatch(DryRunSucceeded(generation_id=apply_id))
  inspect_transition(
    apply.dispatch(ApplyFailed(generation_id=apply_id, message="dom failure")),
    Failed(reason=ApplyFailed(message="dom failure")),
  )
  inspect(apply.committed_revision() is None, content="true")

  let (mismatch, mismatch_id, mismatch_revision) = generative_ui_start_for_test(
    3,
  )
  let _ = mismatch.dispatch(
    generative_ui_finalize(mismatch_id, mismatch_revision, 0),
  )
  let _ = mismatch.dispatch(
    CandidateValid(
      generation_id=mismatch_id,
      current_revision=mismatch_revision,
    ),
  )
  let _ = mismatch.dispatch(DryRunSucceeded(generation_id=mismatch_id))
  inspect_transition(
    mismatch.dispatch(
      ApplySucceeded(
        generation_id=mismatch_id,
        revision=GenerativeUiRevision::GenerativeUiRevision(99),
      ),
    ),
    Failed(
      reason=ApplyRevisionMismatch(
        expected=GenerativeUiRevision::GenerativeUiRevision(4),
        received=GenerativeUiRevision::GenerativeUiRevision(99),
      ),
    ),
  )
}

///|
test "generative ui ignores stale generations and terminal late events" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let _ = lifecycle.dispatch(generative_ui_cancel(generation_id, revision, 0))
  let restarted = lifecycle.restart(revision)
  let restarted_id = match restarted {
    Started(generation_id~) => generation_id
    _ => abort("expected lifecycle restart")
  }
  inspect(restarted_id.to_int(), content="2")
  let _ = lifecycle.dispatch(generative_ui_finalize(restarted_id, revision, 0))
  inspect_transition(
    lifecycle.dispatch(generative_ui_chunk(generation_id, revision, 0, "stale")),
    Ignored(reason=StaleGeneration),
  )
  inspect(lifecycle.phase() == Validating, content="true")
  inspect(lifecycle.candidate_source(), content="")

  inspect_transition(
    lifecycle.dispatch(
      CandidateValid(generation_id~, current_revision=revision),
    ),
    Ignored(reason=StaleGeneration),
  )
  let _ = lifecycle.dispatch(
    CandidateValid(generation_id=restarted_id, current_revision=revision),
  )
  inspect_transition(
    lifecycle.dispatch(DryRunSucceeded(generation_id~)),
    Ignored(reason=StaleGeneration),
  )
  let _ = lifecycle.dispatch(DryRunSucceeded(generation_id=restarted_id))
  inspect_transition(
    lifecycle.dispatch(
      ApplySucceeded(
        generation_id~,
        revision=GenerativeUiRevision::GenerativeUiRevision(1),
      ),
    ),
    Ignored(reason=StaleGeneration),
  )
  let _ = lifecycle.dispatch(
    ApplySucceeded(
      generation_id=restarted_id,
      revision=GenerativeUiRevision::GenerativeUiRevision(1),
    ),
  )
  inspect_transition(
    lifecycle.dispatch(generative_ui_chunk(restarted_id, revision, 0, "late")),
    Ignored(reason=TerminalState),
  )
  inspect(lifecycle.phase() == Committed, content="true")
}

///|
test "generative ui resumption requires a newly selected committed revision" {
  let (first, first_id, first_revision) = generative_ui_start_for_test(10)
  let _ = first.dispatch(generative_ui_finalize(first_id, first_revision, 0))
  let _ = first.dispatch(
    CandidateValid(generation_id=first_id, current_revision=first_revision),
  )
  let _ = first.dispatch(DryRunSucceeded(generation_id=first_id))
  let _ = first.dispatch(
    ApplySucceeded(
      generation_id=first_id,
      revision=GenerativeUiRevision::GenerativeUiRevision(11),
    ),
  )
  let committed_revision = first.committed_revision().unwrap()

  let started = first.restart(committed_revision)
  inspect(
    started == Started(generation_id=first.generation_id().unwrap()),
    content="true",
  )
  match first.base_revision() {
    Some(revision) => inspect(revision.to_int(), content="11")
    None => inspect(false, content="true")
  }
  inspect(first.phase() == Receiving, content="true")
}

///|
test "generative ui rejects an oversized chunk without mutating input state" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let oversized = String::repeat("x", GENERATIVE_UI_MAX_CHUNK_LENGTH + 1)
  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, 0, oversized),
    ),
    Rejected(reason=InputLimitExceeded(limit=ChunkLength)),
  )
  inspect(lifecycle.next_sequence(), content="0")
  inspect(lifecycle.candidate_source(), content="")
}

///|
test "generative ui rejects an overflow-adjacent sequence without mutation" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, 0x7FFFFFFF, "x"),
    ),
    Rejected(reason=SequenceGap(expected=0, received=0x7FFFFFFF)),
  )
  inspect(lifecycle.next_sequence(), content="0")
  inspect(lifecycle.candidate_source(), content="")
}

///|
test "generative ui rejects aggregate input growth at the limit" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let chunk = String::repeat("x", GENERATIVE_UI_MAX_CHUNK_LENGTH)
  let chunk_count = GENERATIVE_UI_MAX_SOURCE_LENGTH /
    GENERATIVE_UI_MAX_CHUNK_LENGTH
  for sequence in 0..<chunk_count {
    inspect_transition(
      lifecycle.dispatch(
        generative_ui_chunk(generation_id, revision, sequence, chunk),
      ),
      ChunkAccepted(sequence~),
    )
  }
  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, chunk_count, "x"),
    ),
    Rejected(reason=InputLimitExceeded(limit=SourceLength)),
  )
  inspect(lifecycle.next_sequence(), content=chunk_count.to_string())
  inspect(
    lifecycle.candidate_source().length(),
    content=GENERATIVE_UI_MAX_SOURCE_LENGTH.to_string(),
  )
}

///|
test "generative ui rejects chunk count overflow without mutating state" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  for sequence in 0..<GENERATIVE_UI_MAX_CHUNKS {
    inspect_transition(
      lifecycle.dispatch(
        generative_ui_chunk(generation_id, revision, sequence, "x"),
      ),
      ChunkAccepted(sequence~),
    )
  }
  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(
        generation_id,
        revision,
        GENERATIVE_UI_MAX_CHUNKS,
        "x",
      ),
    ),
    Rejected(reason=InputLimitExceeded(limit=ChunkCount)),
  )
  inspect(
    lifecycle.next_sequence(),
    content=GENERATIVE_UI_MAX_CHUNKS.to_string(),
  )
  inspect(
    lifecycle.candidate_source().length(),
    content=GENERATIVE_UI_MAX_CHUNKS.to_string(),
  )
}

///|
test "generative ui preserves duplicate and stale precedence over input limits" {
  let (lifecycle, generation_id, revision) = generative_ui_start_for_test(0)
  let chunk = String::repeat("x", GENERATIVE_UI_MAX_CHUNK_LENGTH)
  let chunk_count = GENERATIVE_UI_MAX_SOURCE_LENGTH /
    GENERATIVE_UI_MAX_CHUNK_LENGTH
  for sequence in 0..<chunk_count {
    let _ = lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, sequence, chunk),
    )
  }
  inspect_transition(
    lifecycle.dispatch(generative_ui_chunk(generation_id, revision, 0, chunk)),
    DuplicateChunk(sequence=0),
  )
  inspect_transition(
    lifecycle.dispatch(
      generative_ui_chunk(generation_id, revision, 0, "conflict"),
    ),
    Rejected(reason=ConflictingDuplicate(sequence=0)),
  )
  let (stale_lifecycle, stale_generation, stale_revision) = generative_ui_start_for_test(
    0,
  )
  let _ = stale_lifecycle.dispatch(
    generative_ui_cancel(stale_generation, stale_revision, 0),
  )
  let _ = stale_lifecycle.restart(stale_revision)
  let stale = GenerativeUiInput::chunk(
    generation_id=stale_generation,
    base_revision=stale_revision,
    sequence=0x7FFFFFFF,
    payload=String::repeat("x", GENERATIVE_UI_MAX_CHUNK_LENGTH + 1),
  )
  inspect_transition(
    stale_lifecycle.dispatch(Input(stale)),
    Ignored(reason=StaleGeneration),
  )
}
