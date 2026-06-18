///|
struct ActionOverlayRuntime {
  cell : @rabbita.Cell
  emit : @rabbita.Emit[OverlayMsg]
  // Runtime identity for child-to-parent outputs. The parent drops the child
  // cell by clearing `overlay_runtime`; queued outputs from an older cell are
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
