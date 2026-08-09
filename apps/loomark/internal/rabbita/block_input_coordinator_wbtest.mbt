///|
priv struct BlockInputTestContext {
  editor : @markdown.MarkdownEditor
  attachment : @md_markdown.MarkdownSemanticAttachment
  document_id : @archive.LoomarkDocumentId
  node_id : @markdown.MarkdownNodeId
}

///|
fn block_input_test_document_id(value : String) -> @archive.LoomarkDocumentId {
  @archive.LoomarkDocumentId::from_string(value) catch {
    _ => abort("test document id must construct")
  }
}

///|
fn BlockInputTestContext::BlockInputTestContext(
  agent_id : String,
  source : String,
) -> BlockInputTestContext {
  let (editor, attachment) = try! @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id~,
    source~,
  )
  let node_id = (try! editor.snapshot()).blocks()[0].node_id()
  {
    editor,
    attachment,
    document_id: block_input_test_document_id("test-document"),
    node_id,
  }
}

///|
fn BlockInputTestContext::input(
  self : BlockInputTestContext,
  text : String,
  selection : @dom_boundary.TextSelection,
) -> PendingBlockInput {
  PendingBlockInput::PendingBlockInput(
    document_id=self.document_id,
    expected_version=self.editor.version(),
    node_id=self.node_id,
    input_id="loomark-block-input",
    text~,
    selection~,
  )
}

///|
fn BlockInputTestContext::caret_input(
  self : BlockInputTestContext,
  text : String,
  offset : Int,
) -> PendingBlockInput {
  self.input(
    text,
    @dom_boundary.TextSelection(offset, offset, @dom_boundary.NoDirection),
  )
}

///|
/// Arm one editor failure so rejected inputs prove they never reached commit.
fn BlockInputTestContext::block_model_with_editor_failure(
  self : BlockInputTestContext,
  document_id : @archive.LoomarkDocumentId,
) -> DriverModel {
  {
    ..test_model(try! self.editor.snapshot(), self.editor.version()),
    state: @core.ApplicationState::ApplicationState(@core.Block),
    document_id,
    fail_next_editor_commit: true,
  }
}

///|
fn BlockInputTestContext::reduce(
  self : BlockInputTestContext,
  input : PendingBlockInput,
  model : DriverModel,
) -> (DriverModel, BlockInputState) {
  let coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let (state, schedule) = coordinator.state.val.enqueue(input)
  let (state, delivery) = state.flush(schedule)
  coordinator.state.val = state
  guard delivery is Some(delivery) else {
    abort("test input must be ready for delivery")
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(model))
  let (next, _) = try! update_editing(
    self.editor,
    self.attachment,
    RawInputCoordinator::RawInputCoordinator(None),
    coordinator,
    model,
    latest_model,
    BlockInput(token=delivery.token, input=delivery.input),
    emit,
  )
  (next, coordinator.state.val)
}

///|
fn assert_block_input_rejected(
  next : DriverModel,
  previous : DriverModel,
  source : String,
) -> Unit raise {
  assert_eq(next.document.source(), source)
  assert_eq(next.document_id, previous.document_id)
  assert_eq(next.document_version, previous.document_version)
  assert_eq(next.source_revision, previous.source_revision)
  assert_eq(next.committed_change_count, previous.committed_change_count)
  assert_eq(next.text_input_generation, previous.text_input_generation)
  assert_eq(next.selection, previous.selection)
  assert_true(next.fail_next_editor_commit)
}

///|
fn assert_block_delivery_finished(state : BlockInputState) -> Unit {
  guard state.pending is None else {
    fail("a finished Block delivery must not retain pending input")
  }
  guard state.in_flight is None else {
    fail("a finished Block delivery must not remain active")
  }
}

///|
test "Block input batching keeps the latest input and ignores an old schedule" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-batching-test", "x",
  )
  let version = context.editor.version()
  let (state, first_schedule) = BlockInputState::BlockInputState().enqueue(
    context.caret_input("a", 1),
  )
  let (state, latest_schedule) = state.enqueue(context.caret_input("ab", 2))

  let (state, old_delivery) = state.flush(first_schedule)
  guard old_delivery is None else {
    fail("an old schedule must not deliver superseded input")
  }
  let (_, latest_delivery) = state.flush(latest_schedule)
  guard latest_delivery is Some(delivery) else {
    fail("the latest schedule must deliver one input")
  }
  assert_eq(delivery.input.document_id, context.document_id)
  assert_eq(delivery.input.expected_version, version)
  assert_eq(delivery.input.node_id, context.node_id)
  assert_eq(delivery.input.input_id, "loomark-block-input")
  assert_eq(delivery.input.text, "ab")
  assert_eq(delivery.input.selection.start(), 2)
  assert_eq(delivery.input.selection.end(), 2)
}

///|
test "Block input batching keeps the pending value through redraw and never retries it" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-display-test", "x",
  )
  let other_document_id = block_input_test_document_id("other-document")
  let version = context.editor.version()
  let (state, schedule) = BlockInputState::BlockInputState().enqueue(
    context.caret_input("ab", 2),
  )

  assert_eq(
    state.display_text(
      document_id=context.document_id,
      version~,
      node_id=context.node_id,
      input_id="loomark-block-input",
      committed_text="x",
    ),
    "ab",
  )
  assert_eq(
    state.display_text(
      document_id=other_document_id,
      version~,
      node_id=context.node_id,
      input_id="loomark-block-input",
      committed_text="x",
    ),
    "x",
  )

  let (state, delivery) = state.flush(schedule)
  guard delivery is Some(delivery) else {
    fail("the latest schedule must deliver one input")
  }
  assert_eq(
    state.display_text(
      document_id=context.document_id,
      version~,
      node_id=context.node_id,
      input_id="loomark-block-input",
      committed_text="x",
    ),
    "ab",
  )

  let (state, resumed) = state.finish(delivery.token)
  guard resumed is None else {
    fail("finishing with no pending input must not schedule another delivery")
  }
  assert_eq(
    state.display_text(
      document_id=context.document_id,
      version~,
      node_id=context.node_id,
      input_id="loomark-block-input",
      committed_text="x",
    ),
    "x",
  )
  let (_, retried) = state.flush(schedule)
  guard retried is None else {
    fail("a finished Block input must not be retried")
  }
}

///|
test "Block input batching waits for an active delivery before releasing newer input" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-in-flight-test", "x",
  )
  let (state, first_schedule) = BlockInputState::BlockInputState().enqueue(
    context.caret_input("a", 1),
  )
  let (state, first_delivery) = state.flush(first_schedule)
  guard first_delivery is Some(first_delivery) else {
    fail("the first input must be delivered")
  }
  assert_true(state.is_active(first_delivery.token))

  let (state, second_schedule) = state.enqueue(context.caret_input("ab", 2))
  assert_false(state.is_active(first_delivery.token))
  let (state, early_delivery) = state.flush(second_schedule)
  guard early_delivery is None else {
    fail("newer input must wait while the first delivery is active")
  }

  let (state, resumed_schedule) = state.finish(first_delivery.token)
  guard resumed_schedule is Some(resumed_schedule) else {
    fail("finishing the active delivery must resume pending input")
  }
  let (_, second_delivery) = state.flush(resumed_schedule)
  guard second_delivery is Some(second_delivery) else {
    fail("the resumed schedule must deliver the latest input")
  }
  assert_eq(second_delivery.input.text, "ab")
  assert_eq(second_delivery.input.selection.start(), 2)
  assert_eq(second_delivery.input.selection.end(), 2)
}

///|
test "Block input cancellation cannot collide with an emitted delivery" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-cancel-test", "x",
  )
  let (state, old_schedule) = BlockInputState::BlockInputState().enqueue(
    context.caret_input("a", 1),
  )
  let (state, old_delivery) = state.flush(old_schedule)
  guard old_delivery is Some(old_delivery) else {
    fail("the old input must be emitted before cancellation")
  }

  let (state, new_schedule) = state
    .cancel()
    .enqueue(context.caret_input("b", 1))
  let (state, new_delivery) = state.flush(new_schedule)
  guard new_delivery is Some(new_delivery) else {
    fail("new input must be deliverable after cancellation")
  }

  assert_false(state.is_active(old_delivery.token))
  assert_true(state.is_active(new_delivery.token))
  let (state, retry) = state.finish(old_delivery.token)
  guard retry is None else {
    fail("an old emitted delivery must not schedule anything")
  }
  assert_true(state.is_active(new_delivery.token))
}

///|
test "Fatal-state rejection cancels active Block input" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "fatal-rejection-block-input-test", "x",
  )
  let model = {
    ..context.block_model_with_editor_failure(context.document_id),
    fatal: true,
  }
  let coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let (state, schedule) = coordinator.state.val.enqueue(
    context.caret_input("xy", 2),
  )
  let (state, delivery) = state.flush(schedule)
  coordinator.state.val = state
  guard delivery is Some(delivery) else {
    fail("the Block input must be active before fatal rejection")
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(model))

  let (next, _) = try! update_model(
    context.editor,
    context.attachment,
    RawInputCoordinator::RawInputCoordinator(None),
    coordinator,
    model,
    latest_model,
    Editing(BlockInput(token=delivery.token, input=delivery.input)),
    emit,
  )

  assert_true(next.fatal)
  assert_eq(next.document.source(), "x")
  assert_eq(next.document_version, model.document_version)
  assert_eq(next.source_revision, model.source_revision)
  assert_eq(next.committed_change_count, model.committed_change_count)
  assert_true(next.fail_next_editor_commit)
  assert_eq(next.rejection, Some("operation=block-input;reason=fatal-state"))
  assert_false(coordinator.state.val.is_active(delivery.token))
  assert_true(coordinator.state.val.pending is None)
  assert_true(coordinator.state.val.in_flight is None)
  assert_eq(
    coordinator.display_text(
      document_id=context.document_id,
      version=context.editor.version(),
      node_id=context.node_id,
      input_id="loomark-block-input",
      committed_text="x",
    ),
    "x",
  )
}

///|
test "Entering fatal state cancels pending and active Block input" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "fatal-transition-block-input-test", "x",
  )
  let model = {
    ..test_model(try! context.editor.snapshot(), context.editor.version()),
    state: @core.ApplicationState::ApplicationState(@core.Block),
    document_id: context.document_id,
  }
  let coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let (state, active_schedule) = coordinator.state.val.enqueue(
    context.caret_input("xy", 2),
  )
  let (state, active_delivery) = state.flush(active_schedule)
  guard active_delivery is Some(active_delivery) else {
    fail("the first Block input must be active before fatal transition")
  }
  let (state, pending_schedule) = state.enqueue(context.caret_input("xyz", 3))
  coordinator.state.val = state
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(model))

  let (next, _) = try! update_model(
    context.editor,
    context.attachment,
    RawInputCoordinator::RawInputCoordinator(None),
    coordinator,
    model,
    latest_model,
    Lifecycle(Fatal("boom")),
    emit,
  )

  assert_true(next.fatal)
  assert_eq(next.error, Some("boom"))
  assert_eq(next.document.source(), "x")
  assert_eq(next.document_version, model.document_version)
  assert_eq(next.source_revision, model.source_revision)
  assert_eq(next.committed_change_count, model.committed_change_count)
  assert_false(coordinator.state.val.is_active(active_delivery.token))
  assert_true(coordinator.state.val.pending is None)
  assert_true(coordinator.state.val.in_flight is None)
  let (_, delayed_delivery) = coordinator.state.val.flush(pending_schedule)
  guard delayed_delivery is None else {
    fail("a pre-fatal Block schedule must remain cancelled")
  }
}

///|
test "Block input check rejects a changed document or version before commit" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-check-test", "x",
  )
  let version = context.editor.version()
  let input = context.caret_input("ab", 2)

  guard check_block_edit(context.document_id, version, input) is Current else {
    fail("matching document and version must be current")
  }
  guard check_block_edit(
      block_input_test_document_id("other-document"),
      version,
      input,
    )
    is WrongDocument else {
    fail("a different active document must be rejected")
  }
  ignore(
    try! context.editor.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=0,
        delete_len=1,
        inserted="y",
      ),
    ),
  )
  guard check_block_edit(context.document_id, context.editor.version(), input)
    is StaleVersion else {
    fail("an advanced editor version must reject old input")
  }
}

///|
test "Stale Block input does not call the editor or change Session state" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "stale-block-input-test", "x",
  )
  let input = context.caret_input("ab", 2)
  ignore(
    try! context.editor.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=0,
        delete_len=1,
        inserted="y",
      ),
    ),
  )
  let model = context.block_model_with_editor_failure(context.document_id)

  let (next, state) = context.reduce(input, model)

  assert_block_input_rejected(next, model, "y")
  assert_block_delivery_finished(state)
}

///|
test "Block input from another document does not call the editor" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "wrong-document-block-input-test", "x",
  )
  let input = {
    ..context.caret_input("ab", 2),
    document_id: block_input_test_document_id("old-document"),
  }
  let active_document_id = block_input_test_document_id("active-document")
  let model = context.block_model_with_editor_failure(active_document_id)

  let (next, state) = context.reduce(input, model)

  assert_block_input_rejected(next, model, "x")
  assert_block_delivery_finished(state)
}

///|
test "Block input selection requires one collapsed grapheme boundary" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "block-input-selection-test", "a😀b",
  )
  let document = try! context.editor.snapshot()

  guard check_block_selection(document, context.caret_input("a😀b", 1))
    is ValidBlockSelection else {
    fail("a collapsed grapheme boundary must be valid")
  }
  guard check_block_selection(
      document,
      context.input(
        "a😀b",
        @dom_boundary.TextSelection(1, 3, @dom_boundary.Forward),
      ),
    )
    is NonCollapsedBlockSelection else {
    fail("a range selection must be unavailable")
  }
  guard check_block_selection(document, context.caret_input("a😀b", 2))
    is InvalidBlockSelection else {
    fail("a position inside a grapheme must be invalid")
  }
}

///|
test "Invalid Block selection does not call the editor" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "invalid-block-selection-test", "a😀b",
  )
  let model = context.block_model_with_editor_failure(context.document_id)

  let (next, state) = context.reduce(context.caret_input("a😀b", 2), model)

  assert_block_input_rejected(next, model, "a😀b")
  assert_block_delivery_finished(state)
}

///|
test "Accepted snapshot restore cancels pending Block input" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "snapshot-cancels-block-input-test", "x",
  )
  let model = {
    ..test_model(try! context.editor.snapshot(), context.editor.version()),
    state: @core.ApplicationState::ApplicationState(@core.Block),
    document_id: context.document_id,
  }
  let coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let (state, old_schedule) = coordinator.state.val.enqueue(
    context.caret_input("xy", 2),
  )
  coordinator.state.val = state
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)

  let (next, _) = try! update_lifecycle(
    context.editor,
    context.attachment,
    RawInputCoordinator::RawInputCoordinator(None),
    coordinator,
    model,
    RestoreSnapshot(version=1, source="x", mode=@core.Block),
    emit,
  )

  assert_eq(next.document.source(), "x")
  assert_true(next.state.mode() == @core.Block)
  assert_block_delivery_finished(coordinator.state.val)
  let (_, old_delivery) = coordinator.state.val.flush(old_schedule)
  guard old_delivery is None else {
    fail("a pre-restore Block schedule must remain cancelled")
  }
}

///|
test "Failed current Block input preserves committed Session state" {
  let context = BlockInputTestContext::BlockInputTestContext(
    "failed-block-input-test", "x",
  )
  let model = {
    ..context.block_model_with_editor_failure(context.document_id),
    selection: Some("before"),
  }

  let (next, state) = context.reduce(context.caret_input("y", 1), model)

  assert_eq((try! context.editor.snapshot()).source(), "x")
  assert_eq(context.editor.version(), model.document_version)
  assert_eq(next.document.source(), "x")
  assert_eq(next.document_version, model.document_version)
  assert_eq(next.source_revision, model.source_revision)
  assert_eq(next.committed_change_count, model.committed_change_count)
  assert_eq(next.text_input_generation, model.text_input_generation)
  assert_eq(next.selection, Some("before"))
  assert_false(next.fail_next_editor_commit)
  assert_block_delivery_finished(state)
}
