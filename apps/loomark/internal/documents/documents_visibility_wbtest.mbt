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
  let documents = Model::Model(documents_test_snapshot())
  let (documents, deletion) = match documents.delete((source_key("one"))) {
  Accepted(transition) => (documents, transition.effects),
  AlreadyPending => fail("unexpected pending deletion")
}
  guard deletion is [DeleteSource(_)] else { fail("active deletion") }
  let before = documents.delete_phase_status(source_key("one"))
  let (documents, _) = match documents.edit(source_key("two"), "two!") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_eq(actions.length(), 1)
  let operation = visibility_save(actions, "two")
  assert_eq(operation.document.text(), "two!")
  assert_true(documents.delete_phase_status(source_key("one")) == before)
}

///|
test "hidden flush starts all waiting documents once and accepts reverse acknowledgments" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "one!") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, _) = match documents.edit(source_key("two"), "two!") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_eq(actions.length(), 2)
  let first = visibility_save(actions, "one")
  let second = visibility_save(actions, "two")
  let (unchanged, repeated) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(unchanged == documents)
  assert_true(repeated.is_empty())
  let (documents, follow_up) = match documents.update(FeedbackReceived(SaveCompleted(second, Stored(second.document))),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(follow_up.is_empty())
  let (documents, follow_up) = match documents.update(FeedbackReceived(SaveCompleted(first, Stored(first.document))),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
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
    let documents = Model::Model(documents_test_snapshot())
    let (documents, _) = match documents.edit(source_key("one"), "first one")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
    let (documents, _) = match documents.edit(source_key("two"), "first two")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
    let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
    let first = visibility_save(actions, "one")
    let second = visibility_save(actions, "two")
    let (documents, _) = match documents.edit(source_key("one"), "latest one")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
    let (documents, _) = match documents.edit(source_key("two"), "latest two")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
    let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
    assert_true(actions.is_empty())
    let (unchanged, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
    assert_true(unchanged == documents)
    assert_true(actions.is_empty())
    let order = if reverse { [second, first] } else { [first, second] }
    let mut documents = documents
    for operation in order {
      let (next, actions) = match documents.update(FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
      guard actions is [PersistSource(latest)] else {
        fail("one latest follow-up")
      }
      assert_eq(latest.document.id(), operation.document.id())
      let (unchanged, duplicate) = match next.update(FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),) {
  Applied(transition) => (next, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
      assert_true(unchanged == next)
      assert_true(duplicate.is_empty())
      let (next, actions) = match next.update(FeedbackReceived(SaveCompleted(latest, Stored(latest.document))),) {
  Applied(transition) => (next, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
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
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("two"), "failed two")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  let operation = visibility_save(actions, "two")
  let (documents, _) = match documents.update(FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  let (documents, _) = match documents.update(CompositionStarted(source_key("one"))) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  let (documents, _) = match documents.edit(source_key("one"), "composing one")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(actions.is_empty())
  assert_true(documents.is_composing(source_key("one")))
  assert_true(
    documents.save_status(source_key("two")) == Some(SaveFailed(WriteFailed)),
  )
  let (unchanged, actions) = match documents.update(VisibilityFlushAll) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(unchanged == documents)
  assert_true(actions.is_empty())
  let (documents, actions) = match documents.update(CompositionEnded(source_key("one")),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  guard actions is [PersistSource(committed)] else {
    fail("composition-end save")
  }
  assert_eq(committed.document.text(), "composing one")
  assert_true(
    documents.save_status(source_key("two")) == Some(SaveFailed(WriteFailed)),
  )
}
