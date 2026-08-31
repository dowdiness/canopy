///|
/// One authoritative document identity and its exact Canonical Markdown.
struct SourceRecord {
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
struct CatalogEntry {
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
struct Catalog(Array[CatalogEntry]) derive(Eq, Debug)

///|
pub fn Catalog::from_entries(entries : Array[CatalogEntry]) -> Self? {
  let ordered = entries.copy()
  ordered.sort_by((left, right) => {
    left.document_id().lexical_compare(right.document_id())
  })
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
struct RepositorySnapshot(
  Array[SourceRecord],
  Catalog,
  Array[RepositoryIssue],
  Array[String]
) derive(Eq, Debug)

///|
fn RepositorySnapshot::new(
  sources : Array[SourceRecord],
  catalog : Catalog,
  issues : Array[RepositoryIssue],
  occupied_source_keys : Array[String],
) -> Self {
  let occupied = Set::from_iter(occupied_source_keys.iter())
  for source in sources {
    occupied.add(source_key(source.document_id()).unwrap())
  }
  let occupied = occupied.to_array()
  occupied.sort_by((left, right) => left.lexical_compare(right))
  RepositorySnapshot(sources.copy(), catalog, issues.copy(), occupied)
}

///|
fn snapshot_from_sources(
  sources : Array[SourceRecord],
  initial_issues : Array[RepositoryIssue],
  occupied_source_keys : Array[String],
) -> RepositorySnapshot? {
  guard !sources.is_empty() else { return None }
  let ordered = sources.copy()
  ordered.sort_by((left, right) => {
    left.document_id().lexical_compare(right.document_id())
  })
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
  Some(RepositorySnapshot::new(ordered, catalog, issues, occupied_source_keys))
}

///|
pub fn RepositorySnapshot::from_sources(sources : Array[SourceRecord]) -> Self? {
  snapshot_from_sources(sources, [], [])
}

///|
pub fn RepositorySnapshot::sources(self : Self) -> ArrayView[SourceRecord] {
  self.0.view()
}

///|
pub fn RepositorySnapshot::source(
  self : Self,
  document_id : String,
) -> SourceRecord? {
  match self.0.view().search_by(source => source.document_id() == document_id) {
    Some(index) => self.0.view().get(index)
    None => None
  }
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
fn RepositorySnapshot::occupied_source_keys(self : Self) -> ArrayView[String] {
  self.3.view()
}

///|
fn accepted_deletion(
  snapshot : RepositorySnapshot,
  document_id : String,
) -> RepositorySnapshot? {
  guard snapshot.source(document_id) is Some(_) &&
    snapshot.sources().length() > 1 else {
    return None
  }
  let key = source_key(document_id).unwrap()
  let sources = snapshot
    .sources()
    .filter(source => source.document_id() != document_id)
  let entries = snapshot
    .catalog()
    .entries()
    .filter(entry => entry.document_id() != document_id)
  let issues = snapshot
    .issues()
    .filter(issue => {
      match issue {
        RepositoryIssue::NameDerivationFailed(issue_id) =>
          issue_id != document_id
        _ => true
      }
    })
  let occupied_source_keys = snapshot
    .occupied_source_keys()
    .filter(occupied => occupied != key)
  guard Catalog::from_entries(entries) is Some(catalog) else { return None }
  Some(RepositorySnapshot::new(sources, catalog, issues, occupied_source_keys))
}

///|
fn accepted_source(
  snapshot : RepositorySnapshot,
  source : SourceRecord,
) -> RepositorySnapshot {
  let document_id = source.document_id()
  let sources = snapshot
    .sources()
    .to_owned()
    .filter(existing => existing.document_id() != document_id)
  sources.push(source)
  sources.sort_by((left, right) => {
    left.document_id().lexical_compare(right.document_id())
  })

  let issues = snapshot
    .issues()
    .to_owned()
    .filter(issue => {
      match issue {
        RepositoryIssue::NameDerivationFailed(issue_id) =>
          issue_id != document_id
        _ => true
      }
    })
  let previous_source = snapshot
    .source(document_id)
    .map(source => source.text())
  let (catalog, current_issues) = next_catalog_after_source(
    snapshot.catalog(),
    document_id,
    previous_source,
    source.text(),
  )
  for issue in current_issues {
    if !issues.contains(issue) {
      issues.push(issue)
    }
  }
  RepositorySnapshot::new(
    sources,
    catalog,
    issues,
    snapshot.occupied_source_keys().to_owned(),
  )
}
