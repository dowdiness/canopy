///|
fn test_source(id : String, text : String) -> SourceRecord {
  SourceRecord::new(id, text).unwrap()
}

///|
fn test_encoded_source(id : String, text : String) -> String {
  encode_source(test_source(id, text))
}

///|
test "reconciliation isolates corrupt and unsupported records" {
  let valid = test_source("document-b", "# Same\n")
  let result = reconcile_scan([
    @indexed_db.ScanEntry::StringRecord(
      "source/v1/document-b",
      encode_source(valid),
    ),
    @indexed_db.ScanEntry::StringRecord("source/v1/broken", "not-json"),
    @indexed_db.ScanEntry::StringRecord(
      "source/v1/wrong-key",
      test_encoded_source("wrong-payload", "# Wrong\n"),
    ),
    @indexed_db.ScanEntry::StringRecord("source/v2/future", "future"),
    @indexed_db.ScanEntry::StringRecord("catalog/v1", "obsolete"),
    @indexed_db.ScanEntry::StringRecord("other", "value"),
    @indexed_db.ScanEntry::UnsupportedValue("binary"),
    @indexed_db.ScanEntry::UnsupportedKey(6),
  ])
  guard result is Reconciliation::Ready(snapshot) else {
    fail("expected ready snapshot")
  }
  assert_eq(snapshot.sources().to_owned(), [valid])
  assert_eq(snapshot.catalog().entries().to_owned(), [
    CatalogEntry::new("document-b", Some("Same")).unwrap(),
  ])
  assert_eq(snapshot.issues().to_owned(), [
    RepositoryIssue::InvalidSource("source/v1/broken"),
    RepositoryIssue::SourceIdentityMismatch("source/v1/wrong-key"),
    RepositoryIssue::UnsupportedSourceSchema("source/v2/future"),
    RepositoryIssue::UnknownRecord("catalog/v1"),
    RepositoryIssue::UnknownRecord("other"),
    RepositoryIssue::UnsupportedRecord("binary"),
    RepositoryIssue::UnsupportedKey(6),
  ])
}

///|
test "legacy migration decisions preserve collision safety" {
  let active = test_encoded_source("legacy-id", "# Legacy\n")
  guard reconcile_scan([
      @indexed_db.ScanEntry::StringRecord(LEGACY_ACTIVE_KEY, active),
    ])
    is Reconciliation::Migrate(mutations) else {
    fail("expected atomic legacy move")
  }
  assert_eq(mutations, [
    @indexed_db.Mutation::Put("source/v1/legacy-id", active),
    @indexed_db.Mutation::Delete(LEGACY_ACTIVE_KEY),
  ])

  guard reconcile_scan([
      @indexed_db.ScanEntry::StringRecord(LEGACY_ACTIVE_KEY, active),
      @indexed_db.ScanEntry::StringRecord(
        "source/v1/legacy-id",
        test_encoded_source("legacy-id", "# Authority\n"),
      ),
    ])
    is Reconciliation::Migrate(mutations) else {
    fail("expected stale active deletion")
  }
  assert_eq(mutations, [@indexed_db.Mutation::Delete(LEGACY_ACTIVE_KEY)])

  guard reconcile_scan([
      @indexed_db.ScanEntry::StringRecord(LEGACY_ACTIVE_KEY, active),
      @indexed_db.ScanEntry::StringRecord("source/v1/legacy-id", "corrupt"),
    ])
    is Reconciliation::Empty(issues, occupied) else {
    fail("expected collision without mutation")
  }
  assert_eq(occupied, ["source/v1/legacy-id"])
  assert_true(
    issues.contains(RepositoryIssue::LegacyMigrationCollision("legacy-id")),
  )
}

///|
test "invalid legacy is preserved and an empty repository stays empty" {
  guard reconcile_scan([
      @indexed_db.ScanEntry::StringRecord(LEGACY_ACTIVE_KEY, "not-json"),
    ])
    is Reconciliation::Empty(issues, occupied) else {
    fail("expected empty repository")
  }
  assert_eq(occupied, [])
  assert_eq(issues, [RepositoryIssue::InvalidLegacyRecord])
}

///|
test "next catalog replaces one identity and keeps lexical order" {
  let current = Catalog::from_entries([
    CatalogEntry::new("document-b", Some("Old")).unwrap(),
    CatalogEntry::new("document-a", None).unwrap(),
  ]).unwrap()
  let (next, issues) = next_catalog(current, "document-b", "# New\n")
  assert_eq(next.entries().to_owned(), [
    CatalogEntry::new("document-a", None).unwrap(),
    CatalogEntry::new("document-b", Some("New")).unwrap(),
  ])
  assert_eq(issues, [])
}
