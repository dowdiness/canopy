///|
/// Map one live offset from a rejected contiguous edit back into the accepted
/// text's UTF-16 coordinates.
fn rejected_text_offset(
  accepted_source : String,
  rejected_source : String,
  offset : Int,
) -> Int {
  let change = @text_change.compute_text_change(
    accepted_source, rejected_source,
  )
  let inserted_len = change.inserted.length()
  let inserted_end = change.start + inserted_len
  let mapped = if offset <= change.start {
    offset
  } else if offset >= inserted_end {
    offset - inserted_len + change.delete_len
  } else {
    change.start
  }
  mapped.clamp(min=0, max=accepted_source.length())
}

///|
/// Map a live selection from one rejected contiguous edit back into the
/// accepted source's UTF-16 coordinates.
fn rejected_text_selection(
  accepted_source : String,
  rejected_source : String,
  selection : @dom_boundary.TextSelection,
) -> @dom_boundary.TextSelection {
  let accepted_value = raw_textarea_value(accepted_source)
  let start = rejected_text_offset(
    accepted_value,
    rejected_source,
    selection.start(),
  )
  let end = rejected_text_offset(
    accepted_value,
    rejected_source,
    selection.end(),
  ).clamp(min=start, max=accepted_value.length())
  @dom_boundary.TextSelection(start, end, selection.direction())
}

///|
/// The preview worker is notified on the next scheduler turn.
const RAW_FAST_PREVIEW_MS : Int = 0

///|
/// The quiet period before the browser-owned Raw source is canonicalized.
const RAW_FAST_FLUSH_MS : Int = 250

///|
/// Browser-owned Raw draft state. Canonical source, parser, CRDT, projection,
/// and persistence remain outside this shell until an explicit flush event.
priv struct RawInputCoordinator {
  epoch : @ref.Ref[Int]
  draft_generation : @ref.Ref[UInt64]
  fast_source : @ref.Ref[String?]
  fast_composing : @ref.Ref[Bool]
  render_barrier_armed : @ref.Ref[Bool]
  render_barrier_waiting : @ref.Ref[Bool]
}

///|
fn RawInputCoordinator::RawInputCoordinator() -> RawInputCoordinator {
  {
    epoch: @ref.Ref(0),
    draft_generation: @ref.Ref(0UL),
    fast_source: @ref.Ref(None),
    fast_composing: @ref.Ref(false),
    render_barrier_armed: @ref.Ref(false),
    render_barrier_waiting: @ref.Ref(false),
  }
}

///|
fn RawInputCoordinator::epoch(self : RawInputCoordinator) -> Int {
  self.epoch.val
}

///|
fn RawInputCoordinator::advance_draft_generation(
  self : RawInputCoordinator,
) -> UInt64 {
  // A delayed Raw tick lives for at most one page-local scheduling window.
  // Resetting after UInt64::max is safe because producing 2^64 draft installs
  // before any such tick settles is physically unreachable.
  let next = if self.draft_generation.val == 0xFFFFFFFFFFFFFFFFUL {
    0UL
  } else {
    self.draft_generation.val + 1UL
  }
  self.draft_generation.val = next
  next
}

///|
fn RawInputCoordinator::install_fast_source(
  self : RawInputCoordinator,
  source : String,
) -> UInt64 {
  let generation = self.advance_draft_generation()
  self.fast_source.val = Some(source)
  generation
}

///|
fn RawInputCoordinator::set_fast_source(
  self : RawInputCoordinator,
  source : String,
) -> Unit {
  self.install_fast_source(source) |> ignore
}

///|
fn RawInputCoordinator::draft_is_current(
  self : RawInputCoordinator,
  generation : UInt64,
) -> Bool {
  self.draft_generation.val == generation
}

///|
fn RawInputCoordinator::fast_source_value(
  self : RawInputCoordinator,
) -> String? {
  self.fast_source.val
}

///|
fn RawInputCoordinator::begin_fast_composition(
  self : RawInputCoordinator,
) -> Unit {
  self.fast_composing.val = true
}

///|
fn RawInputCoordinator::finish_fast_composition(
  self : RawInputCoordinator,
) -> Unit {
  self.fast_composing.val = false
}

///|
fn RawInputCoordinator::fast_composing(self : RawInputCoordinator) -> Bool {
  self.fast_composing.val
}

///|
fn RawInputCoordinator::display_source(
  self : RawInputCoordinator,
  committed_source : String,
) -> String {
  match self.fast_source.val {
    Some(source) => raw_textarea_value(source)
    None => committed_source
  }
}

///|
/// Invalidate delayed DOM repairs and legacy direct-driver work without
/// changing the browser-owned draft. Authority transitions explicitly install
/// their accepted source after cancellation.
fn RawInputCoordinator::cancel_pending(self : RawInputCoordinator) -> Unit {
  self.epoch.val += 1
  self.advance_draft_generation() |> ignore
  self.fast_composing.val = false
}

///|
fn RawInputCoordinator::cancel_pending_for_navigation(
  self : RawInputCoordinator,
) -> Unit {
  self.cancel_pending()
}

///|
fn RawInputCoordinator::phase_json(self : RawInputCoordinator) -> Json? {
  ignore(self)
  None
}

///|
fn RawInputCoordinator::mark_publish_started(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  ignore(self)
  ignore(token)
}

///|
fn RawInputCoordinator::mark_publish_finished(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  ignore(self)
  ignore(token)
}

///|
fn RawInputCoordinator::arm_render_barrier(self : RawInputCoordinator) -> Unit {
  self.render_barrier_armed.val = true
}

///|
fn RawInputCoordinator::release_render_barrier(
  self : RawInputCoordinator,
) -> @cmd.Cmd {
  self.render_barrier_armed.val = false
  self.render_barrier_waiting.val = false
  @rabbita_runtime.none
}

///|
fn RawInputCoordinator::render_barrier_armed(
  self : RawInputCoordinator,
) -> Bool {
  self.render_barrier_armed.val
}

///|
fn RawInputCoordinator::render_barrier_waiting(
  self : RawInputCoordinator,
) -> Bool {
  self.render_barrier_waiting.val
}

///|
/// Capture the Block DOM selection before its controlled input is rendered.
fn block_input_command(
  block : @markdown.MarkdownBlockSnapshot,
  input_id : String,
  text : String,
  document_id : @archive.LoomarkDocumentId,
  expected_version : @markdown.MarkdownDocumentVersion,
  coordinator : BlockInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let selection = @dom_boundary.read_text_selection_id(input_id) catch {
    _ => return @rabbita_runtime.none
  }
  coordinator.enqueue(
    PendingBlockInput::PendingBlockInput(
      document_id~,
      expected_version~,
      node_id=block.node_id(),
      input_id~,
      text~,
      selection~,
    ),
    emit,
  )
}
