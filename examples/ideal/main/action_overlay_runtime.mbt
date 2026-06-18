///|
struct ActionOverlayHost {
  runtime : ActionOverlayRuntime?
  next_token : Int
}

///|
fn ActionOverlayHost::empty() -> ActionOverlayHost {
  { runtime: None, next_token: 1 }
}

///|
fn ActionOverlayHost::mount(
  self : ActionOverlayHost,
  runtime : ActionOverlayRuntime,
) -> ActionOverlayHost {
  { runtime: Some(runtime), next_token: self.next_token + 1 }
}

///|
fn ActionOverlayHost::close(self : ActionOverlayHost) -> ActionOverlayHost {
  { ..self, runtime: None }
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
