///|
#derive(Eq, Hash, @debug.Debug)
pub(all) struct SourceSnapshot {
  doc_id : String
  version : Int32
  text_hash : Int32 // 32-bit; sufficient for stale-result rejection, not a cross-document cache key
  utf16_len : Int32
}

///|
pub fn SourceSnapshot::SourceSnapshot(
  doc_id~ : String,
  version~ : Int32,
  source~ : String,
) -> SourceSnapshot {
  { doc_id, version, text_hash: source.hash(), utf16_len: source.length(), }
}

///|
pub fn SourceSnapshot::matches(
  self : SourceSnapshot,
  other : SourceSnapshot,
) -> Bool {
  self.doc_id == other.doc_id &&
  self.version == other.version &&
  self.text_hash == other.text_hash &&
  self.utf16_len == other.utf16_len
}

///|
pub extend SourceSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourceSnapshot with Eq::{equal, not_equal}

///|
pub extend SourceSnapshot with Hash::{hash, hash_combine}
