///|
/// Return an immutable detached snapshot for private browser assertions.
pub fn private_dev_host_snapshot() -> String {
  detached_snapshot.val
}

///|
/// Return the last committed logical focus token, detached from the DOM.
pub fn private_dev_host_focus_token() -> String {
  detached_focus_token.val
}
