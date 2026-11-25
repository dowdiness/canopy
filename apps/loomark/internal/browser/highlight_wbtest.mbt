///|
fn query(text : String) -> SearchQuery {
  SearchQuery::parse(text).unwrap()
}

///|
test "occurrences ignore case, do not overlap" {
  assert_eq(occurrences("Write, rewrite", query("Writ")), [(0, 4), (9, 13)])
  assert_eq(occurrences("aaaa", query("aa")), [(0, 2), (2, 4)])
}

///|
test "a query of only spaces asks for nothing" {
  assert_eq(SearchQuery::parse("  ") is None, true)
  assert_eq(query(" Writ ").found_in("rewrite"), true)
}
