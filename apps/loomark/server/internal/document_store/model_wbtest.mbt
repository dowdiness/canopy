///|
test "revision admission preserves the JS safe-integer boundary" {
  inspect(valid_revision(9007199254740990.0, saved=false), content="true")
  inspect(valid_revision(9007199254740991.0, saved=false), content="false")
  inspect(valid_revision(9007199254740991.0, saved=true), content="true")
  inspect(valid_revision(9007199254740992.0, saved=true), content="false")
  inspect(valid_revision(-1.0, saved=false), content="false")
  inspect(valid_revision(1.5, saved=false), content="false")
  inspect(valid_revision(0.0, saved=true), content="false")
}

///|
test "UUID validation checks the entire value, version and variant" {
  inspect(
    valid_identity("a2000000-0000-4000-8000-000000000001"),
    content="true",
  )
  inspect(
    valid_identity("A2000000-0000-4000-B000-000000000001"),
    content="true",
  )
  inspect(
    valid_identity("a2000000-0000-9000-8000-000000000001"),
    content="false",
  )
  inspect(
    valid_identity("a2000000-0000-4000-7000-000000000001"),
    content="false",
  )
  inspect(
    valid_identity("a2000000-0000-4000-8000-000000000001/x"),
    content="false",
  )
  inspect(
    valid_identity("00000000-0000-0000-0000-000000000000"),
    content="false",
  )
  inspect(
    valid_identity("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"),
    content="false",
  )
}
