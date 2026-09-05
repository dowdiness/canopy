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
      "source/v1/old", "{\"document_id\":\"old\",\"text\":\"# Old\\n\"}",
    ),
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
  guard result is Reconciliation::Ready(snapshot, Some(initial)) else {
    fail("expected ready snapshot")
  }
  assert_eq(initial, valid)
  assert_eq(snapshot.sources().to_owned(), [valid])
  assert_eq(snapshot.occupied_source_keys().to_owned(), [
    "source/v1/broken", "source/v1/document-b", "source/v1/old", "source/v1/wrong-key",
  ])
  assert_eq(snapshot.catalog().entries().to_owned(), [
    CatalogEntry::new("document-b", Some("Same")).unwrap(),
  ])
  assert_eq(snapshot.issues().to_owned(), [
    RepositoryIssue::InvalidSource("source/v1/broken"),
    RepositoryIssue::UnsupportedRecord("source/v1/old"),
    RepositoryIssue::SourceIdentityMismatch("source/v1/wrong-key"),
    RepositoryIssue::UnsupportedSourceSchema("source/v2/future"),
    RepositoryIssue::UnknownRecord("catalog/v1"),
    RepositoryIssue::UnknownRecord("other"),
    RepositoryIssue::UnsupportedRecord("binary"),
    RepositoryIssue::UnsupportedKey(6),
  ])
}

///|
test "initial Document is the accepted Editing Document or deterministic fallback" {
  let selected = SourceRecord::new(
    "document-a",
    "# A\n",
    change_order=ChangeOrder::from_int64(20L).unwrap(),
  ).unwrap()
  let editing = SourceRecord::new(
    "document-b",
    "# B\n",
    change_order=ChangeOrder::from_int64(10L).unwrap(),
  ).unwrap()
  let sources = [
    @indexed_db.ScanEntry::StringRecord(
      source_key("document-a").unwrap(),
      encode_source(selected),
    ),
    @indexed_db.ScanEntry::StringRecord(
      source_key("document-b").unwrap(),
      encode_source(editing),
    ),
  ]
  let cases : Array[(Array[@indexed_db.ScanEntry], SourceRecord)] = [
    ([], selected),
    ([StringRecord(EDITING_DOCUMENT_KEY, "document-b")], editing),
    ([StringRecord(EDITING_DOCUMENT_KEY, "")], selected),
    ([StringRecord(EDITING_DOCUMENT_KEY, "missing")], selected),
    ([UnsupportedValue(EDITING_DOCUMENT_KEY)], selected),
  ]
  for case in cases {
    let (metadata, expected) = case
    guard reconcile_scan(metadata + sources)
      is Reconciliation::Ready(snapshot, Some(initial)) else {
      fail("expected ready repository")
    }
    assert_eq(initial, expected)
    assert_eq(snapshot.selected(), Some(selected))
    assert_eq(snapshot.issues(), [])
  }
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
    is Reconciliation::Ready(snapshot, _) else {
    fail("expected ready collision snapshot without mutation")
  }
  assert_eq(snapshot.sources().length(), 0)
  assert_eq(snapshot.occupied_source_keys().to_owned(), ["source/v1/legacy-id"])
  assert_true(
    snapshot
    .issues()
    .contains(RepositoryIssue::LegacyMigrationCollision("legacy-id")),
  )
}

///|
test "invalid legacy is preserved in a ready empty repository" {
  guard reconcile_scan([
      @indexed_db.ScanEntry::StringRecord(LEGACY_ACTIVE_KEY, "not-json"),
    ])
    is Reconciliation::Ready(snapshot, _) else {
    fail("expected ready empty repository")
  }
  assert_eq(snapshot.sources().length(), 0)
  assert_eq(snapshot.catalog().entries().length(), 0)
  assert_eq(snapshot.issues().to_owned(), [RepositoryIssue::InvalidLegacyRecord])
}

///|
test "empty scan is directly ready with an empty snapshot" {
  guard reconcile_scan([]) is Reconciliation::Ready(snapshot, None) else {
    fail("expected ready empty repository")
  }
  assert_eq(snapshot.sources(), [])
  assert_eq(snapshot.catalog().entries(), [])
}

///|
test "snapshot source and accepted Source transition preserve repository state" {
  let original = RepositorySnapshot::from_sources([
    SourceRecord::new("document-b", "# B\n").unwrap(),
    SourceRecord::new("document-a", "plain text\n").unwrap(),
  ]).unwrap()
  let accepted = accepted_source(
    original,
    SourceRecord::new("document-b", "# New B\n").unwrap(),
  )
  assert_eq(accepted.source("document-b").unwrap().text(), "# New B\n")
  assert_eq(accepted.source("missing"), None)
  assert_eq(accepted.sources().to_owned(), [
    SourceRecord::new("document-a", "plain text\n").unwrap(),
    SourceRecord::new("document-b", "# New B\n").unwrap(),
  ])
  assert_eq(accepted.catalog().entries().to_owned(), [
    CatalogEntry::new("document-a", Some("plain text")).unwrap(),
    CatalogEntry::new("document-b", Some("New B")).unwrap(),
  ])
  assert_eq(accepted.issues().to_owned(), [])
}

///|
test "acknowledged deletion applies to the latest immutable Snapshot" {
  let newer = SourceRecord::new(
    "document-b",
    "# B\n",
    change_order=ChangeOrder::from_int64(20L).unwrap(),
  ).unwrap()
  let older = SourceRecord::new(
    "document-a",
    "# A\n",
    change_order=ChangeOrder::from_int64(10L).unwrap(),
  ).unwrap()
  let snapshot = RepositorySnapshot::from_sources([older, newer]).unwrap()
  let deleted = snapshot
    .apply_acknowledged(SourceDeleted("document-b"))
    .unwrap()
  assert_eq(deleted.sources().to_owned(), [older])
  assert_eq(deleted.selected(), Some(older))
  assert_eq(deleted.apply_acknowledged(SourceDeleted("missing")), None)
}

///|
test "acknowledged deltas update and can empty the snapshot" {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new("document-a", "# A\n").unwrap(),
  ]).unwrap()
  let stored = snapshot
    .apply_acknowledged(
      SourceStored(
        SourceRecord::new(
          "document-a",
          "# A newer\n",
          change_order=ChangeOrder::from_int64(9L).unwrap(),
        ).unwrap(),
      ),
    )
    .unwrap()
  assert_eq(stored.selected().unwrap().text(), "# A newer\n")
  let deleted = stored.apply_acknowledged(SourceDeleted("document-a")).unwrap()
  assert_eq(deleted.sources(), [])
  assert_eq(deleted.catalog().entries(), [])
  assert_eq(deleted.selected(), None)
}

///|
test "accepted suffix edit reuses certified Catalog name" {
  let original = RepositorySnapshot::from_sources([
    test_source("document-a", "# Stable\n\nOld body\n"),
  ]).unwrap()
  let suffix = accepted_source(
    original,
    test_source("document-a", "# Stable\n\nNew body with # Later\n"),
  )
  assert_eq(suffix.catalog().entries()[0].name(), Some("Stable"))

  let changed = accepted_source(
    suffix,
    test_source("document-a", "# Changed\n\nNew body\n"),
  )
  assert_eq(changed.catalog().entries()[0].name(), Some("Changed"))
}

///|
test "accepted recovered heading suffix edit cannot use certified reuse" {
  let original = RepositorySnapshot::from_sources([
    test_source("document-a", "# )bad\n\nOld body\n"),
  ]).unwrap()
  assert_eq(original.catalog().entries()[0].name(), Some(")bad"))

  let accepted = accepted_source(
    original,
    test_source("document-a", "# )bad\n\nNew body\n"),
  )
  assert_eq(accepted.catalog().entries()[0].name(), Some(")bad"))
}

///|
test "snapshot orders newest Change order first with lexical tie break" {
  let older = SourceRecord::new(
    "a",
    "# Older\n",
    change_order=ChangeOrder::from_int64(10L).unwrap(),
  ).unwrap()
  let tied_b = SourceRecord::new(
    "z",
    "# Z\n",
    change_order=ChangeOrder::from_int64(20L).unwrap(),
  ).unwrap()
  let tied_a = SourceRecord::new(
    "b",
    "# B\n",
    change_order=ChangeOrder::from_int64(20L).unwrap(),
  ).unwrap()
  let snapshot = RepositorySnapshot::from_sources([older, tied_b, tied_a]).unwrap()
  assert_eq(snapshot.sources().to_owned(), [tied_a, tied_b, older])
  assert_eq(snapshot.catalog().entries().map(entry => entry.document_id()), [
    "b", "z", "a",
  ])
}

///|
test "snapshot orders equal Change orders lexically" {
  let snapshot = RepositorySnapshot::from_sources([
    test_source("z", "# Z\n"),
    test_source("aa", "# AA\n"),
    test_source("m", "# M\n"),
  ]).unwrap()
  assert_eq(snapshot.sources().to_owned(), [
    test_source("aa", "# AA\n"),
    test_source("m", "# M\n"),
    test_source("z", "# Z\n"),
  ])
  assert_eq(snapshot.catalog().entries().to_owned(), [
    CatalogEntry::new("aa", Some("AA")).unwrap(),
    CatalogEntry::new("m", Some("M")).unwrap(),
    CatalogEntry::new("z", Some("Z")).unwrap(),
  ])
}

///|
test "accepted sources preserve lexical catalog and unrelated issues" {
  let original = RepositorySnapshot::new(
    [test_source("b", "# B\n"), test_source("a", "# A\n")],
    Catalog::from_entries([
      CatalogEntry::new("a", Some("A")).unwrap(),
      CatalogEntry::new("b", Some("B")).unwrap(),
    ]).unwrap(),
    [RepositoryIssue::UnknownRecord("other"), NameDerivationFailed("b")],
    ["source/v1/a", "source/v1/b", "source/v1/corrupt"],
  )
  let with_c = accepted_source(original, test_source("c", "# C\n"))
  assert_eq(with_c.catalog().entries().to_owned(), [
    CatalogEntry::new("a", Some("A")).unwrap(),
    CatalogEntry::new("b", Some("B")).unwrap(),
    CatalogEntry::new("c", Some("C")).unwrap(),
  ])
  assert_eq(with_c.issues().to_owned(), [
    RepositoryIssue::UnknownRecord("other"),
    NameDerivationFailed("b"),
  ])
  assert_eq(with_c.occupied_source_keys().to_owned(), [
    "source/v1/a", "source/v1/b", "source/v1/c", "source/v1/corrupt",
  ])
  let with_d = accepted_source(with_c, test_source("d", "# C\n"))
  assert_eq(with_d.catalog().entries().to_owned(), [
    CatalogEntry::new("a", Some("A")).unwrap(),
    CatalogEntry::new("b", Some("B")).unwrap(),
    CatalogEntry::new("c", Some("C")).unwrap(),
    CatalogEntry::new("d", Some("C")).unwrap(),
  ])
  let with_a = accepted_source(with_c, test_source("a", "# A2\n"))
  assert_eq(with_a.sources().to_owned(), [
    test_source("a", "# A2\n"),
    test_source("b", "# B\n"),
    test_source("c", "# C\n"),
  ])
}

///|
test "accepted source does not duplicate current name issues" {
  let original = RepositorySnapshot::new(
    [test_source("a", "# A\n")],
    Catalog::from_entries([CatalogEntry::new("a", Some("A")).unwrap()]).unwrap(),
    [NameDerivationFailed("a")],
    ["source/v1/a"],
  )
  let accepted = accepted_source(original, test_source("a", "# New\n"))
  assert_eq(accepted.issues().to_owned(), [])
  assert_eq(accepted.catalog().entries().to_owned(), [
    CatalogEntry::new("a", Some("New")).unwrap(),
  ])
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
