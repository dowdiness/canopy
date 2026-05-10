// Full UAX #29 WordBreakTest conformance.
//
// Cases are generated from `testdata/WordBreakTest.txt` (Unicode 15.1) by
// `scripts/gen_break_test_cases.py` into `wordbreaktest_cases_wbtest.mbt`.
//
// Failure mode: prints the first divergence. Useful for diagnosing
// state-machine / property-table bugs.

///|
test "UAX #29 WordBreakTest 15.1 conformance" {
  let mut passed = 0
  let mut failed = 0
  let mut first_failure : String? = None
  for case in word_break_test_cases {
    let (text, expected) = case
    let actual = word_boundaries(text)
    if arrays_equal(actual, expected) {
      passed = passed + 1
    } else {
      failed = failed + 1
      if first_failure is None {
        first_failure = Some(format_failure(text, expected, actual))
      }
    }
  }
  match first_failure {
    None => ()
    Some(msg) => fail("conformance failure: \{msg}")
  }
  let total = passed + failed
  inspect(
    "\{passed}/\{total}",
    content="\{word_break_test_cases.length()}/\{word_break_test_cases.length()}",
  )
}
