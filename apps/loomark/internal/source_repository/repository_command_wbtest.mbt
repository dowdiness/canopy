///|
test "repository open begins with a complete store scan" {
  inspect(
    Repr(open(result=_ => @cmd.none)),
    content="IndexedDBScan({ name: \"loomark\", version: 1, store_name: \"documents\" })",
  )
}

///|
test "repository open routes legacy migration through one atomic mutation" {
  inspect(
    Repr(
      continue_open(
        Reconciliation::Migrate([
          @indexed_db.Mutation::Put("source/v1/document-1", "encoded"),
          @indexed_db.Mutation::Delete(LEGACY_ACTIVE_KEY),
        ]),
        _ => @cmd.none,
      ),
    ),
    content="IndexedDBMutate(\n  { name: \"loomark\", version: 1, store_name: \"documents\" },\n  [Put(\"source/v1/document-1\", \"encoded\"), Delete(\"active\")],\n)",
  )
}

///|
test "repository save commits one Source record" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# Old\n").unwrap(),
  ]).unwrap()
  inspect(
    Repr(save(snapshot, "document-1", "# Saved\n", result=_ => @cmd.none)),
    content="IndexedDBPut(\n  { name: \"loomark\", version: 1, store_name: \"documents\" },\n  \"source/v1/document-1\",\n  \"{\\\"document_id\\\":\\\"document-1\\\",\\\"text\\\":\\\"# Saved\\\\n\\\"}\",\n)",
  )
}

///|
test "repository save rejects missing identity before storage" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# Old\n").unwrap(),
  ]).unwrap()
  let emitted : Array[SaveResult] = []
  let command = save(snapshot, "missing", "# Invalid\n", result=result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [SaveResult::Failed(SaveFailure::InvalidSource)])
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "save completion publishes the next snapshot after storage completes" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# Old\n").unwrap(),
    SourceRecord::new("document-2", "# Other\n").unwrap(),
  ]).unwrap()
  let source = SourceRecord::new("document-1", "# Saved\n").unwrap()
  let emitted : Array[SaveResult] = []
  let _ = finish_save(snapshot, source, @indexed_db.WriteResult::Stored, result => {
    emitted.push(result)
    @cmd.none
  })
  guard emitted.get(0) is Some(SaveResult::Stored(next)) else {
    fail("stored completion did not publish a snapshot")
  }
  assert_eq(next.source("document-1").unwrap().text(), "# Saved\n")
  assert_eq(next.source("document-2").unwrap().text(), "# Other\n")
}

///|
test "open write completion rescans and preserves failure classifications" {
  inspect(
    Repr(finish_open_write(@indexed_db.WriteResult::Stored, _ => @cmd.none)),
    content="IndexedDBScan({ name: \"loomark\", version: 1, store_name: \"documents\" })",
  )
  let emitted : Array[OpenResult] = []
  for
    stored in [
      @indexed_db.WriteResult::Unavailable,
      @indexed_db.WriteResult::QuotaExceeded,
      @indexed_db.WriteResult::Failed,
    ] {
    let _ = finish_open_write(stored, result => {
      emitted.push(result)
      @cmd.none
    })
  }
  assert_eq(emitted, [
    OpenResult::Failed(OpenFailure::StorageUnavailable),
    OpenResult::Failed(OpenFailure::QuotaExceeded),
    OpenResult::Failed(OpenFailure::WriteFailed),
  ])
}

///|
test "create rejects an observed occupied key before storage" {
  let source = SourceRecord::new("document-1", "# One\n").unwrap()
  let snapshot = RepositorySnapshot::new(
    [source],
    Catalog::from_entries([
      CatalogEntry::new("document-1", Some("One")).unwrap(),
    ]).unwrap(),
    [],
    ["source/v1/document-1", "source/v1/corrupt"],
  )
  let emitted : Array[CreateResult] = []
  let command = create_with_document_id(snapshot, "", result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [
    CreateResult::Failed(CreateFailure::DocumentIdentityUnavailable),
  ])
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
  let emitted : Array[CreateResult] = []
  let command = create_with_document_id(snapshot, "corrupt", result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [
    CreateResult::Failed(CreateFailure::DocumentIdentityUnavailable),
  ])
  assert_false(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "create prepares one put for a valid identity" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# One\n").unwrap(),
  ]).unwrap()
  inspect(
    Repr(create_with_document_id(snapshot, "document-2", _ => @cmd.none)),
    content="IndexedDBPut(\n  { name: \"loomark\", version: 1, store_name: \"documents\" },\n  \"source/v1/document-2\",\n  \"{\\\"document_id\\\":\\\"document-2\\\",\\\"text\\\":\\\"# Untitled\\\\n\\\"}\",\n)",
  )
}

///|
test "create completion maps stored and write failures" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# One\n").unwrap(),
  ]).unwrap()
  let source = SourceRecord::new("document-2", "# Untitled\n").unwrap()
  let emitted : Array[CreateResult] = []
  for
    stored in [
      @indexed_db.WriteResult::Stored,
      @indexed_db.WriteResult::Unavailable,
      @indexed_db.WriteResult::QuotaExceeded,
      @indexed_db.WriteResult::Failed,
    ] {
    let _ = finish_create(snapshot, source, stored, result => {
      emitted.push(result)
      @cmd.none
    })
  }
  guard emitted.get(0) is Some(CreateResult::Created(created, "document-2")) else {
    fail("stored not created")
  }
  assert_eq(created.source("document-1").unwrap().text(), "# One\n")
  assert_eq(created.source("document-2").unwrap().text(), "# Untitled\n")
  assert_eq(
    emitted.get(1),
    Some(CreateResult::Failed(CreateFailure::StorageUnavailable)),
  )
  assert_eq(
    emitted.get(2),
    Some(CreateResult::Failed(CreateFailure::QuotaExceeded)),
  )
  assert_eq(
    emitted.get(3),
    Some(CreateResult::Failed(CreateFailure::WriteFailed)),
  )
}
