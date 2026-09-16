///|
test "mutations distinguish deletion, empty text and strict request shape" {
  let id = "a2000000-0000-4000-8000-000000000001"
  let body : Json = {
    "operationId": id.to_json(),
    "baseRevision": 0,
    "text": "",
  }
  guard decode_mutation(body, deleting=false) is Some(save) else {
    fail("Expected save")
  }
  assert_true(save.text == Some(""))
  assert_true(decode_mutation(body, deleting=true) is None)
  let deletion : Json = { "operationId": id.to_json(), "baseRevision": 2 }
  guard decode_mutation(deletion, deleting=true) is Some(remove) else {
    fail("Expected delete")
  }
  assert_true(remove.text is None)
  assert_true(decode_mutation(deletion, deleting=false) is None)
  assert_true(
    decode_mutation(
      { "operationId": id.to_json(), "baseRevision": 0, "owner": "forged" },
      deleting=false,
    )
    is None,
  )
}
