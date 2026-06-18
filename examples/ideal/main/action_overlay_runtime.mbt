///|
// `runtime` and `context` are co-valid: both Some when mounted, both None when
// closed. `mount`/`close`/`empty` are the only write paths and must stay in
// lockstep. TODO: consolidate into a single
// `active: (NodeActionContext, ActionOverlayRuntime)?` field to make this
// invariant structurally unrepresentable-to-violate.
struct ActionOverlayHost {
  runtime : ActionOverlayRuntime?
  context : NodeActionContext?
  next_token : Int
}

///|
fn ActionOverlayHost::empty() -> ActionOverlayHost {
  { runtime: None, context: None, next_token: 1 }
}

///|
fn ActionOverlayHost::mount(
  self : ActionOverlayHost,
  context : NodeActionContext,
  runtime : ActionOverlayRuntime,
) -> ActionOverlayHost {
  {
    runtime: Some(runtime),
    context: Some(context),
    next_token: self.next_token + 1,
  }
}

///|
fn ActionOverlayHost::close(self : ActionOverlayHost) -> ActionOverlayHost {
  { ..self, runtime: None, context: None }
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
