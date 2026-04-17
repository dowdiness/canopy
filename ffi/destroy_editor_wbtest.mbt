// Whitebox tests for the destroy_editor lifecycle in the FFI package.
// Covers: handle removal, last_created_handle reset, unknown-handle no-op,
// and create → destroy → recreate leaving exactly one entry.

///|
fn clear_lambda_handles() -> Unit {
  let keys = lambda_handles.keys().to_array()
  for k in keys {
    lambda_handles.remove(k)
  }
  let vkeys = view_states.keys().to_array()
  for k in vkeys {
    view_states.remove(k)
  }
  let pvkeys = pretty_view_states.keys().to_array()
  for k in pvkeys {
    pretty_view_states.remove(k)
  }
  last_created_handle.val = None
}

///|
test "destroy_editor: clears handle state" {
  clear_lambda_handles()
  let handle = create_editor("test-destroy-1")
  destroy_editor(handle)
  // Whitebox: handle must be removed from the registry
  inspect(lambda_handles.contains(handle), content="false")
  // Whitebox: last_created_handle must be reset to None
  inspect(last_created_handle.val is None, content="true")
  // Public-API fallback: unknown handle returns empty/default values
  inspect(get_text(handle), content="")
  inspect(get_diagnostics_json(handle), content="[]")
}

///|
test "destroy_editor: unknown handle is a safe no-op" {
  clear_lambda_handles()
  // Must not crash or abort
  destroy_editor(999999)
  inspect(lambda_handles.contains(999999), content="false")
}

///|
test "destroy_editor: create → destroy → recreate leaves exactly one entry" {
  clear_lambda_handles()
  let h1 = create_editor("agent-a")
  destroy_editor(h1)
  // Recreate after teardown — this is the isolation case that a bug
  // in destroy's cleanup (e.g. stale next_handle, leftover scope) could break.
  let h2 = create_editor("agent-b")
  inspect(lambda_handles.contains(h1), content="false")
  inspect(lambda_handles.contains(h2), content="true")
  inspect(lambda_handles.length(), content="1")
  // Cleanup
  destroy_editor(h2)
}
