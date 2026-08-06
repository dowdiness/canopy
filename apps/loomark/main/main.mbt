///|
/// Start the page-owned Loomark application exactly once.
fn main {
  ignore(@app.mount_standalone("app", ""))
}
