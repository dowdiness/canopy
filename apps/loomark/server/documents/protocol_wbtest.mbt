///|
test "mutations distinguish deletion, empty text and strict request shape" {
  let id = "a2000000-0000-4000-8000-000000000001"
  let body : Json = {
    "operationId": Json(id),
    "baseRevision": 0,
    "text": "",
    "changedAt": 1700000000000,
  }
  guard decode_mutation(body, deleting=false) is Some(save) else {
    fail("Expected save")
  }
  assert_true(save.content is Some({ text: "", changed_at: 1700000000000.0, }))
  assert_true(decode_mutation(body, deleting=true) is None)
  let deletion : Json = { "operationId": Json(id), "baseRevision": 2 }
  guard decode_mutation(deletion, deleting=true) is Some(remove) else {
    fail("Expected delete")
  }
  assert_true(remove.content is None)
  assert_true(decode_mutation(deletion, deleting=false) is None)
  assert_true(
    decode_mutation(
      { "operationId": Json(id), "baseRevision": 0, "owner": "forged" },
      deleting=false,
    )
    is None,
  )
}

///|
test "a save needs a Change time in whole milliseconds since the epoch" {
  let id = "a2000000-0000-4000-8000-000000000001"
  fn save(changed_at : Json) -> Json {
    {
      "operationId": Json(id),
      "baseRevision": 0,
      "text": "text",
      "changedAt": changed_at,
    }
  }
  assert_true(decode_mutation(save(0), deleting=false) is Some(_))
  assert_true(decode_mutation(save(-1), deleting=false) is None)
  assert_true(decode_mutation(save(1.5), deleting=false) is None)
  assert_true(decode_mutation(save("1"), deleting=false) is None)
  assert_true(
    decode_mutation(
      { "operationId": Json(id), "baseRevision": 0, "text": "text" },
      deleting=false,
    )
    is None,
  )
}
