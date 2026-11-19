///|
/// The authoritative persisted document: identity plus exact text.
pub struct DocumentId(String) derive(Eq, Hash, Debug)

///|
fn valid_uuid(value : String) -> Bool {
  guard value.length() == 36 else { return false }
  for i in 0..<36 {
    if i == 8 || i == 13 || i == 18 || i == 23 {
      guard value[i] == '-' else { return false }
    } else {
      guard value[i] is ('0'..='9' | 'a'..='f' | 'A'..='F') else {
        return false
      }
    }
  }
  value[14] is ('1'..='8') && value[19] is ('8' | '9' | 'a' | 'b' | 'A' | 'B')
}

///|
pub fn DocumentId::parse(value : String) -> DocumentId raise DocumentError {
  guard valid_uuid(value) else { raise InvalidIdentity }
  DocumentId(value)
}

///|
pub fn DocumentId::value(self : Self) -> String {
  self.0
}

///|
/// When a document's text last changed, in whole milliseconds since the epoch
/// by the clock of the device where it changed. It travels with the text, so
/// every device orders documents the same way.
pub struct ChangeTime(Double) derive(Eq, Compare, Debug)

///|
/// The device clock, read by the shell at the moment text changes.
pub fn ChangeTime::now() -> ChangeTime {
  ChangeTime(@browser.now())
}

///|
pub(all) suberror InvalidChangeTime derive(Eq, Debug)

///|
/// The rule every boundary shares: whole milliseconds from the epoch up to
/// the largest integer JavaScript represents exactly.
pub fn ChangeTime::parse(value : Double) -> ChangeTime raise InvalidChangeTime {
  guard value >= 0.0 &&
    value <= 9007199254740991.0 &&
    @double.floor(value) == value else {
    raise InvalidChangeTime
  }
  ChangeTime(value)
}

///|
pub fn ChangeTime::value(self : Self) -> Double {
  self.0
}

///|
/// A document's position in the Document index: its Change time, then its
/// Document ID for documents changed at the same time.
pub(all) struct IndexKey(ChangeTime, DocumentId) derive(Eq, Debug)

///|
/// Document index order: the most recently changed document first, and
/// Document ID order among documents changed at the same time.
pub fn index_order(left : IndexKey, right : IndexKey) -> Int {
  match right.0.compare(left.0) {
    0 => left.1.value().lexical_compare(right.1.value())
    order => order
  }
}

///|
/// The item that leads the Document index among `items`.
pub fn[T] first_in_index(
  items : ArrayView[T],
  index_key : (T) -> IndexKey,
) -> T? {
  items.fold(init=None, (first, item) => {
    match first {
      Some(first) if index_order(index_key(first), index_key(item)) <= 0 =>
        Some(first)
      _ => Some(item)
    }
  })
}

///|
/// One version of a document's content: its text and the Change time of that
/// text. Saved documents, remote revisions, and pending saves each hold one.
pub(all) struct Content(String, ChangeTime) derive(Eq, Debug)

///|
pub fn Content::text(self : Self) -> String {
  self.0
}

///|
pub fn Content::changed_at(self : Self) -> ChangeTime {
  self.1
}

///|
pub struct Document(DocumentId, Content) derive(Eq, Debug)

///|
/// An advisory startup-selection hint parsed from accepted SavedDocuments.
pub struct EditingDocumentHint(DocumentId) derive(Eq, Debug)

///|
pub(all) suberror DocumentError {
  InvalidIdentity
} derive(Eq, Debug)

///|
pub fn Document::create(
  id : DocumentId,
  text : String,
  changed_at : ChangeTime,
) -> Document {
  Document(id, Content(text, changed_at))
}

///|
pub fn Document::update(
  self : Self,
  text : String,
  changed_at : ChangeTime,
) -> Document {
  Document(self.0, Content(text, changed_at))
}

///|
pub fn Document::with_content(self : Self, content : Content) -> Document {
  Document(self.0, content)
}

///|
/// The working copy holding `text`. Text equal to one of the `known`
/// versions keeps that version, Change time included (the first match wins);
/// other text takes `changed_at`.
pub fn Document::working(
  self : Self,
  text : String,
  changed_at : ChangeTime,
  known~ : Array[Content],
) -> Document {
  match known.search_by(content => content.text() == text) {
    Some(index) => Document(self.0, known[index])
    None => self.update(text, changed_at)
  }
}

///|
pub fn Document::id(self : Self) -> DocumentId {
  self.0
}

///|
pub fn Document::content(self : Self) -> Content {
  self.1
}

///|
pub fn Document::text(self : Self) -> String {
  self.1.text()
}

///|
pub fn Document::changed_at(self : Self) -> ChangeTime {
  self.1.changed_at()
}

///|
/// The position of this document in `index_order`.
pub fn Document::index_key(self : Self) -> IndexKey {
  IndexKey(self.changed_at(), self.0)
}

///|
struct CatalogEntry {
  document_id : DocumentId
  derived_name : @document_lead.DerivedName
} derive(Eq, Debug)

///|
pub fn CatalogEntry::document_id(self : Self) -> DocumentId {
  self.document_id
}

///|
pub fn CatalogEntry::name(self : Self) -> String {
  self.derived_name.text()
}

///|
pub struct Catalog(Array[CatalogEntry]) derive(Eq, Debug)

///|
pub fn Catalog::entries(self : Self) -> ArrayView[CatalogEntry] {
  self.0.exact_view()
}

///|
fn catalog_for(documents : Array[Document]) -> Catalog {
  Catalog(
    documents.map(document => {
      document_id: document.id(),
      derived_name: @document_lead.derive_name(document.text()),
    }),
  )
}

///|
pub(all) enum RepositoryIssue {
  InvalidSource(String)
  UnsupportedSourceSchema(String)
  InvalidDocumentReplica(String)
  UnknownRecord(String)
  UnsupportedRecord(String)
  UnsupportedKey(Int)
} derive(Eq, Debug)

///|
pub(all) suberror ReplicaApplyError {
  StaleReplica
  StorageKeyConflict
  InvalidReplicaWrite
} derive(Eq, Debug)

///|
pub(all) enum RepositoryChange {
  Stored(Document)
  Deleted(DocumentId)
} derive(Eq, Debug)

///|
pub struct SavedDocuments {
  documents : Array[Document]
  // Catalog entries share the documents' lexical identity order.
  catalog_value : Catalog
  issues_value : Array[RepositoryIssue]
  observed_source_keys : Array[String]
  replicas : Array[DocumentReplica]
  observed_replica_keys : Array[String]
} derive(Eq, Debug)

///|
fn sort_documents(documents : Array[Document]) -> Array[Document] {
  let result = documents.copy()
  result.sort_by((left, right) => {
    left.id().value().lexical_compare(right.id().value())
  })
  result
}

///|
fn sort_keys(keys : Array[String]) -> Array[String] {
  let result = keys.copy()
  result.sort_by((left, right) => left.lexical_compare(right))
  result
}

///|
fn compare_replicas(left : DocumentReplica, right : DocumentReplica) -> Int {
  let account_order = left
    .account()
    .value()
    .lexical_compare(right.account().value())
  if account_order != 0 {
    account_order
  } else {
    left.document_id().value().lexical_compare(right.document_id().value())
  }
}

///|
pub fn SavedDocuments::from_documents(
  documents : Array[Document],
) -> SavedDocuments? {
  let ordered = sort_documents(documents)
  let ids = Set::from_iter(ordered.iter().map(document => document.id()))
  guard ids.length() == ordered.length() else { return None }
  let observed = ordered.map(document => source_key(document.id()))
  Some({
    documents: ordered,
    catalog_value: catalog_for(ordered),
    issues_value: [],
    observed_source_keys: observed,
    replicas: [],
    observed_replica_keys: [],
  })
}

///|
fn rebuild_saved_documents(
  documents : Array[Document],
  issues : Array[RepositoryIssue],
  observed_source_keys : Array[String],
  replicas : Array[DocumentReplica],
  observed_replica_keys : Array[String],
) -> SavedDocuments {
  let ordered = sort_documents(documents)
  let ordered_replicas = replicas.copy()
  ordered_replicas.sort_by(compare_replicas)
  {
    documents: ordered,
    catalog_value: catalog_for(ordered),
    issues_value: issues.copy(),
    observed_source_keys: sort_keys(observed_source_keys),
    replicas: ordered_replicas,
    observed_replica_keys: sort_keys(observed_replica_keys),
  }
}

///|
pub fn SavedDocuments::all(self : Self) -> ArrayView[Document] {
  self.documents.exact_view()
}

///|
pub fn SavedDocuments::find(self : Self, id : DocumentId) -> Document? {
  self.documents
  .exact_view()
  .search_by(document => document.id() == id)
  .map(i => self.documents[i])
}

///|
pub fn SavedDocuments::editing_document_hint(
  self : Self,
  document_id : DocumentId,
) -> EditingDocumentHint? {
  self.find(document_id).map(document => EditingDocumentHint(document.id()))
}

///|
pub fn SavedDocuments::catalog(self : Self) -> Catalog {
  self.catalog_value
}

///|
pub fn SavedDocuments::issues(self : Self) -> ArrayView[RepositoryIssue] {
  self.issues_value.exact_view()
}

///|
pub fn SavedDocuments::replicas_for(
  self : Self,
  account : AccountId,
) -> Array[DocumentReplica] {
  self.replicas.filter(replica => replica.account() == account)
}

///|
pub fn SavedDocuments::replicas(self : Self) -> ArrayView[DocumentReplica] {
  self.replicas.exact_view()
}

///|
fn SavedDocuments::find_replica_index(
  self : Self,
  account : AccountId,
  document_id : DocumentId,
) -> Int? {
  self.replicas
  .exact_view()
  .search_by(replica => {
    replica.account == account && replica.document_id == document_id
  })
}

///|
pub fn SavedDocuments::replica(
  self : Self,
  account : AccountId,
  document_id : DocumentId,
) -> DocumentReplica? {
  self
  .find_replica_index(account, document_id)
  .map(index => self.replicas[index])
}

///|
pub fn SavedDocuments::apply_replica(
  self : Self,
  replica : DocumentReplica,
) -> SavedDocuments raise ReplicaApplyError {
  let key = replica_key(replica.account, replica.document_id)
  let replicas = self.replicas.copy()
  let observed_replicas = match
    self.find_replica_index(replica.account, replica.document_id) {
    Some(index) => {
      let previous = replicas[index]
      guard replica.generation > previous.generation else { raise StaleReplica }
      replicas[index] = replica
      self.observed_replica_keys
    }
    None => {
      guard !self.observed_replicas(key) else { raise StorageKeyConflict }
      let insertion = replicas
        .exact_view()
        .search_by(candidate => compare_replicas(replica, candidate) < 0)
        .unwrap_or(replicas.length())
      replicas.insert(insertion, replica)
      let keys = self.observed_replica_keys.copy()
      let key_insertion = keys
        .exact_view()
        .search_by(existing => key.lexical_compare(existing) < 0)
        .unwrap_or(keys.length())
      keys.insert(key_insertion, key)
      keys
    }
  }
  { ..self, replicas, observed_replica_keys: observed_replicas, }
}

///|
pub fn SavedDocuments::apply_sync_start(
  self : Self,
  replica : DocumentReplica,
) -> SavedDocuments? {
  guard replica.document() is Some(document) &&
    self.find(replica.document_id()) == Some(document) &&
    self.apply(Deleted(replica.document_id())) is Some(without_source) else {
    return None
  }
  Some(without_source.apply_replica(replica)) catch {
    _ => None
  }
}

///|
/// Apply the complete semantic result of one committed IndexedDB transaction.
/// Compound replica writes must become visible in memory as one change too.
pub fn SavedDocuments::apply_replica_write(
  self : Self,
  write : ReplicaWrite,
) -> SavedDocuments raise ReplicaApplyError {
  match write {
    Store(replica) => self.apply_replica(replica)
    Remove(replica) => {
      guard self.find_replica_index(replica.account(), replica.document_id())
        is Some(index) else {
        raise InvalidReplicaWrite
      }
      let replicas = self.replicas.copy()
      ignore(replicas.remove(index))
      { ..self, replicas, }
    }
    Fork(replica, recovery) => {
      guard self.find(recovery.id()) is None &&
        !self.observed(source_key(recovery.id())) &&
        self.apply(Stored(recovery)) is Some(with_recovery) else {
        raise InvalidReplicaWrite
      }
      with_recovery.apply_replica(replica)
    }
    PromoteSource(replica) =>
      match self.apply_sync_start(replica) {
        Some(saved) => saved
        None => raise InvalidReplicaWrite
      }
  }
}

///|
fn SavedDocuments::observed(self : Self, key : String) -> Bool {
  self.observed_source_keys.contains(key)
}

///|
fn SavedDocuments::observed_replicas(self : Self, key : String) -> Bool {
  self.observed_replica_keys.contains(key)
}

///|
pub fn SavedDocuments::apply(
  self : Self,
  change : RepositoryChange,
) -> SavedDocuments? {
  match change {
    Stored(document) => {
      let index = self.documents
        .exact_view()
        .search_by(existing => {
          document.id().value().lexical_compare(existing.id().value()) <= 0
        })
        .unwrap_or(self.documents.length())
      let documents = self.documents.copy()
      let catalog_entries = self.catalog_value.0.copy()
      match self.documents.get(index) {
        Some(previous) if previous.id() == document.id() => {
          documents[index] = document
          if previous.text() != document.text() {
            let entry = catalog_entries[index]
            catalog_entries[index] = {
              ..entry,
              derived_name: entry.derived_name.update(document.text()),
            }
          }
        }
        _ => {
          documents.insert(index, document)
          catalog_entries.insert(index, {
            document_id: document.id(),
            derived_name: @document_lead.derive_name(document.text()),
          })
        }
      }
      let key = source_key(document.id())
      let observed_source_keys = if self.observed(key) {
        self.observed_source_keys
      } else {
        let keys = self.observed_source_keys.copy()
        let insertion = keys
          .exact_view()
          .search_by(existing => key.lexical_compare(existing) < 0)
          .unwrap_or(keys.length())
        keys.insert(insertion, key)
        keys
      }
      Some({
        ..self,
        documents,
        catalog_value: Catalog(catalog_entries),
        observed_source_keys,
      })
    }
    Deleted(id) => {
      guard self.documents
        .exact_view()
        .search_by(document => document.id() == id)
        is Some(index) else {
        return None
      }
      let documents = self.documents.copy()
      let catalog_entries = self.catalog_value.0.copy()
      ignore(documents.remove(index))
      ignore(catalog_entries.remove(index))
      let key = source_key(id)
      Some({
        ..self,
        documents,
        catalog_value: Catalog(catalog_entries),
        observed_source_keys: self.observed_source_keys.filter(observed => {
          observed != key
        }),
      })
    }
  }
}

///|
pub extend Catalog with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Catalog with Eq::{equal, not_equal}

///|
pub extend CatalogEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CatalogEntry with Eq::{equal, not_equal}

///|
pub extend Document with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend DocumentError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DocumentError with Eq::{equal, not_equal}

///|
pub extend DocumentId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DocumentId with Eq::{equal, not_equal}

///|
pub extend DocumentId with Hash::{hash, hash_combine}

///|
pub extend EditingDocumentHint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EditingDocumentHint with Eq::{equal, not_equal}

///|
pub extend ReplicaApplyError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReplicaApplyError with Eq::{equal, not_equal}

///|
pub extend RepositoryChange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RepositoryChange with Eq::{equal, not_equal}

///|
pub extend RepositoryIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RepositoryIssue with Eq::{equal, not_equal}

///|
pub extend SavedDocuments with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SavedDocuments with Eq::{equal, not_equal}

///|
pub extend ChangeTime with Eq::{equal, not_equal}

///|
pub extend ChangeTime with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend ChangeTime with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend InvalidChangeTime with Eq::{equal, not_equal}

///|
pub extend InvalidChangeTime with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend IndexKey with Eq::{equal, not_equal}

///|
pub extend IndexKey with @moonbitlang/core/debug.Debug::{to_repr}
