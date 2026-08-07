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
pub fn dev_host_select_raw() -> Unit {
  @app.select_raw()
}

///|
pub fn dev_host_select_block() -> Unit {
  @app.select_block()
}

///|
pub fn dev_host_select_preview() -> Unit {
  @app.select_preview()
}

///|
pub fn dev_host_restore_snapshot(
  version : Int,
  source : String,
  mode : String,
) -> Unit {
  @app.restore_snapshot(version, source, mode)
}

///|
pub fn dev_host_force_editor_failure() -> Unit {
  @app.force_editor_failure()
}

///|
/// Arm only the private parser-publication recovery seam.
pub fn dev_host_force_parser_failure() -> Unit {
  @app.force_parser_failure()
}

///|
pub fn dev_host_force_reconstruction_failure() -> Unit {
  @app.force_reconstruction_failure()
}

///|
pub fn dev_host_focus_preview() -> Unit {
  @app.focus_preview()
}

///|
pub fn dev_host_focus_raw() -> Unit {
  @app.focus_raw()
}

///|
pub fn dev_host_focus_block() -> Unit {
  @app.focus_block()
}

///|
pub fn dev_host_probe_stale_block_selection() -> Unit {
  @app.probe_stale_block_selection()
}

///|
pub fn dev_host_probe_deleted_block_selection() -> Unit {
  @app.probe_deleted_block_selection()
}

///|
pub fn dev_host_capture_focus() -> String {
  @app.capture_focus()
}

///|
pub fn dev_host_restore_focus(token : String) -> Unit {
  @app.restore_focus(token)
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
