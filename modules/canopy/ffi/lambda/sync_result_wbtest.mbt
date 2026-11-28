///|
test "sync error reports accepted history and keeps a valid projection usable" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("partial-sync-result-v011")
  defer destroy_editor(handle)
  let before_version = get_version_json(handle)
  let partial =
    #|{"schema":2,"format":"event-graph-walker/text-sync","operations":[{"id":{"replica_id":"partial-sync-remote-v011","sequence":0},"parents":[],"kind":"insert","content":"A","origin_left":null,"origin_right":null},{"id":{"replica_id":"partial-sync-remote-v011","sequence":2},"parents":[{"replica_id":"partial-sync-remote-v011","sequence":1}],"kind":"insert","content":"C","origin_left":{"replica_id":"partial-sync-remote-v011","sequence":1},"origin_right":null}],"heads":[{"replica_id":"partial-sync-remote-v011","sequence":2}]}
  let result = apply_sync_json(handle, partial)
  match @json.parse(result) {
    Object(fields) => {
      assert_true(fields.contains("error"))
      assert_eq(fields.get("history_advanced"), Some(Json::boolean(true)))
      assert_eq(fields.get("projection_available"), Some(Json::boolean(true)))
    }
    _ => fail("expected partial-admission error metadata")
  }
  assert_eq(get_text(handle), "A")
  assert_true(get_version_json(handle) != before_version)
  let missing_parent =
    #|{"schema":2,"format":"event-graph-walker/text-sync","operations":[{"id":{"replica_id":"partial-sync-remote-v011","sequence":1},"parents":[{"replica_id":"partial-sync-remote-v011","sequence":0}],"kind":"insert","content":"B","origin_left":{"replica_id":"partial-sync-remote-v011","sequence":0},"origin_right":null}],"heads":[{"replica_id":"partial-sync-remote-v011","sequence":1}]}
  assert_eq(apply_sync_json(handle, missing_parent), "ok")
  assert_eq(get_text(handle), "ABC")
}
