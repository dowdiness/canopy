///|
fn stored_result(
  writer : CheckpointWriter,
  checkpoint : SyncCheckpoint,
) -> Result[(CheckpointWriter, CheckpointWrite?), WriterError] {
  Ok(writer.stored(checkpoint)) catch {
    error => Err(error)
  }
}

///|
fn failed_result(
  writer : CheckpointWriter,
  checkpoint : SyncCheckpoint,
) -> Result[CheckpointWriter, WriterError] {
  Ok(writer.failed(checkpoint)) catch {
    error => Err(error)
  }
}

///|
test "writes in progress retain only one newest follow-up" {
  let first = enrolled("original").edit("first").unwrap()
  let second = first.checkpoint().edit("second").unwrap()
  let latest = second.checkpoint().edit("latest").unwrap()
  let (writer, _) = CheckpointWriter::Available.enqueue(first)
  let (writer, follow_up) = writer.enqueue(second)
  assert_eq(follow_up, None)
  let (writer, follow_up) = writer.enqueue(latest)
  assert_eq(follow_up, None)
  assert_eq(writer, CheckpointWriter::Storing(first, Some(latest)))
  let (writer, follow_up) = writer.stored(first.checkpoint())
  assert_eq(follow_up, Some(latest))
  assert_eq(writer, CheckpointWriter::Storing(latest, None))
}

///|
test "storage failure retains newest write for explicit retry" {
  let first = enrolled("original").edit("first").unwrap()
  let latest = first.checkpoint().edit("latest").unwrap()
  let (writer, _) = CheckpointWriter::Available.enqueue(first)
  let (writer, _) = writer.enqueue(latest)
  let failed = writer.failed(first.checkpoint())
  assert_eq(failed, CheckpointWriter::RetryPending(latest))
  let (retrying, retry) = failed.retry()
  assert_eq(retry, latest)
  assert_eq(retrying, CheckpointWriter::Storing(latest, None))
}

///|
test "completion from another account cannot finish the active write" {
  let active = enrolled("old").edit("changed").unwrap()
  let other_account = SyncCheckpoint::enroll(
      test_account(value="account-b"),
      sync_doc("old"),
    )
    .edit("changed")
    .unwrap()
    .checkpoint()
  let (writer, _) = CheckpointWriter::Available.enqueue(active)
  assert_eq(
    stored_result(writer, other_account),
    Err(WriterError::StaleCompletion),
  )
  assert_eq(
    failed_result(writer, other_account),
    Err(WriterError::StaleCompletion),
  )
}

///|
test "completion must match active document and generation" {
  let active = enrolled("old").edit("active").unwrap()
  let wrong_document = SyncCheckpoint::enroll(
      test_account(),
      Document::create("other", "old") catch {
        _ => abort("invalid test document")
      },
    )
    .edit("active")
    .unwrap()
    .checkpoint()
  let wrong_generation = active.checkpoint().edit("newer").unwrap().checkpoint()
  let (writer, _) = CheckpointWriter::new().enqueue(active)
  for completion in [wrong_document, wrong_generation] {
    assert_eq(
      stored_result(writer, completion),
      Err(WriterError::StaleCompletion),
    )
    assert_eq(
      failed_result(writer, completion),
      Err(WriterError::StaleCompletion),
    )
  }
}

///|
test "coalescing preserves an unpersisted conflict recovery" {
  let first = enrolled("base").edit("local").unwrap()
  let conflict = preserve_conflict(
    first.checkpoint(),
    remote_present(1.0, "remote"),
    "recovery",
  )
  let newer = conflict.checkpoint().edit("newer local").unwrap()
  let (writer, _) = CheckpointWriter::Available.enqueue(first)
  let (writer, _) = writer.enqueue(conflict)
  let (writer, _) = writer.enqueue(newer)
  guard writer is CheckpointWriter::Storing(_, Some(retained)) else {
    fail("expected waiting write")
  }
  guard retained is CheckpointWrite::CheckpointAndRecovery(checkpoint, recovery) else {
    fail("expected atomic recovery write")
  }
  assert_eq(checkpoint, newer.checkpoint())
  assert_eq(recovery.id(), "recovery")
  guard writer.failed(first.checkpoint()) is RetryPending(retained) else {
    fail("expected retry")
  }
  guard retained is CheckpointAndRecovery(checkpoint, recovery) else {
    fail("expected recovery on retry")
  }
  assert_eq(checkpoint, newer.checkpoint())
  assert_eq(recovery.text(), "local")
}
