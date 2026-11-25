///|
fn query(text : String) -> @text_search.Query {
  @text_search.Query::parse(text).unwrap()
}

///|
test "occurrences ignore case, do not overlap" {
  assert_eq(query("Writ").occurrences("Write, rewrite"), [(0, 4), (9, 13)])
  assert_eq(query("aa").occurrences("aaaa"), [(0, 2), (2, 4)])
}

///|
test "a query of only spaces asks for nothing" {
  assert_true(@text_search.Query::parse("  ") is None)
  assert_true(query(" Writ ").found_in(@text_search.Searchable::of("ReWrite")))
}
