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
pub(all) enum SourceDecodeFailure {
  InvalidRecord
  IdentityMismatch
} derive(Eq, Debug)

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
pub(all) enum CatalogDecodeFailure {
  InvalidCatalog
} derive(Eq, Debug)

///|
pub(all) enum NameDerivationFailure {
  ParseFailed
  UnsafeInline
} derive(Eq, Debug)
