///|
/// The authoritative persisted document: identity plus exact text.
pub struct Document(String, String) derive(Eq, Debug)

///|
/// An advisory startup-selection hint parsed from accepted SavedDocuments.
pub struct EditingDocumentHint(String) derive(Eq, Debug)

///|
pub(all) suberror DocumentError {
  InvalidIdentity
} derive(Eq, Debug)

///|
pub fn Document::create(
  id : String,
  text : String,
) -> Document raise DocumentError {
  if id == "" {
    raise InvalidIdentity
  }
  Document(id, text)
}

///|
pub fn Document::update(self : Self, text : String) -> Document {
  Document(self.0, text)
}

///|
pub fn Document::id(self : Self) -> String {
  self.0
}

///|
pub fn Document::text(self : Self) -> String {
  self.1
}

///|
struct CatalogEntry {
  document_id : String
  derived_name : @document_lead.DerivedName
} derive(Eq, Debug)

///|
pub fn CatalogEntry::document_id(self : Self) -> String {
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
  UnknownRecord(String)
  UnsupportedRecord(String)
  UnsupportedKey(Int)
} derive(Eq, Debug)

///|
pub(all) enum RepositoryChange {
  Stored(Document)
  Deleted(String)
} derive(Eq, Debug)

///|
pub struct SavedDocuments {
  documents : Array[Document]
  catalog_value : Catalog
  issues_value : Array[RepositoryIssue]
  observed_source_keys : Array[String]
} derive(Eq, Debug)

///|
fn sort_documents(documents : Array[Document]) -> Array[Document] {
  let result = documents.copy()
  result.sort_by((left, right) => left.id().lexical_compare(right.id()))
  result
}

///|
fn sort_keys(keys : Array[String]) -> Array[String] {
  let result = keys.copy()
  result.sort_by((left, right) => left.lexical_compare(right))
  result
}

///|
pub fn SavedDocuments::from_documents(
  documents : Array[Document],
) -> SavedDocuments? {
  let ordered = sort_documents(documents)
  let ids = Set::from_iter(ordered.iter().map(document => document.id()))
  guard ids.length() == ordered.length() else { return None }
  let observed = ordered.map(document => SOURCE_KEY_PREFIX + document.id())
  Some({
    documents: ordered,
    catalog_value: catalog_for(ordered),
    issues_value: [],
    observed_source_keys: observed,
  })
}

///|
fn rebuild_saved_documents(
  documents : Array[Document],
  issues : Array[RepositoryIssue],
  observed_source_keys : Array[String],
) -> SavedDocuments {
  let ordered = sort_documents(documents)
  {
    documents: ordered,
    catalog_value: catalog_for(ordered),
    issues_value: issues.copy(),
    observed_source_keys: sort_keys(observed_source_keys),
  }
}

///|
pub fn SavedDocuments::all(self : Self) -> ArrayView[Document] {
  self.documents.view()
}

///|
pub fn SavedDocuments::find(self : Self, id : String) -> Document? {
  self.documents
  .view()
  .search_by(document => document.id() == id)
  .map(i => self.documents[i])
}

///|
pub fn SavedDocuments::editing_document_hint(
  self : Self,
  document_id : String,
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
fn SavedDocuments::observed(self : Self, key : String) -> Bool {
  self.observed_source_keys.contains(key)
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
      let key = SOURCE_KEY_PREFIX + document.id()
      if !observed.contains(key) {
        observed.push(key)
      }
      Some(rebuild_saved_documents(documents, self.issues_value, observed))
    }
    Deleted(id) => {
      guard self.find(id) is Some(_) else { return None }
      let key = SOURCE_KEY_PREFIX + id
      Some(
        rebuild_saved_documents(
          documents.filter(document => document.id() != id),
          self.issues_value,
          observed.filter(observed_key => observed_key != key),
        ),
      )
    }
  }
}
