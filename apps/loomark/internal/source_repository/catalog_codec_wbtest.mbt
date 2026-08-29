///|
test "catalog construction sorts identities and preserves duplicate names" {
  let catalog = Catalog::from_entries([
    CatalogEntry::new("document-b", Some("Same")).unwrap(),
    CatalogEntry::new("document-a", Some("Same")).unwrap(),
    CatalogEntry::new("document-c", None).unwrap(),
  ]).unwrap()
  assert_eq(catalog.entries().to_owned(), [
    CatalogEntry::new("document-a", Some("Same")).unwrap(),
    CatalogEntry::new("document-b", Some("Same")).unwrap(),
    CatalogEntry::new("document-c", None).unwrap(),
  ])
  assert_eq(decode_catalog(encode_catalog(catalog)), Ok(catalog))
}

///|
test "catalog rejects empty or duplicate identities" {
  assert_eq(CatalogEntry::new("", None), None)
  assert_eq(
    Catalog::from_entries([
      CatalogEntry::new("document-a", None).unwrap(),
      CatalogEntry::new("document-a", Some("Duplicate")).unwrap(),
    ]),
    None,
  )
}

///|
test "catalog decoder is strict and rejects unsorted entries" {
  for
    encoded in [
      "not-json", "{}", "{\"entries\":[],\"extra\":true}", "{\"entries\":[{\"document_id\":\"document-a\"}]}",
      "{\"entries\":[{\"document_id\":\"\",\"name\":null}]}", "{\"entries\":[{\"document_id\":\"document-a\",\"name\":1}]}",
      "{\"entries\":[{\"document_id\":\"document-b\",\"name\":null},{\"document_id\":\"document-a\",\"name\":null}]}",
    ] {
    assert_eq(
      decode_catalog(encoded),
      Err(CatalogDecodeFailure::InvalidCatalog),
    )
  }
}
