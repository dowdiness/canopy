///|
/// Versioned errors owned by the private focus-token codec.
priv enum FocusTokenError {
  Malformed
  UnsupportedVersion(Int)
  Ambiguous
}

///|
/// Detached logical focus state for the private driver only.
let detached_focus_token : @ref.Ref[String] = { val: "" }

///|
/// Focus tokens have a private wire version independent from snapshots.
const FOCUS_TOKEN_VERSION : Int = 1

///|
/// The private driver maps a pure focus target to one mounted control.
fn focus_target_id(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "loomark-input"
    @core.BlockEditor => "loomark-block-input"
    @core.PreviewControl => "loomark-preview"
  }
}

///|
fn focus_target_name(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "raw"
    @core.BlockEditor => "block"
    @core.PreviewControl => "preview"
  }
}

///|
/// Serialize a known focus target and revision at the private shell boundary.
fn encode_focus_token(
  target : @core.FocusTarget,
  source_revision : Int,
) -> String {
  "v" +
  FOCUS_TOKEN_VERSION.to_string() +
  "|" +
  focus_target_name(target) +
  "|" +
  source_revision.to_string()
}

///|
/// Decode a token exactly once before handing its typed locator to the core.
fn decode_focus_token(
  token : String,
) -> Result[@core.FocusLocator, FocusTokenError] {
  let parts = token.split("|").to_array()
  guard parts.length() == 3 else { return Err(FocusTokenError::Malformed) }
  guard parts[0].has_prefix("v") else { return Err(FocusTokenError::Malformed) }
  let version = @string.parse_int(parts[0][1:], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  if version != FOCUS_TOKEN_VERSION {
    return Err(FocusTokenError::UnsupportedVersion(version))
  }
  let target = match parts[1] {
    "raw" => @core.RawEditor
    "block" => @core.BlockEditor
    "preview" => @core.PreviewControl
    _ => return Err(FocusTokenError::Ambiguous)
  }
  let source_revision = @string.parse_int(parts[2], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  Ok(@core.FocusLocator(target~, source_revision~))
}

///|
/// Map codec failures to one private-driver error category.
fn focus_token_error(error : FocusTokenError) -> (String, String) {
  match error {
    FocusTokenError::Malformed => ("malformed-focus", "malformed focus token")
    FocusTokenError::UnsupportedVersion(version) =>
      (
        "unsupported-focus-version",
        "unsupported focus token version: " + version.to_string(),
      )
    FocusTokenError::Ambiguous => ("ambiguous-focus", "ambiguous focus target")
  }
}

///|
/// Map pure focus compatibility rejections to one private-driver category.
fn focus_rejection(error : @core.FocusDecisionError) -> (String, String) {
  match error {
    @core.Stale => ("stale-focus", "stale focus token")
    @core.ModeInapplicable =>
      (
        "focus-mode-inapplicable", "focus target is inapplicable in current mode",
      )
  }
}

///|
fn reject_focus(
  model : DriverModel,
  error : @core.FocusDecisionError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_rejection(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
fn reject_focus_token(
  model : DriverModel,
  error : FocusTokenError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_token_error(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
fn after_render(
  action : (&@cmd.Scheduler) -> Unit raise @dom_boundary.DomBoundaryError,
  failed : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      action(scheduler) catch {
        error => scheduler.add(failed(EffectFailed(error.message())))
      }
    },
    kind=@cmd.AfterRender,
  )
}

///|
/// Revalidate a structural selection after the edited blocks are rendered,
/// then focus the exact block and restore its relative UTF-16 caret.
/// Routine input may follow a newer render when keystrokes overtake one frame;
/// its superseded callback yields while structural edits report stale revisions.
fn block_selection_after_render(
  selection : BlockSelection,
  source_revision : Int,
  report_superseded~ : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  after_render(
    scheduler => {
      match detached_model.val {
        Some(model) =>
          if model.state.mode() != @core.Block {
            scheduler.add(
              emit(
                BlockSelectionRejected("block selection mode is stale", None),
              ),
            )
          } else if model.source_revision != source_revision {
            // Rapid input can queue several post-render selections in one
            // frame. Rabbita runs AfterRender effects newest-first, so an older
            // superseded selection must not emit a message that schedules a
            // second render after the newest selection restored the caret.
            if report_superseded {
              scheduler.add(
                emit(BlockSelectionRejected("block selection is stale", None)),
              )
            }
          } else {
            match block_selection_target(model.document, selection) {
              Some(index) => {
                let id = block_input_id(index)
                @dom_boundary.focus_id(id)
                @dom_boundary.write_text_selection_id(
                  id,
                  @dom_boundary.TextSelection(
                    selection.start,
                    selection.end,
                    @dom_boundary.NoDirection,
                  ),
                )
              }
              None =>
                scheduler.add(
                  emit(
                    BlockSelectionRejected(
                      "block selection target is unavailable",
                      None,
                    ),
                  ),
                )
            }
          }
        None =>
          scheduler.add(
            emit(
              BlockSelectionRejected("block selection model unavailable", None),
            ),
          )
      }
    },
    emit,
  )
}

///|
/// Revalidate the latest model after rendering, then perform the final DOM
/// write without queuing a state update after it.
fn focus_latest_after_render(
  locator : @core.FocusLocator,
  token : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  after_render(
    scheduler => {
      match detached_model.val {
        Some(model) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(target) => {
              let previous_token = detached_focus_token.val
              detached_focus_token.val = token
              @dom_boundary.focus_id(focus_target_id(target)) catch {
                error => {
                  detached_focus_token.val = previous_token
                  scheduler.add(emit(EffectFailed(error.message())))
                }
              }
            }
            @core.Rejected(error) => scheduler.add(emit(FocusRejected(error)))
          }
        None => scheduler.add(emit(EffectFailed("focus model unavailable")))
      }
    },
    emit,
  )
}
