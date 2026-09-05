///|
/// Largest integer represented exactly by JavaScript Number.
const MAX_CHANGE_ORDER : Int64 = 9_007_199_254_740_991L

///|
/// Opaque ordering value assigned when Document text changes.
struct ChangeOrder(Int64) derive(Eq, Debug)

///|
pub fn ChangeOrder::from_int64(value : Int64) -> Self? {
  guard value >= 0L && value <= MAX_CHANGE_ORDER else { return None }
  Some(ChangeOrder(value))
}

///|
pub fn ChangeOrder::value(self : Self) -> Int64 {
  self.0
}

///|
pub fn ChangeOrder::next(self : Self) -> Self? {
  ChangeOrder::from_int64(self.0 + 1L)
}

///|
/// Advance beyond the current order and any browser-observed order.
pub fn ChangeOrder::advance(self : Self, observed : Self) -> Self? {
  match self.next() {
    Some(next) =>
      if observed.value().compare(next.value()) > 0 {
        Some(observed)
      } else {
        Some(next)
      }
    None => None
  }
}

///|
/// One authoritative document identity and its exact Canonical Markdown.
struct SourceRecord {
  document_id : String
  text : String
  change_order : ChangeOrder
} derive(Eq, Debug)

///|
pub fn SourceRecord::new(
  document_id : String,
  text : String,
  change_order? : ChangeOrder = ChangeOrder(0L),
) -> Self? {
  guard document_id != "" else { return None }
  Some({ document_id, text, change_order })
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
pub fn SourceRecord::change_order(self : Self) -> ChangeOrder {
  self.change_order
}

///|
priv enum SourceDecodeFailure {
  InvalidRecord
  IdentityMismatch
  UnsupportedSchema
}

///|
/// One rebuildable display-name entry, identified only by Document ID.
struct CatalogEntry {
  document_id : String
  name : String?
  change_order : ChangeOrder
} derive(Eq, Debug)

///|
pub fn CatalogEntry::new(
  document_id : String,
  name : String?,
  change_order? : ChangeOrder = ChangeOrder(0L),
) -> Self? {
  guard document_id != "" else { return None }
  Some({ document_id, name, change_order })
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
pub fn CatalogEntry::change_order(self : Self) -> ChangeOrder {
  self.change_order
}

///|
fn compare_change_order(
  left_order : ChangeOrder,
  left_id : String,
  right_order : ChangeOrder,
  right_id : String,
) -> Int {
  let by_newest = right_order.value().compare(left_order.value())
  if by_newest != 0 {
    by_newest
  } else {
    left_id.lexical_compare(right_id)
  }
}

///|
/// A deterministic catalog ordered by newest Change order, then Document ID.
struct Catalog(Array[CatalogEntry]) derive(Eq, Debug)

///|
pub fn Catalog::from_entries(entries : Array[CatalogEntry]) -> Self? {
  let ordered = entries.copy()
  ordered.sort_by((left, right) => {
    compare_change_order(
      left.change_order(),
      left.document_id(),
      right.change_order(),
      right.document_id(),
    )
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
pub(all) enum AcknowledgedChange {
  SourceStored(SourceRecord)
  SourceDeleted(String)
} derive(Eq, Debug)

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
  let ordered = sources.copy()
  ordered.sort_by((left, right) => {
    compare_change_order(
      left.change_order(),
      left.document_id(),
      right.change_order(),
      right.document_id(),
    )
  })
  let identities = Set::from_iter(
    ordered.iter().map(source => source.document_id()),
  )
  guard identities.length() == ordered.length() else { return None }
  let issues = initial_issues.copy()
  let entries = ordered.map(source => {
    let name = match @document_lead.derive_name(source.text()) {
      Ok(name) => name
      Err(_) => {
        let issue = NameDerivationFailed(source.document_id())
        if !issues.contains(issue) {
          issues.push(issue)
        }
        None
      }
    }
    CatalogEntry::new(
      source.document_id(),
      name,
      change_order=source.change_order(),
    ).unwrap()
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
pub fn RepositorySnapshot::latest_change_order(self : Self) -> ChangeOrder {
  self
  .selected()
  .map(source => source.change_order())
  .unwrap_or(ChangeOrder(0L))
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
    compare_change_order(
      left.change_order(),
      left.document_id(),
      right.change_order(),
      right.document_id(),
    )
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
    change_order=source.change_order(),
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

///|
fn accepted_deletion(
  snapshot : RepositorySnapshot,
  document_id : String,
) -> RepositorySnapshot? {
  guard snapshot.source(document_id) is Some(_) else { return None }
  let sources = snapshot
    .sources()
    .filter(source => source.document_id() != document_id)
  let issues = snapshot
    .issues()
    .filter(issue => {
      match issue {
        RepositoryIssue::NameDerivationFailed(issue_id) =>
          issue_id != document_id
        _ => true
      }
    })
  let deleted_key = source_key(document_id).unwrap()
  let occupied = snapshot
    .occupied_source_keys()
    .filter(key => key != deleted_key)
  snapshot_from_sources(sources, issues, occupied)
}

///|
pub fn RepositorySnapshot::apply_acknowledged(
  self : Self,
  change : AcknowledgedChange,
) -> Self? {
  match change {
    SourceStored(source) => Some(accepted_source(self, source))
    SourceDeleted(document_id) => accepted_deletion(self, document_id)
  }
}
