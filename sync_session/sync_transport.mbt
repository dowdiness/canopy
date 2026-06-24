///|
pub(open) trait SyncTransport {
  fn send(Self, Bytes) -> Unit
  fn on_receive(Self, (Bytes) -> Unit) -> Unit
  fn close(Self) -> Unit
}
