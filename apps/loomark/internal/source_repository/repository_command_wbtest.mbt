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
test "repository save begins by committing the Source record" {
  let catalog = Catalog::from_entries([]).unwrap()
  inspect(
    Repr(save(catalog, "document-1", "# Saved\n", result=_ => @cmd.none)),
    content="IndexedDBPut(\n  { name: \"loomark\", version: 1, store_name: \"documents\" },\n  \"source/v1/document-1\",\n  \"{\\\"document_id\\\":\\\"document-1\\\",\\\"text\\\":\\\"# Saved\\\\n\\\"}\",\n)",
  )
}

///|
test "repository save rejects an invalid identity before storage" {
  let catalog = Catalog::from_entries([]).unwrap()
  let emitted : Array[SaveResult] = []
  let _ = save(catalog, "", "# Invalid\n", result=result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [SaveResult::Failed(SaveFailure::InvalidSource)])
}
