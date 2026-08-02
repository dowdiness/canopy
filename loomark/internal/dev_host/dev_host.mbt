///|
/// Private JavaScript link root for the disposable Vanilla harness.
pub fn mount_dev_host(host_id : String, source : String) -> String {
  @app.mount(host_id, source)
}

///|
pub fn dev_host_snapshot() -> String {
  @app.snapshot()
}

///|
pub fn dev_host_request_source(source : String) -> Unit {
  @app.request_source(source)
}

///|
pub fn dev_host_select_preview() -> Unit {
  @app.select_preview()
}

///|
pub fn dev_host_focus_preview() -> Unit {
  @app.focus_preview()
}

///|
pub fn dev_host_write_selection(start : Int, end : Int) -> Unit {
  @app.write_selection(start, end)
}

///|
pub fn dev_host_write_selection_failure() -> Unit {
  @app.write_selection_failure()
}

///|
pub fn dev_host_measure_preview() -> Unit {
  @app.measure_preview()
}

///|
pub fn dev_host_measure_failure() -> Unit {
  @app.measure_failure()
}

///|
pub fn dev_host_stop_listening() -> Unit {
  @app.stop_listening()
}

///|
pub fn dev_host_fail(message : String) -> Unit {
  @app.fail(message)
}
