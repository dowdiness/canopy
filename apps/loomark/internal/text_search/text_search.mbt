// Case-insensitive text search over plain values. Both the query and the
// text it is matched against are lower-cased once, when they are made, so
// matching never repeats or forgets that step.

///|
/// Text searched for ignoring case: trimmed, in lower case, and never empty.
pub struct Query {
  priv lower : String
}

///|
/// The query `text` asks for, or `None` when it asks for nothing.
pub fn Query::parse(text : String) -> Query? {
  match text.trim().to_owned().to_lower() {
    "" => None
    lower => Some({ lower, })
  }
}

///|
/// Text a query is matched against, in lower case.
pub struct Searchable {
  priv lower : String
} derive(Eq, Hash, Debug)

///|
pub fn Searchable::of(text : String) -> Searchable {
  { lower: text.to_lower(), }
}

///|
/// Whether `text` contains `self`.
pub fn Query::found_in(self : Query, text : Searchable) -> Bool {
  text.lower.contains(self.lower)
}

///|
/// Where `self` occurs in `text` ignoring case, as code unit ranges that do
/// not overlap. Text whose lower case changes its length has none, as its
/// offsets would not line up.
pub fn Query::occurrences(self : Query, text : String) -> Array[(Int, Int)] {
  let lower = text.to_lower()
  guard lower.length() == text.length() else { return [] }
  let needle = self.lower
  let found = []
  let mut from = 0
  while lower.view(start_offset=from).find(needle) is Some(offset) {
    let at = from + offset
    found.push((at, at + needle.length()))
    from = at + needle.length()
  }
  found
}

///|
pub extend Searchable with Eq::{equal, not_equal}

///|
pub extend Searchable with Hash::{hash, hash_combine}

///|
pub extend Searchable with @moonbitlang/core/debug.Debug::{to_repr}
