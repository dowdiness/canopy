// Full UAX #29 GraphemeBreakTest conformance.
//
// Cases are generated from `testdata/GraphemeBreakTest.txt` (Unicode
// 15.1) by `scripts/gen_break_test_cases.py` into
// `graphemebreaktest_cases.mbt`.
//
// Failure mode: prints the first divergence. Useful for diagnosing
// state-machine / property-table bugs.

///|
test "UAX #29 GraphemeBreakTest 15.1 conformance" {
  let mut passed = 0
  let mut failed = 0
  let mut first_failure : String? = None
  for case in break_test_cases {
    let (text, expected) = case
    let actual = grapheme_boundaries(text)
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
    content="\{break_test_cases.length()}/\{break_test_cases.length()}",
  )
}

///|
fn arrays_equal(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn format_failure(
  text : String,
  expected : Array[Int],
  actual : Array[Int],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("\n  text codeunits: [")
  for i in 0..<text.length() {
    if i > 0 {
      buf.write_string(",")
    }
    let cu = text.at(i).to_int()
    buf.write_string(cu.to_string())
  }
  buf.write_string("]\n  expected: ")
  buf.write_string(format_array(expected))
  buf.write_string("\n  actual:   ")
  buf.write_string(format_array(actual))
  buf.to_string()
}

///|
fn format_array(a : Array[Int]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[")
  for i, v in a {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(v.to_string())
  }
  buf.write_string("]")
  buf.to_string()
}
