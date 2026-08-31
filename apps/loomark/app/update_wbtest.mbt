///|
fn test_repository() -> @source_repository.RepositorySnapshot {
  @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Old\n").unwrap(),
  ]).unwrap()
}

///|
fn test_preview_state(text : String) -> @preview.State {
  let engine = @preview.PreviewEngine::PreviewEngine()
  let (state, _) = engine.activate(@preview.Input(0, text))
  state
}

///|
fn test_checkpoint(
  epoch? : Int = 1,
  quiet_revision? : Int = 1,
  eligibility? : CheckpointEligibility = Deferred,
) -> Checkpoint {
  { epoch, quiet_revision, eligibility }
}

///|
fn test_editing_state(text : String, save : SaveState) -> EditingState {
  {
    activation: { document_id: "document-1", generation: 0 },
    text,
    composing: false,
    save,
    last_checkpoint_epoch: 0,
    creation: Idle,
    mode: Text,
    compact: false,
    preview: test_preview_state(text),
    repository: test_repository(),
  }
}

///|
fn test_update(model : Model, msg : Msg) -> (Model, @cmd.Cmd) {
  update(
    model,
    msg,
    @cmd.Emit(_ => @cmd.none),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
}

///|
fn test_update_with_messages(
  model : Model,
  msg : Msg,
) -> (Model, @cmd.Cmd, Array[Msg]) {
  let messages : Array[Msg] = []
  let (model, command) = update(
    model,
    msg,
    @cmd.Emit(message => {
      messages.push(message)
      @cmd.none
    }),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
  (model, command, messages)
}

///|
test "opened snapshot installs repository" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-b", "# B\n").unwrap(),
    @source_repository.SourceRecord::new("document-a", "# A\n").unwrap(),
  ]).unwrap()
  let (model, _) = test_update(
    Loading(false),
    Opened(@source_repository.OpenResult::Ready(snapshot)),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.activation.document_id, "document-a")
  assert_eq(editing.repository, snapshot)
}

///|
test "saved document selection activates its exact Source without writing" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# First\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Second\n").unwrap(),
  ]).unwrap()
  let initial = {
    ..test_editing_state("# First\n", Saved),
    repository: snapshot,
  }
  let (model, command) = test_update(
    Editing(initial),
    DocumentSelected("document-2"),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.activation.document_id, "document-2")
  assert_eq(editing.activation.generation, 1)
  assert_eq(editing.text, "# Second\n")
  assert_true(editing.save == Saved)
  assert_true(editing.preview == test_preview_state("# Second\n"))
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "stale activation cannot change current text" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    activation: { document_id: "document-1", generation: 1 },
  }
  let stale : Activation = { document_id: "document-1", generation: 0 }
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(stale, @text_change.TextChange::ReplaceAll("# Stale\n")),
  )
  assert_true(model == Editing(initial))
}

///|
test "TextChanged remains free of repository IO" {
  let (model, command, messages) = test_update_with_messages(
    Editing(test_editing_state("# Old\n", Saved)),
    TextChanged(
      { document_id: "document-1", generation: 0 },
      @text_change.TextChange::ReplaceAll("# New\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.text, "# New\n")
  assert_true(editing.save == Waiting(test_checkpoint()))
  assert_eq(editing.last_checkpoint_epoch, 1)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
  assert_eq(messages.length(), 2)
  guard messages[0] is QuietElapsed(_, 1, 1) else {
    fail("expected quiet timer message")
  }
  guard messages[1] is MaximumElapsed(_, 1) else {
    fail("expected maximum timer message")
  }
}

///|
test "missing active Source fails closed instead of publishing Saved" {
  let repository = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-other", "# New\n").unwrap(),
  ]).unwrap()
  let initial = { ..test_editing_state("# Old\n", Saved), repository, }
  let (model, _, messages) = test_update_with_messages(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# New\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Waiting(test_checkpoint()))
  assert_false(can_activate(editing))
  assert_eq(messages.length(), 2)
}

///|
test "later deferred edit re-arms quiet without restarting maximum" {
  let initial = {
    ..test_editing_state("# Draft\n", Waiting(test_checkpoint())),
    last_checkpoint_epoch: 1,
  }
  let (model, _, messages) = test_update_with_messages(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Latest\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Waiting(test_checkpoint(quiet_revision=2)))
  assert_eq(editing.last_checkpoint_epoch, 1)
  assert_eq(messages.length(), 1)
  guard messages[0] is QuietElapsed(_, 1, 2) else {
    fail("expected only the latest quiet message")
  }
}

///|
test "exact acknowledged revert becomes Saved without another write" {
  let initial = {
    ..test_editing_state("# Draft\n", Waiting(test_checkpoint())),
    last_checkpoint_epoch: 1,
  }
  let (model, command) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Old\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_eq(editing.text, "# Old\n")
  assert_eq(editing.last_checkpoint_epoch, 1)
  assert_true(can_activate(editing))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
  assert_false(@debug.to_string(command).contains("QuietElapsed"))
}

///|
test "exact in-flight revert removes pending checkpoint" {
  let initial = {
    ..test_editing_state(
      "# Draft\n",
      Saving("# Candidate\n", Some(test_checkpoint())),
    ),
    last_checkpoint_epoch: 1,
  }
  let (model, command) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Candidate\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# Candidate\n", None))
  assert_eq(editing.last_checkpoint_epoch, 1)
  assert_false(@debug.to_string(command).contains("QuietElapsed"))
}

///|
test "New Document serializes creation from a saved activation" {
  let initial = test_editing_state("# Current\n", Saved)
  let (model, command) = test_update(Editing(initial), CreateRequested)
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.creation == Creating)
  assert_true(editing.activation == initial.activation)
  assert_eq(editing.text, initial.text)
  assert_eq(editing.repository, initial.repository)
  assert_true(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "acknowledged creation installs the next Snapshot and activates baseline" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let next = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Current\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Untitled\n").unwrap(),
  ]).unwrap()
  let (model, command) = test_update(
    Editing(initial),
    CreateCompleted(
      initial.activation,
      @source_repository.CreateResult::Created(next, "document-2"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.activation.document_id, "document-2")
  assert_eq(editing.activation.generation, 1)
  assert_eq(editing.text, "# Untitled\n")
  assert_true(editing.save == Saved)
  assert_true(editing.creation == Idle)
  assert_eq(editing.repository, next)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "creation failure preserves the active document and Snapshot" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let (model, _) = test_update(
    Editing(initial),
    CreateCompleted(
      initial.activation,
      @source_repository.CreateResult::Failed(
        @source_repository.CreateFailure::QuotaExceeded,
      ),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.activation == initial.activation)
  assert_eq(editing.text, initial.text)
  assert_true(editing.save == initial.save)
  assert_true(
    editing.creation ==
    CreationFailed(@source_repository.CreateFailure::QuotaExceeded),
  )
  assert_true(editing.preview == initial.preview)
  assert_eq(editing.repository, initial.repository)
}

///|
test "unacknowledged text prevents switching and creation" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Waiting\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Other\n").unwrap(),
  ]).unwrap()
  let initial = {
    ..test_editing_state("# Waiting\n", Waiting(test_checkpoint())),
    repository: snapshot,
  }
  let (selected, _) = test_update(
    Editing(initial),
    DocumentSelected("document-2"),
  )
  let (created, _) = test_update(Editing(initial), CreateRequested)
  assert_true(selected == Editing(initial))
  assert_true(created == Editing(initial))
}

///|
test "queued text input cannot change a creating document" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Queued\n"),
    ),
  )
  assert_true(model == Editing(initial))
}

///|
test "current quiet uses the repository snapshot" {
  let initial = test_editing_state("# New\n", Waiting(test_checkpoint()))
  let (model, command) = test_update(
    Editing(initial),
    QuietElapsed(initial.activation, 1, 1),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# New\n", None))
  assert_true(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "quiet and maximum race starts exactly one write" {
  let initial = test_editing_state("# New\n", Waiting(test_checkpoint()))
  let (after_maximum, first_command) = test_update(
    Editing(initial),
    MaximumElapsed(initial.activation, 1),
  )
  guard after_maximum is Editing(saving_after_maximum) else {
    fail("expected Editing")
  }
  assert_true(saving_after_maximum.save == Saving("# New\n", None))
  assert_true(@debug.to_string(first_command).contains("IndexedDBPut"))
  let (after_stale_quiet, second_command) = test_update(
    after_maximum,
    QuietElapsed(initial.activation, 1, 1),
  )
  assert_true(after_stale_quiet == after_maximum)
  assert_false(@debug.to_string(second_command).contains("IndexedDBPut"))

  let (after_quiet, reverse_first) = test_update(
    Editing(initial),
    QuietElapsed(initial.activation, 1, 1),
  )
  guard after_quiet is Editing(saving_after_quiet) else {
    fail("expected Editing")
  }
  assert_true(saving_after_quiet.save == Saving("# New\n", None))
  assert_true(@debug.to_string(reverse_first).contains("IndexedDBPut"))
  let (after_stale_maximum, reverse_second) = test_update(
    after_quiet,
    MaximumElapsed(initial.activation, 1),
  )
  assert_true(after_stale_maximum == after_quiet)
  assert_false(@debug.to_string(reverse_second).contains("IndexedDBPut"))
}

///|
test "stale epoch and quiet revision cannot start a write" {
  let checkpoint = test_checkpoint(epoch=2)
  let initial = {
    ..test_editing_state("# Latest\n", Waiting(checkpoint)),
    last_checkpoint_epoch: 2,
  }
  let (after_old_maximum, maximum_command) = test_update(
    Editing(initial),
    MaximumElapsed(initial.activation, 1),
  )
  let (after_old_quiet, quiet_command) = test_update(
    Editing(initial),
    QuietElapsed(initial.activation, 2, 0),
  )
  assert_true(after_old_maximum == Editing(initial))
  assert_true(after_old_quiet == Editing(initial))
  assert_false(@debug.to_string(maximum_command).contains("IndexedDBPut"))
  assert_false(@debug.to_string(quiet_command).contains("IndexedDBPut"))
}

///|
test "hidden eligibility is fenced and single-flight" {
  let checkpoint = test_checkpoint()
  let waiting = test_editing_state("# Latest\n", Waiting(checkpoint))
  let (hidden, hidden_command) = test_update(
    Editing(waiting),
    VisibilityChanged(true),
  )
  guard hidden is Editing(hidden_editing) else { fail("expected Editing") }
  assert_true(hidden_editing.save == Saving("# Latest\n", None))
  assert_true(@debug.to_string(hidden_command).contains("IndexedDBPut"))

  let (visible, visible_command) = test_update(
    Editing(waiting),
    VisibilityChanged(false),
  )
  assert_true(visible == Editing(waiting))
  assert_false(@debug.to_string(visible_command).contains("IndexedDBPut"))

  let active = test_editing_state(
    "# Latest\n",
    Saving("# Old\n", Some(checkpoint)),
  )
  let (eligible, active_command) = test_update(
    Editing(active),
    VisibilityChanged(true),
  )
  guard eligible is Editing(active_editing) else { fail("expected Editing") }
  assert_true(
    active_editing.save ==
    Saving("# Old\n", Some(test_checkpoint(eligibility=Eligible))),
  )
  assert_false(@debug.to_string(active_command).contains("IndexedDBPut"))

  let saved = test_editing_state("# Old\n", Saved)
  let (without_pending, no_pending_command) = test_update(
    Editing(saved),
    VisibilityChanged(true),
  )
  assert_true(without_pending == Editing(saved))
  assert_false(@debug.to_string(no_pending_command).contains("IndexedDBPut"))
}

///|
test "successful save installs returned snapshot" {
  let initial = test_editing_state("# New\n", Saving("# New\n", None))
  let next = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# New\n").unwrap(),
  ]).unwrap()
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# New\n",
      @source_repository.SaveResult::Stored(next),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_eq(editing.repository, next)
}

///|
test "stale completion remains fenced by activation and candidate" {
  let initial = {
    ..test_editing_state("# Latest\n", Saving("# Latest\n", None)),
    activation: { document_id: "document-1", generation: 1 },
  }
  let stale : Activation = { document_id: "document-1", generation: 0 }
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      stale,
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  assert_true(model == Editing(initial))
}

///|
test "completion behind deferred text waits without another write" {
  let checkpoint = test_checkpoint()
  let initial = test_editing_state(
    "# Latest\n",
    Saving("# Old\n", Some(checkpoint)),
  )
  let (model, command) = test_update(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Waiting(checkpoint))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "completion without pending state allocates a fenced checkpoint" {
  let initial = {
    ..test_editing_state("# Latest\n", Saving("# Old\n", None)),
    last_checkpoint_epoch: 1,
  }
  let (model, command, messages) = test_update_with_messages(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Waiting(test_checkpoint(epoch=2)))
  assert_eq(editing.last_checkpoint_epoch, 2)
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
  assert_eq(messages.length(), 2)
  guard messages[0] is QuietElapsed(_, 2, 1) else {
    fail("expected defensive quiet timer")
  }
  guard messages[1] is MaximumElapsed(_, 2) else {
    fail("expected defensive maximum timer")
  }
}

///|
test "completion promotes one eligible latest checkpoint" {
  let checkpoint = test_checkpoint(eligibility=Eligible)
  let initial = test_editing_state(
    "# Latest\n",
    Saving("# Old\n", Some(checkpoint)),
  )
  let completion = SaveCompleted(
    initial.activation,
    "# Old\n",
    @source_repository.SaveResult::Stored(test_repository()),
  )
  let (model, command) = test_update(Editing(initial), completion)
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# Latest\n", None))
  assert_true(@debug.to_string(command).contains("IndexedDBPut"))
  let (after_duplicate, duplicate_command) = test_update(model, completion)
  assert_true(after_duplicate == model)
  assert_false(@debug.to_string(duplicate_command).contains("IndexedDBPut"))
}

///|
test "composition commit arms one deferred checkpoint after ending" {
  let initial = { ..test_editing_state("# Old\n", Saved), composing: true }
  let (changed, change_command, change_messages) = test_update_with_messages(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Committed\n"),
    ),
  )
  guard changed is Editing(composing) else { fail("expected Editing") }
  assert_true(composing.save == Waiting(test_checkpoint()))
  assert_true(change_messages.is_empty())
  assert_false(@debug.to_string(change_command).contains("IndexedDBPut"))
  let (ended, _, end_messages) = test_update_with_messages(
    changed,
    CompositionEnded(initial.activation),
  )
  guard ended is Editing(editing) else { fail("expected Editing") }
  assert_false(editing.composing)
  assert_true(editing.save == Waiting(test_checkpoint()))
  assert_eq(end_messages.length(), 2)
  guard end_messages[0] is QuietElapsed(_, 1, 1) else {
    fail("expected composition quiet timer")
  }
  guard end_messages[1] is MaximumElapsed(_, 1) else {
    fail("expected composition maximum timer")
  }
}

///|
test "maximum during composition persists the committed text after ending" {
  let initial = {
    ..test_editing_state("# Committed\n", Waiting(test_checkpoint())),
    composing: true,
  }
  let (eligible, maximum_command) = test_update(
    Editing(initial),
    MaximumElapsed(initial.activation, 1),
  )
  guard eligible is Editing(waiting) else { fail("expected Editing") }
  assert_true(waiting.save == Waiting(test_checkpoint(eligibility=Eligible)))
  assert_false(@debug.to_string(maximum_command).contains("IndexedDBPut"))
  let (ended, persist_command) = test_update(
    eligible,
    CompositionEnded(initial.activation),
  )
  guard ended is Editing(saving) else { fail("expected Editing") }
  assert_true(saving.save == Saving("# Committed\n", None))
  assert_true(@debug.to_string(persist_command).contains("IndexedDBPut"))
}

///|
test "composition end keeps eligible pending behind the active write" {
  let checkpoint = test_checkpoint(eligibility=Eligible)
  let initial = {
    ..test_editing_state("# Latest\n", Saving("# Old\n", Some(checkpoint))),
    composing: true,
  }
  let (model, command) = test_update(
    Editing(initial),
    CompositionEnded(initial.activation),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_false(editing.composing)
  assert_true(editing.save == Saving("# Old\n", Some(checkpoint)))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "active completion retains eligible text until composition ends" {
  let checkpoint = test_checkpoint(eligibility=Eligible)
  let initial = {
    ..test_editing_state("# Latest\n", Saving("# Old\n", Some(checkpoint))),
    composing: true,
  }
  let (completed, completion_command) = test_update(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  guard completed is Editing(waiting) else { fail("expected Editing") }
  assert_true(waiting.save == Waiting(checkpoint))
  assert_false(@debug.to_string(completion_command).contains("IndexedDBPut"))
  let (ended, persist_command) = test_update(
    completed,
    CompositionEnded(initial.activation),
  )
  guard ended is Editing(saving) else { fail("expected Editing") }
  assert_true(saving.save == Saving("# Latest\n", None))
  assert_true(@debug.to_string(persist_command).contains("IndexedDBPut"))
}

///|
test "failure handling and foreign completion preserve active state" {
  let initial = test_editing_state("# New\n", Saving("# New\n", None))
  let (failed, _) = test_update(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# New\n",
      @source_repository.SaveResult::Failed(
        @source_repository.SaveFailure::WriteFailed,
      ),
    ),
  )
  guard failed is Editing(editing) else { fail("expected Editing") }
  assert_true(
    editing.save == Failed(@source_repository.SaveFailure::WriteFailed, false),
  )
  let (foreign, _) = test_update(
    Editing(initial),
    SaveCompleted(
      { document_id: "document-2", generation: 0 },
      "# New\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  assert_true(foreign == Editing(initial))
}

///|
test "edits after failure require explicit retry" {
  let failure = @source_repository.SaveFailure::WriteFailed
  let initial = test_editing_state("# Failed\n", Failed(failure, false))
  let (model, command, messages) = test_update_with_messages(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Latest\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.text, "# Latest\n")
  assert_true(editing.save == Failed(failure, false))
  assert_true(messages.is_empty())
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "retry during composition persists only the committed result" {
  let failure = @source_repository.SaveFailure::WriteFailed
  let initial = {
    ..test_editing_state("# Failed\n", Failed(failure, false)),
    composing: true,
  }
  let (deferred, retry_command) = test_update(Editing(initial), RetrySave)
  guard deferred is Editing(retrying) else { fail("expected Editing") }
  assert_true(retrying.save == Failed(failure, true))
  assert_false(@debug.to_string(retry_command).contains("IndexedDBPut"))
  let (changed, _) = test_update(
    deferred,
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Committed\n"),
    ),
  )
  guard changed is Editing(committed) else { fail("expected Editing") }
  assert_true(committed.save == Failed(failure, true))
  let (ended, persist_command) = test_update(
    changed,
    CompositionEnded(initial.activation),
  )
  guard ended is Editing(saving) else { fail("expected Editing") }
  assert_eq(saving.text, "# Committed\n")
  assert_true(saving.save == Saving("# Committed\n", None))
  assert_true(@debug.to_string(persist_command).contains("IndexedDBPut"))
}

///|
test "same-document stale success and failure cannot replace active save" {
  let initial = test_editing_state("# Latest\n", Saving("# Latest\n", None))
  let stale_success = SaveCompleted(
    initial.activation,
    "# Old\n",
    @source_repository.SaveResult::Stored(test_repository()),
  )
  let stale_failure = SaveCompleted(
    initial.activation,
    "# Old\n",
    @source_repository.SaveResult::Failed(
      @source_repository.SaveFailure::WriteFailed,
    ),
  )
  let (after_success, _) = test_update(Editing(initial), stale_success)
  let (after_failure, _) = test_update(Editing(initial), stale_failure)
  assert_true(after_success == Editing(initial))
  assert_true(after_failure == Editing(initial))
}

///|
test "old equal-text quiet timer cannot satisfy a later ABA edit" {
  let initial = test_editing_state("# Old\n", Saved)
  let (after_first, _) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# B\n"),
    ),
  )
  let (after_middle, _) = test_update(
    after_first,
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# C\n"),
    ),
  )
  let (after_aba, _) = test_update(
    after_middle,
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# B\n"),
    ),
  )
  let (after_old_quiet, command) = test_update(
    after_aba,
    QuietElapsed(initial.activation, 1, 1),
  )
  guard after_old_quiet is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Waiting(test_checkpoint(quiet_revision=3)))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "failed attempt exact acknowledged revert is truthfully Saved" {
  let failure = @source_repository.SaveFailure::WriteFailed
  let initial = test_editing_state("# Unsaved\n", Failed(failure, false))
  let (model, command) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Old\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_true(can_activate(editing))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "active failure after acknowledged revert is truthfully Saved" {
  let initial = test_editing_state("# Old\n", Saving("# Unsaved\n", None))
  let (model, command) = test_update(
    Editing(initial),
    SaveCompleted(
      initial.activation,
      "# Unsaved\n",
      @source_repository.SaveResult::Failed(
        @source_repository.SaveFailure::WriteFailed,
      ),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_true(can_activate(editing))
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}
