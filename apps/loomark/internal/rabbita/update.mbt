///|

///|
/// Archive completion channel: only a correlated acknowledgment can advance
/// the queue, and a promoted pending archive is the sole next command.
fn update_archive_queue(
  model : DriverModel,
  completion : @archive_storage.LocalArchiveWriteCompletion,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  let outcome = match completion.result() {
    @archive_storage.LocalArchiveStorageWrite::Stored =>
      @repository.LocalArchiveWriteOutcome::Stored
    @archive_storage.LocalArchiveStorageWrite::Failed(error) =>
      @repository.LocalArchiveWriteOutcome::Failed(error)
  }
  let (archive_queue, queue_completion) = model.archive_queue.complete(
    completion.pending(),
    outcome,
  )
  let command = match queue_completion {
    @repository.LocalArchiveQueueCompletion::Promoted(pending) =>
      local_archive_write_command(Some(pending), emit)
    _ => @rabbita_runtime.none
  }
  let event_detail = match queue_completion {
    @repository.LocalArchiveQueueCompletion::Ignored =>
      Some("archive-ack-ignored")
    _ => model.event_detail
  }
  ({ ..model, archive_queue, event_detail }, command)
}

///|
/// Mode gate for editing-surface events. ReplaceSource is deliberately
/// exempt: driver source replacement works in any mode. The split Preview
/// pairs the Raw textarea with the rendered Preview even while the Preview
/// tab is selected, so Raw input stays live there.
fn editing_mode_applicable(
  event : EditingEvent,
  mode : @core.ApplicationMode,
  split_preview_open : Bool,
) -> String? {
  match event {
    ReplaceSource(_) | ProbeBlockSelection(_) => None
    LocalTextInput(_)
    | RawFastPreview(_)
    | RawFastFlush(_, _)
    | RawInput(_, _)
    | RawSelectionEdit(_)
    | CommitCapturedRawSelection(_) =>
      if raw_draft_surface_live(mode, split_preview_open) {
        None
      } else {
        Some("Raw input is unavailable outside Raw mode")
      }
    BlockFocused(_)
    | BlockHeading(_, _)
    | BlockToggleList(_)
    | BlockDelete
    | BlockInput(..)
    | BlockSplit(..)
    | BlockMerge(..)
    | BlockNavigate(..) =>
      if mode == @core.Block {
        None
      } else {
        Some("Block editing is unavailable outside Block mode")
      }
  }
}

///|
/// Editing-surface dispatcher: mode-gated input and structural requests
/// through the atomic editor façade.
fn update_editing(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : EditingEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) raise {
  match event {
    RawFastPreview(generation) | RawFastFlush(generation, _) if !raw_input_coordinator.draft_is_current(
        generation,
      ) => return (model, @rabbita_runtime.none)
    BlockInput(token~, input~) => {
      if !block_input_coordinator.is_active(token) {
        return (model, block_input_coordinator.finish(token, emit))
      }
      if model.state.mode() != @core.Block {
        return (model, block_input_coordinator.finish(token, emit))
      }
      match check_block_edit(model.document_id, editor.version(), input) {
        Current => ()
        WrongDocument | StaleVersion =>
          return (model, block_input_coordinator.finish(token, emit))
      }
    }
    _ => ()
  }
  match
    editing_mode_applicable(event, model.state.mode(), model.split_preview_open) {
    Some(message) => {
      let next = record_error(
        model, "mode-inapplicable", "editor-dispatch", message,
      )
      (next, @rabbita_runtime.none)
    }
    None =>
      match event {
        LocalTextInput(source) =>
          match model.runtime_state {
            EditorRuntimeState::LocalText(previous) => {
              raw_input_coordinator.cancel_pending()
              if source == previous {
                (model, @rabbita_runtime.none)
              } else {
                local_text_replacement(
                  {
                    ..model,
                    runtime_state: EditorRuntimeState::LocalText(source),
                    source_revision: model.source_revision + 1,
                    text_input_generation: model.text_input_generation + 1,
                    committed_change_count: model.committed_change_count + 1,
                    error: None,
                    error_code: None,
                    error_operation: None,
                  },
                  source,
                  emit,
                )
              }
            }
            _ =>
              (
                {
                  ..model,
                  rejection: Some(
                    "operation=local-text-input;reason=local-text-inactive",
                  ),
                },
                @rabbita_runtime.none,
              )
          }
        RawFastPreview(_) => (model, @rabbita_runtime.none)
        RawFastFlush(_, source) =>
          if raw_input_coordinator.fast_composing() {
            (model, @rabbita_runtime.none)
          } else {
            match raw_input_coordinator.fast_source_value() {
              Some(current) if current == source =>
                update_editing(
                  editor,
                  attachment,
                  raw_input_coordinator,
                  block_input_coordinator,
                  model,
                  latest_model,
                  if model.runtime_state is EditorRuntimeState::LocalText(_) {
                    LocalTextInput(source)
                  } else {
                    RawInput(source, None)
                  },
                  emit,
                  projection_session?,
                )
              _ => (model, @rabbita_runtime.none)
            }
          }
        CommitCapturedRawSelection(inserted) =>
          match model.raw_selection {
            None => {
              let next = record_error(
                model, "raw-selection-unavailable", "raw-selection-edit", "Raw selection is unavailable",
              )
              (next, @rabbita_runtime.none)
            }
            Some(selection) =>
              update_editing(
                editor,
                attachment,
                raw_input_coordinator,
                block_input_coordinator,
                model,
                latest_model,
                RawSelectionEdit(
                  ({ selection, inserted } : RawSelectionEditRequest),
                ),
                emit,
                projection_session?,
              )
          }
        RawSelectionEdit(request) => {
          let (next, outcome, persistence_command) = commit_raw_selection_edit(
            editor,
            attachment,
            model,
            request,
            emit,
            projection_session?,
          )
          let (next, selection_command) = match outcome {
            RawSelectionEditOutcome::Applied(selection)
            | RawSelectionEditOutcome::Unchanged(selection) => {
              raw_input_coordinator.cancel_pending()
              raw_input_coordinator.set_fast_source(next.document.source())
              (next, raw_selection_after_render(latest_model, selection, emit))
            }
            RawSelectionEditOutcome::Rejected(rejection) =>
              (
                {
                  ..next,
                  rejection: Some(
                    "operation=raw-selection-edit;reason=" +
                    raw_selection_edit_rejection_reason(rejection),
                  ),
                },
                @rabbita_runtime.none,
              )
          }
          (next, @cmd.batch([persistence_command, selection_command]))
        }
        ReplaceSource(source) | RawInput(source, _) => {
          if model.runtime_state is EditorRuntimeState::LocalText(_) {
            return update_editing(
              editor,
              attachment,
              raw_input_coordinator,
              block_input_coordinator,
              model,
              latest_model,
              LocalTextInput(source),
              emit,
              projection_session?,
            )
          }
          let raw_input_epoch = raw_input_coordinator.epoch()
          let raw_selection = match event {
            RawInput(_, selection) => selection
            _ => None
          }
          let raw_event = event is RawInput(_, _)
          let transition = @core.reduce(
            model.state,
            @core.ApplicationEvent::RequestCanonicalSource(source~),
          )
          let mut next = if raw_event {
            { ..model, text_input_generation: model.text_input_generation + 1 }
          } else {
            model
          }
          let mut restore_raw_value = false
          let mut persistence_command = @rabbita_runtime.none
          for decision in transition.decisions() {
            match decision {
              @core.ReplaceCanonicalSource(source) => {
                let old_requested = preview_requested(next)
                let (committed, accepted, changed, commit_command) = commit_source(
                  editor,
                  next,
                  transition.state(),
                  source,
                  "editor-dispatch",
                  emit,
                  projection_session?,
                )
                next = match projection_session {
                  Some(session) =>
                    update_preview_document_with_projection(
                      attachment,
                      session,
                      committed,
                      old_requested,
                      accepted~,
                      changed~,
                    )
                  None =>
                    update_preview_after_authority(
                      attachment,
                      committed,
                      old_requested,
                      accepted~,
                      changed~,
                    )
                }
                if accepted {
                  raw_input_coordinator.cancel_pending()
                  raw_input_coordinator.set_fast_source(next.document.source())
                } else if raw_event {
                  raw_input_coordinator.set_fast_source(next.document.source())
                }
                persistence_command = @cmd.batch([
                  persistence_command, commit_command,
                ])
                restore_raw_value = restore_raw_value ||
                  (raw_event && !accepted)
              }
              @core.SnapshotRejected(_) =>
                next = record_error(
                  next, "invalid-snapshot", "editor-dispatch", "snapshot rejected",
                )
            }
          }
          let command = if restore_raw_value {
            let repair_generation = next.text_input_generation
            let repair_source_revision = next.source_revision
            after_render(
              scheduler => {
                ignore(scheduler)
                let accepted_source = next.document.source()
                if raw_input_coordinator.epoch() == raw_input_epoch &&
                  raw_input_repair_eligible(
                    latest_model.val,
                    repair_generation,
                    repair_source_revision,
                  ) {
                  @dom_boundary.write_text_value_id(
                    "loomark-input", accepted_source,
                  )
                  match raw_selection {
                    Some(selection) =>
                      @dom_boundary.write_text_selection_id(
                        "loomark-input",
                        rejected_text_selection(
                          accepted_source, source, selection,
                        ),
                      )
                    None => ()
                  }
                }
              },
              emit,
            )
          } else {
            @rabbita_runtime.none
          }
          (next, @cmd.batch([persistence_command, command]))
        }
        BlockFocused(key) =>
          if model.active_block_key == Some(key) {
            (model, @rabbita_runtime.none)
          } else {
            let (_, selected_index) = model.document
              .blocks()
              .fold(init=(0, None), (state, block) => {
                let (index, found) = state
                (
                  index + 1,
                  match found {
                    Some(_) => found
                    None => if block.key() == key { Some(index) } else { None }
                  },
                )
              })
            match selected_index {
              None => {
                let next = record_error(
                  model, "block-selection-rejected", "editor-dispatch", "focused block is unavailable",
                )
                (next, @rabbita_runtime.none)
              }
              Some(index) => {
                let next = { ..model, active_block_key: Some(key) }
                (
                  next,
                  after_render(
                    scheduler => {
                      ignore(scheduler)
                      @dom_boundary.focus_id(block_input_id(index))
                    },
                    emit,
                  ),
                )
              }
            }
          }
        BlockHeading(requested_level, originating_selection) =>
          match block_format_target(model, originating_selection) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "formatting requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              guard block_allows_heading(block.kind()) else {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              if requested_level == 0 && block.kind() is @markdown.Paragraph {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              let target_level = match block.kind() {
                @markdown.Heading(level~) if level == requested_level => 0
                _ => requested_level
              }
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::ChangeHeadingLevel(
                  node_id=block.node_id(),
                  level=target_level,
                ),
                originating_selection,
                "loomark-heading-" + requested_level.to_string(),
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockToggleList(originating_selection) =>
          match block_format_target(model, originating_selection) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "formatting requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              guard block_allows_list(block.kind()) else {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::ToggleListItem(
                  node_id=block.node_id(),
                ),
                originating_selection,
                "loomark-toggle-list",
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockDelete =>
          match active_block(model) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "deletion requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::Delete(node_id=block.node_id()),
                None,
                "loomark-delete-block",
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockInput(token~, input~) => {
          match check_block_selection(model.document, input) {
            ValidBlockSelection => ()
            NonCollapsedBlockSelection
            | InvalidBlockSelection
            | MissingBlockSelectionTarget =>
              return (model, block_input_coordinator.finish(token, emit))
          }
          if !block_input_coordinator.is_active(token) {
            return (model, block_input_coordinator.finish(token, emit))
          }
          match check_block_edit(model.document_id, editor.version(), input) {
            Current => ()
            WrongDocument | StaleVersion =>
              return (model, block_input_coordinator.finish(token, emit))
          }
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::CommitTextControlEdit(
              node_id=input.node_id,
              new_text=input.text,
            ),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          let finish_command = block_input_coordinator.finish(token, emit)
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(
                next.document,
                selection,
                offset=input.selection.end(),
              )
            None => None
          }
          let next = if accepted {
            {
              ..next,
              text_input_generation: model.text_input_generation + 1,
              active_block_key: match selection {
                Some(selection) => Some(selection.key)
                None => model.active_block_key
              },
              selection: match selection {
                Some(selection) => Some(block_selection_label(selection))
                None => None
              },
            }
          } else {
            next
          }
          match selection {
            Some(selection) =>
              // Clearing the final payload can install the façade's empty
              // paragraph sentinel and replace the rendered control. Ordinary
              // input keeps the browser's native caret and must not queue an
              // older caret write over newer keystrokes.
              if input.text == "" {
                (
                  next,
                  @cmd.batch([
                    persistence_command,
                    finish_command,
                    block_selection_after_render(
                      latest_model,
                      selection,
                      next.source_revision,
                      report_superseded=false,
                      emit,
                    ),
                  ]),
                )
              } else {
                (next, @cmd.batch([persistence_command, finish_command]))
              }
            None =>
              if accepted {
                (next, @cmd.batch([persistence_command, finish_command]))
              } else {
                let accepted_text = next.document
                  .blocks()
                  .fold(init=None, (found, block) => {
                    match found {
                      Some(_) => found
                      None =>
                        if block.node_id() == input.node_id {
                          Some(block.text())
                        } else {
                          None
                        }
                    }
                  })
                match accepted_text {
                  Some(text) => {
                    let offset = rejected_text_offset(
                      text,
                      input.text,
                      input.selection.end(),
                    )
                    let repair_generation = next.text_input_generation
                    let repair_source_revision = next.source_revision
                    (
                      next,
                      @cmd.batch([
                        persistence_command,
                        finish_command,
                        after_render(
                          scheduler => {
                            ignore(scheduler)
                            if repair_eligible(
                                latest_model.val,
                                @core.Block,
                                repair_generation,
                                repair_source_revision,
                              ) {
                              @dom_boundary.write_text_value_id(
                                input.input_id,
                                text,
                              )
                              @dom_boundary.focus_id(input.input_id)
                              @dom_boundary.write_text_selection_id(
                                input.input_id,
                                @dom_boundary.TextSelection(
                                  offset,
                                  offset,
                                  @dom_boundary.NoDirection,
                                ),
                              )
                            }
                          },
                          emit,
                        ),
                      ]),
                    )
                  }
                  None =>
                    (next, @cmd.batch([persistence_command, finish_command]))
                }
              }
          }
        }
        BlockSplit(node_id~, offset~) => {
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::SplitBlock(node_id~, offset~),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(next.document, selection)
            None => None
          }
          let next = {
            ..next,
            active_block_key: match selection {
              Some(selection) => Some(selection.key)
              None => model.active_block_key
            },
            selection: match selection {
              Some(selection) => Some(block_selection_label(selection))
              None => None
            },
          }
          match selection {
            Some(selection) =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    selection,
                    next.source_revision,
                    report_superseded=false,
                    emit,
                  ),
                ]),
              )
            None => (next, persistence_command)
          }
        }
        BlockMerge(node_id~, selection=originating_selection) => {
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::MergeWithPrevious(node_id~),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let resolved_selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(next.document, selection)
            None => None
          }
          let next = {
            ..next,
            active_block_key: match resolved_selection {
              Some(selection) => Some(selection.key)
              None => model.active_block_key
            },
            selection: match resolved_selection {
              Some(selection) => Some(block_selection_label(selection))
              None => None
            },
          }
          match resolved_selection {
            Some(selection) =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    selection,
                    next.source_revision,
                    report_superseded=false,
                    emit,
                  ),
                ]),
              )
            None =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    originating_selection,
                    next.source_revision,
                    report_superseded=true,
                    emit,
                  ),
                ]),
              )
          }
        }
        BlockNavigate(key~, direction~) =>
          match block_navigation_selection(model.document, key, direction) {
            None => (model, @rabbita_runtime.none)
            Some(selection) => {
              let next = {
                ..model,
                active_block_key: Some(selection.key),
                selection: Some(block_selection_label(selection)),
              }
              (
                next,
                block_selection_after_render(
                  latest_model,
                  selection,
                  next.source_revision,
                  report_superseded=true,
                  emit,
                ),
              )
            }
          }
        ProbeBlockSelection(kind) => {
          let blocks = model.document.blocks().to_array()
          if blocks.is_empty() {
            let next = record_error(
              model, "block-selection-rejected", "browser-effect", "block selection probe has no target",
            )
            (next, @rabbita_runtime.none)
          } else {
            let block = blocks[0]
            let selection = BlockSelection::{
              key: block.key(),
              index: 0,
              start: 0,
              end: 0,
            }
            let previous_revision = model.source_revision
            let source = if kind == "deleted" { "" } else { "replacement\n" }
            let (committed, accepted, changed, persistence_command) = commit_source(
              editor,
              model,
              model.state,
              source,
              "editor-dispatch",
              emit,
              projection_session?,
            )
            let next = match projection_session {
              Some(session) =>
                update_preview_document_with_projection(
                  attachment,
                  session,
                  committed,
                  preview_requested(model),
                  accepted~,
                  changed~,
                )
              None =>
                update_preview_after_authority(
                  attachment,
                  committed,
                  preview_requested(model),
                  accepted~,
                  changed~,
                )
            }
            if accepted && changed {
              raw_input_coordinator.cancel_pending()
            }
            let expected_revision = if kind == "stale" {
              previous_revision
            } else {
              next.source_revision
            }
            (
              next,
              @cmd.batch([
                persistence_command,
                block_selection_after_render(
                  latest_model,
                  selection,
                  expected_revision,
                  report_superseded=true,
                  emit,
                ),
              ]),
            )
          }
        }
      }
  }
}

///|
/// Commit the browser-owned Raw source only when leaving the fast text path.
/// The commit is a mode-boundary operation, never a per-keystroke operation.
fn flush_fast_raw_source(
  editor : @markdown.MarkdownEditor,
  raw_input_coordinator : RawInputCoordinator,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, Bool, Bool, @cmd.Cmd) raise {
  match raw_input_coordinator.fast_source_value() {
    Some(source) if raw_textarea_value(model.document.source()) !=
      raw_textarea_value(source) => {
      let (next, accepted, changed, command) = commit_source(
        editor,
        model,
        model.state,
        source,
        "raw-mode-boundary",
        emit,
        projection_session?,
      )
      if accepted {
        raw_input_coordinator.set_fast_source(next.document.source())
      }
      (next, accepted, changed, command)
    }
    _ => (model, false, false, @rabbita_runtime.none)
  }
}

///|
/// View-surface dispatcher: mode selection, split, focus commands, and the
/// effect reports that accompany them. Not mode-gated.
fn update_navigation(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : NavigationEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) raise {
  if model.runtime_state is EditorRuntimeState::LocalText(_) {
    match event {
      SelectBlock
      | SelectPreview
      | ToggleSplitPreview
      | FocusBlock
      | FocusPreview =>
        return (
          {
            ..model,
            rejection: Some("operation=navigation;reason=local-text-raw-only"),
          },
          @rabbita_runtime.none,
        )
      _ => ()
    }
  }
  match event {
    SelectRaw | SelectBlock | SelectPreview => {
      // The outer or-pattern already narrowed `event` to the Select*
      // variants; `_` is required because this inner match re-matches the
      // full NavigationEvent type.
      let mode = match event {
        SelectRaw => @core.Raw
        SelectBlock => @core.Block
        SelectPreview => @core.Preview
        _ => @core.Raw
      }
      let needs_flush = match raw_input_coordinator.fast_source_value() {
        Some(source) =>
          raw_draft_surface_live(model.state.mode(), model.split_preview_open) &&
          raw_textarea_value(model.document.source()) !=
          raw_textarea_value(source)
        None => false
      }
      let (model, flush_command) = if needs_flush {
        let (next, accepted, _, command) = flush_fast_raw_source(
          editor,
          raw_input_coordinator,
          model,
          emit,
          projection_session?,
        )
        if !accepted {
          return (next, command)
        }
        (next, command)
      } else {
        (model, @rabbita_runtime.none)
      }
      if mode != model.state.mode() {
        raw_input_coordinator.cancel_pending_for_navigation()
        block_input_coordinator.cancel_pending()
      }
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::SelectMode(mode~),
      )
      let old_requested = preview_requested(model)
      let next_model = { ..model, state: transition.state() }
      let next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
      }
      if mode == @core.Raw {
        raw_input_coordinator.set_fast_source(next.document.source())
      }
      (next, flush_command)
    }
    ToggleSplitPreview => {
      let needs_flush = match raw_input_coordinator.fast_source_value() {
        Some(source) =>
          model.state.mode() == @core.Preview &&
          raw_draft_surface_live(model.state.mode(), model.split_preview_open) &&
          raw_textarea_value(model.document.source()) !=
          raw_textarea_value(source)
        None => false
      }
      let (model, flush_command) = if needs_flush {
        let (next, accepted, _, command) = flush_fast_raw_source(
          editor,
          raw_input_coordinator,
          model,
          emit,
          projection_session?,
        )
        if !accepted {
          return (next, command)
        }
        (next, command)
      } else {
        (model, @rabbita_runtime.none)
      }
      if model.state.mode() == @core.Preview && model.split_preview_open {
        raw_input_coordinator.cancel_pending_for_navigation()
      }
      let old_requested = preview_requested(model)
      let next_model = {
        ..model,
        split_preview_open: !model.split_preview_open,
      }
      let next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
      }
      (next, flush_command)
    }
    FocusRaw | FocusBlock | FocusPreview => {
      // The outer or-pattern already narrowed `event` to the Focus*
      // variants; `_` is required because this inner match re-matches the
      // full NavigationEvent type.
      let target = match event {
        FocusRaw => @core.RawEditor
        FocusBlock => @core.BlockEditor
        FocusPreview => @core.PreviewControl
        _ => @core.PreviewControl
      }
      let locator = @core.FocusLocator(
        target~,
        source_revision=model.source_revision,
      )
      let token = encode_focus_token(target, model.source_revision)
      match @core.decide_focus(model.state, model.source_revision, locator) {
        @core.Compatible(_) => {
          let next = match target {
            @core.BlockEditor => {
              let active_block_key = model.document
                .blocks()
                .get(0)
                .map(block => block.key())
              { ..model, active_block_key, }
            }
            _ => model
          }
          (next, focus_latest_after_render(latest_model, locator, token, emit))
        }
        @core.Rejected(error) => reject_focus(model, error)
      }
    }
    FocusRejected(error) => reject_focus(model, error)
    RestoreFocus(token) =>
      match decode_focus_token(token) {
        Ok(locator) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(target) => {
              let next = match target {
                @core.BlockEditor => {
                  let active_block_key = model.document
                    .blocks()
                    .get(0)
                    .map(block => block.key())
                  { ..model, active_block_key, }
                }
                _ => model
              }
              (
                next,
                focus_latest_after_render(latest_model, locator, token, emit),
              )
            }
            @core.Rejected(error) => reject_focus(model, error)
          }
        Err(error) => reject_focus_token(model, error)
      }
    EffectFailed(message) => {
      let next = record_error(
        model, "browser-effect-failed", "browser-effect", message,
      )
      (next, @rabbita_runtime.none)
    }
    BlockSelectionRejected(message, selection) => {
      let next = record_error(
        model, "block-selection-rejected", "browser-effect", message,
      )
      let command = match selection {
        Some(selection) =>
          block_selection_after_render(
            latest_model,
            selection,
            next.source_revision,
            report_superseded=true,
            emit,
          )
        None => @rabbita_runtime.none
      }
      (next, command)
    }
  }
}

///|
/// Apply a driver selection-read result to the probe model. Pure.
fn apply_selection_read(
  model : DriverModel,
  start : Int,
  end : Int,
) -> DriverModel {
  { ..model, selection: Some(start.to_string() + ":" + end.to_string()) }
}

///|
/// Apply a driver measurement result to the probe model. Pure.
fn apply_measurement(
  model : DriverModel,
  width : Double,
  height : Double,
) -> DriverModel {
  { ..model, measurement: Some(width.to_string() + ":" + height.to_string()) }
}

///|
/// Driver/test instrumentation dispatcher: probes, measurements, and their
/// outbound results.
fn update_probe(
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : ProbeEvent,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  match event {
    WriteSelection(start~, end~) =>
      (
        model,
        after_render(
          scheduler => {
            let selection = @dom_boundary.TextSelection(
              start,
              end,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id("loomark-input", selection)
            let read = @dom_boundary.read_text_selection_id("loomark-input")
            scheduler.add(
              emit(Probe(SelectionRead(start=read.start(), end=read.end()))),
            )
          },
          emit,
        ),
      )
    WriteSelectionFailure =>
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            let selection = @dom_boundary.TextSelection(
              0,
              1,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id(
              "loomark-missing-input", selection,
            )
          },
          emit,
        ),
      )
    CaptureRawSelection =>
      (
        model,
        after_render(
          scheduler => {
            let selection = @dom_boundary.read_text_selection_id(
              "loomark-input",
            )
            scheduler.add(emit(Probe(RawSelectionCaptured(selection))))
          },
          emit,
        ),
      )
    RawSelectionCaptured(selection) => {
      let bound = versioned_raw_selection_from_dom(model, selection) catch {
        error => {
          let next = record_error(
            model,
            "invalid-raw-selection",
            "browser-effect",
            raw_dom_selection_conversion_error_detail(error),
          )
          return (next, @rabbita_runtime.none)
        }
      }
      let markdown = bound.selection
      (
        {
          ..model,
          raw_selection: Some(bound),
          selection: Some(
            markdown.anchor().to_string() + ":" + markdown.head().to_string(),
          ),
        },
        @rabbita_runtime.none,
      )
    }
    InstallRawSelection =>
      (
        model,
        match model.raw_selection {
          Some(selection) =>
            raw_selection_after_render(latest_model, selection, emit)
          None => @rabbita_runtime.none
        },
      )
    MeasurePreview =>
      (
        model,
        after_render(
          scheduler => {
            let measurement = @dom_boundary.measure_element_id(
              "loomark-preview",
            )
            scheduler.add(
              emit(
                Probe(
                  Measured(
                    width=measurement.offset_width(),
                    height=measurement.offset_height(),
                  ),
                ),
              ),
            )
          },
          emit,
        ),
      )
    MeasureFailure =>
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            ignore(@dom_boundary.measure_element_id("loomark-missing-preview"))
          },
          emit,
        ),
      )
    SelectionRead(start~, end~) =>
      (apply_selection_read(model, start, end), @rabbita_runtime.none)
    Measured(width~, height~) =>
      (apply_measurement(model, width, height), @rabbita_runtime.none)
  }
}

///|
/// Run a recovery action immediately in the originating activation turn and
/// route boundary failures back through an allowed recovery event.
fn recovery_effect_command(
  effect : () -> Unit raise @dom_boundary.DomBoundaryError,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    effect() catch {
      error =>
        scheduler.add(emit(Lifecycle(RecoveryEffectFailed(error.message()))))
    }
  })
}

///|
/// Application-control dispatcher: failures, restore, subscriptions, fatal,
/// resize, and driver protocol errors.
fn update_lifecycle(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  event : LifecycleEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
  projection_worker? : ProjectionWorkerRuntime,
) -> (DriverModel, @cmd.Cmd) raise {
  match event {
    EditorFailure => {
      let next = { ..model, fail_next_editor_commit: true }
      (next, @rabbita_runtime.none)
    }
    RetryLocalPersistence(document_id) => {
      guard document_id == model.document_id &&
        model.archive_persistence_enabled else {
        return (
          { ..model, event_detail: Some("retry-local-persistence-ignored") },
          @rabbita_runtime.none,
        )
      }
      retry_local_persistence(editor, model, emit)
    }
    ForceParserFailure => {
      let next = { ..model, force_parser_failure: true }
      (next, @rabbita_runtime.none)
    }
    ForceReconstructionFailure => {
      let next = { ..model, force_reconstruction_failure: true }
      (next, @rabbita_runtime.none)
    }
    ArmRawRenderBarrier => {
      raw_input_coordinator.arm_render_barrier()
      (model, @rabbita_runtime.none)
    }
    ReleaseRawRenderBarrier =>
      (model, raw_input_coordinator.release_render_barrier())
    RecoveryCopy =>
      (
        model,
        recovery_effect_command(
          () => @dom_boundary.copy_text(runtime_source(model)),
          emit,
        ),
      )
    RecoveryDownload =>
      (
        model,
        recovery_effect_command(
          () => {
            @dom_boundary.download_text(
              "loomark-recovered.md",
              runtime_source(model),
            )
          },
          emit,
        ),
      )
    RecoveryReload =>
      (model, recovery_effect_command(() => @dom_boundary.reload(), emit))
    RecoveryEffectFailed(detail) =>
      (
        {
          ..model,
          error: Some("Recovery action failed: " + detail),
          error_code: Some("recovery-effect-failed"),
          error_operation: Some("recovery-action"),
        },
        @rabbita_runtime.none,
      )
    RestoreSnapshot(version~, source~, mode~) => {
      let snapshot = @core.ApplicationStateSnapshot::ApplicationStateSnapshot(
        version~,
        source~,
        mode~,
      )
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::RestoreSnapshot(
          snapshot~,
          canonical_source=model.document.source(),
        ),
      )
      let mut next = model
      let mut accepted = true
      let mut source_changed = false
      let mut persistence_command = @rabbita_runtime.none
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let (committed, commit_accepted, changed, commit_command) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "restore-snapshot",
              emit,
              projection_session?,
            )
            next = committed
            accepted = accepted && commit_accepted
            source_changed = source_changed || changed
            persistence_command = @cmd.batch([
              persistence_command, commit_command,
            ])
          }
          @core.SnapshotRejected(error) => {
            accepted = false
            let message = match error {
              @core.UnsupportedSnapshotVersion(version) =>
                "unsupported snapshot version: " + version.to_string()
            }
            next = record_error(
              next, "unsupported-snapshot-version", "restore-snapshot", message,
            )
          }
        }
      }
      if accepted {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        next = { ..next, state: transition.state() }
      }
      next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next,
            preview_requested(model),
            accepted~,
            changed=source_changed,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next,
            preview_requested(model),
            accepted~,
            changed=source_changed,
          )
      }
      (next, persistence_command)
    }
    CustomEvent(detail) => {
      let next = {
        ..model,
        event_detail: Some(detail),
        event_count: model.event_count + 1,
      }
      (next, @rabbita_runtime.none)
    }
    ControlInstalled => {
      let next = { ..model, control_ready: true }
      (next, @rabbita_runtime.none)
    }
    SubscriptionInstalled => {
      let next = { ..model, event_install_count: model.event_install_count + 1 }
      (next, @rabbita_runtime.none)
    }
    SubscriptionUnloaded => {
      let next = { ..model, event_unload_count: model.event_unload_count + 1 }
      (next, @rabbita_runtime.none)
    }
    InvalidRequest(message) => {
      let code = if message == "restore-snapshot" {
        "invalid-snapshot"
      } else {
        "invalid-request"
      }
      let next = record_error(
        model,
        code,
        "editor-dispatch",
        "invalid driver request: " + message,
      )
      (next, @rabbita_runtime.none)
    }
    StopListening => {
      let next = { ..model, listening: false }
      (next, @rabbita_runtime.none)
    }
    Fatal(message) => {
      raw_input_coordinator.cancel_pending()
      block_input_coordinator.cancel_pending()
      let next = { ..model, fatal: true, error: Some(message), rejection: None }
      (next, @rabbita_runtime.none)
    }
    ProjectionWorkerResolved(request_id, expected, raw) =>
      match projection_worker {
        None => (model, @rabbita_runtime.none)
        Some(worker) => {
          guard worker.accepts(request_id, expected) else {
            return (model, @rabbita_runtime.none)
          }
          match projection_worker_response_artifact(raw) {
            Err(detail) => worker.recover(model, emit, detail)
            Ok((response_request_id, stamp, artifact)) =>
              if response_request_id != request_id || stamp != expected {
                worker.recover(
                  model, emit, "projection Worker response envelope mismatch",
                )
              } else {
                worker.mark_healthy()
                match artifact {
                  None => (model, @rabbita_runtime.none)
                  Some(preview) => {
                    guard preview.source == model.document.source() else {
                      return worker.recover(
                        model, emit, "projection Worker Preview source mismatch",
                      )
                    }
                    let projection_error = model.error_code ==
                      Some("projection-failed") ||
                      model.error_code == Some("projection-pending")
                    (
                      {
                        ..model,
                        semantic_document: None,
                        preview_artifact: Some({ stamp, preview }),
                        semantic_read_count: model.semantic_read_count + 1,
                        error: if projection_error {
                          None
                        } else {
                          model.error
                        },
                        error_code: if projection_error {
                          None
                        } else {
                          model.error_code
                        },
                        error_operation: if projection_error {
                          None
                        } else {
                          model.error_operation
                        },
                      },
                      @rabbita_runtime.none,
                    )
                  }
                }
              }
          }
        }
      }
    Resize(viewport) => {
      let next = {
        ..model,
        compact_split: compact_split_for_width(viewport.width),
        resize_count: model.resize_count + 1,
      }
      (next, @rabbita_runtime.none)
    }
  }
}

///|
fn recovery_control_event(event : DriverEvent) -> Bool {
  match event {
    Lifecycle(
      RecoveryCopy
      | RecoveryDownload
      | RecoveryReload
      | RecoveryEffectFailed(_)
    ) => true
    _ => false
  }
}

///|
/// Total dispatch: the envelope constructor encodes the concern, so routing
/// cannot misclassify. Archive completions land even in fatal state; recovery
/// controls remain available while every editing event is rejected.
fn update_model(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : DriverEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
  projection_worker? : ProjectionWorkerRuntime,
  bootstrap_mode? : StandaloneBootstrapMode,
  session_ref? : @ref.Ref[EditorSession],
) -> (DriverModel, @cmd.Cmd) raise {
  update_model_with_raw_preview_runtime(
    editor,
    attachment,
    raw_input_coordinator,
    block_input_coordinator,
    model,
    latest_model,
    event,
    emit,
    projection_session?,
    projection_worker?,
    bootstrap_mode?,
    session_ref?,
    raw_preview_runtime?=None,
  )
}

///|
fn update_model_with_raw_preview_runtime(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : DriverEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
  projection_worker? : ProjectionWorkerRuntime,
  bootstrap_mode? : StandaloneBootstrapMode,
  raw_preview_runtime? : RawPreviewRuntime,
  session_ref? : @ref.Ref[EditorSession],
) -> (DriverModel, @cmd.Cmd) raise {
  let (next, command) = match event {
    Bootstrap(loaded) =>
      match (session_ref, bootstrap_mode) {
        (Some(session_ref), Some(mode)) =>
          update_standalone_bootstrap(
            session_ref,
            model,
            loaded,
            model.document.source(),
            mode,
            emit,
          )
        _ => (model, @rabbita_runtime.none)
      }
    Archive(completion) => update_archive_queue(model, completion, emit)
    _ if model.bootstrap_pending =>
      (
        {
          ..model,
          rejection: Some(
            "operation=" +
            driver_event_name(event) +
            ";reason=bootstrap-pending",
          ),
        },
        @rabbita_runtime.none,
      )
    _ if model.fatal && !recovery_control_event(event) => {
      match event {
        Editing(BlockInput(..)) => block_input_coordinator.cancel_pending()
        _ => ()
      }
      let next = {
        ..model,
        rejection: Some(
          "operation=" + driver_event_name(event) + ";reason=fatal-state",
        ),
      }
      (next, @rabbita_runtime.none)
    }
    Editing(edit_event) =>
      update_editing(
        editor,
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        latest_model,
        edit_event,
        emit,
        projection_session?,
      )
    Navigation(nav_event) =>
      update_navigation(
        editor,
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        latest_model,
        nav_event,
        emit,
        projection_session?,
      )
    Probe(probe_event) => update_probe(model, latest_model, probe_event, emit)
    GotRawPreviewMsg(msg) =>
      update_raw_preview_msg(
        msg, model, raw_input_coordinator, raw_preview_runtime, emit,
      )
    Lifecycle(life_event) =>
      update_lifecycle(
        editor,
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        life_event,
        emit,
        projection_session?,
        projection_worker?,
      )
  }
  let next = match projection_session {
    None => next
    Some(session_ref) =>
      match session_ref.val {
        None => next
        Some(session) => update_projection_demand(session, next)
      }
  }
  match event {
    Bootstrap(_) | Lifecycle(RestoreSnapshot(..)) =>
      raw_input_coordinator.set_fast_source(runtime_source(next))
    _ if !raw_draft_surface_live(next.state.mode(), next.split_preview_open) =>
      raw_input_coordinator.set_fast_source(next.document.source())
    _ => ()
  }
  let next = match next.raw_preview.artifact() {
    Some(stamped) if stamped.preview.source !=
      current_preview_source(next, raw_input_coordinator) =>
      { ..next, raw_preview: next.raw_preview.clear() }
    _ => next
  }
  projection_trace_driver_model_adopted()
  publish(next, Some(raw_input_coordinator), None)
  (next, command)
}
