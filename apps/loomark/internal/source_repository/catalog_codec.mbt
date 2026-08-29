///|
pub fn encode_catalog(catalog : Catalog) -> String {
  let entries = catalog
    .entries()
    .map(entry => {
      Json::object({
        "document_id": Json::string(entry.document_id()),
        "name": match entry.name() {
          Some(name) => Json::string(name)
          None => Json::null()
        },
      })
    })
  Json::object({ "entries": Json::array(entries) }).stringify()
}

///|
pub fn decode_catalog(
  encoded : String,
) -> Result[Catalog, CatalogDecodeFailure] {
  let value = @json.parse(encoded) catch { _ => return Err(InvalidCatalog) }
  guard value is Json::Object(fields) && fields.length() == 1 else {
    return Err(InvalidCatalog)
  }
  guard fields.get("entries") is Some(Json::Array(encoded_entries)) else {
    return Err(InvalidCatalog)
  }
  let entries = encoded_entries.filter_map(decode_catalog_entry)
  guard entries.length() == encoded_entries.length() else {
    return Err(InvalidCatalog)
  }
  let identities = entries.map(entry => entry.document_id())
  guard identities.is_sorted() else { return Err(InvalidCatalog) }
  match catalog_from_sorted_entries(entries) {
    Some(catalog) => Ok(catalog)
    None => Err(InvalidCatalog)
  }
}

///|
fn decode_catalog_entry(value : Json) -> CatalogEntry? {
  guard value is Json::Object(fields) && fields.length() == 2 else {
    return None
  }
  let document_id = match fields.get("document_id") {
    Some(Json::String(document_id)) if document_id != "" => document_id
    _ => return None
  }
  let name = match fields.get("name") {
    Some(Json::String(name)) => Some(name)
    Some(Json::Null) => None
    _ => return None
  }
  CatalogEntry::new(document_id, name)
}
