///|
test "public writer starts a transition-produced write" {
  let account = try! @source_repository.AccountId::parse("account")
  let document = try! @source_repository.Document::create("document", "before")
  let checkpoint = @source_repository.SyncCheckpoint::enroll(account, document)
  let write = checkpoint.edit("after").unwrap()
  let (_, started) = @source_repository.CheckpointWriter::new().enqueue(write)
  assert_eq(started, Some(write))
}
