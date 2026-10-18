///|
/// A subscription's connection to nodes that exist only after rendering. The
/// render can complete after the subscription unloads, and a connection can
/// fail on its own, so every transition follows from the current state.
priv enum Attachment[C] {
  AwaitingRender
  Attached(C)
  Detached
}

///|
priv struct AfterRender[C] {
  mut state : Attachment[C]
  release : (C) -> Unit
}

///|
/// Resolves this render's nodes once, after rendering. `attach` returns `None`
/// when the nodes are absent or cannot be connected.
fn[C] AfterRender::AfterRender(
  scheduler : &@cmd.Scheduler,
  attach : (AfterRender[C]) -> C?,
  release~ : (C) -> Unit,
) -> AfterRender[C] {
  let connection = { state: AwaitingRender, release, }
  scheduler.add(
    @cmd.custom_cmd(kind=@cmd.after_render, _ => {
      if connection.state is AwaitingRender {
        connection.state = match attach(connection) {
          Some(attached) => Attached(attached)
          None => Detached
        }
      }
    }),
  )
  connection
}

///|
/// Runs `action` after the next render while the connection is attached.
fn[C] AfterRender::after_render(
  self : AfterRender[C],
  scheduler : &@cmd.Scheduler,
  action : (C) -> Unit,
) -> Unit {
  scheduler.add(
    @cmd.custom_cmd(kind=@cmd.after_render, _ => {
      if self.state is Attached(attached) {
        action(attached)
      }
    }),
  )
}

///|
/// Runs `action` now if the connection is attached.
fn[C] AfterRender::with_attached(
  self : AfterRender[C],
  action : (C) -> Unit,
) -> Unit {
  if self.state is Attached(attached) {
    action(attached)
  }
}

///|
fn[C] AfterRender::detach(self : AfterRender[C]) -> Unit {
  let previous = self.state
  self.state = Detached
  if previous is Attached(attached) {
    (self.release)(attached)
  }
}
