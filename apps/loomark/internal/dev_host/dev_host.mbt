///|
/// Private JavaScript link root for the disposable Vanilla harness.
pub fn mount_dev_host(host_id : String, source : String) -> String {
  @app.mount_private_dev_host(host_id, source)
}

///|
pub fn dev_host_snapshot() -> String {
  @app.private_dev_host_snapshot()
}

///|
pub fn dev_host_request_source(source : String) -> Unit {
  @app.dispatch_private_dev_host("source|" + source)
}

///|
pub fn dev_host_select_raw() -> Unit {
  @app.dispatch_private_dev_host("select-raw")
}

///|
pub fn dev_host_select_block() -> Unit {
  @app.dispatch_private_dev_host("select-block")
}

///|
pub fn dev_host_select_preview() -> Unit {
  @app.dispatch_private_dev_host("select-preview")
}

///|
pub fn dev_host_restore_snapshot(
  version : Int,
  source : String,
  mode : String,
) -> Unit {
  let payload : Map[String, Json] = {
    "version": version.to_json(),
    "source": source.to_json(),
    "mode": mode.to_json(),
  }
  @app.dispatch_private_dev_host(
    "restore-snapshot|" + Json::object(payload).stringify(),
  )
}

///|
pub fn dev_host_force_editor_failure() -> Unit {
  @app.dispatch_private_dev_host("editor-failure")
}

///|
/// Arm only the private parser-publication recovery seam.
pub fn dev_host_force_parser_failure() -> Unit {
  @app.dispatch_private_dev_host("force-parser-failure")
}

///|
pub fn dev_host_force_reconstruction_failure() -> Unit {
  @app.dispatch_private_dev_host("force-reconstruction-failure")
}

///|
pub fn dev_host_arm_raw_render_barrier() -> Unit {
  @app.dispatch_private_dev_host("arm-raw-render-barrier")
}

///|
pub fn dev_host_release_raw_render_barrier() -> Unit {
  @app.dispatch_private_dev_host("release-raw-render-barrier")
}

///|
pub fn dev_host_focus_preview() -> Unit {
  @app.dispatch_private_dev_host("focus-preview")
}

///|
pub fn dev_host_focus_raw() -> Unit {
  @app.dispatch_private_dev_host("focus-raw")
}

///|
pub fn dev_host_focus_block() -> Unit {
  @app.dispatch_private_dev_host("focus-block")
}

///|
pub fn dev_host_probe_stale_block_selection() -> Unit {
  @app.dispatch_private_dev_host("probe-stale-block-selection")
}

///|
pub fn dev_host_probe_deleted_block_selection() -> Unit {
  @app.dispatch_private_dev_host("probe-deleted-block-selection")
}

///|
pub fn dev_host_capture_focus() -> String {
  @app.private_dev_host_focus_token()
}

///|
pub fn dev_host_restore_focus(token : String) -> Unit {
  @app.dispatch_private_dev_host("restore-focus|" + token)
}

///|
pub fn dev_host_write_selection(start : Int, end : Int) -> Unit {
  @app.dispatch_private_dev_host(
    "write-selection|" + start.to_string() + "|" + end.to_string(),
  )
}

///|
pub fn dev_host_write_selection_failure() -> Unit {
  @app.dispatch_private_dev_host("write-selection-failure")
}

///|
pub fn dev_host_measure_preview() -> Unit {
  @app.dispatch_private_dev_host("measure-preview")
}

///|
pub fn dev_host_measure_failure() -> Unit {
  @app.dispatch_private_dev_host("measure-failure")
}

///|
pub fn dev_host_stop_listening() -> Unit {
  @app.dispatch_private_dev_host("stop-listening")
}

///|
pub fn dev_host_fail(message : String) -> Unit {
  @app.dispatch_private_dev_host("fatal|" + message)
}
