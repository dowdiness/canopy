// Whitebox tests for the file load/save FFI surface (file_io.mbt). The inbound
// load path (`on_file_opened`) and the no-host safety of `load_file`/`save_file`
// are exercisable without a JS host; the actual picker/write lives in the
// injected `@io.FileHost` and is covered by the app-layer integration.

///|
test "on_file_opened replaces the document and records an undoable edit" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("file_io_load_agent")
  // Seed without recording so the only undo entry is the file load itself.
  set_text(handle, "original source")
  on_file_opened(handle, "loaded from file", 1000)
  assert_eq(get_text(handle), "loaded from file")
  // Routing through `set_text_and_record` (not `set_text`) is the whole point:
  // a user-visible load must be undoable.
  assert_eq(undo_manager_can_undo(handle), true)
  destroy_editor(handle)
}

///|
test "load_file / save_file are safe no-ops when no FileHost is registered" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("file_io_nohost_agent")
  set_text(handle, "abc")
  // No `register_file_host` call in this test: `@io.request_open` /
  // `@io.save_text` must no-op rather than crash, and leave the doc untouched.
  load_file(handle)
  save_file(handle, "untitled.lambda")
  assert_eq(get_text(handle), "abc")
  destroy_editor(handle)
}

///|
test "on_file_opened on an unknown handle is a no-op" {
  reset_coordinator_for_phase1_tests()
  // Models a file read completing after the editor was destroyed: the handle
  // misses the registry and the loaded content is dropped, not crashed on.
  on_file_opened(999999, "content for a dead editor", 1)
  assert_eq(get_text(999999), "")
}
