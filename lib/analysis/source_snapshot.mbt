///|
pub(all) struct SourceSnapshot {
  doc_id : String
  version : Int
  text_hash : Int // 32-bit; sufficient for stale-result rejection, not a cross-document cache key
  utf16_len : Int
} derive(Eq, Hash, @debug.Debug)

///|
pub fn SourceSnapshot::SourceSnapshot(
  doc_id~ : String,
  version~ : Int,
  source~ : String,
) -> SourceSnapshot {
  { doc_id, version, text_hash: source.hash(), utf16_len: source.length() }
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
