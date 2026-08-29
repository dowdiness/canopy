///|
const LEGACY_ACTIVE_KEY : String = "active"

///|
priv enum Reconciliation {
  Ready(RepositorySnapshot)
  Migrate(Array[@indexed_db.Mutation])
  Empty(Array[RepositoryIssue], Array[String])
}

///|
fn reconcile_scan(entries : Array[@indexed_db.ScanEntry]) -> Reconciliation {
  let sources : Array[SourceRecord] = []
  let issues : Array[RepositoryIssue] = []
  let raw_source_keys : Set[String] = Set([])
  let valid_source_ids : Set[String] = Set([])
  let mut legacy : (String, SourceRecord)? = None
  for entry in entries {
    match entry {
      StringRecord(key, encoded) =>
        if key == LEGACY_ACTIVE_KEY {
          match decode_source_value(encoded) {
            Ok(source) => legacy = Some((encoded, source))
            Err(_) => issues.push(InvalidLegacyRecord)
          }
        } else if key.strip_prefix(SOURCE_KEY_PREFIX) is Some(_) {
          raw_source_keys.add(key)
          match decode_source(key, encoded) {
            Ok(source) => {
              valid_source_ids.add(source.document_id())
              sources.push(source)
            }
            Err(InvalidRecord) => issues.push(InvalidSource(key))
            Err(IdentityMismatch) => issues.push(SourceIdentityMismatch(key))
          }
        } else if key.strip_prefix("source/v") is Some(_) {
          issues.push(UnsupportedSourceSchema(key))
        } else {
          issues.push(UnknownRecord(key))
        }
      UnsupportedValue(key) => {
        if key.strip_prefix(SOURCE_KEY_PREFIX) is Some(_) {
          raw_source_keys.add(key)
        }
        if key == LEGACY_ACTIVE_KEY {
          issues.push(InvalidLegacyRecord)
        } else {
          issues.push(UnsupportedRecord(key))
        }
      }
      UnsupportedKey(position) => issues.push(UnsupportedKey(position))
    }
  }
  match legacy {
    Some((encoded, source)) => {
      let document_id = source.document_id()
      let target_key = source_key(document_id).unwrap()
      if valid_source_ids.contains(document_id) {
        return Migrate([@indexed_db.Mutation::Delete(LEGACY_ACTIVE_KEY)])
      }
      if raw_source_keys.contains(target_key) {
        issues.push(LegacyMigrationCollision(document_id))
      } else {
        return Migrate([
          @indexed_db.Mutation::Put(target_key, encoded),
          @indexed_db.Mutation::Delete(LEGACY_ACTIVE_KEY),
        ])
      }
    }
    None => ()
  }
  guard snapshot_from_sources(sources, issues, raw_source_keys.to_array())
    is Some(snapshot) else {
    return Empty(issues, raw_source_keys.to_array())
  }
  Ready(snapshot)
}

///|
fn next_catalog(
  current : Catalog,
  document_id : String,
  source : String,
) -> (Catalog, Array[RepositoryIssue]) {
  let issues : Array[RepositoryIssue] = []
  let name = match derive_name(source) {
    Ok(name) => name
    Err(_) => {
      issues.push(NameDerivationFailed(document_id))
      None
    }
  }
  let entries = current
    .entries()
    .filter(entry => entry.document_id() != document_id)
  entries.push(CatalogEntry::new(document_id, name).unwrap())
  (Catalog::from_entries(entries).unwrap(), issues)
}
