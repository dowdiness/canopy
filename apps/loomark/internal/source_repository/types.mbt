///|
/// One authoritative document identity and its exact Canonical Markdown.
pub struct SourceRecord {
  document_id : String
  text : String
} derive(Eq, Debug)

///|
pub fn SourceRecord::new(document_id : String, text : String) -> Self? {
  guard document_id != "" else { return None }
  Some({ document_id, text })
}

///|
pub fn SourceRecord::document_id(self : Self) -> String {
  self.document_id
}

///|
pub fn SourceRecord::text(self : Self) -> String {
  self.text
}

///|
priv enum SourceDecodeFailure {
  InvalidRecord
  IdentityMismatch
}

///|
/// One rebuildable display-name entry, identified only by Document ID.
pub struct CatalogEntry {
  document_id : String
  name : String?
} derive(Eq, Debug)

///|
pub fn CatalogEntry::new(document_id : String, name : String?) -> Self? {
  guard document_id != "" else { return None }
  Some({ document_id, name })
}

///|
pub fn CatalogEntry::document_id(self : Self) -> String {
  self.document_id
}

///|
pub fn CatalogEntry::name(self : Self) -> String? {
  self.name
}

///|
/// A deterministic catalog ordered lexically by Document ID.
pub struct Catalog(Array[CatalogEntry]) derive(Eq, Debug)

///|
pub fn Catalog::from_entries(entries : Array[CatalogEntry]) -> Self? {
  let ordered = entries.copy()
  ordered.sort_by_key(entry => entry.document_id())
  catalog_from_sorted_entries(ordered)
}

///|
pub fn Catalog::entries(self : Self) -> ArrayView[CatalogEntry] {
  self.0.view()
}

///|
fn catalog_from_sorted_entries(entries : Array[CatalogEntry]) -> Catalog? {
  let identities = Set::from_iter(
    entries.iter().map(entry => entry.document_id()),
  )
  guard identities.length() == entries.length() else { return None }
  Some(Catalog(entries.copy()))
}

///|
pub(all) enum RepositoryIssue {
  InvalidSource(String)
  SourceIdentityMismatch(String)
  UnsupportedSourceSchema(String)
  UnknownRecord(String)
  UnsupportedRecord(String)
  UnsupportedKey(Int)
  NameDerivationFailed(String)
  InvalidLegacyRecord
  LegacyMigrationCollision(String)
} derive(Eq, Debug)

///|
pub struct RepositorySnapshot(
  Array[SourceRecord],
  Catalog,
  Array[RepositoryIssue]
) derive(Eq, Debug)

///|
fn RepositorySnapshot::new(
  sources : Array[SourceRecord],
  catalog : Catalog,
  issues : Array[RepositoryIssue],
) -> Self {
  RepositorySnapshot(sources.copy(), catalog, issues.copy())
}

///|
fn snapshot_from_sources(
  sources : Array[SourceRecord],
  initial_issues : Array[RepositoryIssue],
) -> RepositorySnapshot? {
  guard !sources.is_empty() else { return None }
  let ordered = sources.copy()
  ordered.sort_by_key(source => source.document_id())
  let identities = Set::from_iter(
    ordered.iter().map(source => source.document_id()),
  )
  guard identities.length() == ordered.length() else { return None }
  let issues = initial_issues.copy()
  let entries = ordered.map(source => {
    let name = match derive_name(source.text()) {
      Ok(name) => name
      Err(_) => {
        issues.push(NameDerivationFailed(source.document_id()))
        None
      }
    }
    CatalogEntry::new(source.document_id(), name).unwrap()
  })
  guard Catalog::from_entries(entries) is Some(catalog) else { return None }
  Some(RepositorySnapshot::new(ordered, catalog, issues))
}

///|
pub fn RepositorySnapshot::from_sources(sources : Array[SourceRecord]) -> Self? {
  snapshot_from_sources(sources, [])
}

///|
pub fn RepositorySnapshot::sources(self : Self) -> ArrayView[SourceRecord] {
  self.0.view()
}

///|
pub fn RepositorySnapshot::selected(self : Self) -> SourceRecord? {
  self.0.get(0)
}

///|
pub fn RepositorySnapshot::catalog(self : Self) -> Catalog {
  self.1
}

///|
pub fn RepositorySnapshot::issues(self : Self) -> ArrayView[RepositoryIssue] {
  self.2.view()
}

///|
pub struct SaveSuccess(Catalog, Array[RepositoryIssue]) derive(Eq, Debug)

///|
pub fn SaveSuccess::new(
  catalog : Catalog,
  issues : Array[RepositoryIssue],
) -> Self {
  SaveSuccess(catalog, issues.copy())
}

///|
pub fn SaveSuccess::catalog(self : Self) -> Catalog {
  self.0
}

///|
pub fn SaveSuccess::issues(self : Self) -> ArrayView[RepositoryIssue] {
  self.1.view()
}
