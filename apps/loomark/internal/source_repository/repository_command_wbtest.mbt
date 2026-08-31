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
  let next = accepted_source(snapshot, source)
  let emitted : Array[SaveResult] = []
  for
    stored in [
      @indexed_db.WriteResult::Stored,
      @indexed_db.WriteResult::Unavailable,
      @indexed_db.WriteResult::QuotaExceeded,
      @indexed_db.WriteResult::Failed,
    ] {
    let _ = finish_save(next, stored, result => {
      emitted.push(result)
      @cmd.none
    })
  }
  assert_eq(emitted.get(0), Some(SaveResult::Stored(next)))
  assert_eq(next.source("document-1").unwrap().text(), "# Saved\n")
  assert_eq(next.source("document-2").unwrap().text(), "# Other\n")
  assert_eq(
    emitted.get(1),
    Some(SaveResult::Failed(SaveFailure::StorageUnavailable)),
  )
  assert_eq(
    emitted.get(2),
    Some(SaveResult::Failed(SaveFailure::QuotaExceeded)),
  )
  assert_eq(emitted.get(3), Some(SaveResult::Failed(SaveFailure::WriteFailed)))
}

///|
test "accepted deletion preserves unrelated repository observations" {
  let snapshot = RepositorySnapshot::new(
    [
      SourceRecord::new("document-1", "# One\n").unwrap(),
      SourceRecord::new("document-2", "# Two\n").unwrap(),
    ],
    Catalog::from_entries([
      CatalogEntry::new("document-1", Some("One")).unwrap(),
      CatalogEntry::new("document-2", Some("Two")).unwrap(),
    ]).unwrap(),
    [
      RepositoryIssue::NameDerivationFailed("document-1"),
      RepositoryIssue::UnknownRecord("metadata/future"),
    ],
    ["source/v1/document-1", "source/v1/document-2", "source/v1/corrupt"],
  )
  let next = accepted_deletion(snapshot, "document-1").unwrap()
  assert_eq(next.sources().map(source => source.document_id()), ["document-2"])
  assert_eq(next.issues(), [RepositoryIssue::UnknownRecord("metadata/future")])
  assert_eq(next.occupied_source_keys(), [
    "source/v1/corrupt", "source/v1/document-2",
  ])
}

///|
test "repository delete prepares one atomic Source deletion" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# One\n").unwrap(),
    SourceRecord::new("document-2", "# Two\n").unwrap(),
  ]).unwrap()
  inspect(
    Repr(delete(snapshot, "document-2", result=_ => @cmd.none)),
    content="IndexedDBMutate(\n  { name: \"loomark\", version: 1, store_name: \"documents\" },\n  [Delete(\"source/v1/document-2\")],\n)",
  )
}

///|
test "repository delete rejects unknown and final identities before storage" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# One\n").unwrap(),
  ]).unwrap()
  let emitted : Array[DeleteResult] = []
  let unknown = delete(snapshot, "missing", result=result => {
    emitted.push(result)
    @cmd.none
  })
  let last_source = delete(snapshot, "document-1", result=result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [
    DeleteResult::Failed(DeleteFailure::InvalidSource),
    DeleteResult::Failed(DeleteFailure::LastSource),
  ])
  assert_false(@debug.to_string(unknown).contains("IndexedDBMutate"))
  assert_false(@debug.to_string(last_source).contains("IndexedDBMutate"))
}

///|
test "delete completion publishes only its prepared snapshot" {
  let original = RepositorySnapshot::from_sources([
    SourceRecord::new("document-1", "# One\n").unwrap(),
    SourceRecord::new("document-2", "# Two\n").unwrap(),
  ]).unwrap()
  let next = accepted_deletion(original, "document-1").unwrap()
  let emitted : Array[DeleteResult] = []
  for
    stored in [
      @indexed_db.WriteResult::Stored,
      @indexed_db.WriteResult::Unavailable,
      @indexed_db.WriteResult::QuotaExceeded,
      @indexed_db.WriteResult::Failed,
    ] {
    let _ = finish_delete(next, stored, result => {
      emitted.push(result)
      @cmd.none
    })
  }
  assert_eq(emitted.get(0), Some(DeleteResult::Deleted(next)))
  assert_true(next.source("document-1") is None)
  assert_eq(next.source("document-2").unwrap().text(), "# Two\n")
  assert_eq(
    emitted.get(1),
    Some(DeleteResult::Failed(DeleteFailure::StorageUnavailable)),
  )
  assert_eq(
    emitted.get(2),
    Some(DeleteResult::Failed(DeleteFailure::QuotaExceeded)),
  )
  assert_eq(
    emitted.get(3),
    Some(DeleteResult::Failed(DeleteFailure::WriteFailed)),
  )
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
  let next = accepted_source(snapshot, source)
  let emitted : Array[CreateResult] = []
  for
    stored in [
      @indexed_db.WriteResult::Stored,
      @indexed_db.WriteResult::Unavailable,
      @indexed_db.WriteResult::QuotaExceeded,
      @indexed_db.WriteResult::Failed,
    ] {
    let _ = finish_create(next, "document-2", stored, result => {
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
