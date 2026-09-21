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
pub struct Document(DocumentId, String) derive(Eq, Debug)

///|
/// An advisory startup-selection hint parsed from accepted SavedDocuments.
pub struct EditingDocumentHint(DocumentId) derive(Eq, Debug)

///|
pub(all) suberror DocumentError {
  InvalidIdentity
} derive(Eq, Debug)

///|
pub fn Document::create(id : DocumentId, text : String) -> Document {
  Document(id, text)
}

///|
pub fn Document::update(self : Self, text : String) -> Document {
  Document(self.0, text)
}

///|
pub fn Document::id(self : Self) -> DocumentId {
  self.0
}

///|
pub fn Document::text(self : Self) -> String {
  self.1
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
  self.0.view()
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
    left.document().id().value().lexical_compare(right.document().id().value())
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
  self.documents.view()
}

///|
pub fn SavedDocuments::find(self : Self, id : DocumentId) -> Document? {
  self.documents
  .view()
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
  self.issues_value.view()
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
  self.replicas.view()
}

///|
fn SavedDocuments::find_replica_index(
  self : Self,
  account : AccountId,
  document_id : DocumentId,
) -> Int? {
  self.replicas
  .view()
  .search_by(replica => {
    replica.account == account && replica.document.id() == document_id
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
  let key = replica_key(replica.account, replica.document.id())
  let replicas = self.replicas.copy()
  let observed_replicas = match
    self.find_replica_index(replica.account, replica.document.id()) {
    Some(index) => {
      let previous = replicas[index]
      guard replica.generation > previous.generation else { raise StaleReplica }
      replicas[index] = replica
      self.observed_replica_keys
    }
    None => {
      guard !self.observed_replicas(key) else { raise StorageKeyConflict }
      let insertion = replicas
        .view()
        .search_by(candidate => compare_replicas(replica, candidate) < 0)
        .unwrap_or(replicas.length())
      replicas.insert(insertion, replica)
      let keys = self.observed_replica_keys.copy()
      let key_insertion = keys
        .view()
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
  guard self.find(replica.document().id()) == Some(replica.document()) &&
    self.apply(Deleted(replica.document().id())) is Some(without_source) else {
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
  let documents = self.documents.copy()
  let observed = self.observed_source_keys.copy()
  match change {
    Stored(document) => {
      let mut replaced = false
      for i = 0; i < documents.length(); i = i + 1 {
        if documents[i].id() == document.id() {
          documents[i] = document
          replaced = true
        }
      }
      if !replaced {
        documents.push(document)
      }
      let key = source_key(document.id())
      if !observed.contains(key) {
        observed.push(key)
      }
      Some(
        rebuild_saved_documents(
          documents,
          self.issues_value,
          observed,
          self.replicas,
          self.observed_replica_keys,
        ),
      )
    }
    Deleted(id) => {
      guard self.find(id) is Some(_) else { return None }
      let key = source_key(id)
      Some(
        rebuild_saved_documents(
          documents.filter(document => document.id() != id),
          self.issues_value,
          observed.filter(observed_key => observed_key != key),
          self.replicas,
          self.observed_replica_keys,
        ),
      )
    }
  }
}
