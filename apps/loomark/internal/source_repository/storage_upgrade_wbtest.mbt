///|
/// The version-1 frame of `replica`: the same frame without any `changed_at`.
fn version_1_frame(replica : DocumentReplica) -> String {
  fn strip(value : Json) -> Json {
    match value {
      Json::Object(fields) => {
        let kept : Map[String, Json] = Map([])
        for key, field in fields {
          if key != "changed_at" {
            kept[key] = strip(field)
          }
        }
        Json::object(kept)
      }
      _ => value
    }
  }

  let encoded = encode_replica(replica)
  let (length, start) = decode_header_length(encoded).unwrap()
  let header = @json.parse(encoded[start:start + length].to_owned()) catch {
    _ => abort("header")
  }
  let header = strip(header).stringify()
  replica_test_frame(header, encoded[start + length:].to_owned())
}

///|
test "a version-1 Source is rewritten with the epoch as its Change time" {
  let id = test_document_id("document")
  let key = source_key(id)
  let version_1 = "{\"document_id\":\"\{id.value()}\",\"text\":\"# A\\n\"}"
  assert_eq(decode_document(key, version_1), None)
  let upgraded = upgrade_record(1, key, version_1).unwrap()
  assert_eq(
    decode_document(key, upgraded),
    Some(Document::create(id, "# A\n", ChangeTime(0.0))),
  )
}

///|
test "version-1 Replicas keep every state and text, at the epoch" {
  let at_epoch = (replica : DocumentReplica, text : String) => {
    guard replica.edit(
        Document::create(test_document_id("document"), text, ChangeTime(0.0)),
      )
      is EditPlan::Persist(write) else {
      abort("edit")
    }
    write.replica()
  }
  let sending = sending_replica("sent", TEST_OPERATION_1)
  let saved = initial_replica("base")
    |> start_save(TEST_OPERATION_1)
    |> ReplicaWrite::replica
  let saved = saved
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let replicas = [
    initial_replica("unpublished"),
    at_epoch(sending, "typed while sending"),
    reconcile_change(saved, remote_present(2.0, "remote")).replica(),
    at_epoch(sending, "newer").request_deletion().replica(),
  ]
  for replica in replicas {
    let version_1 = version_1_frame(replica)
    assert_eq(decode_replica(test_replica_key(), version_1), None)
    let upgraded = upgrade_record(1, test_replica_key(), version_1).unwrap()
    assert_eq(decode_replica(test_replica_key(), upgraded), Some(replica))
  }
}

///|
test "the upgrade leaves other records and later versions alone" {
  let id = test_document_id("document")
  let version_1 = "{\"document_id\":\"\{id.value()}\",\"text\":\"x\"}"
  assert_eq(upgrade_record(2, source_key(id), version_1), None)
  assert_eq(upgrade_record(1, "other", version_1), None)
  assert_eq(upgrade_record(1, source_key(id), "not json"), None)
  assert_eq(
    upgrade_record(
      1,
      source_key(id),
      "{\"document_id\":\"\{id.value()}\",\"text\":\"x\",\"change_order\":0}",
    ),
    None,
  )
}
