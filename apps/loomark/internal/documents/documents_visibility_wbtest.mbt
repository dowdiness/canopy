///|
fn visibility_save(actions : Array[Action], id : String) -> SaveOperation {
  for action in actions {
    if action is PersistSource(operation) &&
      operation.document.id() == document_id(id) {
      return operation
    }
  }
  abort("expected save for " + id)
}

///|
test "hidden flush leaves an active deletion alone while saving another document" {
  let documents = State::State(documents_test_snapshot())
  let (documents, deletion) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard deletion is [DeleteSource(_)] else { fail("active deletion") }
  let before = documents.delete_phase_status(source_key("one"))
  let (documents, _) = documents.reduce(TextChanged(source_key("two"), "two!"))
  let (documents, actions) = documents.reduce(VisibilityFlushAll)
  assert_eq(actions.length(), 1)
  let operation = visibility_save(actions, "two")
  assert_eq(operation.document.text(), "two!")
  assert_true(documents.delete_phase_status(source_key("one")) == before)
}

///|
test "hidden flush starts all waiting documents once and accepts reverse acknowledgments" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "one!"))
  let (documents, _) = documents.reduce(TextChanged(source_key("two"), "two!"))
  let (documents, actions) = documents.reduce(VisibilityFlushAll)
  assert_eq(actions.length(), 2)
  let first = visibility_save(actions, "one")
  let second = visibility_save(actions, "two")
  let (unchanged, repeated) = documents.reduce(VisibilityFlushAll)
  assert_true(unchanged == documents)
  assert_true(repeated.is_empty())
  let (documents, follow_up) = documents.reduce(
    FeedbackReceived(SaveCompleted(second, Stored(second.document))),
  )
  assert_true(follow_up.is_empty())
  let (documents, follow_up) = documents.reduce(
    FeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  assert_true(follow_up.is_empty())
  assert_eq(
    documents.snapshot().find(document_id("one")).unwrap().text(),
    "one!",
  )
  assert_eq(
    documents.snapshot().find(document_id("two")).unwrap().text(),
    "two!",
  )
  assert_true(documents.save_status(source_key("one")) == Some(Clean))
  assert_true(documents.save_status(source_key("two")) == Some(Clean))
}

///|
test "hidden flush coalesces both in-flight lanes regardless of acknowledgment order" {
  for reverse in [false, true] {
    let documents = State::State(documents_test_snapshot())
    let (documents, _) = documents.reduce(
      TextChanged(source_key("one"), "first one"),
    )
    let (documents, _) = documents.reduce(
      TextChanged(source_key("two"), "first two"),
    )
    let (documents, actions) = documents.reduce(VisibilityFlushAll)
    let first = visibility_save(actions, "one")
    let second = visibility_save(actions, "two")
    let (documents, _) = documents.reduce(
      TextChanged(source_key("one"), "latest one"),
    )
    let (documents, _) = documents.reduce(
      TextChanged(source_key("two"), "latest two"),
    )
    let (documents, actions) = documents.reduce(VisibilityFlushAll)
    assert_true(actions.is_empty())
    let (unchanged, actions) = documents.reduce(VisibilityFlushAll)
    assert_true(unchanged == documents)
    assert_true(actions.is_empty())
    let order = if reverse { [second, first] } else { [first, second] }
    let mut documents = documents
    for operation in order {
      let (next, actions) = documents.reduce(
        FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
      )
      guard actions is [PersistSource(latest)] else {
        fail("one latest follow-up")
      }
      assert_eq(latest.document.id(), operation.document.id())
      let (unchanged, duplicate) = next.reduce(
        FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
      )
      assert_true(unchanged == next)
      assert_true(duplicate.is_empty())
      let (next, actions) = next.reduce(
        FeedbackReceived(SaveCompleted(latest, Stored(latest.document))),
      )
      assert_true(actions.is_empty())
      documents = next
    }
    assert_eq(
      documents.snapshot().find(document_id("one")).unwrap().text(),
      "latest one",
    )
    assert_eq(
      documents.snapshot().find(document_id("two")).unwrap().text(),
      "latest two",
    )
  }
}

///|
test "hidden flush defers composition and does not retry a failed document" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    TextChanged(source_key("two"), "failed two"),
  )
  let (documents, actions) = documents.reduce(VisibilityFlushAll)
  let operation = visibility_save(actions, "two")
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "composing one"),
  )
  let (documents, actions) = documents.reduce(VisibilityFlushAll)
  assert_true(actions.is_empty())
  assert_true(documents.is_composing(source_key("one")))
  assert_true(
    documents.save_status(source_key("two")) == Some(SaveFailed(WriteFailed)),
  )
  let (unchanged, actions) = documents.reduce(VisibilityFlushAll)
  assert_true(unchanged == documents)
  assert_true(actions.is_empty())
  let (documents, actions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard actions is [PersistSource(committed)] else {
    fail("composition-end save")
  }
  assert_eq(committed.document.text(), "composing one")
  assert_true(
    documents.save_status(source_key("two")) == Some(SaveFailed(WriteFailed)),
  )
}
