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
  let start = rejected_text_offset(
    accepted_source,
    rejected_source,
    selection.start(),
  )
  let end = rejected_text_offset(
    accepted_source,
    rejected_source,
    selection.end(),
  ).clamp(min=start, max=accepted_source.length())
  @dom_boundary.TextSelection(start, end, selection.direction())
}

///|
/// Capture the live Raw selection before the accepted model may need to repair
/// a rejected controlled value on the same textarea node.
fn raw_input_command(
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let selection = @dom_boundary.read_text_selection_id("loomark-input") catch {
      error => {
        scheduler.add(emit(Navigation(EffectFailed(error.message()))))
        return
      }
    }
    scheduler.add(emit(Editing(RawInput(source, Some(selection)))))
  })
}

///|
/// Capture the DOM text cursor before the controlled textarea is rendered again.
fn block_input_command(
  block : @markdown.MarkdownBlockSnapshot,
  input_id : String,
  text : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let selection = @dom_boundary.read_text_selection_id(input_id) catch {
      error => {
        scheduler.add(emit(Navigation(EffectFailed(error.message()))))
        return
      }
    }
    scheduler.add(
      emit(
        Editing(
          BlockInput(
            node_id=block.node_id(),
            input_id~,
            text~,
            selection_offset=selection.end(),
          ),
        ),
      ),
    )
  })
}
