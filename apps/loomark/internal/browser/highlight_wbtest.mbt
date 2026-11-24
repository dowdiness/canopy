///|
test "occurrences ignore case, do not overlap" {
  assert_eq(occurrences("Write, rewrite", "writ"), [(0, 4), (9, 13)])
  assert_eq(occurrences("aaaa", "aa"), [(0, 2), (2, 4)])
  assert_eq(occurrences("Write", ""), [])
}
