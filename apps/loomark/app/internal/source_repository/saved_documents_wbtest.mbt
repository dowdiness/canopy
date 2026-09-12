///|
fn doc(id : String, text : String) -> Document {
  Document::create(id, text) catch {
    _ => abort("invalid test id")
  }
}

///|
fn rejects_empty_id() -> Bool {
  let _ = Document::create("", "x") catch {
    err => return err == InvalidIdentity
  }
  false
}

///|
test "Document validates empty identity and updates exactly" {
  assert_true(rejects_empty_id())
  let first = doc("a", "old")
  assert_eq(first.update("new").text(), "new")
  assert_eq(first.text(), "old")
}

///|
test "Document accessors preserve ownership" {
  let text = "exact\n日本語"
  let value = doc("id", text)
  assert_eq(value.id(), "id")
  assert_eq(value.text(), text)
}

///|
test "from_documents sorts lexical and accepts empty" {
  let saved = SavedDocuments::from_documents([doc("z", "z"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(x => x.id()), ["a", "z"])
  assert_eq(SavedDocuments::from_documents([]).unwrap().all(), [])
}

///|
test "from_documents rejects duplicate identities" {
  assert_eq(
    SavedDocuments::from_documents([doc("a", "1"), doc("a", "2")]),
    None,
  )
}

///|
test "catalog derives names in document order" {
  let saved = SavedDocuments::from_documents([
    doc("b", "# Bee\n"),
    doc("a", "plain"),
  ]).unwrap()
  assert_eq(saved.catalog().entries().map(x => (x.document_id(), x.name())), [
    ("a", "plain"),
    ("b", "Bee"),
  ])
}

///|
test "apply stores replacement and preserves unrelated issue" {
  let saved = SavedDocuments::from_documents([doc("a", "old"), doc("b", "b")]).unwrap()
  let next = saved.apply(RepositoryChange::Stored(doc("a", "new"))).unwrap()
  assert_eq(next.find("a").unwrap().text(), "new")
  assert_eq(saved.find("a").unwrap().text(), "old")
}

///|
test "apply inserts and deletes while retaining lexical order" {
  let saved = SavedDocuments::from_documents([doc("b", "b")]).unwrap()
  let inserted = saved.apply(RepositoryChange::Stored(doc("a", "a"))).unwrap()
  assert_eq(inserted.all().map(x => x.id()), ["a", "b"])
  assert_eq(
    inserted
    .apply(RepositoryChange::Deleted("a"))
    .unwrap()
    .all()
    .map(x => x.id()),
    ["b"],
  )
  assert_eq(inserted.apply(RepositoryChange::Deleted("missing")), None)
}

///|
test "from_documents keeps lexical order without startup selection state" {
  let saved = SavedDocuments::from_documents([doc("b", "b"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(document => document.id()), ["a", "b"])
}
