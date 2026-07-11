///|
struct ActionOverlayHost {
  // Both context and runtime are active or neither is — the tuple enforces this
  // structurally. `mount`/`close`/`empty` are the only write paths.
  active : (@lambda_edits.ActionContext, ActionOverlayRuntime)?
  next_token : Int
}

///|
fn ActionOverlayHost::empty() -> ActionOverlayHost {
  { active: None, next_token: 1 }
}

///|
fn ActionOverlayHost::mount(
  self : ActionOverlayHost,
  context : @lambda_edits.ActionContext,
  runtime : ActionOverlayRuntime,
) -> ActionOverlayHost {
  { active: Some((context, runtime)), next_token: self.next_token + 1 }
}

///|
fn ActionOverlayHost::close(self : ActionOverlayHost) -> ActionOverlayHost {
  { ..self, active: None }
}

///|
struct ActionOverlayRuntime {
  cell : @rabbita.Cell
  emit : @rabbita.Emit[OverlayMsg]
  // Runtime identity for child-to-parent outputs. The parent drops the child
  // cell by clearing the host runtime; queued outputs from an older cell are
  // ignored when this token no longer matches the current runtime.
  token : Int
}

///|
fn ActionOverlayRuntime::send(
  self : ActionOverlayRuntime,
  msg : OverlayMsg,
) -> Cmd {
  (self.emit)(msg)
}

///|
fn ActionOverlayRuntime::view(self : ActionOverlayRuntime) -> @rabbita.Html {
  self.cell.view()
}
